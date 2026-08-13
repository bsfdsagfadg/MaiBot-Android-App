import 'dart:async';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:xterm/xterm.dart';


/// 终端标签页类型
enum TerminalTabType {
  fixed, // 固定的MaiBot终端（只读、颜色过滤、不可关闭）
  system, // 系统终端（可交互、可关闭）
}

/// 终端标签页数据模型
class TerminalTab {
  final String id;
  final String title;
  final TerminalTabType type;
  final Terminal terminal;
  bool isActive;
  final StreamSubscription? outputSubscription;

  TerminalTab({
    required this.id,
    required this.title,
    required this.type,
    required this.terminal,
    this.isActive = false,
    this.outputSubscription,
  });
}

/// 多终端标签页管理器
class TerminalTabManager extends GetxController {
  // 所有终端标签页列表
  final RxList<TerminalTab> tabs = <TerminalTab>[].obs;

  // 当前激活的标签页索引
  final RxInt activeTabIndex = 0.obs;


  /// 初始化固定的终端标签页
  void initializeFixedTabs(Terminal maibotTerminal, Terminal napcatTerminal) {
    // 清空现有标签页
    tabs.clear();

    // 添加固定的MaiBot终端标签页
    final maibotTab = TerminalTab(
      id: 'fixed_maibot',
      title: 'MaiBot',
      type: TerminalTabType.fixed,
      terminal: maibotTerminal,
      isActive: true,
    );

    // 添加固定的NapCat终端标签页
    final napcatTab = TerminalTab(
      id: 'fixed_napcat',
      title: 'NapCat',
      type: TerminalTabType.fixed,
      terminal: napcatTerminal,
      isActive: false,
    );

    tabs.add(maibotTab);
    tabs.add(napcatTab);
    activeTabIndex.value = 0;
  }


  /// 切换到指定标签页
  void switchToTab(int index) {
    if (index >= 0 && index < tabs.length) {
      // 将所有标签页设为非激活状态
      for (var tab in tabs) {
        tab.isActive = false;
      }

      // 激活指定标签页
      tabs[index].isActive = true;
      activeTabIndex.value = index;

      Log.i('[TerminalTabManager] ${'切换到标签页: ${tabs[index].title} (索引: $index)'}');
    }
  }

  /// 关闭指定标签页
  void closeTab(int index) {
    if (index < 0 || index >= tabs.length) {
      return;
    }

    final tab = tabs[index];

    // 固定标签页不能关闭
    if (tab.type == TerminalTabType.fixed) {
      Get.snackbar('提示', 'MaiBot终端不能关闭');
      return;
    }

    try {
      // 如果有其他需要清理的资源，在这里处理
      tab.outputSubscription?.cancel();
      // 移除标签页
      tabs.removeAt(index);

      // 如果关闭的是当前激活的标签页，切换到前一个标签页
      if (index == activeTabIndex.value) {
        final newIndex = (index > 0) ? index - 1 : 0;
        if (tabs.isNotEmpty) {
          switchToTab(newIndex);
        }
      } else if (index < activeTabIndex.value) {
        // 如果关闭的标签页在当前激活标签页之前，需要更新索引
        activeTabIndex.value = activeTabIndex.value - 1;
      }

      Log.i('[TerminalTabManager] ${'关闭标签页: ${tab.title}'}');
    } catch (e) {
      Log.e('[TerminalTabManager] ${'关闭标签页失败: $e'}');
    }
  }

  /// 获取当前激活的标签页
  TerminalTab? get activeTab {
    if (activeTabIndex.value >= 0 && activeTabIndex.value < tabs.length) {
      return tabs[activeTabIndex.value];
    }
    return null;
  }

  @override
  void onClose() {
    // 清理资源

    // 关闭所有系统终端的PTY
    for (var tab in tabs) {
      if (tab.type == TerminalTabType.system) {
        try {
          tab.outputSubscription?.cancel();
        } catch (e) {
          Log.e('[TerminalTabManager] ${'清理终端资源失败: $e'}');
        }
      }
    }
    tabs.clear();
    super.onClose();
  }
}
