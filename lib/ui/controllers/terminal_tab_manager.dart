import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:xterm/xterm.dart';

import '../../../core/constants/scripts.dart' as scripts;

/// 终端标签页类型
enum TerminalTabType {
  fixed, // 固定的MaiBot/NapCat终端（只读）
  system, // 自定义交互终端（可写、可交互、可关闭）
}

/// 终端标签页数据模型
class TerminalTab {
  final String id;
  final String title;
  final TerminalTabType type;
  final Terminal terminal;
  bool isActive;
  final StreamSubscription? outputSubscription;
  final Process? process;

  TerminalTab({
    required this.id,
    required this.title,
    required this.type,
    required this.terminal,
    this.isActive = false,
    this.outputSubscription,
    this.process,
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

      Log.i('切换到标签页: ${tabs[index].title} (索引: $index)', tag: 'TerminalTabManager');
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
      tab.outputSubscription?.cancel();
      tab.process?.kill(ProcessSignal.sigkill);
      tabs.removeAt(index);

      if (index == activeTabIndex.value) {
        final newIndex = (index > 0) ? index - 1 : 0;
        if (tabs.isNotEmpty) {
          switchToTab(newIndex);
        }
      } else if (index < activeTabIndex.value) {
        activeTabIndex.value = activeTabIndex.value - 1;
      }

      Log.i('关闭标签页: ${tab.title}', tag: 'TerminalTabManager');
    } catch (e) {
      Log.e('关闭标签页失败: $e', tag: 'TerminalTabManager');
    }
  }

  /// 创建新的系统交互终端
  Future<void> createNewSystemTab() async {
    final newId = 'system_${DateTime.now().millisecondsSinceEpoch}';
    final newTitle = '终端 ${tabs.length + 1}';
    final newTerminal = Terminal(maxLines: 5000);
    final prootPath = '${RuntimeEnvir.binPath}/proot';
    Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);
    final args = [
      '-0', '-r', scripts.ubuntuPath,
      '--link2symlink',
      '-b', '/dev', '-b', '/proc', '-b', '/sys',
      '-b', '${RuntimeEnvir.tmpPath}:/tmp',
      '-b', '${RuntimeEnvir.tmpPath}:/dev/shm',
      '-w', '/root',
      '/bin/bash', '-l'
    ];
    final env = {
      'PROOT_TMP_DIR': RuntimeEnvir.tmpPath,
      'LD_LIBRARY_PATH': RuntimeEnvir.binPath,
      'PROOT_LOADER': '${RuntimeEnvir.binPath}/loader',
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
      'FORCE_COLOR': '1',
      'CLICOLOR_FORCE': '1',
      'CLICOLOR': '1',
      'PYTHONUNBUFFERED': '1',
      'PYTHONIOENCODING': 'utf-8',
      'PYTHON_COLORS': '1',
      'RICH_FORCE_COLOR': '1',
      'LOGURU_COLORIZE': 'true',
      'UV_COLOR': 'always',
      'UV_PROGRESS_MODE': 'visual',
      'UV_NO_PROGRESS': '0',
      'UV_INDEX_URL': 'https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple',
      'PIP_NO_COLOR': '0',
      'COLUMNS': '100',
      'LINES': '30',
      'LANG': 'C.UTF-8',
      'LC_ALL': 'C.UTF-8',
      'TMPDIR': '/tmp',
      'TEMP': '/tmp',
      'TMP': '/tmp',
    };
    try {
      final process = await Process.start(prootPath, args, environment: env);

      newTerminal.onOutput = (data) {
        process.stdin.add(utf8.encode(data));
      };

      final sub = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
        newTerminal.write(data.replaceAllMapped(RegExp(r'(?<!\r)\n'), (m) => '\r\n'));
      });
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
        newTerminal.write(data.replaceAllMapped(RegExp(r'(?<!\r)\n'), (m) => '\r\n'));
      });

      process.exitCode.then((_) {
        // 自动提示
      });

      final newTab = TerminalTab(
        id: newId,
        title: newTitle,
        type: TerminalTabType.system,
        terminal: newTerminal,
        isActive: false,
        outputSubscription: sub,
        process: process,
      );

      tabs.add(newTab);
      switchToTab(tabs.length - 1);
    } catch (e) {
      Log.e('创建系统终端失败: $e', tag: 'TerminalTabManager');
      Get.snackbar('创建失败', '无法拉起交互终端: $e', snackPosition: SnackPosition.BOTTOM);
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

    // 关闭所有系统终端的进程与订阅
    for (var tab in tabs) {
      if (tab.type == TerminalTabType.system) {
        try {
          tab.outputSubscription?.cancel();
          tab.process?.kill(ProcessSignal.sigkill);
        } catch (e) {
          Log.e('清理终端资源失败: $e', tag: 'TerminalTabManager');
        }
      }
    }
    super.onClose();
  }
}
