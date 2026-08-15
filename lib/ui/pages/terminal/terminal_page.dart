import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:xterm/xterm.dart';

import '../../controllers/home_controller.dart';
import 'terminal_theme.dart';

/// MaiBot 启动加载与初始终端监视页面（支持三种形态：看板卡片 / MaiBot 终端 / NapCat 终端）
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final HomeController controller = Get.put(HomeController(), permanent: true);

  // 0: Material You 看板卡片模式, 1: MaiBot 启动/安装终端, 2: NapCat 终端
  int _displayMode = 0;
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _displayMode = 1;
    }
  }

  void _cycleNextMode() {
    setState(() {
      if (_displayMode == 0) {
        // 卡片 -> MaiBot 终端
        _displayMode = 1;
      } else if (_displayMode == 1) {
        // MaiBot 终端 -> NapCat 终端 (若已连接) 或回卡片
        if (controller.napcatClient.isConnected) {
          _displayMode = 2;
        } else {
          _displayMode = 0;
        }
      } else {
        // NapCat 终端 -> 卡片
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
                // 1. 终端视图层（形态 1: MaiBot / 形态 2: NapCat）
                if (isTerminalVisible)
                  Positioned.fill(
                    child: Column(
                      children: [
                        // 顶栏控制条（Material 3 Tonal 风格）
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainer,
                            border: Border(
                              bottom: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // 状态标签指示器
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
                                style: const ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const Spacer(),
                              // 复制按钮
                              IconButton(
                                icon: const Icon(Icons.copy_all_rounded, size: 18),
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
                                      '${_displayMode == 2 ? 'NapCat' : 'MaiBot'} 终端输出已复制',
                                      snackPosition: SnackPosition.BOTTOM,
                                      duration: const Duration(seconds: 2),
                                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    );
                                  }
                                },
                              ),
                              // 清屏按钮
                              IconButton(
                                icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                                tooltip: '清屏',
                                onPressed: () {
                                  final activeTerminal = _displayMode == 2
                                      ? controller.napcatShowTerminal
                                      : controller.terminal;
                                  activeTerminal.buffer.clear();
                                  activeTerminal.buffer.setCursor(0, 0);
                                },
                              ),
                              // 最小化 / 返回看板
                              IconButton(
                                icon: const Icon(Icons.close_fullscreen_rounded, size: 18),
                                tooltip: '返回看板卡片',
                                onPressed: () {
                                  setState(() {
                                    _displayMode = 0;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        // 终端渲染内容
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

                // 2. 形态 0: Material You 启动与进度看板
                if (!isTerminalVisible)
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 品牌图标（圆角容器 + 主题色）
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Icon(
                                Icons.smart_toy_rounded,
                                size: 38,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 标题与副标题
                            Text(
                              'MaiBot',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '正在准备运行环境与初始化组件',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 28),

                            // 动态进度条与当前步骤
                            GetBuilder<HomeController>(
                              builder: (ctrl) {
                                final progressVal = ctrl.progress.clamp(0.0, 1.0);
                                final pct = (progressVal * 100).toInt();
                                final stepText = ctrl.currentProgress.isNotEmpty
                                    ? ctrl.currentProgress.trim()
                                    : '正在初始化...';

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // 步骤名与百分比 Badge
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            stepText,
                                            style: theme.textTheme.labelLarge?.copyWith(
                                              color: colorScheme.onSurface,
                                              fontWeight: FontWeight.w600,
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
                                    const SizedBox(height: 12),

                                    // Material 3 平滑进度条
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: progressVal > 0 ? progressVal : null,
                                        minHeight: 8,
                                        backgroundColor: colorScheme.surfaceContainerHighest,
                                        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 24),

                            // 形态切换按钮组
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
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
