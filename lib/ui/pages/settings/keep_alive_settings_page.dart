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
      setState(() {
        _isBatteryOptimizationIgnored = status.isGranted;
      });
    } catch (e) {
      Log.e('检查电池优化豁免状态失败: $e', 'MaiBot');
    }
  }

  // 检测并查询当前设备上特定保活命令的实际生效状态
  Future<void> _checkShizukuStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final isBinderRunning = await _shizukuApi.pingBinder() ?? false;
      if (!isBinderRunning) {
        setState(() {
          _shizukuAvailable = false;
          _shizukuPermissionGranted = false;
        });
        return;
      }

      final hasPermission = await _shizukuApi.checkPermission() ?? false;
      setState(() {
        _shizukuAvailable = isBinderRunning;
        _shizukuPermissionGranted = hasPermission;
      });

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

        setState(() {
          _shizukuDozeWhitelist = isDozeWhitelisted;
          _shizukuRunAnyInBackground = isRunAnyAllowed;
          _shizukuPhantomProcessLimit = isPhantomIncreased;
        });
      }
    } catch (e) {
      Log.e('检查 Shizuku 状态失败: $e', 'KeepAliveSettingsPage');
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
      Log.e('请求电池优化豁免失败: $e', 'MaiBot');
      Get.snackbar('请求失败', '请求电池优化豁免时发生错误: $e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 3));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('后台保活设置', style: TextStyle(fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              '为了让 MaiBot 在后台稳定运行，建议开启以下权限和设置。\n\n💡 防杀终极指南：\n请在系统多任务（最近任务）界面为 MaiBot 加上小锁。只要保留在后台不手贱划掉清理，配合下方的电池优化等设置，MaiBot 就能稳定长久地陪伴你！',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver),
            title: const Text('电池优化豁免'),
            subtitle: Text(_isBatteryOptimizationIgnored ? '已授权' : '未授权（点击授权）'),
            trailing: _isBatteryOptimizationIgnored
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.warning, color: Colors.orange),
            onTap: _requestBatteryOptimization,
          ),
          ListTile(
            leading: const Icon(Icons.wifi_lock),
            title: const Text('保持 Wi-Fi 唤醒 (WLAN 锁)'),
            subtitle: const Text('息屏时防止 Wi-Fi 休眠，避免断网导致的掉线（重启应用后生效）'),
            trailing: Switch(
              value: _enableWifiLock.get() ?? true,
              onChanged: (bool value) {
                _enableWifiLock.set(value);
                setState(() {});
              },
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Shizuku 保活扩展',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.extension),
            title: const Text('Shizuku 授权状态'),
            subtitle: Text(
              !_shizukuAvailable
                  ? '服务未运行，请先启动 Shizuku 应用程序'
                  : (_shizukuPermissionGranted ? '已成功授权并连接' : '已检测到服务，点击请求授权'),
            ),
            trailing: Icon(
              !_shizukuAvailable
                  ? Icons.error_outline
                  : (_shizukuPermissionGranted
                      ? Icons.check_circle_outline
                      : Icons.help_outline),
              color: !_shizukuAvailable
                  ? Colors.red
                  : (_shizukuPermissionGranted ? Colors.green : Colors.orange),
            ),
            onTap: () async {
              await _ensureShizukuPermission();
              await _checkShizukuStatus();
            },
          ),
          ListTile(
            leading: const Icon(Icons.battery_charging_full),
            title: const Text('强制 Doze 电池优化白名单'),
            subtitle: const Text('通过 Shell 将本应用加入 Doze 白名单，保证息屏连接不中断'),
            trailing: Switch(
              value: _shizukuDozeWhitelist,
              onChanged: (bool value) {
                _toggleDozeWhitelist(value);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_suggest),
            title: const Text('无限制后台运行'),
            subtitle: const Text('突破 Android AppOps 后台广播与进程限制，始终允许在后台运行'),
            trailing: Switch(
              value: _shizukuRunAnyInBackground,
              onChanged: (bool value) {
                _toggleRunAnyInBackground(value);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('提高幻影进程限制'),
            subtitle: const Text('将最大幻影进程数限制提高至64，避免因进程过多导致子进程被意外杀掉'),
            trailing: Switch(
              value: _shizukuPhantomProcessLimit,
              onChanged: (bool value) {
                _togglePhantomProcess(value);
              },
            ),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('添加后台锁提示'),
            subtitle: Text(
                '请在系统的多任务（最近任务）界面，下拉或长按 MaiBot 卡片，为其添加后台锁定状态（通常显示为小锁图标）。这能有效防止系统自动清理应用。'),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off),
            title: const Text('从最近活动中隐藏自身'),
            subtitle: const Text(
                '开启后应用将不会出现在最近任务列表中。\n⚠️ 警告：这会导致系统在内存紧张时大概率清理掉本应用，引起运行不稳定，请谨慎开启！'),
            trailing: Switch(
              value: Get.find<HomeController>().hideFromRecents.get() ?? false,
              onChanged: (bool value) {
                Get.find<HomeController>().setHideFromRecents(value);
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }
}
