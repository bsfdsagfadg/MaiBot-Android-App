import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';

import '../../../../core/constants/scripts.dart' as scripts;

// 显示自定义 Git Clone 对话框
Future<void> showCustomGitCloneDialog() async {
  final scriptPath = '${scripts.ubuntuPath}/root/maibot-startup.sh';
  final scriptFile = File(scriptPath);

  // 检查脚本文件是否存在
  if (!await scriptFile.exists()) {
    Get.snackbar(
      '提示',
      '启动脚本文件不存在，请先启动一次应用',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
    return;
  }

  // 读取当前的自定义 Git Clone 命令
  String currentCommand = '';
  try {
    final content = await scriptFile.readAsString();
    final match = RegExp(r'^CUSTOM_GIT_CLONE="([^"]*)"$', multiLine: true)
        .firstMatch(content);
    if (match != null) {
      currentCommand = match.group(1) ?? '';
    }
  } catch (e) {
    Get.snackbar(
      '错误',
      '读取启动脚本失败: $e',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
    return;
  }

  // 显示编辑对话框
  final commandController = TextEditingController(text: currentCommand);

  final result = await Get.dialog<bool>(
    AlertDialog(
      title: const Text('自定义 Git Clone 命令'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '自定义克隆命令，以使用 fork 的 MaiBot 仓库；目标目录固定为 MaiBot，不可自定义。\n留空则使用默认逻辑（从镜像源获取官方最新 tag）。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              '示例：\ngit clone https://github.com/MaiM-with-u/MaiBot.git',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: commandController,
              decoration: const InputDecoration(
                labelText: 'Git Clone 命令',
                hintText: '留空使用默认逻辑',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              keyboardType: TextInputType.multiline,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Get.back(result: true),
          child: const Text('保存'),
        ),
      ],
    ),
  );

  if (result == true) {
    final newCommand = commandController.text.trim();

    try {
      String content = await scriptFile.readAsString();

      // 替换 CUSTOM_GIT_CLONE 变量的值
      content = content.replaceFirst(
        RegExp(r'^CUSTOM_GIT_CLONE="[^"]*"$', multiLine: true),
        'CUSTOM_GIT_CLONE="$newCommand"',
      );

      await scriptFile.writeAsString(content);
      Log.i('已更新自定义 Git Clone 命令: $newCommand', 'MaiBot');

      Get.snackbar(
        '保存成功',
        newCommand.isEmpty ? '已清除自定义命令，将使用默认逻辑' : '自定义 Git Clone 命令已保存',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      Get.snackbar(
        '保存失败',
        '写入启动脚本失败: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      Log.e('保存自定义 Git Clone 命令失败: $e', 'MaiBot');
    }
  }

  commandController.dispose();
}
