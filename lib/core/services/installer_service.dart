import 'dart:io';
import 'dart:isolate';

import 'package:global_repository/global_repository.dart';

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

    try {
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

    // 5. 同步依赖
    final venvDir = Directory('${RuntimeEnvir.homePath}/MaiBot/.venv');
    if (!venvDir.existsSync()) {
      onProgress('正在同步 Python 依赖库 (可能需要几分钟)...');
      final success = await _runInProot('cd /root/MaiBot && /root/.local/bin/uv sync');
      if (!success) return false;
    }
    
    // 6. 安装 NapCat
    final napcatDir = Directory('${RuntimeEnvir.homePath}/napcat');
    if (!napcatDir.existsSync()) {
      onProgress('正在下载 NapCatQQ 组件...');
      final success = await _runInProot('curl -o /root/napcat.sh https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh && bash /root/napcat.sh');
      if (!success) return false;
    }

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
    const mirrors = [
      'https://ghfast.top/',
      'https://ghproxy.vip/',
      'https://gh-proxy.com/',
      ''
    ];
    
    final tmpDir = '${RuntimeEnvir.homePath}/MaiBot_tmp';
    
    for (final mirror in mirrors) {
      final repo = '${mirror}https://github.com/Mai-with-u/MaiBot.git';
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
