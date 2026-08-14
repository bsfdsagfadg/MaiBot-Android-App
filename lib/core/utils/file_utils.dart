import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../config/app_config.dart';

// 为了获取Apk So库路径，我们需要一个MethodChannel
MethodChannel _channel = const MethodChannel(Config.methodChannel);

/// 获取 Apk So 库路径
/// Gets the path of the Apk So library
Future<String> getLibPath() async {
  return await _channel.invokeMethod('lib_path');
}

/// 获取 MaiBot 备份与数据持久化下载目录，按优先级自适应探测不同 Android 分身/主系统路径
Directory getMaiBotBackupDirectory() {
  const candidates = [
    '/storage/emulated/0/Download/MaiBot',
    '/sdcard/Download/MaiBot',
    '/storage/self/primary/Download/MaiBot',
  ];
  for (final path in candidates) {
    final dir = Directory(path);
    if (dir.existsSync()) {
      return dir;
    }
  }
  // 默认选用首选路径
  final primary = Directory(candidates.first);
  try {
    if (!primary.existsSync()) {
      primary.createSync(recursive: true);
    }
  } catch (_) {}
  return primary;
}


extension TerminalExt on Terminal {
  void writeProgress(String data) {
    write('\x1b[31m- $data\x1b[0m\n\r');
  }
}

