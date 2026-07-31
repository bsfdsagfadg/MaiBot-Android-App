import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:global_repository/global_repository.dart';
import 'package:xterm/xterm.dart';

import '../config/app_config.dart';

// 为了获取Apk So库路径，我们需要一个MethodChannel
MethodChannel _channel = const MethodChannel(Config.methodChannel);

/// 获取 Apk So 库路径
/// Gets the path of the Apk So library
Future<String> getLibPath() async {
  return await _channel.invokeMethod('lib_path');
}

Pty createPTY({
  String? shell,
  int rows = 25,
  int columns = 80,
}) {
  Map<String, String> envir = Map.from(Platform.environment);
  envir['HOME'] = RuntimeEnvir.homePath;
  // proot environment setup
  envir['TERMUX_PREFIX'] = RuntimeEnvir.usrPath;
  envir['TERM'] = 'xterm-256color';
  envir['PATH'] = RuntimeEnvir.path;
  // proot deps
  envir['PROOT_LOADER'] = '${RuntimeEnvir.binPath}/loader';
  envir['LD_LIBRARY_PATH'] = RuntimeEnvir.binPath;
  envir['PROOT_TMP_DIR'] = RuntimeEnvir.tmpPath;

  return Pty.start(
    '${RuntimeEnvir.binPath}/${shell ?? 'bash'}',
    arguments: [],
    environment: envir,
    workingDirectory: RuntimeEnvir.homePath,
    rows: rows,
    columns: columns,
  );
}

extension TerminalExt on Terminal {
  void writeProgress(String data) {
    write('\x1b[31m- $data\x1b[0m\n\r');
  }
}

extension PTYExt on Pty {
  void writeString(String data) {
    write(Uint8List.fromList(utf8.encode(data)));
  }
}
