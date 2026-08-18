import 'package:flutter/services.dart';
import 'package:global_repository/global_repository.dart';
import '../config/app_config.dart';
import '../../ui/pages/settings/maintenance_actions.dart';
import 'backend_process_manager.dart';

/// 前台服务桥接与通知回调管理类
class ForegroundServiceManager {
  static const _channel = MethodChannel(Config.methodChannel);

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'exit_app') {
        Log.i('收到通知栏退出指令，正在退出应用...', tag: 'ForegroundService');
        await MaintenanceActions.performExit(showConfirmation: false);
      }
    });
  }

  /// 启动前台服务与后台容器
  static Future<void> startService() async {
    await BackendProcessManager.startService(target: ServiceTarget.all);
  }

  /// 停止前台服务与后台容器
  static Future<void> stopService() async {
    await BackendProcessManager.stopService(target: ServiceTarget.all);
  }

  /// 重启后台容器与服务
  static Future<void> restartContainer() async {
    await BackendProcessManager.restartService(target: ServiceTarget.all);
  }

  /// 仅独立重启 MaiBot
  static Future<void> restartMaiBot() async {
    await BackendProcessManager.restartService(target: ServiceTarget.maibot);
  }

  /// 仅独立重启 NapCat
  static Future<void> restartNapCat() async {
    await BackendProcessManager.restartService(target: ServiceTarget.napcat);
  }

  static bool get userClickedStopButton => BackendProcessManager.userClickedStop;

  static Future<bool> isRunningService() async {
    return BackendProcessManager.maibotState.value == ProcessState.running ||
           BackendProcessManager.napcatState.value == ProcessState.running;
  }

  static void updateNotification({
    String? title,
    String? text,
  }) {
    Log.d('updateNotification called with title: $title, text: $text', tag: 'ForegroundService');
  }
}
