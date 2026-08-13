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


extension TerminalExt on Terminal {
  void writeProgress(String data) {
    write('\x1b[31m- $data\x1b[0m\n\r');
  }
}

