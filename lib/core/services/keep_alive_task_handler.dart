import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:global_repository/global_repository.dart';

import '../config/app_config.dart';
import 'foreground_service.dart';
import 'pty_socket_bridge.dart';

/// 前台服务回调函数
/// Foreground service callback
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(KeepAliveTaskHandler());
}

/// 前台任务处理器
///
/// 运行在独立 Isolate（与 UI Isolate 静态变量不共享），因此所有状态
/// （用户主动停止、启动指令）都通过 [TaskMessages] 控制消息维护在本类内。
/// Foreground task handler
class KeepAliveTaskHandler extends TaskHandler {
  /// 服务重建计数器
  int _rebuildCount = 0;

  /// 标记是否是用户主动划掉通知（用于区分系统自动清理）
  static bool _userDismissedNotification = false;

  /// 用户主动停止标记（经 [TaskMessages.userStop] 消息在本 Isolate 内维护）
  bool _userStopped = false;

  /// onStart 完成前到达的启动指令排队标记（如备份恢复后立即拉起容器）
  bool _startMaibotPending = false;
  bool _startNapcatPending = false;

  PtySocketBridge? _maibotBridge;
  PtySocketBridge? _napcatBridge;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    Log.i('前台服务已启动', 'KeepAliveTaskHandler');
    RuntimeEnvir.initEnvirWithPackageName(Config.packageName);

    _maibotBridge = PtySocketBridge(
      name: 'MaiBot',
      port: Ports.maibotPtySocket,
      command: 'source ${RuntimeEnvir.homePath}/common.sh\nstart_maibot\n',
    );
    _napcatBridge = PtySocketBridge(
      name: 'NapCat',
      port: Ports.napcatPtySocket,
      command:
          'source ${RuntimeEnvir.homePath}/common.sh\nlogin_ubuntu "bash /root/launcher.sh"\n',
    );

    await _maibotBridge!.startServer();
    await _napcatBridge!.startServer();

    // 补发 onStart 完成前已到达的启动指令，避免消息被吞导致容器永不启动
    if (_startMaibotPending) {
      _maibotBridge!.resetRestartCount();
      _maibotBridge!.start();
    }
    if (_startNapcatPending) {
      _napcatBridge!.resetRestartCount();
      _napcatBridge!.start();
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data == TaskMessages.startMaibot) {
      _startMaibotPending = true;
      _maibotBridge?.resetRestartCount();
      _maibotBridge?.start();
    } else if (data == TaskMessages.startNapcat) {
      _startNapcatPending = true;
      _napcatBridge?.resetRestartCount();
      _napcatBridge?.start();
    } else if (data == TaskMessages.userStop) {
      _userStopped = true;
      Log.i('收到用户停止指令，停止自动重建', 'KeepAliveTaskHandler');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.isRunningService.then((isRunning) {
      if (!isRunning && !_userStopped) {
        Log.w('检测到服务意外停止，准备重建...', 'KeepAliveTaskHandler');
        _rebuildService();
      }
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTaskRemoved) async {
    Log.i('前台服务被销毁，isTaskRemoved: $isTaskRemoved, 用户主动划掉: $_userDismissedNotification',
        'KeepAliveTaskHandler');

    if (!_userDismissedNotification && !_userStopped) {
      Log.w('检测到系统自动清理通知或服务被终止，准备重建...', 'KeepAliveTaskHandler');
      await Future.delayed(const Duration(milliseconds: 500));
      await _rebuildService();
    }

    _userDismissedNotification = false;
  }

  /// 重建服务
  Future<void> _rebuildService() async {
    try {
      _rebuildCount++;
      Log.i('正在重建服务（第 $_rebuildCount 次）...', 'KeepAliveTaskHandler');

      final result = await ForegroundServiceManager.startService();

      if (result is ServiceRequestSuccess) {
        Log.i('服务重建成功', 'KeepAliveTaskHandler');
        _rebuildCount = 0; // 重置计数器
      } else if (result is ServiceRequestFailure) {
        Log.e('服务重建失败: ${result.error}', 'KeepAliveTaskHandler');

        // 如果重建失败，等待更长时间后再次尝试
        if (_rebuildCount < 5) {
          await Future.delayed(Duration(seconds: _rebuildCount * 2));
          await _rebuildService();
        } else {
          Log.e('服务重建失败次数过多，停止尝试', 'KeepAliveTaskHandler');
          _rebuildCount = 0;
        }
      }
    } catch (e) {
      Log.e('重建服务时发生异常: $e', 'KeepAliveTaskHandler');
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    // 通知按钮点击时调用
    if (id == 'btn_open') {
      Log.i('用户点击打开界面按钮', 'KeepAliveTaskHandler');
      FlutterForegroundTask.launchApp('/');
    } else if (id == 'btn_stop') {
      Log.i('用户点击停止按钮', 'KeepAliveTaskHandler');
      // 用户点击停止运行按钮，先标记为手动停止，然后退出应用
      // （stopService 内的 user_stop 消息为冗余保险，本 Isolate 内直接标记）
      _userStopped = true;
      ForegroundServiceManager.stopService().then((_) {
        exit(0);
      });
    }
  }

  @override
  void onNotificationPressed() {
    // 点击通知时调用
    Log.i('用户点击通知', 'KeepAliveTaskHandler');
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {
    Log.w('用户主动划掉通知，准备重建服务...', 'KeepAliveTaskHandler');

    _userDismissedNotification = true;

    if (!_userStopped) {
      Log.i('检测到用户主动划掉通知，将重建服务', 'KeepAliveTaskHandler');
      Future.delayed(const Duration(milliseconds: 500), () {
        _rebuildService();
      });
    } else {
      Log.i('不重建服务（用户手动停止）', 'KeepAliveTaskHandler');
    }
  }
}
