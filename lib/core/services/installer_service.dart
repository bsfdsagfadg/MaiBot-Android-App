import 'dart:io';
import 'dart:isolate';

import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';

import 'native_extractor.dart';
import '../config/app_config.dart';
import '../constants/scripts.dart' as scripts;
class InstallerService {
  static Future<bool> runInstallPipeline(Function(String) onProgress) async {
    final ubuntuDir = Directory(scripts.ubuntuPath);
    
    // 1. 原生解压 (Native Extraction)
    if (!ubuntuDir.existsSync()) {
      onProgress('正在解压 Ubuntu 根文件系统...');
      try {
        final archivePath = '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}';
        final targetPath = '${scripts.prootDistroPath}/installed-rootfs';
        
        // 使用 Dart 在后台 Isolate 进行纯原生解压 (完美处理软链接和 POSIX 权限)
        await Isolate.run(() {
          NativeExtractor.extractTarXz(archivePath, targetPath);
        });

        // 移动内容
        final extractedDir = Directory('$targetPath/${scripts.ubuntuName}');
        if (extractedDir.existsSync()) {
          extractedDir.renameSync(scripts.ubuntuPath);
        }
      } catch (e) {
        Log.e('解压过程发生异常: $e', 'InstallerService');
        return false;
      }
    }

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

      // 2. DNS 与 APT 环境注入
      onProgress('配置网络代理与 DNS...');
      _writeNetworkConfigs();

    // 3. 安装 UV
    final uvExecutable = File('${RuntimeEnvir.homePath}/.local/bin/uv');
    if (!uvExecutable.existsSync()) {
      onProgress('正在下载并安装 Python 依赖管理器 (uv)...');
      final success = await _downloadAndInstallUv();
      if (!success) return false;
    }

    // 4. 克隆 MaiBot
    final maibotDir = Directory('${RuntimeEnvir.homePath}/MaiBot');
    if (!maibotDir.existsSync()) {
      onProgress('正在拉取 MaiBot 核心源码...');
      final success = await _cloneMaibot();
      if (!success) return false;
    }

    // 4.5 恢复插件与默认适配器克隆
    final pluginsDir = Directory('${RuntimeEnvir.homePath}/MaiBot/plugins');
    final adapterDir = Directory('${pluginsDir.path}/MaiBot-Napcat-Adapter');
    
    bool shouldRestorePlugins = !pluginsDir.existsSync() || pluginsDir.listSync().where((e) => !e.path.endsWith('__pycache__') && !e.path.endsWith('__init__.py') && !e.path.endsWith('hello_world_plugin')).isEmpty;
    
    if (hasBackupPlugins && shouldRestorePlugins) {
      onProgress('正在从备份中恢复插件...');
      if (!pluginsDir.existsSync()) pluginsDir.createSync(recursive: true);
      await Process.run('${RuntimeEnvir.binPath}/busybox', ['cp', '-r', '${restoreTempDir.path}/MaiBot/plugins/*', '${pluginsDir.path}/']);
    } else if (!adapterDir.existsSync()) {
      onProgress('安装默认适配器插件...');
      await _runInProot('git clone --depth=1 --branch main https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git /root/MaiBot/plugins/MaiBot-Napcat-Adapter');
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
      final success = await _runInProot('cd /root/MaiBot && /root/.local/bin/uv sync');
      if (!success) return false;
      await _runInProot('cd /root/MaiBot && /root/.local/bin/uv pip install pip');
      if (!success) return false;
    }
    
    // 6. 安装 NapCat
    final napcatDir = Directory('${RuntimeEnvir.homePath}/napcat');
    final qqBinary = File('${scripts.ubuntuPath}/opt/QQ/qq');
    if (!napcatDir.existsSync() || !qqBinary.existsSync()) {
      onProgress('正在清理依赖并下载 NapCatQQ 组件...');
      await _runInProot('apt --fix-broken install -y');
      onProgress('正在下载 NapCatQQ 组件...');
      final success = await _runInProot('curl -o /root/napcat.sh https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh && bash /root/napcat.sh');
      if (!success) return false;

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
      Log.e('后续配置执行异常: $e', 'InstallerService');
      return false;
    }
  }

  static void _writeNetworkConfigs() {
    try {
      final resolvConf = File('${scripts.ubuntuPath}/etc/resolv.conf');
      resolvConf.writeAsStringSync('nameserver 223.5.5.5\nnameserver 114.114.114.114\nnameserver 8.8.8.8\n');

      final aptConfDir = Directory('${scripts.ubuntuPath}/etc/apt/apt.conf.d');
      if (!aptConfDir.existsSync()) aptConfDir.createSync(recursive: true);
      
      final networkConf = File('${aptConfDir.path}/99custom-network');
      networkConf.writeAsStringSync('Acquire::http::Pipeline-Depth "0";\nAcquire::Retries "3";\n');
      
      final sourcesList = File('${scripts.ubuntuPath}/etc/apt/sources.list');
      sourcesList.writeAsStringSync(
        'deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble main restricted universe multiverse\n'
        'deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-updates main restricted universe multiverse\n'
        'deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-security main restricted universe multiverse\n'
      );
    } catch (e) {
      Log.e('Failed to write network configs: $e', 'InstallerService');
    }
  }

  static Future<bool> _downloadAndInstallUv() async {
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
      final res = await Process.run('${RuntimeEnvir.binPath}/busybox', ['wget', '-O', tmpArchive, target]);
      if (res.exitCode == 0) {
        downloaded = true;
        break;
      }
    }
    
    if (!downloaded) return false;
    
    final extractRes = await Process.run('${RuntimeEnvir.binPath}/busybox', [
      'tar', '-xzf', tmpArchive, '-C', RuntimeEnvir.tmpPath
    ]);
    
    if (extractRes.exitCode == 0) {
      final localBin = Directory('${RuntimeEnvir.homePath}/.local/bin');
      if (!localBin.existsSync()) localBin.createSync(recursive: true);
      
      File('${RuntimeEnvir.tmpPath}/uv-aarch64-unknown-linux-gnu/uv').copySync('${localBin.path}/uv');
      File('${RuntimeEnvir.tmpPath}/uv-aarch64-unknown-linux-gnu/uvx').copySync('${localBin.path}/uvx');
      Process.runSync('chmod', ['+x', '${localBin.path}/uv', '${localBin.path}/uvx']);
      return true;
    }
    return false;
  }

  static Future<bool> _cloneMaibot() async {
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
      // Cleanup before try
      final tDir = Directory(tmpDir);
      if (tDir.existsSync()) tDir.deleteSync(recursive: true);
      
      final success = await _runInProot('git clone --depth=1 --branch main $repo /root/MaiBot_tmp');
      if (success) {
        Directory(tmpDir).renameSync('${RuntimeEnvir.homePath}/MaiBot');
        return true;
      }
    }
    return false;
  }

  static Future<bool> _runInProot(String command) async {
    final prootPath = '${RuntimeEnvir.binPath}/proot';
    final args = [
      '-0', '-r', scripts.ubuntuPath,
      '--link2symlink',
      '-b', '/dev', '-b', '/proc', '-b', '/sys',
      '-b', '${RuntimeEnvir.tmpPath}:/tmp',
      '-w', '/root',
      '/bin/sh', '-c',
      'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; $command'
    ];
    
    final res = await Process.run(prootPath, args, environment: {
      'PROOT_TMP_DIR': RuntimeEnvir.tmpPath,
      'LD_LIBRARY_PATH': RuntimeEnvir.binPath,
      'PROOT_LOADER': '${RuntimeEnvir.binPath}/loader',
    });
    
    return res.exitCode == 0;
  }
}
