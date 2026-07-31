import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';

import 'keep_alive_task_handler.dart';

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
