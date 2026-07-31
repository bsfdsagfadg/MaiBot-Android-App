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
import '../../core/services/env_bootstrapper.dart';
import '../../core/services/foreground_service.dart';
import '../../core/services/progress_tracker.dart';
import '../../core/services/socket_stream_client.dart';
import '../../core/utils/version_utils.dart';
import 'napcat_controller.dart';
import 'terminal_tab_manager.dart';
import 'webview_controller.dart';

class HomeController extends GetxController with WidgetsBindingObserver {
  static final _ansiColorRegExp = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
  // 终端标签页管理器
  late final TerminalTabManager terminalTabManager;
  Setting privacySetting = 'privacy'.setting;
  Setting showTerminalWhiteText = 'show_terminal_white_text'.setting;
  Setting hideFromRecents = 'hide_from_recents'.setting;

  // 前台服务 PTY 转发 Socket 客户端
  late final SocketStreamClient maibotClient;
  late final SocketStreamClient napcatClient;

  late Terminal terminal = Terminal(
    maxLines: 5000,
    onOutput: (data) {
      maibotClient.socket?.add(utf8.encode(data));
    },
  );

  late Terminal napcatShowTerminal = Terminal(
    maxLines: 5000,
    onOutput: (data) {
      napcatClient.socket?.add(utf8.encode(data));
    },
  );

  // 安装进度跟踪器
  late final ProgressTracker progressTracker;

  bool _isLocalhostDetected = false; // localhost:6185 检测标志
  bool _isAppInForeground = true; // 应用是否在前台
  Timer? _localhostProbeTimer; // [Fix 4.2 / 5.1] 本地端口主动探测定时器

  double get progress => progressTracker.progress;
  String get currentProgress => progressTracker.currentProgress;

  final WebviewController webviewController = Get.put(WebviewController());
  final NapcatController napcatController = Get.put(NapcatController());

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

  void _handleMaibotLine(String line) async {
    napcatController.handleMaibotOutput(line);
    napcatController.handleNapcatOutput(line);
    final cleanLine = line.replaceAll(_ansiColorRegExp, '');
    if (cleanLine.contains('访问地址:')) {
      _isLocalhostDetected = true;
      // 仅在非历史回放（实时流数据）时增加进度计数，防止重连重放触发
      if (!maibotClient.isReplaying) {
        await progressTracker.bump();
      }
      _checkAndNavigateToWebview();
      Future.delayed(const Duration(milliseconds: 2000), () => update());
    }
  }

  void _handleNapcatLine(String line) {
    napcatController.handleNapcatOutput(line);
    _checkAndNavigateToWebview();
  }

  // 初始化环境，将动态库中的文件链接到数据目录
  // Init environment and link files from the dynamic library to the data directory
  Future<void> loadMaiBot() async {
    await progressTracker.startWatching();

    // 创建相关文件夹
    await Directory(RuntimeEnvir.tmpPath).create(recursive: true);
    await Directory(RuntimeEnvir.homePath).create(recursive: true);
    await Directory(RuntimeEnvir.binPath).create(recursive: true);

    // initEnvir 内部会一并创建 busybox 软链接
    await EnvBootstrapper.initEnvir();

    progressTracker.setProgress('复制 Ubuntu 系统镜像...');
    await AssetsUtils.copyAssetToPath('assets/${Config.ubuntuFileName}',
        '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}');
    await AssetsUtils.copyAssetToPath('assets/maibot-startup.sh',
        '${RuntimeEnvir.homePath}/maibot-startup.sh');
    await AssetsUtils.copyAssetToPath(
        'assets/config.toml', '${RuntimeEnvir.homePath}/config.toml');
    await progressTracker.bump();

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

    await progressTracker.bump();

    // 触发前台服务拉起容器
    progressTracker.setProgress('开始拉起 MaiBot 容器...');
    // 确保前台服务在运行（系统可能已回收服务进程），否则 start_maibot 消息会被丢弃
    if (!await ForegroundServiceManager.isRunningService()) {
      final result = await ForegroundServiceManager.startService();
      if (result is ServiceRequestFailure) {
        Log.e('前台服务未运行且启动失败: ${result.error}', 'MaiBot');
      }
    }
    FlutterForegroundTask.sendDataToTask(TaskMessages.startMaibot);

    // [Fix] 重构回归修复：start_napcat 控制消息曾失去发送方，导致 NapCat PTY 永不拉起、终端空白。
    // 已安装（launcher.sh 存在）时直接拉起 NapCat PTY；
    // 未安装（首次初始化）时由 ProgressTracker 在 "Napcat 已安装" 进度处触发。
    // 与容器内 install_napcat 的安装判定保持一致：
    // launcher.sh + QQ 主程序 + napcat 运行目录（package.json）三者齐备才视为已安装
    final launcherFile = File('$ubuntuPath/root/launcher.sh');
    final qqBinary = File('$ubuntuPath/opt/QQ/qq');
    final napcatPackage = File('$ubuntuPath/root/napcat/package.json');
    if (await launcherFile.exists() &&
        await qqBinary.exists() &&
        await napcatPackage.exists()) {
      Log.i('检测到 NapCat 已安装，直接拉起 NapCat 容器', 'MaiBot');
      FlutterForegroundTask.sendDataToTask(TaskMessages.startNapcat);
    }
    maibotClient.connect();
    napcatClient.connect();
  }

  @override
  void onInit() {
    super.onInit();

    // 初始化终端标签页管理器
    terminalTabManager = TerminalTabManager();

    // 初始化 Socket 客户端（须先于 terminal/napcatShowTerminal 的首次访问，
    // 它们的 onOutput 回调会引用 client.socket）
    maibotClient = SocketStreamClient(
      port: Ports.maibotPtySocket,
      onData: (event) => terminal.write(event),
      onLine: _handleMaibotLine,
    );
    napcatClient = SocketStreamClient(
      port: Ports.napcatPtySocket,
      onData: (event) => napcatShowTerminal.write(event),
      onLine: _handleNapcatLine,
    );

    // 初始化进度跟踪器（terminal 尚未访问，延迟注入）
    progressTracker = ProgressTracker(
      onChanged: () => update(),
      // NapCat 安装完成时拉起其 PTY
      onNapcatInstalled: () {
        Log.i('检测到 Napcat 已安装，发送指令启动 NapCat 容器', 'MaiBot');
        FlutterForegroundTask.sendDataToTask(TaskMessages.startNapcat);
      },
    );
    progressTracker.terminal = terminal;

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
        for (final port in Ports.localhostProbePorts) {
          try {
            final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 800));
            await socket.close();
            _isLocalhostDetected = true;
            Log.i('主动探测 127.0.0.1:$port 成功，设置 _isLocalhostDetected = true', 'MaiBot');
            break;
          } catch (_) {}
        }
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
        _checkAndNavigateToWebview();
        break;
      case AppLifecycleState.paused:
        _isAppInForeground = false;
        break;
      default:
        break;
    }
  }

  // 设置是否从最近活动中隐藏自身
  Future<void> setHideFromRecents(bool value) async {
    hideFromRecents.set(value);
    try {
      const channel = MethodChannel(Config.methodChannel);
      await channel.invokeMethod('hide_from_recents', {'hide': value});
    } catch (e) {
      Log.e('设置从最近活动隐藏失败: $e', 'MaiBot');
    }
  }

  @override
  void onClose() {
    try {
      progressTracker.dispose();
      _localhostProbeTimer?.cancel();
      maibotClient.dispose();
      napcatClient.dispose();
    } catch (e) {
      Log.e('清理终端引用时出错: $e', 'MaiBot');
    }

    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
