import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';

import '../constants/scripts.dart' as scripts;

/// 备份服务：将 MaiBot 数据打包到手机下载目录
class BackupService {
  /// 执行备份操作
  static Future<bool> performBackup({bool showLoadingDialog = false}) async {
    try {
      // 检查并请求存储权限
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          // 如果 MANAGE_EXTERNAL_STORAGE 未授予，尝试传统的存储权限
          var storageStatus = await Permission.storage.status;
          if (!storageStatus.isGranted) {
            storageStatus = await Permission.storage.request();
            if (!storageStatus.isGranted) {
              Get.snackbar(
                '权限不足',
                '需要存储权限才能备份数据',
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: Colors.orange,
                colorText: Colors.white,
                duration: const Duration(seconds: 3),
              );
              return false;
            }
          }
        }
      }

      // 权限获取成功后，如果需要显示加载对话框
      if (showLoadingDialog) {
        Get.dialog(
          const Center(child: CircularProgressIndicator()),
          barrierDismissible: false,
        );
      }

      // 获取当前时间戳
      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      // 备份文件路径（保存到下载文件夹）
      final backupDir = Directory('/storage/emulated/0/Download/MaiBot');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final backupFileName = 'MaiBot-backup-$timestamp.tar.gz';
      final backupPath = '${backupDir.path}/$backupFileName';

      // 使用 tar 命令压缩 data 目录
      final dataPath = '${scripts.ubuntuPath}/root/MaiBot/data';
      final dataDir = Directory(dataPath);

      if (!await dataDir.exists()) {
        Get.snackbar(
          '备份失败',
          'MaiBot 数据目录不存在',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return false;
      }

      // 确保备份的其他目标文件夹都存在，避免 tar 报错
      final List<String> pathsToCreate = [
        '${scripts.ubuntuPath}/root/MaiBot/config',
        '${scripts.ubuntuPath}/root/MaiBot/plugins',
        '${scripts.ubuntuPath}/root/napcat/config',
      ];
      for (final path in pathsToCreate) {
        final dir = Directory(path);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }

      // 执行备份命令，工作目录设为 /root
      final result = await Process.run('${RuntimeEnvir.binPath}/busybox', [
        'tar',
        '-czf',
        backupPath,
        '--exclude=MaiBot/plugins/hello_world_plugin',
        '-C',
        '${scripts.ubuntuPath}/root',
        'MaiBot/data',
        'MaiBot/config',
        'MaiBot/plugins',
        'napcat/config',
      ]);

      if (result.exitCode == 0) {
        final backupFile = File(backupPath);
        final fileSize = await backupFile.length();
        final fileSizeMB = (fileSize / 1024 / 1024).toStringAsFixed(2);

        if (showLoadingDialog) {
          Get.back(); // 关闭加载对话框
        }

        Get.snackbar(
          '备份成功',
          '备份文件: $backupFileName\n大小: ${fileSizeMB}MB',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3),
        );
        Log.i('备份成功: $backupPath (${fileSizeMB}MB)', 'MaiBot');
        return true;
      } else {
        if (showLoadingDialog) {
          Get.back(); // 关闭加载对话框
        }

        Get.snackbar(
          '备份失败',
          '错误: ${result.stderr}',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        Log.e('备份失败: ${result.stderr}', 'MaiBot');
        return false;
      }
    } catch (e) {
      if (showLoadingDialog) {
        Get.back(); // 关闭加载对话框
      }

      Get.snackbar(
        '备份失败',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      Log.e('备份异常: $e', 'MaiBot');
      return false;
    }
  }
}
