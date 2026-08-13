import 'package:flutter/services.dart';
import 'package:global_repository/global_repository.dart';
import '../constants/scripts.dart' as scripts;
import '../config/app_config.dart';
import 'config_service.dart';

/// 前台服务管理类 (全面拥抱 Native Backend，已剔除 flutter_foreground_task)
class ForegroundServiceManager {
  static bool _userClickedStopButton = false;
  static bool _isRunning = false;
  static const _channel = MethodChannel(Config.methodChannel);

  static void init() {
    // 初始化不再需要配置复杂的 Flutter Foreground Task
  }

  static Future<void> startService() async {
    _userClickedStopButton = false;
    Log.i('通过 Native 桥接启动前台服务...', 'ForegroundService');

    try {
      // 同步配置
      await ConfigService.ensureConfigsSynced();

      await _channel.invokeMethod('start_native_backend', {
        'binPath': RuntimeEnvir.binPath,
        'homePath': RuntimeEnvir.homePath,
        'tmpPath': RuntimeEnvir.tmpPath,
        'ubuntuPath': scripts.ubuntuPath,
      });
      _isRunning = true;
    } catch (e) {
      Log.e('启动 Native Backend 失败: $e', 'ForegroundService');
    }
  }

  static Future<void> stopService() async {
    _userClickedStopButton = true;
    Log.i('用户点击停止按钮，停止原生前台服务', 'ForegroundService');
    try {
      await _channel.invokeMethod('stop_native_backend', {
        'binPath': RuntimeEnvir.binPath,
      });
      _isRunning = false;
    } catch (e) {
      Log.e('停止 Native Backend 失败: $e', 'ForegroundService');
    }
  }

  static Future<void> restartContainer() async {
    await stopService();
    await Future.delayed(const Duration(milliseconds: 500));
    await startService();
  }

  static bool get userClickedStopButton => _userClickedStopButton;

  static Future<bool> isRunningService() async {
    return _isRunning;
  }

  static Future<void> updateNotification({
    String? title,
    String? text,
  }) async {
    // Native Backend 服务已在 Java 层固定了通知内容，若需动态更新可在此通过 MethodChannel 调用
  }
}
