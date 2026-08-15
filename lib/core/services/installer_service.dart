import 'dart:io';
import 'dart:convert';

import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';

import '../config/app_config.dart';
import '../constants/scripts.dart' as scripts;
class InstallerService {
  /// 记录当前流水线是否为首次/全新安装
  static bool lastInstallWasFresh = false;

  static Future<bool> runInstallPipeline({
    required Function(String) onProgress,
    Function(String)? onLog,
    Function(String)? onNapcatLog,
  }) async {
    final ubuntuDir = Directory(scripts.ubuntuPath);
    
    // 1. 原生解压 (Native Extraction)
    final rootfsMarker = File('${scripts.ubuntuPath}/.rootfs_ready');
    bool isExtracted = false;
    if (ubuntuDir.existsSync() && rootfsMarker.existsSync()) {
      final coreFile = File('${scripts.ubuntuPath}/bin/bash');
      if (coreFile.existsSync()) {
        isExtracted = true;
      }
    }
    
    lastInstallWasFresh = !isExtracted;
    
    if (!isExtracted) {
      if (ubuntuDir.existsSync()) {
        try {
          ubuntuDir.deleteSync(recursive: true);
        } catch (_) {}
      }
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
            if (!line.contains('chown') && !line.contains('mknod') && !line.contains('Operation not permitted')) {
              onLog('\x1b[31m[tar]\x1b[0m $line\r\n');
            }
          });
          await process.exitCode;
        } else {
          await Process.run('${RuntimeEnvir.binPath}/busybox', args);
        }

        // 移动内容
        final extractedDir = Directory('$targetPath/${scripts.ubuntuName}');
        if (extractedDir.existsSync()) {
          extractedDir.renameSync(scripts.ubuntuPath);
        }

        // 标记 Rootfs 解压完成
        rootfsMarker.writeAsStringSync('ready');

        // 2. DNS 与系统环境注入
        onProgress('配置网络代理与系统参数...');
        _writeNetworkConfigs(onLog);
      } catch (e) {
        Log.e('解压过程发生异常: $e', tag: 'InstallerService');
        return false;
      }
    }

    // 2. 独立自愈校验系统依赖（git, curl, wget, sudo 等）
    final depSuccess = await _ensureSystemDependencies(onProgress, onLog);
    if (!depSuccess) {
      Log.e('系统基础依赖修复/安装失败', tag: 'InstallerService');
      return false;
    }
    try {
      // 3. 校验并安装 uv
    final uvExecutable = File('${scripts.ubuntuPath}/root/.local/bin/uv');
    final uvxExecutable = File('${scripts.ubuntuPath}/root/.local/bin/uvx');
    if (!uvExecutable.existsSync() || uvExecutable.lengthSync() < 10000 || !uvxExecutable.existsSync()) {
      onProgress('正在下载并安装 Python 依赖管理器 (uv)...');
      final success = await _downloadAndInstallUv(onLog);
      if (!success) return false;
    }

    // 4. 克隆 MaiBot
    final maibotDir = Directory('${scripts.ubuntuPath}/root/MaiBot');
    final botPy = File('${maibotDir.path}/bot.py');
    final pyproject = File('${maibotDir.path}/pyproject.toml');
    if (!maibotDir.existsSync() || !botPy.existsSync() || !pyproject.existsSync()) {
      if (maibotDir.existsSync()) {
        await _runInProot('rm -rf /root/MaiBot');
      }
      onProgress('正在获取 MaiBot 源码...');
      final success = await _cloneMaibot(onLog);
      if (!success) return false;
    }

    // 4.5 默认适配器克隆
    final pluginsDir = Directory('${scripts.ubuntuPath}/root/MaiBot/plugins');
    final adapterDir = Directory('${pluginsDir.path}/MaiBot-Napcat-Adapter');
    final adapterMain = File('${adapterDir.path}/adapter.py');
    final adapterInit = File('${adapterDir.path}/__init__.py');
    
    if (!adapterDir.existsSync() || (!adapterMain.existsSync() && !adapterInit.existsSync())) {
      if (adapterDir.existsSync()) {
        await _runInProot('rm -rf /root/MaiBot/plugins/MaiBot-Napcat-Adapter');
      }
      onProgress('安装默认适配器插件...');
      for (final mirror in ['https://ghfast.top/', 'https://gh-proxy.com/', 'https://mirror.ghproxy.com/', '']) {
        final adapterUrl = '${mirror}https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git';
        final res = await _runInProot('git -c gc.auto=0 clone --depth=1 --branch main $adapterUrl /root/MaiBot/plugins/MaiBot-Napcat-Adapter', onLog: onLog);
        if (res) break;
      }
      final adapterConfig = File('${adapterDir.path}/config.toml');
      if (adapterConfig.existsSync()) adapterConfig.deleteSync();
    }
    // 5. 同步 Python 依赖库
    final venvDir = Directory('${scripts.ubuntuPath}/root/MaiBot/.venv');
    final venvMarker = File('${venvDir.path}/.venv_sync_done');
    final pythonBin = File('${venvDir.path}/bin/python');
    if (!venvDir.existsSync() || !venvMarker.existsSync() || !pythonBin.existsSync()) {
      if (venvDir.existsSync() && !venvMarker.existsSync()) {
        // 说明上次依赖安装到一半被中断，清理未完成的残破虚拟环境以防幽灵缺失
        await _runInProot('rm -rf /root/MaiBot/.venv');
      }
      onProgress('正在同步 Python 依赖库 (国内镜像加速)...');
      final uvSyncCmd =
          'cd /root/MaiBot && '
          'if command -v script >/dev/null 2>&1; then '
          '  script -q -e -c "/root/.local/bin/uv sync --color always --index-url https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple" /dev/null; '
          'else '
          '  /root/.local/bin/uv sync --color always --index-url https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple; '
          'fi';
      final success = await _runInProot(uvSyncCmd, onLog: onLog);
      if (!success) return false;
      final pipSuccess = await _runInProot('cd /root/MaiBot && /root/.local/bin/uv pip install -i https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple pip', onLog: onLog);
      if (!pipSuccess) return false;
      venvMarker.writeAsStringSync('ready');
    }

    // 6. 安装 NapCat
    final napcatDir = Directory('${scripts.ubuntuPath}/root/napcat');
    final qqBinary = File('${scripts.ubuntuPath}/opt/QQ/qq');
    final launcherSh = File('${scripts.ubuntuPath}/root/launcher.sh');
    final napcatEntry = File('${napcatDir.path}/napcat.mjs');
    if (!napcatDir.existsSync() || !qqBinary.existsSync() || !launcherSh.existsSync() || !napcatEntry.existsSync()) {
      onProgress('正在清理依赖并下载 NapCatQQ 组件...');
      await _runInProot('echo "[APT] 检查并修复破损的系统包..." && dpkg --configure -a || true && apt-get --fix-broken install -y', onLog: onLog);
      onProgress('正在下载 NapCatQQ 组件...');
      bool downloaded = false;
      for (final mirror in ['https://ghfast.top/', 'https://gh-proxy.com/', 'https://mirror.ghproxy.com/', '']) {
        final url = '${mirror}https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh';
        final res = await _runInProot('echo "[网络] 尝试获取安装脚本: $url" && curl -sL -f --connect-timeout 10 --max-time 30 -o /root/napcat.sh $url', onLog: onLog);
        if (res) { downloaded = true; break; }
      }
      if (!downloaded) return false;
      
      final success = await _runInProot(
        r"sed -i 's@apt-get install.*QQ\.deb.*@& || exit 1@g' /root/napcat.sh "
        r"&& sed -i 's@curl -k -L -#@curl -k -L @g' /root/napcat.sh "
        r"&& sed -i 's@curl -k -L @curl -k -L --connect-timeout 10 --max-time 300 @g' /root/napcat.sh "
        r"&& bash /root/napcat.sh", 
        onLog: onLog
      );
      if (!success) return false;
    }
    onProgress('初始化完成，正在准备启动...');
    return true;
  } catch (e) {
    Log.e('后续配置执行异常: $e', tag: 'InstallerService');
    return false;
  }
  }

  static void _writeNetworkConfigs(Function(String)? onLog) {
    try {
      // 确保系统目录与临时目录存在且权限正确，彻底杜绝 ca-certificates 或 dpkg 找不到路径
      Directory('${scripts.ubuntuPath}/tmp').createSync(recursive: true);
      Directory('${scripts.ubuntuPath}/var/tmp').createSync(recursive: true);
      Directory('${scripts.ubuntuPath}/etc/ssl/certs').createSync(recursive: true);
      Directory('${scripts.ubuntuPath}/var/cache/apt/archives/partial').createSync(recursive: true);
      Directory('${scripts.ubuntuPath}/var/lib/apt/lists/partial').createSync(recursive: true);
      Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);

      onLog?.call('\x1b[32m[DNS]\x1b[0m 正在写入 resolv.conf...\r\n');
      final resolvConf = File('${scripts.ubuntuPath}/etc/resolv.conf');
      resolvConf.writeAsStringSync('nameserver 223.5.5.5\nnameserver 119.29.29.29\nnameserver 114.114.114.114\nnameserver 8.8.8.8\n');

      final aptConfDir = Directory('${scripts.ubuntuPath}/etc/apt/apt.conf.d');
      if (!aptConfDir.existsSync()) aptConfDir.createSync(recursive: true);
      
      // APT 极限加速：全局阻断冗余推荐包风暴、禁用多语言翻译索引下载（节约70%更新体积）、关闭管道深度避免网络卡死、禁用文件系统缓存开销
      final speedupConf = File('${aptConfDir.path}/99speedup');
      speedupConf.writeAsStringSync(
        'APT::Install-Recommends "false";\n'
        'APT::Install-Suggests "false";\n'
        'Acquire::Languages "none";\n'
        'Acquire::Check-Valid-Until "false";\n'
        'Acquire::http::Timeout "10";\n'
        'Acquire::https::Timeout "10";\n'
        'Acquire::Retries "3";\n'
        'Acquire::http::Pipeline-Depth "0";\n'
        'Dir::Cache::pkgcache "";\n'
        'Dir::Cache::srcpkgcache "";\n'
      );

      // DPKG 加速：在 PRoot 虚拟文件系统中跳过耗时的逐文件物理 fsync，并跳过数万个无用文档小文件写入
      final dpkgConfDir = Directory('${scripts.ubuntuPath}/etc/dpkg/dpkg.cfg.d');
      if (!dpkgConfDir.existsSync()) dpkgConfDir.createSync(recursive: true);
      final dpkgSpeedup = File('${dpkgConfDir.path}/02apt-speedup');
      dpkgSpeedup.writeAsStringSync('force-unsafe-io\n');
      
      final dpkgNoDoc = File('${dpkgConfDir.path}/01nodoc');
      dpkgNoDoc.writeAsStringSync(
        'path-exclude /usr/share/doc/*\n'
        'path-exclude /usr/share/man/*\n'
        'path-exclude /usr/share/groff/*\n'
        'path-exclude /usr/share/info/*\n'
        'path-exclude /usr/share/lintian/*\n'
        'path-exclude /usr/share/linda/*\n'
        'path-exclude /usr/share/locale/*\n'
      );

      // 部署 apt-fast (基于 aria2c 的多连接并发下载加速器)
      final localBinDir = Directory('${scripts.ubuntuPath}/usr/local/bin');
      if (!localBinDir.existsSync()) localBinDir.createSync(recursive: true);
      final aptFastScript = File('${localBinDir.path}/apt-fast');
      aptFastScript.writeAsStringSync(
        '#!/bin/bash\n'
        '# apt-fast: high-speed multi-connection wrapper for apt-get using aria2c\n'
        'set -e\n'
        'APT_REAL="/usr/bin/apt-get"\n'
        '[ ! -x "\$APT_REAL" ] && APT_REAL="apt-get"\n\n'
        'if ! command -v aria2c >/dev/null 2>&1 || [ \$# -eq 0 ]; then\n'
        '    exec "\$APT_REAL" "\$@"\n'
        'fi\n\n'
        'case "\$1" in\n'
        '    install|reinstall|dist-upgrade|upgrade|build-dep|source)\n'
        '        TMP_URI_FILE="/tmp/apt-fast-\$\$.uris"\n'
        '        TMP_LIST_FILE="/tmp/apt-fast-\$\$.list"\n'
        '        mkdir -p /var/cache/apt/archives/partial\n'
        '        if "\$APT_REAL" --print-uris -y "\$@" > "\$TMP_URI_FILE" 2>/dev/null; then\n'
        '            awk \'{\n'
        '                gsub(/\\047/, "", \$1);\n'
        '                gsub(/\\047/, "", \$2);\n'
        '                if (\$1 ~ /^https?:\\/\\// || \$1 ~ /^ftp:\\/\\//) {\n'
        '                    print \$1;\n'
        '                    print "  dir=/var/cache/apt/archives";\n'
        '                    print "  out=" \$2;\n'
        '                }\n'
        '            }\' "\$TMP_URI_FILE" > "\$TMP_LIST_FILE"\n'
        '            if [ -s "\$TMP_LIST_FILE" ]; then\n'
        '                echo -e "\\e[32m[apt-fast]\\e[0m 使用 aria2c 多连接并发下载软件包..."\n'
        '                aria2c \\\n'
        '                    --no-conf \\\n'
        '                    -i "\$TMP_LIST_FILE" \\\n'
        '                    -j 8 \\\n'
        '                    -x 8 \\\n'
        '                    -s 8 \\\n'
        '                    -k 1M \\\n'
        '                    --allow-overwrite=true \\\n'
        '                    --auto-file-renaming=false \\\n'
        '                    --file-allocation=none \\\n'
        '                    --console-log-level=warn \\\n'
        '                    --summary-interval=0 \\\n'
        '                    --connect-timeout=10 \\\n'
        '                    --timeout=30 \\\n'
        '                    --max-tries=5 \\\n'
        '                    --retry-wait=2 \\\n'
        '                    --dir=/var/cache/apt/archives || true\n'
        '            fi\n'
        '            rm -f "\$TMP_URI_FILE" "\$TMP_LIST_FILE"\n'
        '        fi\n'
        '        exec "\$APT_REAL" "\$@"\n'
        '        ;;\n'
        '    *)\n'
        '        exec "\$APT_REAL" "\$@"\n'
        '        ;;\n'
        'esac\n'
      );
      Process.runSync('${RuntimeEnvir.binPath}/busybox', ['chmod', '+x', aptFastScript.path]);
      
      // 创建 apt-get 与 apt 的覆盖软连接至 /usr/local/bin
      final aptGetLink = Link('${localBinDir.path}/apt-get');
      if (!aptGetLink.existsSync()) {
        try { aptGetLink.createSync('apt-fast'); } catch (_) {}
      }
      final aptLink = Link('${localBinDir.path}/apt');
      if (!aptLink.existsSync()) {
        try { aptLink.createSync('apt-fast'); } catch (_) {}
      }

      // UV 国内镜像与加速配置
      final uvConfigDir = Directory('${scripts.ubuntuPath}/root/.config/uv');
      if (!uvConfigDir.existsSync()) uvConfigDir.createSync(recursive: true);
      final uvToml = File('${uvConfigDir.path}/uv.toml');
      uvToml.writeAsStringSync(
        '[[index]]\n'
        'url = "https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple"\n'
        'default = true\n'
      );
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

      _writeSourcesList('http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/', onLog);
    } catch (e) {
      Log.e('Failed to write network configs: $e', tag: 'InstallerService');
    }
  }

  static void _writeSourcesList(String mirrorUrl, Function(String)? onLog) {
    try {
      onLog?.call('\x1b[32m[APT]\x1b[0m 配置镜像源 -> $mirrorUrl\r\n');
      final sourcesList = File('${scripts.ubuntuPath}/etc/apt/sources.list');
      sourcesList.writeAsStringSync(
        'deb $mirrorUrl noble main restricted universe multiverse\n'
        'deb $mirrorUrl noble-updates main restricted universe multiverse\n'
        'deb $mirrorUrl noble-security main restricted universe multiverse\n'
      );
    } catch (e) {
      Log.e('Failed to write sources.list: $e', tag: 'InstallerService');
    }
  }

  /// 检查系统核心依赖，缺失时自动多镜像源尝试自愈修复
  static Future<bool> _ensureSystemDependencies(Function(String) onProgress, Function(String)? onLog) async {
    final gitBinary = File('${scripts.ubuntuPath}/usr/bin/git');
    final curlBinary = File('${scripts.ubuntuPath}/usr/bin/curl');
    final wgetBinary = File('${scripts.ubuntuPath}/usr/bin/wget');
    final sudoBinary = File('${scripts.ubuntuPath}/usr/bin/sudo');
    final aria2Binary = File('${scripts.ubuntuPath}/usr/bin/aria2c');

    // 核心依赖全部完好，直接跳过（零耗时，秒级通过）
    if (gitBinary.existsSync() && curlBinary.existsSync() && wgetBinary.existsSync() && sudoBinary.existsSync() && aria2Binary.existsSync()) {
      _writeNetworkConfigs(onLog);
      return true;
    }

    onProgress('正在检查并安装系统运行依赖 (git/curl/aria2)...');
    _writeNetworkConfigs(onLog);

    const aptMirrors = [
      'http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/',
      'http://mirrors.ustc.edu.cn/ubuntu-ports/',
      'http://mirrors.aliyun.com/ubuntu-ports/',
      'http://mirrors.volces.com/ubuntu-ports/',
      'http://ports.ubuntu.com/ubuntu-ports/',
    ];

    for (final mirror in aptMirrors) {
      _writeSourcesList(mirror, onLog);
      
      // 显式在容器内创建临时目录并强制重设 TMPDIR=/tmp，彻底根治 CA 证书安装去宿主 cache 目录寻找临时文件的异常
      final repairCmd = 
          'mkdir -p /tmp /var/tmp /etc/ssl/certs && chmod 1777 /tmp /var/tmp; '
          'export TMPDIR=/tmp; export TEMP=/tmp; export TMP=/tmp; export DEBIAN_FRONTEND=noninteractive; '
          'dpkg --configure -a || true; '
          'apt-get --fix-broken install -y || true; '
          'apt-get update && apt-get install -y --no-install-recommends sudo wget git curl ca-certificates aria2';
      
      final success = await _runInProot(repairCmd, onLog: onLog, timeout: const Duration(minutes: 5));
      if (success && gitBinary.existsSync() && curlBinary.existsSync()) {
        _writeNetworkConfigs(onLog);
        return true;
      }
    }

    return gitBinary.existsSync();
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
      final localBin = Directory('${scripts.ubuntuPath}/root/.local/bin');
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
    final tmpDir = '${scripts.ubuntuPath}/root/MaiBot_tmp';
    
    for (final mirror in mirrors) {
      final repo = customRepoUrl.isNotEmpty ? customRepoUrl : '${mirror}https://github.com/Mai-with-u/MaiBot.git';
      // Cleanup before try (using busybox to bypass Dart read-only file deletion issues in .git)
      await Process.run('${RuntimeEnvir.binPath}/busybox', ['rm', '-rf', tmpDir]);
      
      // Use -c gc.auto=0 to prevent git auto maintenance from hanging the proot process after clone
      final success = await _runInProot('git -c gc.auto=0 clone --depth=1 --branch main $repo /root/MaiBot_tmp', onLog: onLog);
      if (success) {
        Directory(tmpDir).renameSync('${scripts.ubuntuPath}/root/MaiBot');
        return true;
      }
    }
    return false;
  }

  static Future<bool> _runInProot(String command, {Function(String)? onLog, Duration timeout = const Duration(minutes: 10)}) async {
    final prootPath = '${RuntimeEnvir.binPath}/proot';
    Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);
    
    final args = [
      '-0', '-r', scripts.ubuntuPath,
      '--link2symlink',
      '-b', '/dev', '-b', '/proc', '-b', '/sys',
      '-b', '${RuntimeEnvir.tmpPath}:/tmp',
      '-b', '${RuntimeEnvir.tmpPath}:/dev/shm',
      '-w', '/root',
      '/bin/sh', '-c',
      'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; '
      'export TERM=xterm-256color; '
      'export COLORTERM=truecolor; '
      'export FORCE_COLOR=1; '
      'export CLICOLOR_FORCE=1; '
      'export CLICOLOR=1; '
      'export PYTHONUNBUFFERED=1; '
      'export PYTHONIOENCODING=utf-8; '
      'export PYTHON_COLORS=1; '
      'export RICH_FORCE_COLOR=1; '
      'export LOGURU_COLORIZE=true; '
      'export UV_COLOR=always; '
      'export UV_PROGRESS_MODE=visual; '
      'export UV_NO_PROGRESS=0; '
      'export UV_INDEX_URL=https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple; '
      'export PIP_NO_COLOR=0; '
      'export COLUMNS=100; '
      'export LINES=30; '
      'export LANG=C.UTF-8; '
      'export LC_ALL=C.UTF-8; '
      'export DEBIAN_FRONTEND=noninteractive; '
      'export GIT_TERMINAL_PROMPT=0; '
      'export UV_LINK_MODE=copy; '
      'export TMPDIR=/tmp; '
      'export TEMP=/tmp; '
      'export TMP=/tmp; '
      'mkdir -p /tmp /var/tmp; '
      '$command'
    ];
    final env = {
      'PROOT_TMP_DIR': RuntimeEnvir.tmpPath,
      'LD_LIBRARY_PATH': RuntimeEnvir.binPath,
      'PROOT_LOADER': '${RuntimeEnvir.binPath}/loader',
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
      'FORCE_COLOR': '1',
      'CLICOLOR_FORCE': '1',
      'CLICOLOR': '1',
      'PYTHONUNBUFFERED': '1',
      'PYTHONIOENCODING': 'utf-8',
      'PYTHON_COLORS': '1',
      'RICH_FORCE_COLOR': '1',
      'LOGURU_COLORIZE': 'true',
      'UV_COLOR': 'always',
      'UV_PROGRESS_MODE': 'visual',
      'UV_NO_PROGRESS': '0',
      'UV_INDEX_URL': 'https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple',
      'PIP_NO_COLOR': '0',
      'COLUMNS': '100',
      'LINES': '30',
      'LANG': 'C.UTF-8',
      'LC_ALL': 'C.UTF-8',
      'TMPDIR': '/tmp',
      'TEMP': '/tmp',
      'TMP': '/tmp',
    };
    if (onLog != null) {
      final process = await Process.start(prootPath, args, environment: env);
      
      process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(
        (data) => onLog(data.replaceAll('\n', '\r\n')),
        onError: (_) {},
      );
      process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(
        (data) => onLog(data.replaceAll('\n', '\r\n')),
        onError: (_) {},
      );
      
      try {
        final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        });
        return exitCode == 0;
      } catch (e) {
        process.kill(ProcessSignal.sigkill);
        return false;
      }
    } else {
      try {
        final res = await Process.run(prootPath, args, environment: env).timeout(timeout, onTimeout: () {
          return ProcessResult(-1, -1, '', 'Timed out');
        });
        return res.exitCode == 0;
      } catch (e) {
        return false;
      }
    }
  }
}
