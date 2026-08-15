import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';

import '../../../core/constants/scripts.dart' as scripts;
import '../../../core/services/backup_service.dart';
import '../../../core/services/foreground_service.dart';

/// 设置页中的破坏性维护操作（重装/清除/退出）。
/// 均为独立于页面状态的静态流程，统一在此收敛。
class MaintenanceActions {
  /// 更新或重装 MaiBot：删除 MaiBot 目录后退出应用
  static Future<void> reinstallMaiBot() async {
    // 首先询问是否需要备份
    final backupChoice = await Get.dialog<String>(
      AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, size: 28, color: Colors.orange),
        title: const Text('重新安装 MaiBot'),
        content: const Text('重新安装将删除所有 MaiBot 数据，\n是否需要先备份当前数据？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: 'cancel'),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Get.back(result: 'no_backup'),
            child: const Text('直接重装'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: 'backup'),
            child: const Text('备份后重装'),
          ),
        ],
      ),
    );

    if (backupChoice == 'cancel' || backupChoice == null) {
      return;
    }

    // 如果选择备份，先执行备份（保持容器停止，若用户取消重装则由下方恢复）
    if (backupChoice == 'backup') {
      bool backupSuccess = await BackupService.performBackup(
        showLoadingDialog: true,
        restoreService: false,
      );

      if (!backupSuccess) {
        // 备份失败，询问是否继续
        final continueAnyway = await Get.dialog<bool>(
          AlertDialog(
            title: const Text('备份失败'),
            content: const Text('数据备份失败，是否仍要继续重新安装？'),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Get.back(result: true),
                child: const Text(
                  '继续重装',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );

        if (continueAnyway != true) {
          // 取消：恢复被暂停的前台服务（restartContainer 内部有运行态守卫）
          await ForegroundServiceManager.restartContainer();
          return;
        }
      }
    }

    // 最终确认重新安装
    final finalConfirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('确认重新安装'),
        content: const Text('确定要删除所有 MaiBot 数据并重新安装吗？\n此操作不可恢复！'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text(
              '确定重装',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (finalConfirm != true) {
      // 取消：恢复被暂停的前台服务（restartContainer 内部有运行态守卫）
      await ForegroundServiceManager.restartContainer();
      return;
    }

    try {
      await ForegroundServiceManager.stopService();
      // 删除 MaiBot 目录（~/MaiBot）
      final maiBotPath = '${scripts.ubuntuPath}/root/MaiBot';
      final maiBotDir = Directory(maiBotPath);
      if (await maiBotDir.exists()) {
        try {
          await Process.run('${RuntimeEnvir.binPath}/busybox',
              ['killall', '-9', 'node', 'python', 'python3', 'bash', 'sh']);
        } catch (_) {}
        await Process.run(
            '${RuntimeEnvir.binPath}/busybox', ['rm', '-rf', maiBotPath]);
        Log.i('已删除 MaiBot 目录: $maiBotPath', tag: 'MaiBot');
      }

      Get.snackbar(
        '重装成功',
        '应用将自动退出，请重新启动',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );

      // 2秒后自动退出应用
      Future.delayed(const Duration(seconds: 2), () {
        exit(0);
      });
    } catch (e) {
      Log.e('重新安装 MaiBot 失败: $e', tag: 'MaiBot');
      Get.snackbar(
        '重新安装失败',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// 更新或重装 NapcatQQ：删除安装判断文件后退出应用
  static Future<void> reinstallNapcat() async {
    // 显示确认对话框
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        icon: const Icon(Icons.refresh_rounded, size: 28, color: Colors.orange),
        title: const Text('确认重新安装 NapCat'),
        content: const Text('此操作将删除 NapcatQQ 安装文件（保留配置文件）并在启动时重新安装，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('确定重装'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ForegroundServiceManager.stopService();
        // 删除 launcher.sh 文件，这是安装判断的依据
        final launcherPath = '${scripts.ubuntuPath}/root/launcher.sh';
        final launcherFile = File(launcherPath);
        if (await launcherFile.exists()) {
          await launcherFile.delete();
          Log.i('已删除 launcher.sh: $launcherPath', tag: 'MaiBot');
        }

        Get.snackbar(
          '重装成功',
          '应用将自动退出，请重新启动',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2),
        );

        // 2秒后自动退出应用
        Future.delayed(const Duration(seconds: 2), () {
          exit(0);
        });
      } catch (e) {
        Log.e('重新安装 NapcatQQ 失败: $e', tag: 'MaiBot');
        Get.snackbar(
          '重新安装失败',
          e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  /// 清除 MaiBot 数据：深度删除所有数据/配置，重启时自动恢复或全新初始化
  static Future<void> clearMaiBotData() async {
    // 显示确认对话框
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded, size: 28, color: Colors.red),
        title: const Text('确认清除数据'),
        content: const Text(
          '此操作将删除 MaiBot 的本地数据、系统配置及适配器配置。\n'
          '重启后将从最近备份自动恢复或以默认配置重新初始化。\n\n'
          '是否确定清除？',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Get.back(result: true),
            child: const Text('确定清除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // 先暂停服务并终止正在后台运行的所有子进程，再删除数据
        await ForegroundServiceManager.stopService();
        try {
          await Process.run('${RuntimeEnvir.binPath}/busybox',
              ['killall', '-9', 'node', 'python', 'python3', 'bash', 'sh']);
        } catch (_) {}

        // 定义需要彻底清理的 MaiBot 数据与配置相关路径
        final List<String> pathsToDelete = [
          '${scripts.ubuntuPath}/root/MaiBot', // 整个 MaiBot 目录（含 data/config/plugins）
          '${scripts.ubuntuPath}/root/config.toml', // 拷贝在根目录的配置模板
          '${RuntimeEnvir.tmpPath}/.restore_complete', // 备份恢复标记
        ];

        bool deletedAny = false;
        for (final path in pathsToDelete) {
          final entityType = FileSystemEntity.typeSync(path);
          if (entityType != FileSystemEntityType.notFound) {
            await Process.run(
                '${RuntimeEnvir.binPath}/busybox', ['rm', '-rf', path]);
            Log.i('已彻底清除路径: $path', tag: 'MaiBot');
            deletedAny = true;
          }
        }

        if (deletedAny) {
          Get.snackbar(
            '清除成功',
            'MaiBot 数据与配置已清除，应用即将退出',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2),
          );

          // 等待提示显示后退出应用
          await Future.delayed(const Duration(seconds: 2));
          exit(0);
        } else {
          Get.snackbar(
            '提示',
            '未检测到本地有任何 MaiBot 相关的旧数据或配置文件',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2),
          );
        }
      } catch (e) {
        Log.e('清除 MaiBot 数据失败: $e', tag: 'MaiBot');
        Get.snackbar(
          '操作失败',
          '清除数据失败: $e',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  /// 重置 Python 环境：删除虚拟环境后退出应用，启动时自动重建
  static Future<void> resetPythonEnv() async {
    // 显示确认对话框
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        icon: const Icon(Icons.restart_alt_rounded, size: 28, color: Colors.orange),
        title: const Text('确认重置 Python 环境'),
        content: const Text(
          '此操作将删除 Python 虚拟环境（.venv 目录）并退出应用。\n'
          '下次启动时会自动重建环境并重新安装所有依赖。\n\n'
          '是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('确定重置'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        // 先暂停服务，避免 PTY 自动重启与删除竞态
        await ForegroundServiceManager.stopService();
        final venvPath = '${scripts.ubuntuPath}/root/MaiBot/.venv';
        final venvDir = Directory(venvPath);

        if (await venvDir.exists()) {
          try {
            await Process.run('${RuntimeEnvir.binPath}/busybox',
                ['killall', '-9', 'node', 'python', 'python3', 'bash', 'sh']);
          } catch (_) {}
          await Process.run(
              '${RuntimeEnvir.binPath}/busybox', ['rm', '-rf', venvPath, '${scripts.ubuntuPath}/root/MaiBot/.venv_sync_ready']);
          Log.i('已删除 Python 虚拟环境与就绪标记: $venvPath', tag: 'MaiBot');
          Get.snackbar(
            '重置成功',
            'Python 环境已删除，应用即将退出',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2),
          );

          // 等待提示显示后退出应用
          await Future.delayed(const Duration(seconds: 2));
          exit(0);
        } else {
          Get.snackbar(
            '提示',
            '虚拟环境目录不存在',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2),
          );
        }
      } catch (e) {
        Log.e('删除 Python 虚拟环境失败: $e', tag: 'MaiBot');
        Get.snackbar(
          '操作失败',
          '删除虚拟环境失败: $e',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  /// 退出应用
  static Future<void> exitApp() async {
    // 显示确认对话框
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        icon: const Icon(Icons.power_settings_new_rounded, size: 28, color: Colors.redAccent),
        title: const Text('确认退出应用'),
        content: const Text('退出应用将终止后台常驻服务与 Linux 容器环境，确定要退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Get.back(result: true),
            child: const Text('退出应用'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      Get.snackbar(
        '退出应用',
        '应用即将退出',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );

      // 2秒后自动退出应用
      Future.delayed(const Duration(seconds: 2), () {
        exit(0);
      });
    }
  }
}
