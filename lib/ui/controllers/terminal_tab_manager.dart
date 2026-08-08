import 'dart:async';
import 'dart:convert';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:xterm/xterm.dart';

import '../../core/utils/file_utils.dart';

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
  final Pty? pty;
  bool isActive;
  final StreamSubscription? outputSubscription;

  TerminalTab({
    required this.id,
    required this.title,
    required this.type,
    required this.terminal,
    this.pty,
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

  // 未注册的挂起系统终端 PTY 列表，防止提前销毁或流中断泄露
  final Set<Pty> _pendingPtys = {};

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
      pty: null, // 固定终端使用外部管理的 pseudoTerminal
      isActive: true,
    );

    // 添加固定的NapCat终端标签页
    final napcatTab = TerminalTab(
      id: 'fixed_napcat',
      title: 'NapCat',
      type: TerminalTabType.fixed,
      terminal: napcatTerminal,
      pty: null, // 固定终端使用外部管理的 napcatTerminal
      isActive: false,
    );

    tabs.add(maibotTab);
    tabs.add(napcatTab);
    activeTabIndex.value = 0;
  }

  /// 添加新的系统终端标签页
  Future<void> addSystemTerminalTab() async {
    try {
      final newIndex =
          tabs.where((t) => t.type == TerminalTabType.system).length + 1;
      final tabId = 'system_${DateTime.now().millisecondsSinceEpoch}';

      // 创建新的终端实例
      final newTerminal = Terminal(
        maxLines: 10000,
      );

      // 创建新的PTY实例
      final newPty = createPTY(
        rows: newTerminal.viewHeight,
        columns: newTerminal.viewWidth,
      );
      _pendingPtys.add(newPty);
      // 标志：是否已经创建了标签页
      var tabCreated = false;
      final StringBuffer preLoginBuffer = StringBuffer();

      void createTabAndFlush(StreamSubscription subscription) {
        if (tabCreated) return;
        tabCreated = true;
        _pendingPtys.remove(newPty);
        
        final newTab = TerminalTab(
          id: tabId,
          title: '终端 $newIndex',
          type: TerminalTabType.system,
          terminal: newTerminal,
          pty: newPty,
          isActive: false,
          outputSubscription: subscription,
        );

        for (var tab in tabs) {
          tab.isActive = false;
        }

        tabs.add(newTab);
        newTab.isActive = true;
        activeTabIndex.value = tabs.length - 1;

        Log.i('添加新系统终端标签页: ${newTab.title} (ID: ${newTab.id})', 'TerminalTabManager');
      }

      // 连接终端的 onResize 和 onOutput 事件（需要在监听输出前就连接好）
      newTerminal.onResize = (width, height, pixelWidth, pixelHeight) {
        newPty.resize(height, width);
      };

      newTerminal.onOutput = (data) {
        newPty.writeString(data);
      };

      // 声明订阅变量以便稍后传入
      StreamSubscription? subscription;

      // 兜底定时器：如果3秒后还没匹配到标识符（例如环境错误或非标准hostname），依然创建标签页展示错误日志
      Future.delayed(const Duration(seconds: 3), () {
        if (!tabCreated && subscription != null) {
          createTabAndFlush(subscription);
          newTerminal.write(preLoginBuffer.toString());
        }
      });

      // 监听PTY输出，等待登录完成后再创建标签页
      subscription = newPty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((event) {
        if (!tabCreated) {
          preLoginBuffer.write(event);
          if (preLoginBuffer.toString().contains('---TERM_READY---') && subscription != null) {
            createTabAndFlush(subscription);
            // 仅输出标记之后的内容，避免显示前面的 source common.sh 等初始化指令
            final parts = preLoginBuffer.toString().split('---TERM_READY---');
            if (parts.length > 1 && parts.last.isNotEmpty) {
              newTerminal.write(parts.last.replaceFirst(RegExp(r'^\r?\n'), ''));
            }
          }
        } else {
          newTerminal.write(event);
        }
      });

      // 登录到ubuntu容器，使用明确的回显标记而非依赖不可靠的 root@localhost 提示符
      final command =
          'source ${RuntimeEnvir.homePath}/common.sh\nlogin_ubuntu "echo ---TERM_READY---; exec bash" \n';
      newPty.writeString(command);
    } catch (e) {
      Log.e('添加系统终端标签页失败: $e', 'TerminalTabManager');
      Get.snackbar('错误', '创建终端失败: $e');
    }
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

      Log.i('切换到标签页: ${tabs[index].title} (索引: $index)', 'TerminalTabManager');
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
      // 关闭PTY
      if (tab.pty != null) {
        tab.pty!.kill();
        tab.outputSubscription?.cancel();
        Log.i('关闭终端PTY: ${tab.title}', 'TerminalTabManager');
      }

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

      Log.i('关闭标签页: ${tab.title}', 'TerminalTabManager');
    } catch (e) {
      Log.e('关闭标签页失败: $e', 'TerminalTabManager');
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
    // 清理未注册的挂起 PTY
    for (final pty in _pendingPtys) {
      try {
        pty.kill();
        Log.i('清理未就绪系统终端 PTY', 'TerminalTabManager');
      } catch (e) {
        Log.e('清理未就绪 PTY 失败: $e', 'TerminalTabManager');
      }
    }
    _pendingPtys.clear();

    // 关闭所有系统终端的PTY
    for (var tab in tabs) {
      if (tab.type == TerminalTabType.system && tab.pty != null) {
        try {
          tab.pty!.kill();
          tab.outputSubscription?.cancel();
          Log.i('清理终端PTY: ${tab.title}', 'TerminalTabManager');
        } catch (e) {
          Log.e('清理终端PTY失败: $e', 'TerminalTabManager');
        }
      }
    }
    tabs.clear();
    super.onClose();
  }
}
