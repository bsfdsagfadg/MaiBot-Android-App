import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';
import 'package:xterm/xterm.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/scripts.dart';
import '../../core/utils/file_utils.dart';
import '../../generated/l10n.dart';
import 'napcat_controller.dart';
import 'terminal_tab_manager.dart';
import 'webview_controller.dart';

class HomeController extends GetxController {
  // 终端标签页管理器
  late final TerminalTabManager terminalTabManager;
  Setting privacySetting = 'privacy'.setting;
  Setting showTerminalWhiteText = 'show_terminal_white_text'.setting;
  Setting hideFromRecents = 'hide_from_recents'.setting;
  Pty? pseudoTerminal;
  Pty? napcatTerminal;
  Pty? maibotLogPty;
  Pty? napcatLogPty;

  StreamSubscription? _qrcodeSubscription;
  StreamSubscription? _webviewSubscription; // 添加webview监听订阅

  late Terminal terminal = Terminal(
    maxLines: 5000,
    onResize: (width, height, pixelWidth, pixelHeight) {
      pseudoTerminal?.resize(height, width);
    },
    onOutput: (data) {
      pseudoTerminal?.writeString(data);
    },
  );

  late Terminal napcatShowTerminal = Terminal(
    maxLines: 5000,
    onResize: (width, height, pixelWidth, pixelHeight) {
      napcatTerminal?.resize(height, width);
    },
    onOutput: (data) {
      napcatTerminal?.writeString(data);
    },
  );
  bool _isLocalhostDetected = false; // localhost:6185 检测标志
  bool _isAppInForeground = true; // 应用是否在前台

  File progressFile = File('${RuntimeEnvir.tmpPath}/progress');
  File progressDesFile = File('${RuntimeEnvir.tmpPath}/progress_des');
  double progress = 0.0;
  double step = 14.0;
  String currentProgress = '';
  
  final WebviewController webviewController = Get.put(WebviewController());
  final NapcatController napcatController = Get.put(NapcatController());

  // 进度 +1
  // Progress +1
  void bumpProgress() {
    try {
      int current = 0;
      if (progressFile.existsSync()) {
        final content = progressFile.readAsStringSync().trim();
        if (content.isNotEmpty) {
          current = int.tryParse(content) ?? 0;
        }
      } else {
        progressFile.createSync(recursive: true);
      }
      progressFile.writeAsStringSync('${current + 1}');
    } catch (e) {
      progressFile.writeAsStringSync('1');
    }
    update();
  }

  // 使用 login_ubuntu 函数，传入要执行的命令
  // Use login_ubuntu function, passing the command to execute
  String get command {
    return 'source ${RuntimeEnvir.homePath}/common.sh\nlogin_ubuntu "if ! command -v tmux >/dev/null 2>&1; then apt-get update && apt-get install -y tmux; fi; export TMUX_TMPDIR=/tmp; tmux new-session -A -s napcat \'while true; do bash /root/launcher.sh 2>&1 | tee /root/napcat_clean.log; echo NapCat 意外退出，3秒后尝试重启...; sleep 3; done\'"\n';
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

  // 监听输出，当输出中包含启动成功的标志时，启动 VewView 和导航栏页面
  void initWebviewListener() {
    if (pseudoTerminal == null || maibotLogPty == null) return;

    // 监听交互式终端，仅用于前端屏幕渲染
    pseudoTerminal!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((event) {
      terminal.write(event);

      // 如果缓冲区满了，清屏
      if (terminal.buffer.lines.length >= 5000) {
        terminal.buffer.clear();
        terminal.buffer.setCursor(0, 0);
      }
    });

    // 监控后台干净日志，用于解析启动标志与 Token
    _webviewSubscription = maibotLogPty!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((event) async {
      if (event.trim().isNotEmpty) {
        final lines = event.split('\n');
        for (var line in lines) {
          if (line.trim().isNotEmpty) {
            Log.i(line, 'MaiBot');
          }
        }
      }

      napcatController.handleMaibotOutput(event);

      // 剥离ANSI颜色代码
      final cleanEvent = event.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');

      // 检查是否包含 MaiBot 启动完成的标志
      if (cleanEvent.contains('访问地址:')) {
        _isLocalhostDetected = true;
        bumpProgress();

        // 检查是否两个条件都满足
        _checkAndNavigateToWebview();

        Future.delayed(const Duration(milliseconds: 2000), () {
          update();
        });
      }
    });
  }

  void initQrcodeListener() {
    if (napcatTerminal == null || napcatLogPty == null) return;

    // 监听交互式终端，仅用于前端屏幕渲染
    napcatTerminal!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((event) {
      napcatShowTerminal.write(event);

      // 避免缓冲区过载
      if (napcatShowTerminal.buffer.lines.length >= 5000) {
        napcatShowTerminal.buffer.clear();
        napcatShowTerminal.buffer.setCursor(0, 0);
      }
    });

    // 监控后台干净日志，用于解析二维码及登录状态
    _qrcodeSubscription = napcatLogPty!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((event) async {
      if (_qrcodeSubscription == null) return;

      if (event.trim().isNotEmpty) {
        final lines = event.split('\n');
        for (var line in lines) {
          if (line.trim().isNotEmpty) {
            Log.i(line, 'MaiBot-Napcat');
          }
        }
      }

      napcatController.handleNapcatOutput(event);
      _checkAndNavigateToWebview();
    });
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
      String fileName = androidFiles[i].replaceAll(RegExp('^lib|\\.so\$'), '');
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
      if (link.existsSync()) {
        try {
          link.deleteSync();
        } catch (e) {
          Log.e('delete link error -> $e');
        }
      }
      try {
        Log.i('create link -> $fileName ${link.path}');
        link.createSync(sourcePath);
      } catch (e) {
        Log.e('installAdbToEnvir error -> $e');
      }
    }

    // 处理 busybox 相关的符号链接，确保 proot 依赖的命令可用
    createBusyboxLink();
  }

  // 同步当前进度
  // Sync the current progress
  void syncProgress() {
    progressFile.createSync(recursive: true);
    progressFile.writeAsStringSync('0');
    progressFile.watch(events: FileSystemEvent.all).listen((event) async {
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
    progressDesFile.createSync(recursive: true);
    progressDesFile.writeAsStringSync('');
    progressDesFile.watch(events: FileSystemEvent.all).listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressDesFile.readAsString();
        if (currentProgress == content) return;
        currentProgress = content;

        // 当进度到达 "Napcat 已安装" 时，启动 NapCat 终端
        if (content.contains('Napcat ${S.current.installed}')) {
          napcatTerminal?.writeString('$command\n');
          bumpProgress();
          Log.i('检测到 Napcat 已安装，启动 NapCat 终端', 'MaiBot');
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
  }

  // 创建 busybox 的软连接，来确保 proot 会用到的命令正常运行
  // create busybox symlinks, to ensure proot can use the commands normally
  void createBusyboxLink() {
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
        if (link.existsSync()) {
          try {
            link.deleteSync();
          } catch (e) {
            Log.e('delete busybox link error -> $e');
          }
        }
        try {
          link.createSync('${RuntimeEnvir.binPath}/busybox');
        } catch (e) {
          Log.e('create busybox link error -> $e');
        }
      }

      String fileLinkPath = '${RuntimeEnvir.binPath}/file';
      Link fileLink = Link(fileLinkPath);
      if (fileLink.existsSync()) {
        try {
          fileLink.deleteSync();
        } catch (e) {
          Log.e('delete file link error -> $e');
        }
      }
      try {
        fileLink.createSync('/system/bin/file');
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
    syncProgress();

    // 创建相关文件夹
    Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);
    Directory(RuntimeEnvir.homePath).createSync(recursive: true);
    Directory(RuntimeEnvir.binPath).createSync(recursive: true);

    await initEnvir();
    createBusyboxLink();

    // 创建终端并初始化
    pseudoTerminal =
        createPTY(rows: terminal.viewHeight, columns: terminal.viewWidth);
    napcatTerminal = 
        createPTY(rows: napcatShowTerminal.viewHeight, columns: napcatShowTerminal.viewWidth);

    // 初始化后台监控日志的 PTY
    maibotLogPty = createPTY(rows: 10, columns: 80);
    napcatLogPty = createPTY(rows: 10, columns: 80);

    // 绑定 napcat 终端的数据通道，使其能够接受用户键盘输入和动态改变大小
    napcatShowTerminal.onResize = (width, height, pixelWidth, pixelHeight) {
      napcatTerminal?.resize(height, width);
    };
    napcatShowTerminal.onOutput = (data) {
      napcatTerminal?.writeString(data);
    };

    setProgress('复制 Ubuntu 系统镜像...');
    await AssetsUtils.copyAssetToPath('assets/${Config.ubuntuFileName}',
        '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}');
    await AssetsUtils.copyAssetToPath('assets/maibot-startup.sh',
        '${RuntimeEnvir.homePath}/maibot-startup.sh');
    await AssetsUtils.copyAssetToPath(
        'assets/config.toml', '${RuntimeEnvir.homePath}/config.toml');
    bumpProgress();

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
    File('${RuntimeEnvir.homePath}/common.sh')
        .writeAsStringSync(getCommonScript(appVersion));

    // 启动干净的后台日志监控
    maibotLogPty!.writeString(
      'source ${RuntimeEnvir.homePath}/common.sh\n'
      'login_ubuntu "if ! command -v tmux >/dev/null 2>&1 || ! tmux has-session -t maibot 2>/dev/null; then > /root/maibot_clean.log; fi; touch /root/maibot_clean.log && tail -f -n +1 /root/maibot_clean.log"\n'
    );
    napcatLogPty!.writeString(
      'source ${RuntimeEnvir.homePath}/common.sh\n'
      'login_ubuntu "if ! command -v tmux >/dev/null 2>&1 || ! tmux has-session -t napcat 2>/dev/null; then > /root/napcat_clean.log; fi; touch /root/napcat_clean.log && tail -f -n +1 /root/napcat_clean.log"\n'
    );

    initWebviewListener();
    bumpProgress();

    initQrcodeListener();

    startMaiBot(pseudoTerminal!);
  }

  Future<void> startMaiBot(Pty pseudoTerminal) async {
    setProgress('开始安装 MaiBot...');
    pseudoTerminal.writeString(
        'source ${RuntimeEnvir.homePath}/common.sh\nstart_maibot\n');
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

    // 监听应用生命周期状态变化
    WidgetsBinding.instance.addObserver(
      LifecycleObserver(
        onResume: () {
          _isAppInForeground = true;
          // 当应用回到前台且两个条件都满足但webview未打开时，打开webview
          if (_isLocalhostDetected &&
              napcatController.isQrcodeProcessed &&
              !webviewController.webviewHasOpen) {
            webviewController.navigateToWebview();
          }
        },
        onPause: () {
          _isAppInForeground = false;
        },
      ),
    );
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

  @override
  void onClose() {
    // 清理订阅，避免内存泄漏
    _qrcodeSubscription?.cancel();
    _webviewSubscription?.cancel();
    _qrcodeSubscription = null;
    _webviewSubscription = null;

    // 释放资源，不强制杀死子进程，允许容器后台保活重连
    try {
      pseudoTerminal = null;
      napcatTerminal = null;
      maibotLogPty = null;
      napcatLogPty = null;
    } catch (e) {
      Log.e('清理终端引用时出错: $e', 'MaiBot');
    }

    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(
      LifecycleObserver(
        onResume: () {},
        onPause: () {},
      ),
    );
    super.onClose();
  }
}

// 应用生命周期观察者类
class LifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  final VoidCallback onPause;

  LifecycleObserver({required this.onResume, required this.onPause});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        onResume();
        break;
      case AppLifecycleState.paused:
        onPause();
        break;
      default:
        break;
    }
  }
}
