import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';

import '../../core/constants/scripts.dart';
import 'napcat_log_parser.dart';

class NapcatController extends GetxController {
  final RxString napCatWebUiToken = ''.obs; // 存储 NapCat WebUI Token
  final RxString maiBotWebUiToken = ''.obs; // 存储 MaiBot WebUI Token
  final RxBool _isQrcodeShowing = false.obs;
  final RxInt _qrcodeRefreshTrigger = 0.obs;
  Setting napCatWebUiEnabled = 'napcat_webui_enabled'.setting;
  final RxBool napCatWebUiEnabledRx = false.obs;

  Dialog? _qrcodeDialog;
  bool isQrcodeProcessed = false;

  @override
  void onInit() {
    super.onInit();
    napCatWebUiEnabledRx.value = napCatWebUiEnabled.get() ?? false;
    _loadMaibotTokenFromFile(); // 应用初始化时尝试读取已有 Token 供冷启动直接使用
  }

  // 更新 NapCat WebUI 启用状态
  void setNapCatWebUiEnabled(bool value) {
    napCatWebUiEnabled.set(value);
    napCatWebUiEnabledRx.value = value;
  }

  /// 优先从本地 webui.json 文件直接读取 WebUI 登录凭证 (Token)
  Future<bool> _loadMaibotTokenFromFile() async {
    try {
      final file = File('$ubuntuPath/root/MaiBot/data/webui.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final parsed = jsonDecode(content);
        if (parsed is Map) {
          final token = parsed['access_token']?.toString() ?? '';
          if (token.isNotEmpty) {
            maiBotWebUiToken.value = token;
            Log.i('成功从 webui.json 读取到 MaiBot Token: $token', tag: 'MaiBot');
            return true;
          }
        }
      }
    } catch (e) {
      Log.e('读取 webui.json 失败: $e', tag: 'MaiBot');
    }
    return false;
  }

  void handleNapcatOutput(String event) async {
    // 剥离ANSI颜色代码，防止颜色字符干扰正则表达式匹配
    final cleanEvent = NapcatLogParser.stripAnsi(event);

    for (final parsed in NapcatLogParser.parseNapcat(cleanEvent)) {
      switch (parsed.type) {
        case NapcatLogEventType.autoLoginSuccess:
          isQrcodeProcessed = true;
          if (_isQrcodeShowing.value && _qrcodeDialog != null) {
            Get.back();
            _isQrcodeShowing.value = false;
            _qrcodeDialog = null;
          }
          Log.i('检测到 NapCat 自动快速登录成功，准备进入主页面...', tag: 'MaiBot');
          break;

        case NapcatLogEventType.napcatToken:
          final token = parsed.payload;
          if (token != null) {
            napCatWebUiToken.value = token;
            Log.i('捕获到 NapCat Token: $token', tag: 'MaiBot');
          }
          break;

        case NapcatLogEventType.qrcodeSaved:
          if (!_isQrcodeShowing.value) {
            await _showQrcodeDialog();
          } else {
            // Refresh existing QR code
            final qrcodePath = '$ubuntuPath/root/napcat/cache/qrcode.png';
            await FileImage(File(qrcodePath)).evict();
            _qrcodeRefreshTrigger.value++;
          }
          break;

        case NapcatLogEventType.configLoaded:
          if (_isQrcodeShowing.value) {
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
          break;

        case NapcatLogEventType.loginError:
          if (_isQrcodeShowing.value) {
            // 关闭二维码对话框
            if (_qrcodeDialog != null) {
              Get.back();
              _isQrcodeShowing.value = false;
              _qrcodeDialog = null;
            }

            // 显示错误提示
            Get.snackbar(
              'NapCat 登录失败',
              parsed.payload ?? '登录失败',
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Colors.red.withValues(alpha: 0.8),
              colorText: Colors.white,
              duration: const Duration(seconds: 5),
            );
          }
          break;
      }
    }
  }

  // 展示二维码登录对话框
  Future<void> _showQrcodeDialog() async {
    _isQrcodeShowing.value = true;
    final qrcodePath = '$ubuntuPath/root/napcat/cache/qrcode.png';
    final qrcodeFile = File(qrcodePath);

    if (!await qrcodeFile.exists()) {
      Get.showSnackbar(GetSnackBar(
        message: '二维码图片不存在：$qrcodePath',
        duration: const Duration(seconds: 3),
      ));
      _isQrcodeShowing.value = false;
      return;
    }

    // 清除图片缓存，防止多次生成同名二维码时 UI 显示旧的失效二维码
    await FileImage(qrcodeFile).evict();

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
            Obx(() {
              // Trigger rebuild when refreshed
              final _ = _qrcodeRefreshTrigger.value;
              return Image.file(
                qrcodeFile,
                key: ValueKey(DateTime.now().millisecondsSinceEpoch),
                width: 200,
                height: 200,
                fit: BoxFit.contain,
              );
            }),
          ],
        ),
      ),
    );

    // 检查异步等待期间是否已经触发了登录成功
    if (isQrcodeProcessed) {
      _isQrcodeShowing.value = false;
      _qrcodeDialog = null;
      return;
    }

    // 使用GetX的导航管理避免上下文问题
    await Get.dialog(
      _qrcodeDialog!,
      barrierDismissible: false,
    );

    _isQrcodeShowing.value = false;
    _qrcodeDialog = null;
  }

  void handleMaibotOutput(String event) async {
    // 剥离ANSI颜色代码
    final cleanEvent = NapcatLogParser.stripAnsi(event);

    // 适配新版日志：🔑 WebUI 登录 Token: ...
    final token = NapcatLogParser.parseMaibotToken(cleanEvent);
    if (token != null) {
      // 从日志中动态捕获到 Token，直接更新状态，不再从文件重复读取
      maiBotWebUiToken.value = token;
      Log.i('成功从日志中抓取到 MaiBot Token: $token', tag: 'MaiBot');
    }
  }

  // 检测登录并询问是否保存QQ
  void _checkAndPromptSaveQQ() async {
    try {
      final String configPath = '$ubuntuPath/root/napcat/config';
      final Directory configDir = Directory(configPath);
      if (!await configDir.exists()) return;

      // 扫描 onebot11_QQ.json 文件
      final List<FileSystemEntity> files = await configDir.list().toList();
      String? loggedInQQ;

      for (var file in files) {
        final String fileName = file.path.split(Platform.pathSeparator).last;
        if (fileName.startsWith('onebot11_') && fileName.endsWith('.json')) {
          loggedInQQ = fileName.substring(
              'onebot11_'.length, fileName.length - '.json'.length);
          // 确保是纯数字QQ号
          if (NapcatLogParser.isQQNumber(loggedInQQ)) {
            break;
          } else {
            loggedInQQ = null;
          }
        }
      }

      if (loggedInQQ == null || loggedInQQ.isEmpty) return;

      // 读取 webui.json
      final File webuiFile = File('$configPath/webui.json');
      if (!await webuiFile.exists()) return;

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
      Log.e('检测登录账号失败: $e', tag: 'MaiBot');
    }
  }
}
