import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xterm/xterm.dart';

import '../../controllers/home_controller.dart';
import '../../controllers/terminal_tab_manager.dart';
import 'terminal_theme.dart';

/// 终端标签页视图
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
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFF21252B),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
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
            icon: const Icon(Icons.cleaning_services_rounded, size: 18, color: Colors.white70),
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

  /// 构建单个标签页项
  Widget _buildTabItem({
    required TerminalTab tab,
    required bool isActive,
    required VoidCallback onTap,
    VoidCallback? onClose,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
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
              color: isActive
                  ? const Color(0xFF61AFEF)
                  : Colors.white54,
            ),
            const SizedBox(width: 6),

            // 标签页标题
            Flexible(
              child: Text(
                tab.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive
                      ? Colors.white
                      : Colors.white60,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 关闭按钮（只有系统终端才显示）
            if (onClose != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white54,
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
        readOnly: tab.type == TerminalTabType.fixed, // 固定终端只读
        backgroundOpacity: 1,
        theme: const ManjaroTerminalTheme(),
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
