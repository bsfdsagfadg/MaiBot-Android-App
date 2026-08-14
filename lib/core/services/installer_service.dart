import 'dart:io';
import 'dart:convert';

import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';

import '../config/app_config.dart';
import '../constants/scripts.dart' as scripts;
class InstallerService {
  static Future<bool> runInstallPipeline({
    required Function(String) onProgress,
    Function(String)? onLog,
    Function(String)? onNapcatLog,
  }) async {
    final ubuntuDir = Directory(scripts.ubuntuPath);
    
    // 1. 原生解压 (Native Extraction)
    bool isExtracted = false;
    if (ubuntuDir.existsSync()) {
      final coreFile = File('${scripts.ubuntuPath}/bin/bash');
      if (coreFile.existsSync()) {
        isExtracted = true;
      } else {
        // 核心文件不存在，说明解压不完整（如系统自动备份恢复导致残缺），删除重压
        ubuntuDir.deleteSync(recursive: true);
      }
    }
    
    if (!isExtracted) {
      onProgress('正在解压 Ubuntu 根文件系统...');
      try {
        final archivePath = '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}';
        final targetPath = '${scripts.prootDistroPath}/installed-rootfs';
        
        Directory(targetPath).createSync(recursive: true);
        
        final args = ['tar', '-xJvf', archivePath, '-C', targetPath];
        if (onLog != null) {
          final process = await Process.start('${RuntimeEnvir.binPath}/busybox', args);
          int extractedFiles = 0;
          final totalFiles = 12684; // 预估包内文件总数
          process.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((line) {
            extractedFiles++;
            if (extractedFiles % 300 == 0 || extractedFiles == totalFiles) {
              final pct = (extractedFiles / totalFiles * 100).clamp(0, 100).toStringAsFixed(1);
              onLog('\x1b[32m[解压进度]\x1b[0m $pct% ($extractedFiles/$totalFiles)\r\n');
            }
          });
          process.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((line) {
            // 过滤掉因为非 Root 导致的 chown 报错洪流，防止 UI 线程卡死
            if (!line.contains('chown') && !line.contains('mknod') && !line.contains('Operation not permitted')) {
              onLog('\x1b[31m[tar]\x1b[0m $line\r\n');
            }
          });
          await process.exitCode; // 忽略可能存在的 chown 权限警告报错
        } else {
          await Process.run('${RuntimeEnvir.binPath}/busybox', args);
        }

        // 移动内容
        final extractedDir = Directory('$targetPath/${scripts.ubuntuName}');
        if (extractedDir.existsSync()) {
          extractedDir.renameSync(scripts.ubuntuPath);
        }

        // 2. DNS 与 APT 环境注入
        onProgress('配置网络代理与 DNS...');
        _writeNetworkConfigs(onLog);

        onProgress('正在安装系统基础依赖...');
        final aptSuccess = await _runInProot('apt-get update && apt-get install -y sudo wget git curl', onLog: onLog);
        if (!aptSuccess) return false;


      } catch (e) {
        Log.e('解压过程发生异常: $e', tag: 'InstallerService');
        return false;
      }
    }

    try {
      // 1.5 备份解析与恢复扫描
    bool hasBackupData = false;
    bool hasBackupConfig = false;
    bool hasBackupPlugins = false;
    bool hasBackupNapcat = false;
    
    final backupDir = Directory('/sdcard/Download/MaiBot');
    final restoreTempDir = Directory('${RuntimeEnvir.tmpPath}/backup_restore');
    final restoreMarker = File('${RuntimeEnvir.tmpPath}/.restore_complete');
    
    if (!restoreMarker.existsSync() && backupDir.existsSync()) {
      // 获取最新的备份文件
      final backups = backupDir.listSync().where((e) => e.path.endsWith('.tar.gz')).toList();
      if (backups.isNotEmpty) {
        backups.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        final latestBackup = backups.first;
        
        onProgress('检测到历史备份，正在扫描解析...');
        if (restoreTempDir.existsSync()) restoreTempDir.deleteSync(recursive: true);
        restoreTempDir.createSync(recursive: true);
        
        final res = await Process.run('${RuntimeEnvir.binPath}/busybox', [
          'tar', '-xzf', latestBackup.path, '-C', restoreTempDir.path
        ]);
        
        if (res.exitCode == 0) {
          if (Directory('${restoreTempDir.path}/MaiBot/data').existsSync()) hasBackupData = true;
          if (Directory('${restoreTempDir.path}/MaiBot/config').existsSync()) hasBackupConfig = true;
          if (Directory('${restoreTempDir.path}/MaiBot/plugins').existsSync()) hasBackupPlugins = true;
          if (Directory('${restoreTempDir.path}/napcat/config').existsSync()) hasBackupNapcat = true;
        }
      }
    }

    final uvExecutable = File('${RuntimeEnvir.homePath}/.local/bin/uv');
    if (!uvExecutable.existsSync()) {
      onProgress('正在下载并安装 Python 依赖管理器 (uv)...');
      final success = await _downloadAndInstallUv(onLog);
      if (!success) return false;
    }

    // 4. 克隆 MaiBot
    final maibotDir = Directory('${RuntimeEnvir.homePath}/MaiBot');
    if (!maibotDir.existsSync() || !File('${maibotDir.path}/bot.py').existsSync()) {
      if (maibotDir.existsSync()) {
        await _runInProot('rm -rf /root/MaiBot');
      }
      onProgress('正在拉取 MaiBot 核心源码...');
      final success = await _cloneMaibot(onLog);
      if (!success) return false;
    }

    // 4.5 恢复插件与默认适配器克隆
    final pluginsDir = Directory('${RuntimeEnvir.homePath}/MaiBot/plugins');
    final adapterDir = Directory('${pluginsDir.path}/MaiBot-Napcat-Adapter');
    
    if (hasBackupPlugins) {
      onProgress('正在从备份中恢复插件...');
      await _runInProot('rm -rf /root/MaiBot/plugins/*');
      if (!pluginsDir.existsSync()) pluginsDir.createSync(recursive: true);
      await Process.run('${RuntimeEnvir.binPath}/busybox', ['cp', '-r', '${restoreTempDir.path}/MaiBot/plugins/', '${RuntimeEnvir.homePath}/MaiBot/']);
    }
    
    if (!adapterDir.existsSync()) {
      onProgress('安装默认适配器插件...');
      for (final mirror in ['https://ghfast.top/', 'https://gh-proxy.com/', 'https://mirror.ghproxy.com/', '']) {
        final adapterUrl = '${mirror}https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git';
        final res = await _runInProot('git clone --depth=1 --branch main $adapterUrl /root/MaiBot/plugins/MaiBot-Napcat-Adapter', onLog: onLog);
        if (res) break;
      }
      final adapterConfig = File('${adapterDir.path}/config.toml');
      if (adapterConfig.existsSync()) adapterConfig.deleteSync();
      
      // 如果有备份，尝试恢复适配器的配置
      final backupAdapterConfig = File('${restoreTempDir.path}/MaiBot/plugins/MaiBot-Napcat-Adapter/config.toml');
      if (hasBackupPlugins && backupAdapterConfig.existsSync()) {
        backupAdapterConfig.copySync(adapterConfig.path);
      }
    }
    // 4.6 恢复数据与配置
    final dataDir = Directory('${RuntimeEnvir.homePath}/MaiBot/data');
    if (!dataDir.existsSync() || dataDir.listSync().isEmpty) {
      if (hasBackupData) {
        onProgress('正在从备份中恢复数据...');
        if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
        await Process.run('${RuntimeEnvir.binPath}/busybox', ['cp', '-r', '${restoreTempDir.path}/MaiBot/data/*', '${dataDir.path}/']);
      }
    }

    final configDir = Directory('${RuntimeEnvir.homePath}/MaiBot/config');
    if (!configDir.existsSync() || configDir.listSync().isEmpty) {
      if (hasBackupConfig) {
        onProgress('正在从备份中恢复核心配置...');
        if (!configDir.existsSync()) configDir.createSync(recursive: true);
        await Process.run('${RuntimeEnvir.binPath}/busybox', ['cp', '-r', '${restoreTempDir.path}/MaiBot/config/*', '${configDir.path}/']);
      }
    }

    final venvDir = Directory('${RuntimeEnvir.homePath}/MaiBot/.venv');
    if (!venvDir.existsSync()) {
      onProgress('正在同步 Python 依赖库 (可能需要几分钟)...');
      final success = await _runInProot('cd /root/MaiBot && /root/.local/bin/uv sync', onLog: onLog);
      if (!success) return false;
      await _runInProot('cd /root/MaiBot && /root/.local/bin/uv pip install pip', onLog: onLog);
      if (!success) return false;
    }
    // 6. 安装 NapCat
    final napcatDir = Directory('${RuntimeEnvir.homePath}/napcat');
    final qqBinary = File('${scripts.ubuntuPath}/opt/QQ/qq');
    if (!napcatDir.existsSync() || !qqBinary.existsSync()) {
      onProgress('正在清理依赖并下载 NapCatQQ 组件...');
      await _runInProot('apt --fix-broken install -y', onLog: onNapcatLog ?? onLog);
      onProgress('正在下载 NapCatQQ 组件...');
      bool downloaded = false;
      for (final mirror in ['https://ghfast.top/', 'https://gh-proxy.com/', 'https://mirror.ghproxy.com/', '']) {
        final url = '${mirror}https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh';
        final res = await _runInProot('curl -sL -f -o /root/napcat.sh $url', onLog: onNapcatLog ?? onLog);
        if (res) { downloaded = true; break; }
      }
      if (!downloaded) return false;
      
      final success = await _runInProot(
        r"sed -i 's|apt-get install.*QQ\.deb.*|& || exit 1|g' /root/napcat.sh "
        r"&& sed -i 's|curl -k -L -#|curl -k -L -sS|g' /root/napcat.sh "
        r"&& bash /root/napcat.sh", 
        onLog: onNapcatLog ?? onLog
      );
      if (!success) return false;
    }

    // 6.5 恢复 NapCat 配置
    final napcatConfigDir = Directory('${napcatDir.path}/config');
    final napcatJson = File('${napcatConfigDir.path}/onebot11.json');
    if (!napcatJson.existsSync() && hasBackupNapcat) {
      onProgress('正在从备份中恢复 NapCat 配置...');
      if (!napcatConfigDir.existsSync()) napcatConfigDir.createSync(recursive: true);
      await Process.run('${RuntimeEnvir.binPath}/busybox', ['cp', '-r', '${restoreTempDir.path}/napcat/config/*', '${napcatConfigDir.path}/']);
    }

    // 7. 清理
    if (restoreTempDir.existsSync()) restoreTempDir.deleteSync(recursive: true);
    restoreMarker.writeAsStringSync('done');
    onProgress('初始化完成！即将启动核心服务...');
    return true;
  } catch (e) {
    Log.e('后续配置执行异常: $e', tag: 'InstallerService');
    return false;
  }
  }

  static void _writeNetworkConfigs(Function(String)? onLog) {
    try {
      onLog?.call('\x1b[32m[DNS]\x1b[0m 正在写入 resolv.conf...\r\n');
      final resolvConf = File('${scripts.ubuntuPath}/etc/resolv.conf');
      resolvConf.writeAsStringSync('nameserver 223.5.5.5\nnameserver 114.114.114.114\nnameserver 8.8.8.8\n');

      final aptConfDir = Directory('${scripts.ubuntuPath}/etc/apt/apt.conf.d');
      if (!aptConfDir.existsSync()) aptConfDir.createSync(recursive: true);
      
      final networkConf = File('${aptConfDir.path}/99custom-network');
      networkConf.writeAsStringSync('Acquire::http::Pipeline-Depth "0";\nAcquire::Retries "3";\n');
      
      onLog?.call('\x1b[32m[Sysdata]\x1b[0m 正在配置伪装系统信息...\r\n');
      final procDir = Directory('${scripts.ubuntuPath}/proc');
      if (!procDir.existsSync()) procDir.createSync(recursive: true);
      final loadavg = File('${procDir.path}/.loadavg');
      if (!loadavg.existsSync()) loadavg.writeAsStringSync('0.12 0.07 0.02 2/165 765\n');
      final stat = File('${procDir.path}/.stat');
      if (!stat.existsSync()) stat.writeAsStringSync('cpu  1957 0 2877 93280 262 342 254 87 0 0\n');
      final uptime = File('${procDir.path}/.uptime');
      if (!uptime.existsSync()) uptime.writeAsStringSync('12345.67 890.12\n');
      final vmstat = File('${procDir.path}/.vmstat');
      if (!vmstat.existsSync()) vmstat.writeAsStringSync('nr_free_pages 100000\n');

      onLog?.call('\x1b[32m[APT]\x1b[0m 正在配置 Tsinghua 镜像源...\r\n');
      
      final sourcesList = File('${scripts.ubuntuPath}/etc/apt/sources.list');
      sourcesList.writeAsStringSync(
        'deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble main restricted universe multiverse\n'
        'deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-updates main restricted universe multiverse\n'
        'deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-security main restricted universe multiverse\n'
      );
    } catch (e) {
      Log.e('Failed to write network configs: $e', tag: 'InstallerService');
    }
  }

  static Future<bool> _downloadAndInstallUv(Function(String)? onLog) async {
    const mirrors = [
      'https://ghfast.top/',
      'https://gh-proxy.com/',
      'https://mirror.ghproxy.com/',
      ''
    ];
    
    final tmpArchive = '${RuntimeEnvir.tmpPath}/uv-aarch64.tar.gz';
    const releaseUrl = 'https://github.com/astral-sh/uv/releases/download/0.9.9/uv-aarch64-unknown-linux-gnu.tar.gz';
    
    bool downloaded = false;
    for (final mirror in mirrors) {
      final target = '$mirror$releaseUrl';
      onLog?.call('\x1b[32m[UV]\x1b[0m 尝试从 $mirror 下载...\r\n');
      
      if (onLog != null) {
        final process = await Process.start('${RuntimeEnvir.binPath}/busybox', ['wget', '-O', tmpArchive, target]);
        process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((data) => onLog(data.replaceAll('\n', '\r\n')));
        process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((data) => onLog(data.replaceAll('\n', '\r\n')));
        final exitCode = await process.exitCode;
        if (exitCode == 0) {
          downloaded = true;
          break;
        }
      } else {
        final res = await Process.run('${RuntimeEnvir.binPath}/busybox', ['wget', '-O', tmpArchive, target]);
        if (res.exitCode == 0) {
          downloaded = true;
          break;
        }
      }
    }
    
    if (!downloaded) {
      onLog?.call('\x1b[31m[UV]\x1b[0m 所有镜像源下载均失败！\r\n');
      return false;
    }
    
    onLog?.call('\x1b[32m[UV]\x1b[0m 下载完成，正在解压...\r\n');
    final extractRes = await Process.run('${RuntimeEnvir.binPath}/busybox', [
      'tar', '-xzf', tmpArchive, '-C', RuntimeEnvir.tmpPath
    ]);
    
    if (extractRes.exitCode == 0) {
      final localBin = Directory('${RuntimeEnvir.homePath}/.local/bin');
      if (!localBin.existsSync()) localBin.createSync(recursive: true);
      
      File('${RuntimeEnvir.tmpPath}/uv-aarch64-unknown-linux-gnu/uv').copySync('${localBin.path}/uv');
      File('${RuntimeEnvir.tmpPath}/uv-aarch64-unknown-linux-gnu/uvx').copySync('${localBin.path}/uvx');
      Process.runSync('${RuntimeEnvir.binPath}/busybox', ['chmod', '+x', '${localBin.path}/uv', '${localBin.path}/uvx']);
      return true;
    }
    return false;
  }

  static Future<bool> _cloneMaibot(Function(String)? onLog) async {
    Setting customGitCloneSetting = 'custom_git_clone_url'.setting;
    String customRepoUrl = customGitCloneSetting.get() ?? '';

    final mirrors = customRepoUrl.isNotEmpty 
      ? [''] // 如果用户自定义了完整 URL，则不再附加前缀镜像
      : [
          'https://ghfast.top/',
          'https://ghproxy.vip/',
          'https://gh-proxy.com/',
          ''
        ];
    final tmpDir = '${RuntimeEnvir.homePath}/MaiBot_tmp';
    
    for (final mirror in mirrors) {
      final repo = customRepoUrl.isNotEmpty ? customRepoUrl : '${mirror}https://github.com/Mai-with-u/MaiBot.git';
      // Cleanup before try (using busybox to bypass Dart read-only file deletion issues in .git)
      await Process.run('${RuntimeEnvir.binPath}/busybox', ['rm', '-rf', tmpDir]);
      
      // Use -c gc.auto=0 to prevent git auto maintenance from hanging the proot process after clone
      final success = await _runInProot('git -c gc.auto=0 clone --depth=1 --branch main $repo /root/MaiBot_tmp', onLog: onLog);
      if (success) {
        Directory(tmpDir).renameSync('${RuntimeEnvir.homePath}/MaiBot');
        return true;
      }
    }
    return false;
  }

  static Future<bool> _runInProot(String command, {Function(String)? onLog}) async {
    final prootPath = '${RuntimeEnvir.binPath}/proot';
    final args = [
      '-0', '-r', scripts.ubuntuPath,
      '--link2symlink',
      '-b', '/dev', '-b', '/proc', '-b', '/sys',
      '-b', '${RuntimeEnvir.tmpPath}:/tmp',
      '-b', '${RuntimeEnvir.homePath}:/root',
      '-w', '/root',
      '/bin/sh', '-c',
      'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; export UV_LINK_MODE=copy; $command'
    ];
    if (onLog != null) {
      final process = await Process.start(prootPath, args, environment: {
        'PROOT_TMP_DIR': RuntimeEnvir.tmpPath,
        'LD_LIBRARY_PATH': RuntimeEnvir.binPath,
        'PROOT_LOADER': '${RuntimeEnvir.binPath}/loader',
      });
      
      process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((data) => onLog(data.replaceAll('\n', '\r\n')));
      process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((data) => onLog(data.replaceAll('\n', '\r\n')));
      
      final exitCode = await process.exitCode;
      return exitCode == 0;
    } else {
      final res = await Process.run(prootPath, args, environment: {
        'PROOT_TMP_DIR': RuntimeEnvir.tmpPath,
        'LD_LIBRARY_PATH': RuntimeEnvir.binPath,
        'PROOT_LOADER': '${RuntimeEnvir.binPath}/loader',
      });
      return res.exitCode == 0;
    }
  }
}
