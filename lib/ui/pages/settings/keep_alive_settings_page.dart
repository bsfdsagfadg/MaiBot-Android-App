import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';
import 'package:shizuku_api/shizuku_api.dart';

import '../../../core/config/app_config.dart';
import '../../controllers/home_controller.dart';

class KeepAliveSettingsPage extends StatefulWidget {
  const KeepAliveSettingsPage({super.key});

  @override
  State<KeepAliveSettingsPage> createState() => _KeepAliveSettingsPageState();
}

class _KeepAliveSettingsPageState extends State<KeepAliveSettingsPage> {
  bool _isBatteryOptimizationIgnored = false;

  final Setting _enableWifiLock = 'enable_wifi_lock'.setting;

  // Shizuku Keep-Alive 状态
  bool _shizukuDozeWhitelist = false;
  bool _shizukuRunAnyInBackground = false;
  bool _shizukuPhantomProcessLimit = false;
  bool _shizukuAvailable = false;
  bool _shizukuPermissionGranted = false;
  final ShizukuApi _shizukuApi = ShizukuApi();

  @override
  void initState() {
    super.initState();
    _checkBatteryOptimizationStatus();
    _checkShizukuStatus();
    if (_enableWifiLock.get() == null) {
      _enableWifiLock.set(true);
    }
  }

  Future<void> _checkBatteryOptimizationStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (mounted) {
        setState(() {
          _isBatteryOptimizationIgnored = status.isGranted;
        });
      }
    } catch (e) {
      Log.e('检查电池优化豁免状态失败: $e', tag: 'MaiBot');
    }
  }

  // 检测并查询当前设备上特定保活命令的实际生效状态
  Future<void> _checkShizukuStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final isBinderRunning = await _shizukuApi.pingBinder() ?? false;
      if (!isBinderRunning) {
        if (mounted) {
          setState(() {
            _shizukuAvailable = false;
            _shizukuPermissionGranted = false;
          });
        }
        return;
      }

      final hasPermission = await _shizukuApi.checkPermission() ?? false;
      if (mounted) {
        setState(() {
          _shizukuAvailable = isBinderRunning;
          _shizukuPermissionGranted = hasPermission;
        });
      }

      if (hasPermission) {
        // 1. 查询 Doze 白名单
        final dozeOut =
            await _shizukuApi.runCommand('dumpsys deviceidle whitelist');
        final isDozeWhitelisted =
            dozeOut != null && dozeOut.contains(Config.packageName);

        // 2. 查询 RUN_ANY_IN_BACKGROUND
        final appopsOut = await _shizukuApi.runCommand(
            'cmd appops get ${Config.packageName} RUN_ANY_IN_BACKGROUND');
        final isRunAnyAllowed =
            appopsOut != null && appopsOut.toLowerCase().contains('allow');

        // 3. 查询 phantom process
        final phantomOut =
            await _shizukuApi.runCommand('dumpsys activity settings');
        final isPhantomIncreased = phantomOut != null &&
            phantomOut.contains('max_phantom_processes=64');

        if (mounted) {
          setState(() {
            _shizukuDozeWhitelist = isDozeWhitelisted;
            _shizukuRunAnyInBackground = isRunAnyAllowed;
            _shizukuPhantomProcessLimit = isPhantomIncreased;
          });
        }
      }
    } catch (e) {
      Log.e('检查 Shizuku 状态失败: $e', tag: 'KeepAliveSettingsPage');
    }
  }

  // 确保已授权 Shizuku 权限
  Future<bool> _ensureShizukuPermission() async {
    final isBinderRunning = await _shizukuApi.pingBinder() ?? false;
    if (!isBinderRunning) {
      Get.snackbar('Shizuku 未运行', '请确认 Shizuku 应用程序已在后台启动并运行',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange,
          colorText: Colors.white);
      setState(() {
        _shizukuAvailable = false;
        _shizukuPermissionGranted = false;
      });
      return false;
    }

    var hasPermission = await _shizukuApi.checkPermission() ?? false;
    if (!hasPermission) {
      final requested = await _shizukuApi.requestPermission() ?? false;
      if (!requested) {
        Get.snackbar('权限拒绝', '未授予 Shizuku 权限',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white);
        setState(() {
          _shizukuPermissionGranted = false;
        });
        return false;
      }
      hasPermission = await _shizukuApi.checkPermission() ?? false;
    }
    setState(() {
      _shizukuAvailable = true;
      _shizukuPermissionGranted = hasPermission;
    });
    return hasPermission;
  }

  // 2. 豁免电池优化 (Doze Whitelist) 状态切换
  Future<void> _toggleDozeWhitelist(bool value) async {
    if (!await _ensureShizukuPermission()) return;
    try {
      if (value) {
        await _shizukuApi
            .runCommand('dumpsys deviceidle whitelist +${Config.packageName}');
        Get.snackbar('设置成功', '已通过 Shell 将本应用加入电池优化白名单',
            snackPosition: SnackPosition.BOTTOM);
      } else {
        await _shizukuApi
            .runCommand('dumpsys deviceidle whitelist -${Config.packageName}');
        Get.snackbar('还原成功', '已将本应用移出电池优化白名单',
            snackPosition: SnackPosition.BOTTOM);
      }
      await _checkShizukuStatus();
    } catch (e) {
      Get.snackbar('执行失败', e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    }
  }

  // 3. 无限制后台运行 AppOps 状态切换
  Future<void> _togglePhantomProcess(bool value) async {
    if (!await _ensureShizukuPermission()) return;
    try {
      if (value) {
        // 第一步：禁止系统自动同步重置设定
        await _shizukuApi
            .runCommand('device_config set_sync_disabled_for_tests persistent');
        // 第二步：将限制提升到 64
        await _shizukuApi.runCommand(
            'device_config put activity_manager max_phantom_processes 64');
        Get.snackbar('设置成功', '已提高幻影进程限制至64',
            snackPosition: SnackPosition.BOTTOM);
      } else {
        // 恢复：启用同步并改回 32
        await _shizukuApi
            .runCommand('device_config set_sync_disabled_for_tests none');
        await _shizukuApi.runCommand(
            'device_config put activity_manager max_phantom_processes 32');
        Get.snackbar('还原成功', '已恢复默认幻影进程限制',
            snackPosition: SnackPosition.BOTTOM);
      }
      await _checkShizukuStatus();
    } catch (e) {
      Get.snackbar('执行失败', e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    }
  }

  Future<void> _toggleRunAnyInBackground(bool value) async {
    if (!await _ensureShizukuPermission()) return;
    try {
      if (value) {
        await _shizukuApi.runCommand(
            'cmd appops set ${Config.packageName} RUN_ANY_IN_BACKGROUND allow');
        await _shizukuApi.runCommand(
            'cmd appops set ${Config.packageName} RUN_IN_BACKGROUND allow');
        Get.snackbar('设置成功', '已允许后台无限制自由运行',
            snackPosition: SnackPosition.BOTTOM);
      } else {
        await _shizukuApi.runCommand(
            'cmd appops set ${Config.packageName} RUN_ANY_IN_BACKGROUND default');
        await _shizukuApi.runCommand(
            'cmd appops set ${Config.packageName} RUN_IN_BACKGROUND default');
        Get.snackbar('还原成功', 'AppOps 权限已恢复至系统默认托管',
            snackPosition: SnackPosition.BOTTOM);
      }
      await _checkShizukuStatus();
    } catch (e) {
      Get.snackbar('执行失败', e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    }
  }

  Future<void> _requestBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) {
        Get.snackbar('已授权', '已获得电池优化豁免权限',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2));
        return;
      }
      final result = await Permission.ignoreBatteryOptimizations.request();
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkBatteryOptimizationStatus();
      if (result.isGranted) {
        Get.snackbar('授权成功', '已获得电池优化豁免权限',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2));
      } else {
        Get.snackbar('授权失败', '未获得电池优化豁免权限',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2));
      }
    } catch (e) {
      Log.e('请求电池优化豁免失败: $e', tag: 'MaiBot');
      Get.snackbar('请求失败', '请求电池优化豁免时发生错误: $e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 3));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('后台保活设置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.blue, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '为确保后台常驻运行不中断，建议完成下方系统权限设置，并在多任务界面为 MaiBot 加锁。',
                    style: TextStyle(color: Colors.blue.shade900, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionTitle('基础保活选项', Icons.battery_charging_full_rounded),
          _buildCard([
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.battery_saver_rounded, color: Colors.green, size: 22),
              ),
              title: const Text('电池优化豁免', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: Text(
                _isBatteryOptimizationIgnored ? '已获得豁免权限，允许后台运行' : '未授权：系统可能在息屏时休眠进程',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              trailing: _isBatteryOptimizationIgnored
                  ? const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22)
                  : FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _requestBatteryOptimization,
                      child: const Text('授权', style: TextStyle(fontSize: 12)),
                    ),
              onTap: _requestBatteryOptimization,
            ),
            const Divider(height: 1, indent: 56),
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.wifi_lock_rounded, color: Colors.indigo, size: 22),
              ),
              title: const Text('保持 Wi-Fi 连接 (WLAN 锁)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: const Text('息屏时避免系统 Wi-Fi 进入休眠，保障网络连接稳定', style: TextStyle(fontSize: 12, color: Colors.black54)),
              value: _enableWifiLock.get() ?? true,
              activeThumbColor: primaryColor,
              onChanged: (bool value) {
                _enableWifiLock.set(value);
                if (mounted) setState(() {});
              },
            ),
          ]),
          const SizedBox(height: 16),
          _buildSectionTitle('Shizuku 进阶配置', Icons.extension_rounded),
          _buildCard([
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link_rounded, color: Colors.purple, size: 22),
              ),
              title: const Text('Shizuku 运行状态', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: Text(
                !_shizukuAvailable
                    ? '未运行：请先启动 Shizuku 应用'
                    : (_shizukuPermissionGranted ? '已连接并获得授权' : '已检测到服务，点击请求授权'),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              trailing: Icon(
                !_shizukuAvailable
                    ? Icons.cancel_rounded
                    : (_shizukuPermissionGranted ? Icons.check_circle_rounded : Icons.info_rounded),
                color: !_shizukuAvailable
                    ? Colors.grey
                    : (_shizukuPermissionGranted ? Colors.green : Colors.orange),
                size: 22,
              ),
              onTap: () async {
                await _ensureShizukuPermission();
                await _checkShizukuStatus();
              },
            ),
            const Divider(height: 1, indent: 56),
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.flash_on_rounded, color: Colors.teal, size: 22),
              ),
              title: const Text('写入系统 Doze 白名单', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: const Text('通过 Shell 命令直接将应用注册至系统低电耗白名单', style: TextStyle(fontSize: 12, color: Colors.black54)),
              value: _shizukuDozeWhitelist,
              activeThumbColor: primaryColor,
              onChanged: (bool value) => _toggleDozeWhitelist(value),
            ),
            const Divider(height: 1, indent: 56),
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tune_rounded, color: Colors.deepOrange, size: 22),
              ),
              title: const Text('无限制后台运行 (AppOps)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: const Text('开启 RUN_ANY_IN_BACKGROUND 权限，允许应用在后台持续运行', style: TextStyle(fontSize: 12, color: Colors.black54)),
              value: _shizukuRunAnyInBackground,
              activeThumbColor: primaryColor,
              onChanged: (bool value) => _toggleRunAnyInBackground(value),
            ),
            const Divider(height: 1, indent: 56),
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.memory_rounded, color: Colors.blueGrey, size: 22),
              ),
              title: const Text('提高幻影进程限制 (Android 12+)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: const Text('将系统幻影进程上限提升至 64，避免 Linux 容器子进程被系统清理', style: TextStyle(fontSize: 12, color: Colors.black54)),
              value: _shizukuPhantomProcessLimit,
              activeThumbColor: primaryColor,
              onChanged: (bool value) => _togglePhantomProcess(value),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSectionTitle('任务管理与隐身', Icons.task_alt_rounded),
          _buildCard([
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.lock_outline_rounded, color: Colors.amber.shade800, size: 22),
              ),
              title: const Text('多任务锁定建议', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: const Text(
                '在系统的最近任务列表中长按或下拉 MaiBot 卡片添加锁定图标，防止一键清理任务时被关闭。',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const Divider(height: 1, indent: 56),
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.visibility_off_rounded, color: Colors.red, size: 22),
              ),
              title: const Text('从最近任务列表中隐藏', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: const Text('隐藏后应用不在多任务列表显示。在系统内存紧张时可能降低保活优先级。', style: TextStyle(fontSize: 12, color: Colors.black54)),
              value: Get.find<HomeController>().hideFromRecents.get() ?? false,
              activeThumbColor: primaryColor,
              onChanged: (bool value) {
                Get.find<HomeController>().setHideFromRecents(value);
                if (mounted) setState(() {});
              },
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
