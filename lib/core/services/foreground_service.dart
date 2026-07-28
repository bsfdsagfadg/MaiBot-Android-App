import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';
import '../utils/file_utils.dart';

/// 前台服务管理类
/// Foreground Service Manager
class ForegroundServiceManager {
  /// 标记用户是否点击了停止按钮（只有这种情况才不重建）
  static bool _userClickedStopButton = false;
  /// [Fix 2.1] 标记是否正在重装/清除数据（暂停 PTY 自动重启）
  static bool _reinstallInProgress = false;
  /// [Fix 2.1] 设置重装/清除数据状态
  static void setReinstallInProgress(bool value) {
    _reinstallInProgress = value;
    Log.i('重装/清除数据状态: $_reinstallInProgress', 'ForegroundService');
  }
  /// [Fix 2.1] 获取重装/清除数据状态
  static bool get reinstallInProgress => _reinstallInProgress;
  /// 初始化前台服务
  /// Initialize foreground service
  static void init() {
    final enableWifiLock = 'enable_wifi_lock'.setting.get() ?? true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'maibot_keep_alive_channel',
        channelName: 'MaiBot后台服务',
        channelDescription: '保持MaiBot在后台运行',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // 每5秒检查一次
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: enableWifiLock,
      ),
    );
  }

  /// 启动前台服务
  /// Start foreground service
  static Future<ServiceRequestResult> startService() async {
    _userClickedStopButton = false; // 重置停止标记
    Log.i('启动前台服务...', 'ForegroundService');

    if (await FlutterForegroundTask.isRunningService) {
      Log.i('服务已在运行，重启服务', 'ForegroundService');
      return FlutterForegroundTask.restartService();
    } else {
      Log.i('启动新服务', 'ForegroundService');
      return FlutterForegroundTask.startService(
        serviceId: 1001,
        notificationTitle: 'MaiBot正在运行',
        notificationText: '应用正在后台保持运行状态',
        notificationIcon: null,
        notificationButtons: [
          const NotificationButton(
            id: 'btn_open',
            text: '打开界面',
          ),
          const NotificationButton(
            id: 'btn_stop',
            text: '停止运行',
          ),
        ],
        callback: startCallback,
      );
    }
  }

  /// 停止前台服务（仅在用户点击停止按钮时调用）
  /// Stop foreground service (only called when user clicks stop button)
  static Future<ServiceRequestResult> stopService() async {
    _userClickedStopButton = true; // 标记为用户点击了停止按钮
    Log.i('用户点击停止按钮，停止前台服务', 'ForegroundService');
    return FlutterForegroundTask.stopService();
  }

  /// 获取用户是否点击了停止按钮
  /// Get if user clicked stop button
  static bool get userClickedStopButton => _userClickedStopButton;

  /// 检查服务是否正在运行
  /// Check if service is running
  static Future<bool> isRunningService() async {
    return FlutterForegroundTask.isRunningService;
  }

  /// 更新通知内容
  /// Update notification content
  static Future<void> updateNotification({
    String? title,
    String? text,
  }) async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.updateService(
        notificationTitle: title ?? 'MaiBot正在运行',
        notificationText: text ?? '应用正在后台保持运行状态',
        notificationButtons: [
          const NotificationButton(
            id: 'btn_stop',
            text: '停止运行',
          ),
        ],
      );
    }
  }
}

/// 前台服务回调函数
/// Foreground service callback
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(KeepAliveTaskHandler());
}

/// 前台任务处理器
/// Foreground task handler
class KeepAliveTaskHandler extends TaskHandler {
  /// 服务重建计数器
  int _rebuildCount = 0;

  /// 标记是否是用户主动划掉通知（用于区分系统自动清理）
  static bool _userDismissedNotification = false;

  Pty? _maibotPty;
  Pty? _napcatPty;
  ServerSocket? _maibotServer;
  ServerSocket? _napcatServer;
  final List<Socket> _maibotSockets = [];
  final List<Socket> _napcatSockets = [];
  final List<List<int>> _maibotBufferChunks = [];
  int _maibotBufferLength = 0;
  final List<List<int>> _napcatBufferChunks = [];
  int _napcatBufferLength = 0;
  int _maibotRestartCount = 0;
  int _napcatRestartCount = 0;

  void _schedulePtyRestart(String name, void Function() startFn, int attempt, void Function(int) updateAttempt) {
    if (ForegroundServiceManager.reinstallInProgress) {
      Log.i('$name exited, 重装/清除数据中，暂停重启', 'KeepAliveTaskHandler');
      return;
    }
    if (attempt >= 10) {
      Log.e('$name exited, max retries (10) reached. Stopping restarts.', 'KeepAliveTaskHandler');
      try {
        File('${RuntimeEnvir.tmpPath}/progress_des').writeAsStringSync('组件 $name 连续启动失败，请点按屏幕查看终端日志');
      } catch (e) {
        Log.e('Failed to write error to progress_des: $e', 'KeepAliveTaskHandler');
      }
      return;
    }
    int delay = 3 * (1 << attempt);
    if (delay > 60) delay = 60;
    updateAttempt(attempt + 1);
    Log.i('$name exited, restarting in ${delay}s (Retry ${attempt + 1}/10)', 'KeepAliveTaskHandler');
    Future.delayed(Duration(seconds: delay), startFn);
  }


  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    Log.i('前台服务已启动', 'KeepAliveTaskHandler');
    RuntimeEnvir.initEnvirWithPackageName('com.maibot.maibot_android');
    try {
      _maibotServer ??= await ServerSocket.bind('127.0.0.1', 20001, shared: true);
      _maibotServer!.listen((socket) {
        _maibotSockets.add(socket);
        if (_maibotBufferChunks.isNotEmpty) {
          socket.add(utf8.encode('\x02__HIST_START__\x03'));
          for (var chunk in _maibotBufferChunks) socket.add(chunk);
          socket.add(utf8.encode('\x02__HIST_END__\x03'));
        }
        socket.listen((data) => _maibotPty?.write(data), onDone: () => _maibotSockets.remove(socket), onError: (_) => _maibotSockets.remove(socket));
      });

      _napcatServer!.listen((socket) {
        _napcatSockets.add(socket);
        if (_napcatBufferChunks.isNotEmpty) {
          socket.add(utf8.encode('\x02__HIST_START__\x03'));
          for (var chunk in _napcatBufferChunks) socket.add(chunk);
          socket.add(utf8.encode('\x02__HIST_END__\x03'));
        }
        socket.listen((data) => _napcatPty?.write(data), onDone: () => _napcatSockets.remove(socket), onError: (_) => _napcatSockets.remove(socket));
      });
    } catch (e) {
      Log.e('ServerSocket bind error: $e', 'KeepAliveTaskHandler');
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'start_maibot') {
      _maibotRestartCount = 0;
      _startMaiBot();
    } else if (data == 'start_napcat') {
      _napcatRestartCount = 0;
      _startNapCat();
    }
  }

  void _startMaiBot() {
    if (_maibotPty != null) return;
    _maibotBufferChunks.clear();
    _maibotBufferLength = 0;
    _maibotPty = createPTY(rows: 25, columns: 80);
    _maibotPty!.output.listen((data) {
      _maibotBufferChunks.add(data);
      _maibotBufferLength += data.length;
      while (_maibotBufferLength > 70000 && _maibotBufferChunks.length > 1) {
        _maibotBufferLength -= _maibotBufferChunks.removeAt(0).length;
      }
      for (var s in _maibotSockets) { try { s.add(data); } catch(_) {} }
    }, onDone: () {
      _maibotPty = null;
      _schedulePtyRestart('MaiBot', _startMaiBot, _maibotRestartCount, (val) => _maibotRestartCount = val);
    });
    _maibotPty!.writeString('source ${RuntimeEnvir.homePath}/common.sh\nstart_maibot\n');
  }

  void _startNapCat() {
    if (_napcatPty != null) return;
    _napcatBufferChunks.clear();
    _napcatBufferLength = 0;
    _napcatPty = createPTY(rows: 25, columns: 80);
    _napcatPty!.output.listen((data) {
      _napcatBufferChunks.add(data);
      _napcatBufferLength += data.length;
      while (_napcatBufferLength > 70000 && _napcatBufferChunks.length > 1) {
        _napcatBufferLength -= _napcatBufferChunks.removeAt(0).length;
      }
      for (var s in _napcatSockets) { try { s.add(data); } catch(_) {} }
    }, onDone: () {
      _napcatPty = null;
      _schedulePtyRestart('NapCat', _startNapCat, _napcatRestartCount, (val) => _napcatRestartCount = val);
    });
    _napcatPty!.writeString('source ${RuntimeEnvir.homePath}/common.sh\nlogin_ubuntu "bash /root/launcher.sh"\n');
  }



  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.isRunningService.then((isRunning) {
      if (!isRunning && !ForegroundServiceManager.userClickedStopButton && !ForegroundServiceManager.reinstallInProgress) {
        Log.w('检测到服务意外停止，准备重建...',  'KeepAliveTaskHandler');
        _rebuildService();
      }
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTaskRemoved) async {
    Log.i('前台服务被销毁，isTaskRemoved: $isTaskRemoved, 用户主动划掉: $_userDismissedNotification',  'KeepAliveTaskHandler');

    if (!_userDismissedNotification && !ForegroundServiceManager.userClickedStopButton) {
      Log.w('检测到系统自动清理通知或服务被终止，准备重建...',  'KeepAliveTaskHandler');
      await Future.delayed(const Duration(milliseconds: 500));
      await _rebuildService();
    }

    _userDismissedNotification = false;
  }

  /// 重建服务
  Future<void> _rebuildService() async {
    try {
      _rebuildCount++;
      Log.i('正在重建服务（第 $_rebuildCount 次）...',  'KeepAliveTaskHandler');

      final result = await ForegroundServiceManager.startService();

      if (result is ServiceRequestSuccess) {
        Log.i('服务重建成功',  'KeepAliveTaskHandler');
        _rebuildCount = 0; // 重置计数器
      } else if (result is ServiceRequestFailure) {
        Log.e('服务重建失败: ${result.error}',  'KeepAliveTaskHandler');

        // 如果重建失败，等待更长时间后再次尝试
        if (_rebuildCount < 5) {
          await Future.delayed(Duration(seconds: _rebuildCount * 2));
          await _rebuildService();
        } else {
          Log.e('服务重建失败次数过多，停止尝试',  'KeepAliveTaskHandler');
          _rebuildCount = 0;
        }
      }
    } catch (e) {
      Log.e('重建服务时发生异常: $e',  'KeepAliveTaskHandler');
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    // 通知按钮点击时调用
    if (id == 'btn_open') {
      Log.i('用户点击打开界面按钮',  'KeepAliveTaskHandler');
      FlutterForegroundTask.launchApp('/');
    } else if (id == 'btn_stop') {
      Log.i('用户点击停止按钮',  'KeepAliveTaskHandler');
      // 用户点击停止运行按钮，先标记为手动停止，然后退出应用
      ForegroundServiceManager.stopService().then((_) {
        exit(0);
      });
    }
  }

  @override
  void onNotificationPressed() {
    // 点击通知时调用
    Log.i('用户点击通知',  'KeepAliveTaskHandler');
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {
    Log.w('用户主动划掉通知，准备重建服务...',  'KeepAliveTaskHandler');

    _userDismissedNotification = true;

    if (!ForegroundServiceManager.userClickedStopButton) {
      Log.i('检测到用户主动划掉通知，将重建服务',  'KeepAliveTaskHandler');
      Future.delayed(const Duration(milliseconds: 500), () {
        _rebuildService();
      });
    } else {
      Log.i('不重建服务（用户手动停止）',  'KeepAliveTaskHandler');
    }
  }
}
