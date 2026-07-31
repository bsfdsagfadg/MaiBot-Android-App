import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:global_repository/global_repository.dart';

import '../utils/file_utils.dart';

/// PTY → Socket 桥接器。
///
/// 在本地端口监听 Socket 连接，将 PTY 输出广播给所有已连接客户端，
/// 并保留最近 [maxBufferLength] 字节的输出，供新连接者回放
/// （以 __HIST_START__ / __HIST_END__ 标记包裹）。
/// PTY 退出后按指数退避自动重启，最多 [maxRestartAttempts] 次。
class PtySocketBridge {
  PtySocketBridge({
    required this.name,
    required this.port,
    required this.command,
    this.pauseRestartCheck,
  });

  /// 组件名称（用于日志）
  final String name;

  /// 本地监听端口
  final int port;

  /// PTY 启动时写入的命令
  final String command;

  /// 返回 true 时暂停自动重启（如重装/清除数据中）
  final bool Function()? pauseRestartCheck;

  static const int maxBufferLength = 70000;
  static const int maxRestartAttempts = 10;

  Pty? _pty;
  ServerSocket? _server;
  final List<Socket> _sockets = [];
  final List<List<int>> _bufferChunks = [];
  int _bufferLength = 0;
  int _restartCount = 0;

  /// 启动 Socket 服务器（幂等）
  Future<void> startServer() async {
    try {
      _server ??= await ServerSocket.bind('127.0.0.1', port, shared: true);
      _server!.listen((socket) {
        _sockets.add(socket);
        if (_bufferChunks.isNotEmpty) {
          socket.add(utf8.encode('\x02__HIST_START__\x03'));
          for (var chunk in _bufferChunks) socket.add(chunk);
          socket.add(utf8.encode('\x02__HIST_END__\x03'));
        }
        socket.listen(
          (data) => _pty?.write(data),
          onDone: () => _sockets.remove(socket),
          onError: (_) => _sockets.remove(socket),
        );
      });
    } catch (e) {
      Log.e('ServerSocket bind error: $e', 'KeepAliveTaskHandler');
    }
  }

  /// 启动 PTY（若已运行则忽略）
  void start() {
    if (_pty != null) return;
    _bufferChunks.clear();
    _bufferLength = 0;
    _pty = createPTY(rows: 25, columns: 80);
    _pty!.output.listen((data) {
      _bufferChunks.add(data);
      _bufferLength += data.length;
      while (_bufferLength > maxBufferLength && _bufferChunks.length > 1) {
        _bufferLength -= _bufferChunks.removeAt(0).length;
      }
      for (var s in _sockets) {
        try {
          s.add(data);
        } catch (_) {}
      }
    }, onDone: () {
      _pty = null;
      _schedulePtyRestart();
    });
    _pty!.writeString(command);
  }

  /// 重置重启计数（组件被显式拉起时调用）
  void resetRestartCount() {
    _restartCount = 0;
  }

  void _schedulePtyRestart() {
    if (pauseRestartCheck?.call() ?? false) {
      Log.i('$name exited, 重装/清除数据中，暂停重启', 'KeepAliveTaskHandler');
      return;
    }
    if (_restartCount >= maxRestartAttempts) {
      Log.e('$name exited, max retries ($maxRestartAttempts) reached. Stopping restarts.',
          'KeepAliveTaskHandler');
      try {
        File('${RuntimeEnvir.tmpPath}/progress_des')
            .writeAsStringSync('组件 $name 连续启动失败，请点按屏幕查看终端日志');
      } catch (e) {
        Log.e('Failed to write error to progress_des: $e', 'KeepAliveTaskHandler');
      }
      return;
    }
    int delay = 3 * (1 << _restartCount);
    if (delay > 60) delay = 60;
    _restartCount++;
    Log.i('$name exited, restarting in ${delay}s (Retry $_restartCount/$maxRestartAttempts)',
        'KeepAliveTaskHandler');
    Future.delayed(Duration(seconds: delay), start);
  }

  /// 关闭 PTY 与所有连接
  void dispose() {
    _sockets.clear();
    _pty?.kill();
    _pty = null;
    _server?.close();
    _server = null;
  }
}
