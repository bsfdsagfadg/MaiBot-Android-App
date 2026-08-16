import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import '../constants/scripts.dart' as scripts;
import 'foreground_service.dart';
import '../utils/file_utils.dart';

/// 备份与恢复服务：支持 MaiBot / NapCat 全量备份与细粒度选择性模块恢复
class BackupService {
  /// 获取本地现有的所有有效备份文件（按修改时间倒序排列，最新的排在最前）
  static List<File> getAvailableBackups() {
    try {
      final backupDirs = [
        getMaiBotBackupDirectory(),
        Directory('${RuntimeEnvir.homePath}/backups'),
      ];
      final seenPaths = <String>{};
      final fileEntries = <({File file, DateTime modified})>[];

      for (final backupDir in backupDirs) {
        if (!backupDir.existsSync()) continue;
        for (final entity in backupDir.listSync()) {
          if (entity is File && entity.path.endsWith('.tar.gz')) {
            if (seenPaths.contains(entity.path)) continue;
            seenPaths.add(entity.path);
            try {
              final stat = entity.statSync();
              if (stat.size > 1024) {
                fileEntries.add((file: entity, modified: stat.modified));
              }
            } catch (_) {}
          }
        }
      }

      fileEntries.sort((a, b) => b.modified.compareTo(a.modified));
      return fileEntries.map((e) => e.file).toList();
    } catch (e) {
      Log.e('扫描备份文件失败: $e', tag: 'BackupService');
      return [];
    }
  }
  /// 安全平滑停止后台进程与 Linux 容器：
  /// 1. 先停用原生服务守护层（防止原生守护进程误判为异常崩溃而立即自动重启）
  /// 2. 向 Python / Node / QQ 进程发送 SIGINT (Ctrl+C / 信号 2)，通知应用优雅保存状态并落盘 SQLite 数据
  /// 3. 等待缓冲期，让数据库完成 WAL checkpoint 和文件关闭
  /// 4. 发送 SIGKILL (信号 9) 彻底清理残留孤儿子进程
  /// 5. 清理 X11 锁文件，确保后续启动不产生锁冲突
  static Future<void> safelyTerminateProcessesForMaintenance() async {
    Log.i('正在平滑停止后台容器与进程...', tag: 'BackupService');

    // 第一步：通知原生守护服务停用，封锁自动重启定时器
    try {
      await ForegroundServiceManager.stopService();
    } catch (e) {
      Log.w('通知原生服务停止异常: $e', tag: 'BackupService');
    }

    // 第二步：向核心进程发送 SIGINT (Ctrl+C，信号 2)，允许 Python / Node / SQLite 优雅写盘退出
    try {
      await Process.run('${RuntimeEnvir.binPath}/busybox',
          ['killall', '-2', 'python', 'python3', 'node', 'qq', 'bash', 'sh']);
    } catch (_) {}

    // 第三步：等待 1 秒缓冲期，确保 SQLite 数据与日志文件安全完成落盘
    await Future.delayed(const Duration(milliseconds: 1000));

    // 第四步：彻底清理所有可能残留的容器进程
    try {
      await Process.run('${RuntimeEnvir.binPath}/busybox',
          ['killall', '-9', 'proot', 'python', 'python3', 'node', 'qq', 'bash', 'sh', 'crashpad_handler']);
    } catch (_) {}

    // 第五步：清理锁文件与孤立 Socket
    try {
      final x1Lock = File('${RuntimeEnvir.tmpPath}/.X1-lock');
      if (x1Lock.existsSync()) x1Lock.deleteSync();
      final x11Unix = Directory('${RuntimeEnvir.tmpPath}/.X11-unix');
      if (x11Unix.existsSync()) x11Unix.deleteSync(recursive: true);
      await Process.run('${RuntimeEnvir.binPath}/busybox', [
        'rm',
        '-rf',
        '${RuntimeEnvir.tmpPath}/SingletonLock',
        '${RuntimeEnvir.tmpPath}/SingletonSocket',
        '${RuntimeEnvir.tmpPath}/SingletonCookie',
        '${scripts.ubuntuPath}/root/.config/QQ/SingletonLock',
        '${scripts.ubuntuPath}/root/.config/QQ/SingletonSocket',
        '${scripts.ubuntuPath}/root/.config/QQ/SingletonCookie',
      ]);
    } catch (_) {}
  }
  /// 确保获取存储权限（支持 Android 11+ 所有文件权限与旧版存储权限），无法获取时降级使用内部目录
  static Future<bool> ensureStoragePermission() async {
    try {
      var manageStatus = await Permission.manageExternalStorage.status;
      if (manageStatus.isGranted) return true;

      var storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) return true;

      manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return true;

      storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      // 若公共存储权限未授予，检查内部备份目录是否可用
      final internalBackupDir = Directory('${RuntimeEnvir.homePath}/backups');
      if (internalBackupDir.existsSync()) {
        return true;
      }
      return false;
    } catch (e) {
      Log.w('请求存储权限异常: $e', tag: 'BackupService');
      return true;
    }
  }

  /// 探测备份文件内部包含的具体模块
  static Future<Map<String, bool>> inspectBackupContents(File backupFile) async {
    final result = {
      'data': false,
      'config': false,
      'plugins': false,
      'napcat': false,
    };

    try {
      final proc = await Process.run('${RuntimeEnvir.binPath}/busybox', [
        'tar',
        '-tzf',
        backupFile.path,
      ]);

      if (proc.exitCode == 0) {
        final lines = proc.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.startsWith('MaiBot/data/')) result['data'] = true;
          if (line.startsWith('MaiBot/config/')) result['config'] = true;
          if (line.startsWith('MaiBot/plugins/')) result['plugins'] = true;
          if (line.startsWith('napcat/config/')) result['napcat'] = true;
        }
      }
    } catch (e) {
      Log.w('解析备份目录结构异常: $e', tag: 'BackupService');
      // 解析异常时默认全选
      return {'data': true, 'config': true, 'plugins': true, 'napcat': true};
    }

    return result;
  }

  /// 执行备份操作
  static Future<bool> performBackup({
    bool showLoadingDialog = false,
    bool restoreService = true,
  }) async {
    // 1. 检查并请求存储权限
    final hasPermission = await ensureStoragePermission();
    if (!hasPermission) {
      Get.snackbar(
        '权限不足',
        '需要存储权限才能备份数据到手机存储',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      return false;
    }

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

    final backupDir = getMaiBotBackupDirectory();
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    final backupFileName = 'MaiBot-backup-$timestamp.tar.gz';
    final backupPath = '${backupDir.path}/$backupFileName';

    bool dialogShown = false;
    if (showLoadingDialog) {
      Get.dialog(
        const PopScope(
          canPop: false,
          child: Center(
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在打包备份数据...', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
        ),
        barrierDismissible: false,
      );
      dialogShown = true;
    }

    void dismissDialog() {
      if (dialogShown) {
        if (Get.isDialogOpen == true) {
          Get.back();
        }
        dialogShown = false;
      }
    }

    try {
      // 平滑发送 SIGINT 退出并终止进程，杜绝数据损坏与自动重启冲突
      await safelyTerminateProcessesForMaintenance();

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

      // 先关闭加载框，再展示 Snackbar 提示
      dismissDialog();

      if (result.exitCode == 0) {
        final backupFile = File(backupPath);
        final fileSize = await backupFile.length();
        final fileSizeMB = (fileSize / 1024 / 1024).toStringAsFixed(2);

        Get.snackbar(
          '备份成功',
          '备份文件: $backupFileName\n大小: ${fileSizeMB}MB',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3),
        );
        Log.i('备份成功: $backupPath (${fileSizeMB}MB)', tag: 'BackupService');
        return true;
      } else {
        Get.snackbar(
          '备份失败',
          '错误: ${result.stderr}',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        Log.e('备份失败: ${result.stderr}', tag: 'BackupService');
        return false;
      }
    } catch (e) {
      dismissDialog();
      Get.snackbar(
        '备份失败',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      Log.e('备份异常: $e', tag: 'BackupService');
      return false;
    } finally {
      dismissDialog();
      if (restoreService) {
        await ForegroundServiceManager.restartContainer();
      }
    }
  }

  /// 执行细粒度选择性备份恢复
  static Future<bool> performSelectiveRestore({
    required File backupFile,
    bool restoreData = true,
    bool restoreConfig = true,
    bool restorePlugins = true,
    bool restoreNapcat = true,
    bool restartService = true,
    bool showSnackbar = true,
  }) async {
    // 确保权限
    await ensureStoragePermission();

    if (!backupFile.existsSync()) {
      if (showSnackbar) {
        Get.snackbar('恢复失败', '备份文件不存在', snackPosition: SnackPosition.BOTTOM);
      }
      return false;
    }

    try {
      Log.i('开始执行选择性备份恢复: ${backupFile.path}', tag: 'BackupService');
      // 平滑发送 SIGINT 退出并终止进程，杜绝数据损坏与自动重启冲突
      await safelyTerminateProcessesForMaintenance();

      final extractTargets = <String>[];
      if (restoreData) extractTargets.add('MaiBot/data');
      if (restoreConfig) extractTargets.add('MaiBot/config');
      if (restorePlugins) extractTargets.add('MaiBot/plugins');
      if (restoreNapcat) extractTargets.add('napcat/config');

      if (extractTargets.isEmpty) {
        if (showSnackbar) {
          Get.snackbar('提示', '未选择任何要恢复的模块', snackPosition: SnackPosition.BOTTOM);
        }
        return true;
      }

      // 确保目标父目录结构完整
      Directory('${scripts.ubuntuPath}/root/MaiBot').createSync(recursive: true);
      Directory('${scripts.ubuntuPath}/root/napcat').createSync(recursive: true);

      final args = [
        'tar',
        '-xzf',
        backupFile.path,
        '-C',
        '${scripts.ubuntuPath}/root',
        ...extractTargets,
      ];

      final res = await Process.run('${RuntimeEnvir.binPath}/busybox', args);
      if (res.exitCode == 0) {
        Log.i('选择性恢复成功: $extractTargets', tag: 'BackupService');
        if (showSnackbar) {
          Get.snackbar(
            '恢复成功',
            '已成功还原选定的数据与配置模块',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 3),
          );
        }
        return true;
      } else {
        Log.e('恢复失败: ${res.stderr}', tag: 'BackupService');
        if (showSnackbar) {
          Get.snackbar('恢复失败', '解压文件失败: ${res.stderr}', snackPosition: SnackPosition.BOTTOM);
        }
        return false;
      }
    } catch (e) {
      Log.e('恢复过程异常: $e', tag: 'BackupService');
      if (showSnackbar) {
        Get.snackbar('恢复异常', e.toString(), snackPosition: SnackPosition.BOTTOM);
      }
      return false;
    } finally {
      if (restartService) {
        await ForegroundServiceManager.restartContainer();
      }
    }
  }

  /// 显示 Material You 风格的备份恢复选择对话框
  static Future<void> showRestoreDialog({
    bool isInitialInstall = false,
    VoidCallback? onCompleted,
  }) async {
    // 确保请求存储权限，避免无权限时直接返回空列表导致提示无备份
    if (!isInitialInstall) {
      await ensureStoragePermission();
    }

    final backups = getAvailableBackups();
    if (backups.isEmpty) {
      if (!isInitialInstall) {
        Get.snackbar(
          '未找到备份',
          '未在手机存储或应用备份目录中找到备份存档',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3),
        );
      }
      onCompleted?.call();
      return;
    }

    int selectedBackupIndex = 0;
    bool restoreData = true;
    bool restoreConfig = true;
    bool restorePlugins = true;
    bool restoreNapcat = true;
    bool isRestoring = false;

    await Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final currentFile = backups[selectedBackupIndex];
          return AlertDialog(
            backgroundColor: colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.settings_backup_restore_rounded, color: colorScheme.onPrimaryContainer, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isInitialInstall ? '检测到历史备份' : '恢复数据备份',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isInitialInstall ? '是否恢复历史存档与配置？' : '选择要还原的存档与模块',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: isRestoring
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text('正在恢复选定模块数据...', style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. 备份文件选择器
                          Text('选择备份存档 (${backups.length} 个可用)',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              )),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: backups.length > 4 ? 4 : backups.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                              itemBuilder: (context, idx) {
                                final f = backups[idx];
                                final isSelected = idx == selectedBackupIndex;
                                final isLatest = idx == 0;
                                final fStat = f.statSync();
                                final fDate =
                                    '${fStat.modified.month.toString().padLeft(2, '0')}-${fStat.modified.day.toString().padLeft(2, '0')} ${fStat.modified.hour.toString().padLeft(2, '0')}:${fStat.modified.minute.toString().padLeft(2, '0')}';
                                final fMB = (fStat.size / 1024 / 1024).toStringAsFixed(1);

                                return ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  selected: isSelected,
                                  selectedTileColor: colorScheme.secondaryContainer.withValues(alpha: 0.4),
                                  leading: Icon(
                                    isSelected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          f.uri.pathSegments.last,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isLatest) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primaryContainer,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text('最新备份',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onPrimaryContainer,
                                              )),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text('$fDate · ${fMB}MB', style: const TextStyle(fontSize: 11)),
                                  onTap: () => setState(() => selectedBackupIndex = idx),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 2. 选择性恢复子模块 Checkbox
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('选择要恢复的模块内容',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  )),
                              TextButton(
                                onPressed: () {
                                  final allSelected = restoreData && restoreConfig && restorePlugins && restoreNapcat;
                                  setState(() {
                                    restoreData = !allSelected;
                                    restoreConfig = !allSelected;
                                    restorePlugins = !allSelected;
                                    restoreNapcat = !allSelected;
                                  });
                                },
                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                child: Text(
                                  (restoreData && restoreConfig && restorePlugins && restoreNapcat) ? '取消全选' : '全选',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            child: Column(
                              children: [
                                CheckboxListTile(
                                  dense: true,
                                  title: const Text('聊天记录与记忆库', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: const Text('MaiBot/data (SQLite 数据库、长期记忆、用户画像)', style: TextStyle(fontSize: 11)),
                                  value: restoreData,
                                  onChanged: (v) => setState(() => restoreData = v ?? true),
                                ),
                                Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                                CheckboxListTile(
                                  dense: true,
                                  title: const Text('核心配置与密钥', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: const Text('MaiBot/config (bot.toml、模型 API Key、WebUI 令牌)', style: TextStyle(fontSize: 11)),
                                  value: restoreConfig,
                                  onChanged: (v) => setState(() => restoreConfig = v ?? true),
                                ),
                                Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                                CheckboxListTile(
                                  dense: true,
                                  title: const Text('已装插件与适配器', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: const Text('MaiBot/plugins (NapCat 适配器与自定义插件)', style: TextStyle(fontSize: 11)),
                                  value: restorePlugins,
                                  onChanged: (v) => setState(() => restorePlugins = v ?? true),
                                ),
                                Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                                CheckboxListTile(
                                  dense: true,
                                  title: const Text('NapCat QQ 账号配置', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: const Text('napcat/config (OneBot11 通信令牌与面板凭证)', style: TextStyle(fontSize: 11)),
                                  value: restoreNapcat,
                                  onChanged: (v) => setState(() => restoreNapcat = v ?? true),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            actions: isRestoring
                ? null
                : [
                    TextButton(
                      onPressed: () {
                        Get.back();
                        onCompleted?.call();
                      },
                      child: Text(isInitialInstall ? '跳过 (全新初始化)' : '取消'),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('开始恢复'),
                      onPressed: () async {
                        setState(() => isRestoring = true);
                        final success = await performSelectiveRestore(
                          backupFile: currentFile,
                          restoreData: restoreData,
                          restoreConfig: restoreConfig,
                          restorePlugins: restorePlugins,
                          restoreNapcat: restoreNapcat,
                          restartService: isInitialInstall,
                          showSnackbar: false,
                        );
                        if (Get.isDialogOpen == true) {
                          Get.back();
                        }
                        if (success) {
                          if (!isInitialInstall) {
                            Get.snackbar(
                              '恢复成功',
                              '已成功还原数据与配置，应用即将退出，请重新打开',
                              snackPosition: SnackPosition.BOTTOM,
                              duration: const Duration(seconds: 3),
                            );
                            Future.delayed(const Duration(seconds: 2), () {
                              SystemNavigator.pop();
                              exit(0);
                            });
                          } else {
                            Get.snackbar(
                              '恢复成功',
                              '已成功还原选定的数据与配置模块',
                              snackPosition: SnackPosition.BOTTOM,
                              duration: const Duration(seconds: 3),
                            );
                          }
                        } else {
                          Get.snackbar(
                            '恢复失败',
                            '数据还原过程中发生错误',
                            snackPosition: SnackPosition.BOTTOM,
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                            duration: const Duration(seconds: 3),
                          );
                        }
                        onCompleted?.call();
                      },
                    ),
                  ],
          );
        },
      ),
      barrierDismissible: false,
    );
  }
}
