import 'dart:async';
import 'dart:io';

import 'package:global_repository/global_repository.dart';
import 'package:xterm/xterm.dart';

import '../../generated/l10n.dart';

/// 安装进度跟踪器。
///
/// 负责监听前台服务写入的 progress / progress_des 文件，
/// 维护 [progress] 与 [currentProgress]，并通过 [onChanged] 通知 UI 刷新。
/// 针对部分 Android OEM (MIUI/HarmonyOS) inotify 事件丢失，
/// 额外提供 1 秒轮询兜底（[Fix 5.2]）。
class ProgressTracker {
  ProgressTracker({required this.onChanged});

  /// 进度变化时回调（通常为 GetX 的 update）
  final void Function() onChanged;

  final File progressFile = File('${RuntimeEnvir.tmpPath}/progress');
  final File progressDesFile = File('${RuntimeEnvir.tmpPath}/progress_des');

  /// 总安装步骤数
  final double step = 14.0;

  double progress = 0.0;
  String currentProgress = '';

  /// 需要被写入进度/清屏的终端（由控制器注入）
  Terminal? terminal;

  Future<void> _bumpLock = Future.value();
  StreamSubscription? _progressSubscription;
  StreamSubscription? _progressDesSubscription;
  Timer? _pollTimer;

  /// 进度 +1（通过锁串行化，避免并发写文件）
  Future<void> bump() async {
    _bumpLock = _bumpLock.then((_) async {
      try {
        int current = 0;
        if (await progressFile.exists()) {
          final content = (await progressFile.readAsString()).trim();
          if (content.isNotEmpty) {
            current = int.tryParse(content) ?? 0;
          }
        } else {
          await progressFile.create(recursive: true);
        }
        await progressFile.writeAsString('${current + 1}');
      } catch (e) {
        await progressFile.writeAsString('1');
      }
      onChanged();
    }).catchError((_) {});
    return _bumpLock;
  }

  /// 同步当前进度：重置进度文件并监听其变化
  Future<void> startWatching() async {
    await progressFile.create(recursive: true);
    await progressFile.writeAsString('0');
    _progressSubscription = progressFile
        .watch(events: FileSystemEvent.all)
        .listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressFile.readAsString();
        Log.e('content -> $content');
        if (content.isEmpty) {
          return;
        }
        progress = int.parse(content) / step;
        Log.e('progress -> $progress');
        onChanged();
      }
    });
    await progressDesFile.create(recursive: true);
    await progressDesFile.writeAsString('');
    _progressDesSubscription = progressDesFile
        .watch(events: FileSystemEvent.all)
        .listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressDesFile.readAsString();
        if (currentProgress == content) return;
        currentProgress = content;
        if (content.contains('Napcat ${S.current.installed}')) {
          await bump();
        }

        // 当进度到达 "MaiBot Core 配置中" 时，清除终端
        if (content.trim().contains('MaiBot Core 配置中')) {
          terminal?.buffer.clear();
          terminal?.buffer.setCursor(0, 0);
          Log.i('检测到 MaiBot Core 配置中，清除终端内容', 'MaiBot');
        }

        onChanged();
      }
    });

    // [Fix 5.2] 部分 Android OEM 系统 inotify 事件丢失，添加 1 秒轮询兜底
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        if (await progressFile.exists()) {
          String content = (await progressFile.readAsString()).trim();
          if (content.isNotEmpty) {
            double p = (int.tryParse(content) ?? 0) / step;
            if (progress != p) {
              progress = p;
              onChanged();
            }
          }
        }
        if (await progressDesFile.exists()) {
          String content = await progressDesFile.readAsString();
          if (currentProgress != content) {
            currentProgress = content;
            if (content.contains('Napcat ${S.current.installed}')) {
              await bump();
            }
            if (content.trim().contains('MaiBot Core 配置中')) {
              terminal?.buffer.clear();
              terminal?.buffer.setCursor(0, 0);
            }
            onChanged();
          }
        }
      } catch (_) {}
    });
  }

  /// 设置当前进度描述并写入终端
  void setProgress(String description) {
    currentProgress = description;
    terminal?.writeProgress(currentProgress);
  }

  /// 停止监听并释放资源
  void dispose() {
    _progressSubscription?.cancel();
    _progressDesSubscription?.cancel();
    _pollTimer?.cancel();
  }
}
