import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:xterm/xterm.dart';

import '../../controllers/home_controller.dart';
import 'terminal_theme.dart';

/// MaiBot 启动加载与初始终端监视页面（正统 Material You / Material 3 风格）
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> with SingleTickerProviderStateMixin {
  final HomeController controller = Get.put(HomeController(), permanent: true);

  // 0: Material You 看板模式, 1: MaiBot 启动终端, 2: NapCat 终端
  int _displayMode = 0;
  DateTime? _lastBackPressTime;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    if (kDebugMode) {
      _displayMode = 1;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _cycleNextMode() {
    setState(() {
      if (_displayMode == 0) {
        _displayMode = 1;
      } else if (_displayMode == 1) {
        if (controller.napcatClient.isConnected) {
          _displayMode = 2;
        } else {
          _displayMode = 0;
        }
      } else {
        _displayMode = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isTerminalVisible = _displayMode != 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_displayMode != 0) {
          setState(() {
            _displayMode = 0;
          });
          return;
        }

        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          Get.snackbar(
            '提示',
            '再次按返回键退出应用',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          );
          return;
        }

        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: isTerminalVisible
            ? getAppTerminalTheme(context).background
            : colorScheme.surface,
        body: SafeArea(
          child: GestureDetector(
            onTap: _cycleNextMode,
            behavior: HitTestBehavior.translucent,
            child: Stack(
              children: [
                // 1. 终端视图层（MaiBot / NapCat 全功能控制台）
                if (isTerminalVisible)
                  Positioned.fill(
                    child: Container(
                      color: getAppTerminalTheme(context).background,
                      child: Column(
                        children: [
                          // 顶栏控制条（深色沉浸式 Tonal 风格）
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1E1E24),
                              border: Border(
                                bottom: BorderSide(
                                  color: Color(0xFF2E2E36),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                SegmentedButton<int>(
                                  segments: [
                                    const ButtonSegment<int>(
                                      value: 0,
                                      icon: Icon(Icons.dashboard_outlined, size: 16),
                                      label: Text('看板'),
                                    ),
                                    const ButtonSegment<int>(
                                      value: 1,
                                      icon: Icon(Icons.smart_toy_outlined, size: 16),
                                      label: Text('MaiBot'),
                                    ),
                                    if (controller.napcatClient.isConnected)
                                      const ButtonSegment<int>(
                                        value: 2,
                                        icon: Icon(Icons.pets_outlined, size: 16),
                                        label: Text('NapCat'),
                                      ),
                                ],
                                selected: {_displayMode},
                                onSelectionChanged: (Set<int> newSelection) {
                                  setState(() {
                                    _displayMode = newSelection.first;
                                  });
                                },
                                style: ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return colorScheme.primaryContainer;
                                    }
                                    return const Color(0xFF282830);
                                  }),
                                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return colorScheme.onPrimaryContainer;
                                    }
                                    return Colors.white70;
                                  }),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.copy_all_rounded, size: 18, color: Colors.white70),
                                tooltip: '复制日志',
                                onPressed: () async {
                                  final activeTerminal = _displayMode == 2
                                      ? controller.napcatShowTerminal
                                      : controller.terminal;
                                  final text = _getTerminalText(activeTerminal);
                                  if (text.isNotEmpty) {
                                    await Clipboard.setData(ClipboardData(text: text));
                                    Get.snackbar(
                                      '已复制',
                                      '${_displayMode == 2 ? 'NapCat' : 'MaiBot'} 终端内容已复制',
                                      snackPosition: SnackPosition.BOTTOM,
                                      duration: const Duration(seconds: 2),
                                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    );
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.cleaning_services_rounded, size: 18, color: Colors.white70),
                                tooltip: '清屏',
                                onPressed: () {
                                  final activeTerminal = _displayMode == 2
                                      ? controller.napcatShowTerminal
                                      : controller.terminal;
                                  activeTerminal.buffer.clear();
                                  activeTerminal.buffer.setCursor(0, 0);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_fullscreen_rounded, size: 18, color: Colors.white70),
                                tooltip: '返回看板',
                                onPressed: () {
                                  setState(() {
                                    _displayMode = 0;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        // 终端渲染视图
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TerminalView(
                              _displayMode == 2
                                  ? controller.napcatShowTerminal
                                  : controller.terminal,
                              readOnly: true,
                              backgroundOpacity: 1,
                              theme: getAppTerminalTheme(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. 形态 0: Material You 核心看板视图
                if (!isTerminalVisible)
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 440),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.06),
                              blurRadius: 36,
                              offset: const Offset(0, 12),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 品牌图标与呼吸光晕
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                final pulseScale = 1.0 + (_pulseController.value * 0.05);
                                return Transform.scale(
                                  scale: pulseScale,
                                  child: child,
                                );
                              },
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      colorScheme.primaryContainer,
                                      colorScheme.primary.withValues(alpha: 0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(26),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colorScheme.primary.withValues(alpha: 0.25),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.smart_toy_rounded,
                                  size: 42,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 标题
                            Text(
                              'MaiBot',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '正在初始化后台运行环境与核心组件',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),

                            // 进度看板容器
                            GetBuilder<HomeController>(
                              builder: (ctrl) {
                                final progressVal = ctrl.progress.clamp(0.0, 1.0);
                                final pct = (progressVal * 100).toInt();
                                final stepText = ctrl.currentProgress.isNotEmpty
                                    ? ctrl.currentProgress.trim()
                                    : '正在准备环境...';

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              stepText,
                                              style: theme.textTheme.titleSmall?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onSurface,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: colorScheme.primaryContainer,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              '$pct%',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onPrimaryContainer,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          value: progressVal > 0 ? progressVal : null,
                                          minHeight: 10,
                                          backgroundColor: colorScheme.surfaceContainerHighest,
                                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 24),

                            // 控制面板与日志切换
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: () {
                                    setState(() {
                                      _displayMode = 1;
                                    });
                                  },
                                  icon: const Icon(Icons.terminal_rounded, size: 18),
                                  label: const Text('MaiBot 日志'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                                if (controller.napcatClient.isConnected) ...[
                                  const SizedBox(width: 12),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _displayMode = 2;
                                      });
                                    },
                                    icon: const Icon(Icons.pets_rounded, size: 18),
                                    label: const Text('NapCat 日志'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getTerminalText(Terminal terminal) {
    final buffer = terminal.buffer;
    final lines = <String>[];
    for (int i = 0; i < buffer.lines.length; i++) {
      lines.add(buffer.lines[i].toString().trimRight());
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n');
  }
}
