import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:xterm/xterm.dart';

import '../../../core/utils/file_utils.dart';
import '../../controllers/home_controller.dart';
import '../../controllers/terminal_tab_manager.dart';
import 'terminal_theme.dart';
class TerminalTabView extends StatefulWidget {
  const TerminalTabView({super.key});

  @override
  State<TerminalTabView> createState() => _TerminalTabViewState();
}

class _TerminalTabViewState extends State<TerminalTabView> {
  final HomeController homeController = Get.find<HomeController>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final manager = homeController.terminalTabManager;
      final tabs = manager.tabs;
      final activeIndex = manager.activeTabIndex.value;

      if (tabs.isEmpty) {
        return const Center(
          child: Text('暂无终端'),
        );
      }

      return Column(
        children: [
          // 标签页头部
          _buildTabBar(tabs, activeIndex, manager),

          // 终端内容区域
          Expanded(
            child: IndexedStack(
              index: activeIndex,
              children: tabs.map((tab) {
                return _buildTerminalContent(tab);
              }).toList(),
            ),
          ),
        ],
      );
    });
  }

  /// 构建标签页栏
  Widget _buildTabBar(
    List<TerminalTab> tabs,
    int activeIndex,
    TerminalTabManager manager,
  ) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 标签页列表（可滚动）
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                return _buildTabItem(
                  tab: tabs[index],
                  isActive: index == activeIndex,
                  onTap: () => manager.switchToTab(index),
                  onClose: tabs[index].type == TerminalTabType.system
                      ? () => _showCloseConfirmDialog(index, manager)
                      : null,
                );
              },
            ),
          ),
          IconButton(
            icon: Icon(Icons.add_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
            tooltip: '新建终端',
            onPressed: () => manager.createNewSystemTab(),
          ),
          IconButton(
            icon: Icon(Icons.copy_all_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            tooltip: '复制终端内容',
            onPressed: () async {
              final activeTab = manager.activeTab;
              if (activeTab != null) {
                final text = _getTerminalText(activeTab.terminal);
                if (text.isNotEmpty) {
                  await Clipboard.setData(ClipboardData(text: text));
                  Get.snackbar(
                    '已复制',
                    '${activeTab.title} 终端内容已复制到剪贴板',
                    snackPosition: SnackPosition.BOTTOM,
                    duration: const Duration(seconds: 2),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  );
                } else {
                  Get.snackbar(
                    '提示',
                    '当前终端无内容',
                    snackPosition: SnackPosition.BOTTOM,
                    duration: const Duration(seconds: 2),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.save_alt_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            tooltip: '保存日志文件',
            onPressed: () async {
              final activeTab = manager.activeTab;
              if (activeTab != null) {
                final text = _getTerminalText(activeTab.terminal);
                try {
                  final dir = getMaiBotBackupDirectory();
                  final now = DateTime.now();
                  final timestamp =
                      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
                  final logFile = File('${dir.path}/terminal_${activeTab.id}_$timestamp.log');
                  await logFile.writeAsString(text);
                  Get.snackbar(
                    '保存成功',
                    '日志已导出至: ${logFile.path}',
                    snackPosition: SnackPosition.BOTTOM,
                    duration: const Duration(seconds: 3),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  );
                } catch (e) {
                  Get.snackbar(
                    '保存失败',
                    '写入日志文件异常: $e',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                    duration: const Duration(seconds: 3),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.cleaning_services_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            tooltip: '清屏',
            onPressed: () {
              final activeTab = manager.activeTab;
              if (activeTab != null) {
                activeTab.terminal.buffer.clear();
                activeTab.terminal.buffer.setCursor(0, 0);
              }
            },
          ),
        ],
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

  /// 构建单个标签页项
  Widget _buildTabItem({
    required TerminalTab tab,
    required bool isActive,
    required VoidCallback onTap,
    VoidCallback? onClose,
  }) {
    final theme = Theme.of(context);
    final activeBg = theme.colorScheme.secondaryContainer;
    final activeFg = theme.colorScheme.onSecondaryContainer;
    final inactiveFg = theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: isActive ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标签页图标
            Icon(
              tab.type == TerminalTabType.fixed
                  ? Icons.lock_outline_rounded
                  : Icons.terminal_rounded,
              size: 14,
              color: isActive ? activeFg : inactiveFg,
            ),
            const SizedBox(width: 6),

            // 标签页标题
            Flexible(
              child: Text(
                tab.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? activeFg : inactiveFg,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 关闭按钮（只有系统终端才显示）
            if (onClose != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: isActive ? activeFg : inactiveFg,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建终端内容
  Widget _buildTerminalContent(TerminalTab tab) {
    return ClipRect(
      child: TerminalView(
        tab.terminal,
        readOnly: tab.type == TerminalTabType.fixed, // 默认与固定终端只读，仅新建终端可写交互
        backgroundOpacity: 1,
        theme: getAppTerminalTheme(context),
      ),
    );
  }


  /// 显示关闭确认对话框
  void _showCloseConfirmDialog(int index, TerminalTabManager manager) {
    Get.dialog(
      AlertDialog(
        title: const Text('确认关闭'),
        content: const Text('确定要关闭这个终端吗？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              manager.closeTab(index);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
