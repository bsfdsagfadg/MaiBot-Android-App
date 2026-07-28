import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:xterm/xterm.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/scripts.dart';
import '../../core/utils/file_utils.dart';
import '../../generated/l10n.dart';
import 'napcat_controller.dart';
import 'terminal_tab_manager.dart';
import 'webview_controller.dart';

class HomeController extends GetxController with WidgetsBindingObserver {
  static final _ansiColorRegExp = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
  static final _libSoRegExp = RegExp(r'^lib|\.so$');
  // 终端标签页管理器
  late final TerminalTabManager terminalTabManager;
  Setting privacySetting = 'privacy'.setting;
  Setting showTerminalWhiteText = 'show_terminal_white_text'.setting;
  Setting hideFromRecents = 'hide_from_recents'.setting;
  
  Socket? maibotSocket;
  Socket? napcatSocket;
  String _maibotLineBuffer = '';
  String _napcatLineBuffer = '';
  StreamSubscription? _progressSubscription;
  StreamSubscription? _progressDesSubscription;
  late Terminal terminal = Terminal(
    maxLines: 5000,
    onOutput: (data) {
      maibotSocket?.add(utf8.encode(data));
    },
  );

  late Terminal napcatShowTerminal = Terminal(
    maxLines: 5000,
    onOutput: (data) {
      napcatSocket?.add(utf8.encode(data));
    },
  );
  bool _isLocalhostDetected = false; // localhost:6185 检测标志
  bool _isAppInForeground = true; // 应用是否在前台
  bool _isMaiBotReplaying = false; // [Fix 4.1] 历史缓冲区回放标记
  Timer? _localhostProbeTimer; // [Fix 4.2 / 5.1] 本地端口主动探测定时器
  Timer? _progressPollTimer; // [Fix 5.2] 进度文件轮询定时器

  File progressFile = File('${RuntimeEnvir.tmpPath}/progress');
  File progressDesFile = File('${RuntimeEnvir.tmpPath}/progress_des');
  double progress = 0.0;
  double step = 14.0;
  String currentProgress = '';
  
  final WebviewController webviewController = Get.put(WebviewController());
  final NapcatController napcatController = Get.put(NapcatController());

  Future<void> _bumpProgressLock = Future.value();

  // 进度 +1
  // Progress +1
  Future<void> bumpProgress() async {
    _bumpProgressLock = _bumpProgressLock.then((_) async {
      try {
        int current = 0;
        if (await progressFile.exists()) {
          final content = (await progressFile.readAsString()).trim();
          if (content.isNotEmpty) {
            current = int.tryParse(content) ?? 0;
          }
        } else {
          await progressFile.create(recursive: true);
        }
        await progressFile.writeAsString('${current + 1}');
      } catch (e) {
        await progressFile.writeAsString('1');
      }
      update();
    }).catchError((_) {});
    return _bumpProgressLock;
  }

  // 检查两个条件是否都满足，如果满足则触发跳转
  void _checkAndNavigateToWebview() {
    // 只有当两个条件都满足且应用在前台时才跳转
    if (_isLocalhostDetected &&
        napcatController.isQrcodeProcessed &&
        _isAppInForeground &&
        !webviewController.webviewHasOpen) {
      webviewController.navigateToWebview();
    }
  }
  void _connectMaiBotSocket() async {
    if (maibotSocket != null) return;
    try {
      maibotSocket = await Socket.connect('127.0.0.1', 20001);
      _maibotLineBuffer = '';
      _isMaiBotReplaying = false;
      maibotSocket!.listen((data) async {
        var event = utf8.decode(data, allowMalformed: true);
        
        // [Fix 4.1] 处理历史缓冲区回放标记
        if (event.contains('\x02__HIST_START__\x03')) {
          _isMaiBotReplaying = true;
          event = event.replaceAll('\x02__HIST_START__\x03', '');
        }
        if (event.contains('\x02__HIST_END__\x03')) {
          event = event.replaceAll('\x02__HIST_END__\x03', '');
          _isMaiBotReplaying = false;
        }

        terminal.write(event);
        
        _maibotLineBuffer += event;
        final lines = _maibotLineBuffer.split('\n');
        _maibotLineBuffer = lines.removeLast();

        for (final line in lines) {
          napcatController.handleMaibotOutput(line);
          napcatController.handleNapcatOutput(line);
          final cleanLine = line.replaceAll(_ansiColorRegExp, '');
          if (cleanLine.contains('访问地址:')) {
            _isLocalhostDetected = true;
            // 仅在非历史回放（实时流数据）时增加进度计数，防止重连重放触发
            if (!_isMaiBotReplaying) {
              await bumpProgress();
            }
            _checkAndNavigateToWebview();
            Future.delayed(const Duration(milliseconds: 2000), () => update());
          }
        }
      }, onDone: () {
        maibotSocket = null;
        Future.delayed(const Duration(seconds: 2), _connectMaiBotSocket);
      }, onError: (e) {
        maibotSocket = null;
        Future.delayed(const Duration(seconds: 2), _connectMaiBotSocket);
      });
    } catch (e) {
      Future.delayed(const Duration(seconds: 2), _connectMaiBotSocket);
    }
  }

  void _connectNapCatSocket() async {
    if (napcatSocket != null) return;
    try {
      napcatSocket = await Socket.connect('127.0.0.1', 20002);
      _napcatLineBuffer = '';
      napcatSocket!.listen((data) {
        var event = utf8.decode(data, allowMalformed: true);
        if (event.contains('\x02__HIST_START__\x03')) {
          event = event.replaceAll('\x02__HIST_START__\x03', '');
        }
        if (event.contains('\x02__HIST_END__\x03')) {
          event = event.replaceAll('\x02__HIST_END__\x03', '');
        }
        napcatShowTerminal.write(event);
        
        _napcatLineBuffer += event;
        final lines = _napcatLineBuffer.split('\n');
        _napcatLineBuffer = lines.removeLast();

        for (final line in lines) {
          napcatController.handleNapcatOutput(line);
        }
        _checkAndNavigateToWebview();
      }, onDone: () {
        napcatSocket = null;
        Future.delayed(const Duration(seconds: 2), _connectNapCatSocket);
      }, onError: (e) {
        napcatSocket = null;
        Future.delayed(const Duration(seconds: 2), _connectNapCatSocket);
      });
    } catch (e) {
      Future.delayed(const Duration(seconds: 2), _connectNapCatSocket);
    }
  }

  // 初始化环境，将动态库中的文件链接到数据目录
  // Init environment and link files from the dynamic library to the data directory
  Future<void> initEnvir() async {
    List<String> androidFiles = [
      'libbash.so',
      'libbusybox.so',
      'liblibtalloc.so.2.so',
      'libloader.so',
      'libproot.so',
      'libsudo.so'
    ];
    String libPath = await getLibPath();
    Log.i('libPath -> $libPath');

    for (int i = 0; i < androidFiles.length; i++) {
      // when android target sdk > 28
      // cannot execute file in /data/data/com.xxx/files/usr/bin
      // so we need create a link to /data/data/com.xxx/files/usr/bin
      final sourcePath = '$libPath/${androidFiles[i]}';
      String fileName = androidFiles[i].replaceAll(_libSoRegExp, '');
      String filePath = '${RuntimeEnvir.binPath}/$fileName';
      // custom path, termux-api will invoke
      File file = File(filePath);
      FileSystemEntityType type = await FileSystemEntity.type(filePath);
      Log.i('$fileName type -> $type');
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.link) {
        // old version adb is plain file
        Log.i('find plain file -> $fileName, delete it');
        await file.delete();
      }
      Link link = Link(filePath);
      if (await link.exists()) {
        try {
          await link.delete();
        } catch (e) {
          Log.e('delete link error -> $e');
        }
      }
      try {
        Log.i('create link -> $fileName ${link.path}');
        await link.create(sourcePath);
      } catch (e) {
        Log.e('installAdbToEnvir error -> $e');
      }
    }

    // 处理 busybox 相关的符号链接，确保 proot 依赖的命令可用
    await createBusyboxLink();
  }

  // 同步当前进度
  // Sync the current progress
  Future<void> syncProgress() async {
    await progressFile.create(recursive: true);
    await progressFile.writeAsString('0');
    _progressSubscription = progressFile.watch(events: FileSystemEvent.all).listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressFile.readAsString();
        Log.e('content -> $content');
        if (content.isEmpty) {
          return;
        }
        progress = int.parse(content) / step;
        Log.e('progress -> $progress');
        update();
      }
    });
    await progressDesFile.create(recursive: true);
    await progressDesFile.writeAsString('');
    _progressDesSubscription = progressDesFile.watch(events: FileSystemEvent.all).listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressDesFile.readAsString();
        if (currentProgress == content) return;
        currentProgress = content;
        if (content.contains('Napcat ${S.current.installed}')) {
          await bumpProgress();
        }

        // 当进度到达 "MaiBot Core 配置中" 时，清除终端
        if (content.trim().contains('MaiBot Core 配置中')) {
          // 清除终端先前显示的所有文本
          terminal.buffer.clear();
          terminal.buffer.setCursor(0, 0);
          Log.i('检测到 MaiBot Core 配置中，清除终端内容', 'MaiBot');
        }

        update();
      }
    });
    // [Fix 5.2] 针对部分 Android OEM 系统 (MIUI/HarmonyOS) inotify 事件丢失添加 1 秒轮询兜底
    _progressPollTimer?.cancel();
    _progressPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        if (await progressFile.exists()) {
          String content = (await progressFile.readAsString()).trim();
          if (content.isNotEmpty) {
            double p = (int.tryParse(content) ?? 0) / step;
            if (progress != p) {
              progress = p;
              update();
            }
          }
        }
        if (await progressDesFile.exists()) {
          String content = await progressDesFile.readAsString();
          if (currentProgress != content) {
            currentProgress = content;
            if (content.contains('Napcat ${S.current.installed}')) {
              await bumpProgress();
            }
            if (content.trim().contains('MaiBot Core 配置中')) {
              terminal.buffer.clear();
              terminal.buffer.setCursor(0, 0);
            }
            update();
          }
        }
      } catch (_) {}
    });
  }

  // 创建 busybox 的软连接，来确保 proot 会用到的命令正常运行
  // create busybox symlinks, to ensure proot can use the commands normally
  Future<void> createBusyboxLink() async {
    try {
      List<String> links = [
        ...[
          'awk',
          'ash',
          'basename',
          'bzip2',
          'curl',
          'cp',
          'chmod',
          'cut',
          'cat',
          'du',
          'dd',
          'find',
          'grep',
          'gzip'
        ],
        ...[
          'hexdump',
          'head',
          'id',
          'lscpu',
          'mkdir',
          'realpath',
          'rm',
          'sed',
          'stat',
          'sh',
          'tr',
          'tar',
          'uname',
          'xargs',
          'xz',
          'xxd'
        ]
      ];

      for (String linkName in links) {
        String linkPath = '${RuntimeEnvir.binPath}/$linkName';
        Link link = Link(linkPath);
        if (await link.exists()) {
          try {
            await link.delete();
          } catch (e) {
            Log.e('delete busybox link error -> $e');
          }
        }
        try {
          await link.create('${RuntimeEnvir.binPath}/busybox');
        } catch (e) {
          Log.e('create busybox link error -> $e');
        }
      }

      String fileLinkPath = '${RuntimeEnvir.binPath}/file';
      Link fileLink = Link(fileLinkPath);
      if (await fileLink.exists()) {
        try {
          await fileLink.delete();
        } catch (e) {
          Log.e('delete file link error -> $e');
        }
      }
      try {
        await fileLink.create('/system/bin/file');
      } catch (e) {
        Log.e('create file link error -> $e');
      }
    } catch (e) {
      Log.e('Create link failed -> $e');
    }
  }

  void setProgress(String description) {
    currentProgress = description;
    terminal.writeProgress(currentProgress);
  }

  Future<void> loadMaiBot() async {
    await syncProgress();

    // 创建相关文件夹
    await Directory(RuntimeEnvir.tmpPath).create(recursive: true);
    await Directory(RuntimeEnvir.homePath).create(recursive: true);
    await Directory(RuntimeEnvir.binPath).create(recursive: true);

    await initEnvir();
    await createBusyboxLink();

    setProgress('复制 Ubuntu 系统镜像...');
    await AssetsUtils.copyAssetToPath('assets/${Config.ubuntuFileName}',
        '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}');
    await AssetsUtils.copyAssetToPath('assets/maibot-startup.sh',
        '${RuntimeEnvir.homePath}/maibot-startup.sh');
    await AssetsUtils.copyAssetToPath(
        'assets/config.toml', '${RuntimeEnvir.homePath}/config.toml');
    await bumpProgress();

    // 获取当前应用版本号
    final appVersion = await getAppVersion();

    // 替换 maibot-startup.sh 中的版本号占位符
    final startupScriptFile =
        File('${RuntimeEnvir.homePath}/maibot-startup.sh');
    if (await startupScriptFile.exists()) {
      String scriptContent = await startupScriptFile.readAsString();
      scriptContent = scriptContent.replaceAll('{{VERSION}}', appVersion);
      await startupScriptFile.writeAsString(scriptContent);
    }

    // 写入 common.sh 脚本
    await File('${RuntimeEnvir.homePath}/common.sh')
        .writeAsString(getCommonScript(appVersion));

    await bumpProgress();

    // 触发前台服务拉起容器
    setProgress('开始拉起 MaiBot 容器...');
    FlutterForegroundTask.sendDataToTask('start_maibot');
    _connectMaiBotSocket();
    _connectNapCatSocket();

    // 重连时不需要单独拉起Napcat终端，统一由MaiBot管理
  }

  @override
  void onInit() {
    super.onInit();

    // 初始化终端标签页管理器
    terminalTabManager = TerminalTabManager();


    // 初始化隐藏最近活动状态
    if (hideFromRecents.get() == true) {
      setHideFromRecents(true);
    }

    // 为 Google Play 上架做准备
    // For Google Play
    Future.delayed(Duration.zero, () async {
      if (privacySetting.get() == null) {
        await Get.to(PrivacyAgreePage(
          onAgreeTap: () {
            privacySetting.set(true);
            Get.back();
          },
        ));
      }

      // 加载并启动 MaiBot
      loadMaiBot();

      // 在终端创建完成后初始化固定标签页
      // 等待terminal创建完成
      Future.delayed(const Duration(milliseconds: 500), () {
        terminalTabManager.initializeFixedTabs(terminal, napcatShowTerminal);
      });
    });

    // [Fix 4.2 / 5.1] 定时主动探测本地 8001 端口并检查跳转条件，解开多重 AND 条件跳转死锁并兜底日志丢失
    _localhostProbeTimer?.cancel();
    _localhostProbeTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (webviewController.webviewHasOpen) {
        timer.cancel();
        return;
      }
      if (!_isLocalhostDetected) {
        try {
          final socket = await Socket.connect('127.0.0.1', 8001, timeout: const Duration(milliseconds: 1000));
          await socket.close();
          _isLocalhostDetected = true;
          Log.i('主动探测 127.0.0.1:8001 成功，设置 _isLocalhostDetected = true', 'MaiBot');
        } catch (_) {}
      }
      _checkAndNavigateToWebview();
    });
    // 监听应用生命周期状态变化
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _isAppInForeground = true;
        // 当应用回到前台且两个条件都满足但webview未打开时，打开webview
        if (_isLocalhostDetected &&
            napcatController.isQrcodeProcessed &&
            !webviewController.webviewHasOpen) {
          webviewController.navigateToWebview();
        }
        break;
      case AppLifecycleState.paused:
        _isAppInForeground = false;
        break;
      default:
        break;
    }
  }

  // 彻底清理可能的残留进程

  // 设置是否从最近活动中隐藏自身
  Future<void> setHideFromRecents(bool value) async {
    hideFromRecents.set(value);
    try {
      const channel = MethodChannel('maibot_channel');
      await channel.invokeMethod('hide_from_recents', {'hide': value});
    } catch (e) {
      Log.e('设置从最近活动隐藏失败: $e', 'MaiBot');
    }
  }

  void onClose() {
    try {
      _progressSubscription?.cancel();
      _progressDesSubscription?.cancel();
      _localhostProbeTimer?.cancel();
      _progressPollTimer?.cancel();
      maibotSocket?.close();
      napcatSocket?.close();
    } catch (e) {
      Log.e('清理终端引用时出错: $e', 'MaiBot');
    }

    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}

