import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';

import '../config/app_config.dart';
import 'keep_alive_task_handler.dart';

/// 前台服务管理类
/// Foreground Service Manager
class ForegroundServiceManager {
  /// 标记用户是否点击了停止按钮（仅 UI Isolate 内有效，供主界面监控使用）
  /// KeepAliveTaskHandler 运行在独立 Isolate，无法读取此静态字段，
  /// 其停止意图通过 [TaskMessages.userStop] 控制消息传递。
  static bool _userClickedStopButton = false;
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

  /// 停止前台服务（仅在用户点击停止按钮/维护操作时调用）
  /// Stop foreground service (only called when user clicks stop button)
  ///
  /// TaskHandler 运行在独立 Isolate，静态标志不可见；停止前先经任务通道
  /// 送达 [TaskMessages.userStop]，防止 onDestroy 将主动停止误判为意外死亡而重建。
  static Future<ServiceRequestResult> stopService() async {
    _userClickedStopButton = true; // 标记为用户点击了停止按钮（UI Isolate 监控用）
    Log.i('用户点击停止按钮，停止前台服务', 'ForegroundService');
    FlutterForegroundTask.sendDataToTask(TaskMessages.userStop);
    // 等待控制消息送达后台 Isolate，再执行停止，避免重建竞态
    await Future.delayed(const Duration(milliseconds: 300));
    return FlutterForegroundTask.stopService();
  }

  /// 恢复前台服务并重新拉起 MaiBot 容器（备份/取消维护后调用）。
  /// 服务已在运行时只补发启动消息（PTY 已在运行则为幂等空操作），
  /// 避免 restartService 触发 onDestroy 重建竞态形成无限重启循环。
  static Future<void> restartContainer() async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(TaskMessages.startMaibot);
      return;
    }
    final result = await startService();
    if (result is ServiceRequestFailure) {
      Log.e('恢复前台服务失败: ${result.error}', 'ForegroundService');
      return;
    }
    FlutterForegroundTask.sendDataToTask(TaskMessages.startMaibot);
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
