import 'dart:io';
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
    Log.i('通过 Native 桥接启动前台服务...', tag: 'ForegroundService');

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
      Log.e('启动 Native Backend 失败: $e', tag: 'ForegroundService');
    }
  }

  static Future<void> stopService() async {
    _userClickedStopButton = true;
    Log.i('用户点击停止按钮，停止原生前台服务', tag: 'ForegroundService');
    try {
      await _channel.invokeMethod('stop_native_backend', {
        'binPath': RuntimeEnvir.binPath,
      });
      _isRunning = false;
    } catch (e) {
      Log.e('停止 Native Backend 失败: $e', tag: 'ForegroundService');
    }
  }

  static Future<void> restartContainer() async {
    Log.i('正在停止并清理后台容器与残留进程...', tag: 'ForegroundService');
    await stopService();

    // 1. 强制终止所有可能占用端口的残留进程 (Python / Node / QQ / PRoot)
    try {
      await Process.run('${RuntimeEnvir.binPath}/busybox',
          ['killall', '-9', 'proot', 'python', 'python3', 'node', 'qq', 'bash', 'sh', 'crashpad_handler']);
    } catch (_) {}

    // 2. 清理残留的 X11 / QQ 单例与 Socket 锁文件，防止端口与单例冲突
    try {
      final x1Lock = File('${RuntimeEnvir.tmpPath}/.X1-lock');
      if (x1Lock.existsSync()) x1Lock.deleteSync();
      final x11Unix = Directory('${RuntimeEnvir.tmpPath}/.X11-unix');
      if (x11Unix.existsSync()) x11Unix.deleteSync(recursive: true);
      await Process.run('${RuntimeEnvir.binPath}/busybox', [
        'rm',
        '-rf',
        '${RuntimeEnvir.tmpPath}/SingletonLock',
        '${RuntimeEnvir.tmpPath}/SingletonSocket',
        '${RuntimeEnvir.tmpPath}/SingletonCookie',
        '${scripts.ubuntuPath}/root/.config/QQ/SingletonLock',
        '${scripts.ubuntuPath}/root/.config/QQ/SingletonSocket',
        '${scripts.ubuntuPath}/root/.config/QQ/SingletonCookie',
      ]);
    } catch (_) {}

    // 3. 充分等待端口和系统资源释放
    await Future.delayed(const Duration(milliseconds: 1200));
    Log.i('端口与资源已释放，正在启动新服务实例...', tag: 'ForegroundService');
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
