import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';
import 'package:xterm/xterm.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../generated/l10n.dart';
import '../../core/constants/scripts.dart';
import '../../core/utils/file_utils.dart';
import '../routes/app_routes.dart';
import 'terminal_tab_manager.dart';

class HomeController extends GetxController {
  // 终端标签页管理器
  late final TerminalTabManager terminalTabManager;
  // bool vsCodeStaring = false;
  SettingNode privacySetting = 'privacy'.setting;
  SettingNode napCatWebUiEnabled = 'napcat_webui_enabled'.setting;
  SettingNode showTerminalWhiteText = 'show_terminal_white_text'.setting;
  Pty? pseudoTerminal;
  Pty? napcatTerminal;

  final RxString napCatWebUiToken = ''.obs; // 存储 NapCat WebUI Token
  final RxString maiBotWebUiToken = ''.obs; // 存储 MaiBot WebUI Token
  final RxBool _isQrcodeShowing = false.obs;
  final RxBool napCatWebUiEnabledRx = false.obs; // GetX 响应式变量用于导航栏更新
  final RxList<Map<String, String>> customWebViews =
      <Map<String, String>>[].obs; // 自定义 WebView 列表
  Dialog? _qrcodeDialog;
  StreamSubscription? _qrcodeSubscription;
  StreamSubscription? _webviewSubscription; // 添加webview监听订阅

  late Terminal terminal = Terminal(
    maxLines: 50000, // Increase max lines to prevent terminal from stopping output after 5000 lines
    onResize: (width, height, pixelWidth, pixelHeight) {
      pseudoTerminal?.resize(height, width);
    },
    onOutput: (data) {
      pseudoTerminal?.writeString(data);
    },
  );
  bool webviewHasOpen = false;
  bool _isLocalhostDetected = false; // localhost:6185 检测标志
  bool _isQrcodeProcessed = false; // 二维码处理完成标志
  bool _isAppInForeground = true; // 应用是否在前台

  File progressFile = File('${RuntimeEnvir.tmpPath}/progress');
  File progressDesFile = File('${RuntimeEnvir.tmpPath}/progress_des');
  double progress = 0.0;
  double step = 14.0;
  String currentProgress = '';

  // 进度 +1
  // Progress +1
  void bumpProgress() {
    try {
      int current = 0;
      if (progressFile.existsSync()) {
        final content = progressFile.readAsStringSync().trim();
        if (content.isNotEmpty) {
          current = int.tryParse(content) ?? 0;
        }
      } else {
        progressFile.createSync(recursive: true);
      }
      progressFile.writeAsStringSync('${current + 1}');
    } catch (e) {
      progressFile.writeAsStringSync('1');
    }
    // 使用 microtask 延迟更新，减少渲染压力
    Future.microtask(() => update());
  }

  // 使用 login_ubuntu 函数，传入要执行的命令
  // Use login_ubuntu function, passing the command to execute
  String get command {
    return 'source ${RuntimeEnvir.homePath}/common.sh\nlogin_ubuntu "bash /root/launcher.sh"\n';
  }

  // 检查两个条件是否都满足，如果满足则触发跳转
  void _checkAndNavigateToWebview() {
    // 只有当两个条件都满足且应用在前台时才跳转
    if (_isLocalhostDetected &&
        _isQrcodeProcessed &&
        _isAppInForeground &&
        !webviewHasOpen) {
      Future.microtask(() {
        // 使用路由跳转
        Get.toNamed(AppRoutes.webview);
        webviewHasOpen = true; // 只有真正打开webview时才设置为true
      });
    }
  }

  // 监听输出，当输出中包含启动成功的标志时，启动 VewView 和导航栏页面
  void initWebviewListener() {
    if (pseudoTerminal == null) return;

    _webviewSubscription = pseudoTerminal!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((event) async {
      // 输出到 Flutter 控制台
      // Output to Flutter console
      if (event.trim().isNotEmpty) {
        // 按行分割输出，避免控制台输出混乱
        final lines = event.split('\n');
        for (var line in lines) {
          if (line.trim().isNotEmpty) {
            Log.i(line, tag: 'MaiBot');
          }
        }
      }

      // 捕获 MaiBot WebUI Token
      if (event.contains('WebUI Access Token:')) {
        final match =
            RegExp(r'WebUI Access Token:\s+([a-f0-9]+)').firstMatch(event);
        if (match != null) {
          final token = match.group(1);
          if (token != null) {
            maiBotWebUiToken.value = token;
            Log.i('捕获到 MaiBot Token: $token', tag: 'MaiBot');
          }
        }
      }

      // 检查是否包含 MaiBot 全部系统初始化完成的标志
      if (event.contains('全部系统初始化完成')) {
        _isLocalhostDetected = true;
        bumpProgress();

        // 检查是否两个条件都满足
        _checkAndNavigateToWebview();

        Future.delayed(const Duration(milliseconds: 2000), () {
          update();
        });

        // 不取消订阅，继续监听以便终端日志持续更新
      }

      // 显示所有输出，不再过滤
      terminal.write(event);
    });
  }

  void initQrcodeListener() {
    if (napcatTerminal == null) return;

    _qrcodeSubscription = napcatTerminal!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((event) async {
      // 先判断订阅是否已取消，避免重复处理
      if (_qrcodeSubscription == null) return;

      // 输出到 Flutter 控制台
      // Output to Flutter console
      if (event.trim().isNotEmpty) {
        // 按行分割输出，避免控制台输出混乱
        final lines = event.split('\n');
        for (var line in lines) {
          if (line.trim().isNotEmpty) {
            Log.i(line, tag: 'MaiBot-Napcat');
          }
        }
      }

      // 捕获 NapCat WebUI Token
      if (event.contains('WebUi Token:')) {
        final match = RegExp(r'WebUi Token:\s+(\w+)').firstMatch(event);
        if (match != null) {
          final token = match.group(1);
          if (token != null) {
            napCatWebUiToken.value = token;
            Log.i('捕获到 NapCat Token: $token', tag: 'MaiBot');
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
        _isQrcodeProcessed = true;

        // 扫码登录成功后，检测是否有新的 napcat_<QQ>.json 配置文件
        _checkAndPromptSaveQQ();

        // 检查是否两个条件都满足
        _checkAndNavigateToWebview();

        // 不再在此处取消订阅，让输出流继续流向日志记录器，防止缓冲区满导致进程卡死
        // We no longer cancel subscription here to keep the output flow going to the logger,
        // preventing process hang due to full buffer.
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

        // 不取消订阅，允许用户重新扫码
      }
    });
  }

  // 初始化环境，将动态库中的文件链接到数据目录
  // Init environment and link files from the dynamic library to the data directory
  Future<void> initEnvir() async {
    List<String> androidFiles = [
      'libbash.so',
      'libbusybox.so',
      'liblibtalloc.so.2.so',
      'libloader.so',
      'libproot.so',
      'libsudo.so'
    ];
    String libPath = await getLibPath();
    Log.i('libPath -> $libPath');

    for (int i = 0; i < androidFiles.length; i++) {
      // when android target sdk > 28
      // cannot execute file in /data/data/com.xxx/files/usr/bin
      // so we need create a link to /data/data/com.xxx/files/usr/bin
      final sourcePath = '$libPath/${androidFiles[i]}';
      String fileName = androidFiles[i].replaceAll(RegExp('^lib|\\.so\$'), '');
      String filePath = '${RuntimeEnvir.binPath}/$fileName';
      // custom path, termux-api will invoke
      File file = File(filePath);
      FileSystemEntityType type = await FileSystemEntity.type(filePath);
      Log.i('$fileName type -> $type');
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.link) {
        // old version adb is plain file
        Log.i('find plain file -> $fileName, delete it');
        await file.delete();
      }
      Link link = Link(filePath);
      if (link.existsSync()) {
        try {
          link.deleteSync();
        } catch (e) {
          Log.e('delete link error -> $e');
        }
      }
      try {
        Log.i('create link -> $fileName ${link.path}');
        link.createSync(sourcePath);
      } catch (e) {
        Log.e('installAdbToEnvir error -> $e');
      }
    }

    // 处理 busybox 相关的符号链接，确保 proot 依赖的命令可用
    createBusyboxLink();
  }

  // 同步当前进度
  // Sync the current progress
  void syncProgress() {
    progressFile.createSync(recursive: true);
    progressFile.writeAsStringSync('0');
    progressFile.watch(events: FileSystemEvent.all).listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressFile.readAsString();
        Log.e('content -> $content');
        if (content.isEmpty) {
          return;
        }
        progress = int.parse(content) / step;
        Log.e('progress -> $progress');
        update();
      }
    });
    progressDesFile.createSync(recursive: true);
    progressDesFile.writeAsStringSync('');
    progressDesFile.watch(events: FileSystemEvent.all).listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressDesFile.readAsString();
        if (currentProgress == content) return;
        currentProgress = content;

        // 当进度到达 "Napcat 已安装" 时，启动 NapCat 终端
        if (content.contains('Napcat ${S.current.installed}')) {
          // 检查快速登录
          _checkQuickLogin();

          bumpProgress();
          Log.i('检测到 Napcat 已安装，启动 NapCat 终端', tag: 'MaiBot');
        }

        // 当进度到达 "MaiBot Core 配置中" 时，清除终端
        if (content.trim().contains('MaiBot Core 配置中')) {
          // 清除终端先前显示的所有文本
          terminal.buffer.clear();
          terminal.buffer.setCursor(0, 0);
          Log.i('检测到 MaiBot Core 配置中，清除终端内容', tag: 'MaiBot');
        }

        update();
      }
    });
  }

  // 创建 busybox 的软连接，来确保 proot 会用到的命令正常运行
  // create busybox symlinks, to ensure proot can use the commands normally
  void createBusyboxLink() {
    try {
      List<String> links = [
        ...[
          'awk',
          'ash',
          'basename',
          'bzip2',
          'curl',
          'cp',
          'chmod',
          'cut',
          'cat',
          'du',
          'dd',
          'find',
          'grep',
          'gzip'
        ],
        ...[
          'hexdump',
          'head',
          'id',
          'lscpu',
          'mkdir',
          'realpath',
          'rm',
          'sed',
          'stat',
          'sh',
          'tr',
          'tar',
          'uname',
          'xargs',
          'xz',
          'xxd'
        ]
      ];

      for (String linkName in links) {
        String linkPath = '${RuntimeEnvir.binPath}/$linkName';
        Link link = Link(linkPath);
        if (link.existsSync()) {
          try {
            link.deleteSync();
          } catch (e) {
            Log.e('delete busybox link error -> $e');
          }
        }
        try {
          link.createSync('${RuntimeEnvir.binPath}/busybox');
        } catch (e) {
          Log.e('create busybox link error -> $e');
        }
      }

      String fileLinkPath = '${RuntimeEnvir.binPath}/file';
      Link fileLink = Link(fileLinkPath);
      if (fileLink.existsSync()) {
        try {
          fileLink.deleteSync();
        } catch (e) {
          Log.e('delete file link error -> $e');
        }
      }
      try {
        fileLink.createSync('/system/bin/file');
      } catch (e) {
        Log.e('create file link error -> $e');
      }
    } catch (e) {
      Log.e('Create link failed -> $e');
    }
  }

  void setProgress(String description) {
    currentProgress = description;
    terminal.writeProgress(currentProgress);
  }

  Future<void> loadMaiBot() async {
    syncProgress();

    // 创建相关文件夹
    Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);
    Directory(RuntimeEnvir.homePath).createSync(recursive: true);
    Directory(RuntimeEnvir.binPath).createSync(recursive: true);

    await initEnvir();
    createBusyboxLink();

    // 创建终端
    pseudoTerminal =
        createPTY(rows: terminal.viewHeight, columns: terminal.viewWidth);
    napcatTerminal = createPTY();

    setProgress('复制 Ubuntu 系统镜像...');
    await AssetsUtils.copyAssetToPath('assets/${Config.ubuntuFileName}',
        '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}');
    await AssetsUtils.copyAssetToPath('assets/maibot-startup.sh',
        '${RuntimeEnvir.homePath}/maibot-startup.sh');
    await AssetsUtils.copyAssetToPath('assets/config.toml',
        '${RuntimeEnvir.homePath}/config.toml');
    bumpProgress();

    // 获取当前应用版本号
    final appVersion = await getAppVersion();

    // 替换 maibot-startup.sh 中的版本号占位符
    final startupScriptFile = File('${RuntimeEnvir.homePath}/maibot-startup.sh');
    if (await startupScriptFile.exists()) {
      String scriptContent = await startupScriptFile.readAsString();
      scriptContent = scriptContent.replaceAll('{{VERSION}}', appVersion);
      await startupScriptFile.writeAsString(scriptContent);
    }

    // 写入 common.sh 脚本
    File('${RuntimeEnvir.homePath}/common.sh')
        .writeAsStringSync(getCommonScript(appVersion));

    initWebviewListener();
    bumpProgress();

    initQrcodeListener();

    startMaiBot(pseudoTerminal!);
  }

  Future<void> startMaiBot(Pty pseudoTerminal) async {
    setProgress('开始安装 MaiBot...');
    pseudoTerminal.writeString(
        'source ${RuntimeEnvir.homePath}/common.sh\nstart_maibot\n');
  }

  @override
  void onInit() {
    super.onInit();

    // 初始化终端标签页管理器
    terminalTabManager = TerminalTabManager();

    // 初始化 NapCat WebUI 启用状态
    napCatWebUiEnabledRx.value = napCatWebUiEnabled.get() ?? false;

    // 从持久化存储加载自定义 WebView 列表
    _loadCustomWebViews();

    // 为 Google Play 上架做准备
    // For Google Play
    Future.delayed(Duration.zero, () async {
      if (privacySetting.get() == null) {
        await Get.to(PrivacyAgreePage(
          onAgreeTap: () {
            privacySetting.set(true);
            Get.back();
          },
        ));
      }

      // 加载并启动 MaiBot
      loadMaiBot();

      // 在终端创建完成后初始化固定标签页
      // 等待terminal创建完成
      Future.delayed(const Duration(milliseconds: 500), () {
        terminalTabManager.initializeFixedTab(terminal);
      });
    });

    // 监听应用生命周期状态变化
    WidgetsBinding.instance.addObserver(
      LifecycleObserver(
        onResume: () {
          _isAppInForeground = true;
          // 当应用回到前台且两个条件都满足但webview未打开时，打开webview
          if (_isLocalhostDetected && _isQrcodeProcessed && !webviewHasOpen) {
            Future.microtask(() {
              Get.toNamed(AppRoutes.webview);
              webviewHasOpen = true;
            });
          }
        },
        onPause: () {
          _isAppInForeground = false;
        },
      ),
    );
  }

  // 加载自定义 WebView 列表
  void _loadCustomWebViews() {
    final stored = box!.get('custom_webviews', defaultValue: <dynamic>[]);
    if (stored is List) {
      customWebViews.value = stored.map((e) {
        if (e is Map) {
          return {
            'title': e['title']?.toString() ?? '',
            'url': e['url']?.toString() ?? '',
          };
        }
        return <String, String>{};
      }).toList();
    }
  }

  // 保存自定义 WebView 列表
  void _saveCustomWebViews() {
    box!.put('custom_webviews', customWebViews.toList());
  }

  // 添加自定义 WebView
  void addCustomWebView(String title, String url) {
    customWebViews.add({'title': title, 'url': url});
    _saveCustomWebViews();
  }

  // 删除自定义 WebView
  void removeCustomWebView(int index) {
    if (index >= 0 && index < customWebViews.length) {
      customWebViews.removeAt(index);
      _saveCustomWebViews();
    }
  }

  // 更新自定义 WebView
  void updateCustomWebView(int index, String title, String url) {
    if (index >= 0 && index < customWebViews.length) {
      customWebViews[index] = {'title': title, 'url': url};
      _saveCustomWebViews();
    }
  }

  // 更新 NapCat WebUI 启用状态（用于同步响应式变量）
  void setNapCatWebUiEnabled(bool value) {
    napCatWebUiEnabled.set(value);
    napCatWebUiEnabledRx.value = value;
  }

  // 检查并提示保存 QQ 号
  Future<void> _checkAndPromptSaveQQ() async {
    final configDir = Directory('$ubuntuPath/root/napcat/config');
    if (!await configDir.exists()) return;

    final files = await configDir.list().toList();
    final List<String> qqs = [];
    for (var file in files) {
      if (file is File) {
        final fileName = file.path.split('/').last;
        final match = RegExp(r'napcat_(\d+)\.json').firstMatch(fileName);
        if (match != null) {
          qqs.add(match.group(1)!);
        }
      }
    }

    if (qqs.isNotEmpty) {
      // 获取已保存的快速登录 QQ
      final savedQQsRaw = 'quick_login_qqs'.setting.get() ?? <dynamic>[];
      final savedQQs = List<String>.from(savedQQsRaw.map((e) => e.toString()));

      // 找出未保存的 QQ
      final newQQs = qqs.where((qq) => !savedQQs.contains(qq)).toList();

      if (newQQs.isNotEmpty) {
        _showSaveQQDialog(newQQs.first, savedQQs);
      }
    }
  }

  void _showSaveQQDialog(String qq, List<String> savedQQs) {
    Get.dialog(
      AlertDialog(
        title: const Text('登录成功'),
        content: Text('检测到 QQ 号 $qq，是否保存到快速登录？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              savedQQs.add(qq);
              'quick_login_qqs'.setting.set(savedQQs);
              Get.back();
              Get.snackbar('保存成功', 'QQ 号 $qq 已保存到快速登录');
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 检查是否有可用的快速登录配置
  Future<void> _checkQuickLogin() async {
    final savedQQsRaw = 'quick_login_qqs'.setting.get() ?? <dynamic>[];
    if (savedQQsRaw.isEmpty) {
      napcatTerminal?.writeString('$command\n');
      return;
    }

    final savedQQs = List<String>.from(savedQQsRaw.map((e) => e.toString()));

    // 检查这些 QQ 的配置文件是否真的存在
    final List<String> availableQQs = [];
    for (var qq in savedQQs) {
      if (await File('$ubuntuPath/root/napcat/config/napcat_$qq.json')
          .exists()) {
        availableQQs.add(qq);
      }
    }

    if (availableQQs.isNotEmpty) {
      Get.dialog(
        AlertDialog(
          title: const Text('快速登录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('检测到以下已保存的账号，是否直接登录？'),
              const SizedBox(height: 10),
              ...availableQQs.map((qq) => ListTile(
                    title: Text(qq),
                    onTap: () {
                      Get.back();
                      // 启动 NapCat 并在启动命令中加入 QQ 参数
                      napcatTerminal?.writeString(
                          'source ${RuntimeEnvir.homePath}/common.sh\nlogin_ubuntu "bash /root/launcher.sh -q $qq"\n');
                      Log.i('使用快速登录: $qq', tag: 'MaiBot');
                    },
                  )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Get.back();
                napcatTerminal?.writeString('$command\n');
              },
              child: const Text('扫码登录'),
            ),
          ],
        ),
      );
    } else {
      napcatTerminal?.writeString('$command\n');
    }
  }

  @override
  void onClose() {
    // 清理订阅，避免内存泄漏
    _qrcodeSubscription?.cancel();
    _webviewSubscription?.cancel();
    _qrcodeSubscription = null;
    _webviewSubscription = null;

    // 杀死所有终端进程，释放端口
    try {
      if (pseudoTerminal != null) {
        Log.i('正在关闭主终端进程...', tag: 'MaiBot');
        pseudoTerminal?.kill();
        pseudoTerminal = null;
      }
      if (napcatTerminal != null) {
        Log.i('正在关闭 NapCat 终端进程...', tag: 'MaiBot-Napcat');
        napcatTerminal?.kill();
        napcatTerminal = null;
      }
    } catch (e) {
      Log.e('关闭终端进程时出错: $e', tag: 'MaiBot');
    }

    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(
      LifecycleObserver(
        onResume: () {},
        onPause: () {},
      ),
    );
    super.onClose();
  }
}

// 应用生命周期观察者类
class LifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  final VoidCallback onPause;

  LifecycleObserver({required this.onResume, required this.onPause});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        onResume();
        break;
      case AppLifecycleState.paused:
        onPause();
        break;
      default:
        break;
    }
  }
}
