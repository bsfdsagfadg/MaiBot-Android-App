import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';

import '../../core/constants/scripts.dart';

class NapcatController extends GetxController {
  final RxString napCatWebUiToken = ''.obs; // 存储 NapCat WebUI Token
  final RxString maiBotWebUiToken = ''.obs; // 存储 MaiBot WebUI Token
  final RxBool _isQrcodeShowing = false.obs;
  
  Setting napCatWebUiEnabled = 'napcat_webui_enabled'.setting;
  final RxBool napCatWebUiEnabledRx = false.obs;

  Dialog? _qrcodeDialog;
  bool isQrcodeProcessed = false;
  
  @override
  void onInit() {
    super.onInit();
    napCatWebUiEnabledRx.value = napCatWebUiEnabled.get() ?? false;
  }

  // 更新 NapCat WebUI 启用状态
  void setNapCatWebUiEnabled(bool value) {
    napCatWebUiEnabled.set(value);
    napCatWebUiEnabledRx.value = value;
  }

  void handleNapcatOutput(String event) async {
    // 检测自动快速登录成功
    if (event.contains('自动快速登录成功')) {
      isQrcodeProcessed = true;
      if (_isQrcodeShowing.value && _qrcodeDialog != null) {
        Get.back();
        _isQrcodeShowing.value = false;
        _qrcodeDialog = null;
      }
      Log.i('检测到 NapCat 自动快速登录成功，准备进入主页面...', 'MaiBot');
    }

    // 捕获 NapCat WebUI Token
    if (event.contains('WebUi Token:')) {
      final match = RegExp(r'WebUi Token:\s+(\w+)').firstMatch(event);
      if (match != null) {
        final token = match.group(1);
        if (token != null) {
          napCatWebUiToken.value = token;
          Log.i('捕获到 NapCat Token: $token', 'MaiBot');
        }
      }
    }

    // 检测指令1显示二维码
    if (event.contains('二维码已保存到') && !_isQrcodeShowing.value) {
      _isQrcodeShowing.value = true;
      final qrcodePath = '$ubuntuPath/root/napcat/cache/qrcode.png';
      final qrcodeFile = File(qrcodePath);

      if (await qrcodeFile.exists()) {
        _qrcodeDialog = Dialog(
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '请用手机QQ扫码登录',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Image.file(
                  qrcodeFile,
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                ),
              ],
            ),
          ),
        );

        // 使用GetX的导航管理避免上下文问题
        await Get.dialog(
          _qrcodeDialog!,
          barrierDismissible: false,
        );

        _isQrcodeShowing.value = false;
        _qrcodeDialog = null;
      } else {
        Get.showSnackbar(GetSnackBar(
          message: '二维码图片不存在：$qrcodePath',
          duration: const Duration(seconds: 3),
        ));
        _isQrcodeShowing.value = false;
      }
    }

    // 检测指令2关闭二维码
    if (event.contains('配置加载') && _isQrcodeShowing.value) {
      // 关闭对话框
      if (_qrcodeDialog != null) {
        Get.back();
        _isQrcodeShowing.value = false;
        _qrcodeDialog = null;
      }

      // 标记二维码处理完成
      isQrcodeProcessed = true;

      // 检测登录并询问是否保存QQ
      _checkAndPromptSaveQQ();
    }

    // 检测指令3处理登录错误
    if (event.contains('Login Error') && _isQrcodeShowing.value) {
      // 关闭二维码对话框
      if (_qrcodeDialog != null) {
        Get.back();
        _isQrcodeShowing.value = false;
        _qrcodeDialog = null;
      }

      // 提取错误信息
      String errorMsg = '登录失败';
      if (event.contains('"message":"')) {
        final match = RegExp(r'"message":"([^"]+)"').firstMatch(event);
        if (match != null) {
          errorMsg = match.group(1) ?? errorMsg;
        }
      }

      // 显示错误提示
      Get.snackbar(
        'NapCat 登录失败',
        errorMsg,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    }
  }
  
  void handleMaibotOutput(String event) {
    // 适配新版日志：🔑 WebUI 登录 Token: ...
    if (event.contains('WebUI 登录 Token:')) {
        final match =
            RegExp(r'WebUI 登录 Token:\s+([a-f0-9]+)').firstMatch(event);
        if (match != null) {
          final token = match.group(1);
          if (token != null) {
            maiBotWebUiToken.value = token;
            Log.i('捕获到 MaiBot Token: $token',  'MaiBot');
          }
        }
      }
  }

  // 检测登录并询问是否保存QQ
  void _checkAndPromptSaveQQ() async {
    try {
      final String configPath = '$ubuntuPath/root/napcat/config';
      final Directory configDir = Directory(configPath);
      if (!configDir.existsSync()) return;

      // 扫描 onebot11_QQ.json 文件
      final List<FileSystemEntity> files = configDir.listSync();
      String? loggedInQQ;

      for (var file in files) {
        final String fileName = file.path.split(Platform.pathSeparator).last;
        if (fileName.startsWith('onebot11_') && fileName.endsWith('.json')) {
          loggedInQQ = fileName.substring(
              'onebot11_'.length, fileName.length - '.json'.length);
          // 确保是纯数字QQ号
          if (RegExp(r'^\d+$').hasMatch(loggedInQQ)) {
            break;
          } else {
            loggedInQQ = null;
          }
        }
      }

      if (loggedInQQ == null || loggedInQQ.isEmpty) return;

      // 读取 webui.json
      final File webuiFile = File('$configPath/webui.json');
      if (!webuiFile.existsSync()) return;

      final Map<String, dynamic> webuiConfig =
          jsonDecode(await webuiFile.readAsString());
      final String currentQQ =
          webuiConfig['autoLoginAccount']?.toString() ?? '';

      if (currentQQ.isEmpty) {
        // 弹出对话框询问
        Get.dialog(
          AlertDialog(
            title: const Text('快速登录设置'),
            content: Text(
                '检测到您已登录 QQ: $loggedInQQ\n是否将其保存为快速登录账号？\n设置后下次启动将免扫码自动登录。'),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  webuiConfig['autoLoginAccount'] = loggedInQQ;
                  await webuiFile.writeAsString(
                    const JsonEncoder.withIndent('    ').convert(webuiConfig),
                  );
                  Get.back();
                  Get.snackbar('保存成功', '已将 $loggedInQQ 设置为快速登录账号',
                      snackPosition: SnackPosition.BOTTOM);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      Log.e('检测登录账号失败: $e', 'MaiBot');
    }
  }
}
