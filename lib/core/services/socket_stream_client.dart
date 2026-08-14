import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';

/// 前台服务 PTY 转发 Socket 客户端。
///
/// 负责连接前台服务监听的本地 Socket、按行缓冲输出、
/// 剥离历史回放标记（__HIST_START__/__HIST_END__）并在断线后自动重连。
class SocketStreamClient {
  SocketStreamClient({
    required this.port,
    this.onData,
    this.onLine,
  });

  /// 本地监听端口（见 [Ports]）
  final int port;

  /// 每收到一个数据块时回调（标记已剥离），通常用于写入终端
  final void Function(String event)? onData;

  /// 每收到一行完整输出时回调
  final void Function(String line)? onLine;

  Socket? _socket;
  String _lineBuffer = '';
  bool _replaying = false;
  bool _disposed = false;
  Timer? _reconnectTimer;
  StreamSubscription? _subscription;

  bool _isConnecting = false;

  /// 当前是否处于历史缓冲区回放阶段
  bool get isReplaying => _replaying;

  /// 是否已建立连接
  bool get isConnected => _socket != null;

  /// 底层 Socket（供终端输入回写）
  Socket? get socket => _socket;

  /// 开始连接（幂等，重复调用无副作用）
  void connect() {
    if (_disposed || _socket != null) return;
    _connect();
  }

  Future<void> _connect() async {
    if (_disposed || isConnected || _isConnecting) return;
    _isConnecting = true;
    try {
      _socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      if (_disposed) {
        _socket?.destroy();
        _socket = null;
        return;
      }
      _subscription = _socket!
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_onStringChunk, onDone: _handleDisconnect, onError: (_) => _handleDisconnect());
    } catch (_) {
      _handleDisconnect();
    } finally {
      _isConnecting = false;
    }
  }

  void _onStringChunk(String event) {
    if (_disposed) return;

    // [Fix 4.1] 处理历史缓冲区回放标记
    if (event.contains('\x02__HIST_START__\x03')) {
      _replaying = true;
      event = event.replaceAll('\x02__HIST_START__\x03', '');
    }
    if (event.contains('\x02__HIST_END__\x03')) {
      event = event.replaceAll('\x02__HIST_END__\x03', '');
      _replaying = false;
    }
    // Normalize \n to \r\n for raw pipe stdout into xterm terminal
    final normalizedEvent = event.replaceAllMapped(RegExp(r'(?<!\r)\n'), (m) => '\r\n');
    onData?.call(normalizedEvent);

    _lineBuffer += event;
    final lines = _lineBuffer.split('\n');
    _lineBuffer = lines.removeLast();
    for (final line in lines) {
      onLine?.call(line);
    }
  }

  void _handleDisconnect() {
    _lineBuffer = '';
    _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), connect);
  }

  /// 关闭连接并停止自动重连
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
  }
}
