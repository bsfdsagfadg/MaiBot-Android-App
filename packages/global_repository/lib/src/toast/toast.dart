// toast.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:global_repository/src/screen_adaptor/view_metric.dart';
import 'package:global_repository/src/widgets/safearea_fix.dart';

/// 显示一个 Toast
/// 在之前的版本中，是通过往 MaterialApp 上包一个 ToastOverlayHost 来实现的
/// ToastOverlayHost 是一个 StatefulWidget，内部维护了一个 OverlayEntry 的列表，initState 时会初始化全局的 OverlayState
/// 后续的 Toast.show 方法会通过全局的 OverlayState 来插入 OverlayEntry
///
/// TODO TODO
void showToast(
  String message, {
  Duration duration = const Duration(milliseconds: 1000),
}) {
  Toast.show(
    message,
    duration: duration,
  );
}

class Toast {
  static OverlayEntry? _current;

  static void showPre(
    String message, {
    Duration duration = const Duration(milliseconds: 1000),
  }) {
    final overlay = ToastOverlayHost.overlay;
    if (overlay == null) {
      throw FlutterError('ToastOverlayHost not mounted');
    }

    final entry = ToastEntry(message: message).build();

    overlay.insert(entry);

    Future.delayed(duration).then((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        entry.remove();
      });
    });
  }

  static void show(
    String message, {
    Duration duration = const Duration(milliseconds: 1000),
  }) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final overlay = _rootOverlay;
      if (overlay == null) return;

      _current?.remove();

      final entry = ToastEntry(message: message).build();
      _current = entry;

      overlay.insert(entry);

      Future.delayed(duration).then((_) {
        Future.delayed(const Duration(milliseconds: 800), () {
          entry.remove();
          if (_current == entry) {
            _current = null;
          }
        });
      });
    });
  }

  static OverlayState? get _rootOverlay {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;

    OverlayState? overlay;

    void visitor(Element element) {
      if (element is StatefulElement && element.state is OverlayState) {
        overlay = element.state as OverlayState;
        return;
      }
      element.visitChildElements(visitor);
    }

    root.visitChildElements(visitor);
    return overlay;
  }
}

class ToastEntry {
  ToastEntry({required this.message});

  final String message;

  OverlayEntry build() {
    return OverlayEntry(
      builder: (context) {
        final width = MediaQuery.of(context).size.width;
        return Positioned(
          bottom: context.w(64),
          width: width,
          child: SafeAreaFix(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(context.w(12)),
                child: Material(
                  color: const Color(0xff303030),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.w(16),
                      vertical: context.w(8),
                    ),
                    child: Text(
                      message,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: context.w(16),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ToastOverlayHost extends StatefulWidget {
  const ToastOverlayHost({super.key, required this.child});

  final Widget child;

  static OverlayState? overlay;

  @override
  State<ToastOverlayHost> createState() => _ToastOverlayHostState();
}

class _ToastOverlayHostState extends State<ToastOverlayHost> {
  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (ctx) {
            // ctx 位于 Overlay 子树内，Overlay.of(ctx) 能找到这个 Overlay 自身
            ToastOverlayHost.overlay ??= Overlay.of(ctx);
            return widget.child;
          },
        ),
      ],
    );
  }
}

// class ToastApp extends StatefulWidget {
//   const ToastApp({Key? key, this.child}) : super(key: key);
//   final Widget? child;

//   @override
//   _ToastAppState createState() => _ToastAppState();
// }

// class _ToastAppState extends State<ToastApp> {
//   @override
//   Widget build(BuildContext context) {
//     var overlay = Overlay(
//       initialEntries: [
//         OverlayEntry(
//           builder: (BuildContext ctx) {
//             contexts.add(ctx);
//             return widget.child!;
//           },
//         ),
//       ],
//     );
//     return Directionality(
//       child: MediaQuery(
//         data: MediaQuery.of(context),
//         child: Localizations(
//           locale: const Locale('en', 'US'),
//           delegates: _localizationsDelegates.toList(),
//           child: overlay,
//         ),
//       ),
//       textDirection: TextDirection.ltr,
//     );
//   }
// }
