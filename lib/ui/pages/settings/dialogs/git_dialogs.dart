import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/services/foreground_service.dart';
import '../../../../core/services/git_service.dart';

/// 统一执行 Git 操作并展示流式日志的弹窗
Future<bool> _runGitTaskWithProgressDialog({
  required String title,
  required Future<ProotExecResult> Function(Function(String) onLog) task,
}) async {
  final logs = <String>[].obs;
  final isDone = false.obs;
  final isSuccess = false.obs;
  final scrollController = ScrollController();

  void appendLog(String text) {
    logs.add(text);
    if (scrollController.hasClients) {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  // 启动后台任务
  Future<void> execute() async {
    try {
      final res = await task(appendLog);
      isSuccess.value = res.success;
      if (res.success) {
        appendLog('\n✅ 操作成功完成！');
      } else {
        appendLog('\n❌ 执行失败 (Exit code: ${res.exitCode})\n${res.stderr}');
      }
    } catch (e) {
      isSuccess.value = false;
      appendLog('\n❌ 任务发生异常: $e');
    } finally {
      isDone.value = true;
    }
  }

  execute();

  final result = await Get.dialog<bool>(
    Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return PopScope(
          canPop: false,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Obx(() {
                          if (!isDone.value) {
                            return const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            );
                          }
                          return Icon(
                            isSuccess.value ? Icons.check_circle_rounded : Icons.error_rounded,
                            color: isSuccess.value ? Colors.green : Colors.red,
                            size: 24,
                          );
                        }),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Obx(
                          () => SingleChildScrollView(
                            controller: scrollController,
                            child: SelectableText(
                              logs.isEmpty ? '正在准备运行环境...' : logs.join(''),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Obx(() {
                      if (!isDone.value) {
                        return const SizedBox(
                          width: double.infinity,
                          child: Center(
                            child: Text(
                              '正在执行，请勿关闭应用...',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        );
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Get.back(result: isSuccess.value),
                            child: const Text('关闭'),
                          ),
                          if (isSuccess.value) ...[
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () async {
                                Get.back(result: true);
                                await ForegroundServiceManager.restartContainer();
                                Get.snackbar(
                                  '重启容器',
                                  '正在重启 MaiBot 服务以应用更新',
                                  snackPosition: SnackPosition.BOTTOM,
                                );
                              },
                              icon: const Icon(Icons.restart_alt_rounded, size: 18),
                              label: const Text('重启容器以生效'),
                            ),
                          ],
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
    barrierDismissible: false,
  );

  return result ?? false;
}

/// 弹出更新 MaiBot 对话框 (git pull)
Future<void> showUpdateMaiBotDialog() async {
  if (!GitService.isMaiBotGitRepo()) {
    Get.snackbar(
      '提示',
      '未检测到 MaiBot Git 仓库，请先完成初始安装',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
    );
    return;
  }

  final confirm = await Get.dialog<bool>(
    AlertDialog(
      icon: const Icon(Icons.cloud_sync_rounded, size: 28, color: Colors.blue),
      title: const Text('更新 MaiBot'),
      content: const Text(
        '将执行 git pull 拉取当前分支的最新提交，并自动同步更新 Python 依赖库。\n\n'
        '数据目录已在 .gitignore 中忽略，更新不会影响您的本地配置与数据。\n\n'
        '确定要检查并更新吗？',
        style: TextStyle(fontSize: 13, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Get.back(result: true),
          child: const Text('开始更新'),
        ),
      ],
    ),
  );

  if (confirm == true) {
    await _runGitTaskWithProgressDialog(
      title: '更新 MaiBot',
      task: (onLog) => GitService.pullMaiBot(onLog: onLog),
    );
  }
}

/// 弹出切换分支对话框 (动态解析远程与本地分支，兼容自定义仓库)
Future<void> showSwitchBranchDialog() async {
  if (!GitService.isMaiBotGitRepo()) {
    Get.snackbar(
      '提示',
      '未检测到 MaiBot Git 仓库',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
    );
    return;
  }

  // 1. 显示加载分支中提示
  Get.dialog(
    const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在查询远程分支列表...', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ),
    ),
    barrierDismissible: false,
  );

  String currentRef = 'main';
  List<String> branches = [];
  try {
    currentRef = await GitService.getCurrentRef();
    branches = await GitService.getAvailableBranches();
  } catch (e) {
    Get.back();
    Get.snackbar('查询失败', '无法拉取分支信息: $e', snackPosition: SnackPosition.BOTTOM);
    return;
  }
  Get.back(); // 关闭加载框

  if (branches.isEmpty) {
    branches = ['main', 'master', 'dev'];
  }

  String selectedBranch = branches.contains(currentRef) ? currentRef : branches.first;
  final customBranchController = TextEditingController();

  final choice = await Get.dialog<String>(
    StatefulBuilder(
      builder: (context, setState) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return AlertDialog(
          icon: const Icon(Icons.alt_route_rounded, size: 28, color: Colors.teal),
          title: const Text('切换 MaiBot 分支'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '当前处于: $currentRef',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '从当前 Git 远程仓库动态获取，兼容自定义 Fork 仓库。切换分支后将自动同步依赖：',
                    style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  ...branches.map((branch) {
                    final isCurrent = branch == currentRef;
                    final isSelected = branch == selectedBranch;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      title: Text(
                        branch + (isCurrent ? ' (当前)' : ''),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          selectedBranch = branch;
                          customBranchController.clear();
                        });
                      },
                    );
                  }),
                  const SizedBox(height: 8),
                  TextField(
                    controller: customBranchController,
                    decoration: const InputDecoration(
                      labelText: '或输入其他分支名',
                      hintText: '例如: feat/new-adapter',
                      prefixIcon: Icon(Icons.edit_road_rounded, size: 20),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      if (val.trim().isNotEmpty) {
                        setState(() {
                          selectedBranch = val.trim();
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final target = customBranchController.text.trim().isNotEmpty
                    ? customBranchController.text.trim()
                    : selectedBranch;
                Get.back(result: target);
              },
              child: const Text('确定切换'),
            ),
          ],
        );
      },
    ),
  );

  if (choice != null && choice.isNotEmpty) {
    await _runGitTaskWithProgressDialog(
      title: '切换分支: $choice',
      task: (onLog) => GitService.switchBranch(choice, onLog: onLog),
    );
  }
}

/// 弹出切换 Release 版本对话框 (按 Tags 切换，注明与分支互斥)
Future<void> showSwitchReleaseTagDialog() async {
  if (!GitService.isMaiBotGitRepo()) {
    Get.snackbar(
      '提示',
      '未检测到 MaiBot Git 仓库',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
    );
    return;
  }

  // 1. 显示加载 Tags 中提示
  Get.dialog(
    const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在获取 Release 版本列表...', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ),
    ),
    barrierDismissible: false,
  );

  String currentRef = '';
  List<String> tags = [];
  try {
    currentRef = await GitService.getCurrentRef();
    tags = await GitService.getReleaseTags();
  } catch (e) {
    Get.back();
    Get.snackbar('查询失败', '无法拉取版本信息: $e', snackPosition: SnackPosition.BOTTOM);
    return;
  }
  Get.back(); // 关闭加载框

  if (tags.isEmpty) {
    Get.snackbar(
      '提示',
      '当前仓库未检索到任何 Release Tag 标签',
      snackPosition: SnackPosition.BOTTOM,
    );
    return;
  }

  String selectedTag = tags.first;

  final choice = await Get.dialog<String>(
    StatefulBuilder(
      builder: (context, setState) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return AlertDialog(
          icon: const Icon(Icons.sell_rounded, size: 28, color: Colors.purple),
          title: const Text('切换 MaiBot Release 版本'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '提示：版本切换通过检出 Release Tag 实现，与分支切换互斥（会相互覆盖当前检出状态）。当前状态: $currentRef',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurface,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '选择要检出的 Release 版本（按版本号降序）：',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  ...tags.map((tag) {
                    final isCurrent = tag == currentRef;
                    final isSelected = tag == selectedTag;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      title: Text(
                        tag + (isCurrent ? ' (当前)' : ''),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          selectedTag = tag;
                        });
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Get.back(result: selectedTag),
              child: const Text('确定检出'),
            ),
          ],
        );
      },
    ),
  );

  if (choice != null && choice.isNotEmpty) {
    await _runGitTaskWithProgressDialog(
      title: '检出版本: $choice',
      task: (onLog) => GitService.switchReleaseTag(choice, onLog: onLog),
    );
  }
}
