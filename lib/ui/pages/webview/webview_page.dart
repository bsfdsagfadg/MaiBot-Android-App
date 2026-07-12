import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../controllers/terminal_controller.dart';
import '../settings/settings_page.dart';
import '../terminal/terminal_tab_view.dart';
import '../../navbar/bottom_nav_bar.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int _previousNavItemCount = 0; // 记录上一次导航栏项目数量

  late final WebViewController _maiBotController;
  late final WebViewController _napCatController;
  final Map<String, WebViewController> _customControllers = {}; // 存储自定义 WebView 控制器，使用 URL 作为 key

  final HomeController homeController = Get.find<HomeController>();

  // 标记 MaiBot WebView 是否初始化
  bool _maiBotInitialized = false;

  Worker? _customWebViewsWorker;
  Worker? _napCatTokenWorker;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSystemUI();
    _initMaiBotController();
    _initNapCatController();

    // 监听自定义 WebView 列表变化,清理已删除的控制器
    _customWebViewsWorker = ever(homeController.webviewController.customWebViews, (List<Map<String, String>> webviews) {
      // 清理不再存在的控制器
      final validUrls = webviews.map((wv) => wv['url'] ?? '').toSet();
      final controllersToRemove = _customControllers.keys.where((key) => !validUrls.contains(key)).toList();
      for (final key in controllersToRemove) {
        _customControllers.remove(key);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _customWebViewsWorker?.dispose();
    _napCatTokenWorker?.dispose();
    _restoreSystemUI();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _maiBotController.clearCache();
      _maiBotController.loadRequest(Uri.parse('about:blank'));
      _napCatController.clearCache();
      _napCatController.loadRequest(Uri.parse('about:blank'));
      for (var controller in _customControllers.values) {
        controller.clearCache();
        controller.loadRequest(Uri.parse('about:blank'));
      }
    } else if (state == AppLifecycleState.resumed) {
      _maiBotController.loadRequest(Uri.parse('http://127.0.0.1:8001'));
      if (homeController.napcatController.napCatWebUiToken.isNotEmpty) {
        _napCatController.loadRequest(Uri.parse('http://127.0.0.1:6099/webui?token=\${homeController.napcatController.napCatWebUiToken.value}'));
      } else {
        _napCatController.loadRequest(Uri.parse('http://127.0.0.1:6099/webui'));
      }
      _customControllers.forEach((url, controller) {
        controller.loadRequest(Uri.parse(url));
      });
    }
  }

  void _initSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));
  }

  void _restoreSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
  }

  // 检查URL是否为本地地址
  bool _isLocalUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      // 检查是否为本地地址
      return host == 'localhost' ||
             host == '127.0.0.1' ||
             host == '0.0.0.0' ||
             host.startsWith('192.168.') ||
             host.startsWith('10.') ||
             (host.startsWith('172.') && _isPrivateIp172(host));
    } catch (e) {
      debugPrint('Error parsing URL: $e');
      return false;
    }
  }

  // 检查是否为172.16.0.0 - 172.31.255.255范围的私有IP
  bool _isPrivateIp172(String host) {
    final parts = host.split('.');
    if (parts.length >= 2) {
      final secondOctet = int.tryParse(parts[1]);
      return secondOctet != null && secondOctet >= 16 && secondOctet <= 31;
    }
    return false;
  }

  // 在外部浏览器中打开URL
  Future<void> _launchInBrowser(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        debugPrint('Cannot launch URL: $url');
        if (mounted) {
          Get.snackbar(
            '无法打开链接',
            '无法在浏览器中打开此链接',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
      if (mounted) {
        Get.snackbar(
          '打开失败',
          '打开链接时出错: $e',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  void _initMaiBotController() {
    _maiBotController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            // 拦截外域URL
            if (!_isLocalUrl(request.url)) {
              debugPrint('Intercepting external URL: ${request.url}');
              _launchInBrowser(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) {
            _injectClipboardScript(_maiBotController);
            _disableZoom(_maiBotController);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('MaiBot WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse('http://127.0.0.1:8001'));

    if (_maiBotController.platform is AndroidWebViewController) {
      if (kDebugMode) {
        AndroidWebViewController.enableDebugging(true);
      }
      final androidController = _maiBotController.platform as AndroidWebViewController;
      androidController
          .setMediaPlaybackRequiresUserGesture(false);
      // 设置混合内容模式以提高兼容性（Android 9+ 需要）
      androidController.setMixedContentMode(MixedContentMode.compatibilityMode);
      // 允许访问本地文件和内容
      androidController.setAllowFileAccess(true);
      androidController.setAllowContentAccess(true);
      // 设置文件选择回调
      androidController.setOnShowFileSelector(_handleFileSelection);
    }

    _maiBotController.addJavaScriptChannel(
      'Android',
      onMessageReceived: (JavaScriptMessage message) {
        if (message.message == 'getClipboardData') {
          _getClipboardData(_maiBotController);
        }
      },
    );

    setState(() {
      _maiBotInitialized = true;
    });
  }

  void _initNapCatController() {
    _napCatController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            // 拦截外域URL
            if (!_isLocalUrl(request.url)) {
              debugPrint('Intercepting external URL: ${request.url}');
              _launchInBrowser(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) {
            _disableZoom(_napCatController);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('NapCat WebView error: ${error.description}');
          },
        ),
      );

    // 监听 Token 变化
    _napCatTokenWorker = ever(homeController.napcatController.napCatWebUiToken, (String token) {
      if (token.isNotEmpty) {
        final url = 'http://127.0.0.1:6099/webui?token=$token';
        _napCatController.loadRequest(Uri.parse(url));
      }
    });

    // 初始加载
    if (homeController.napcatController.napCatWebUiToken.isNotEmpty) {
      final url = 'http://127.0.0.1:6099/webui?token=${homeController.napcatController.napCatWebUiToken.value}';
      _napCatController.loadRequest(Uri.parse(url));
    } else {
      _napCatController.loadRequest(Uri.parse('http://127.0.0.1:6099/webui'));
    }

    if (_napCatController.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      final androidController = _napCatController.platform as AndroidWebViewController;
      androidController
          .setMediaPlaybackRequiresUserGesture(false);
      // 设置混合内容模式以提高兼容性（Android 9+ 需要）
      androidController.setMixedContentMode(MixedContentMode.compatibilityMode);
      // 允许访问本地文件和内容
      androidController.setAllowFileAccess(true);
      androidController.setAllowContentAccess(true);
      // 设置文件选择回调
      androidController.setOnShowFileSelector(_handleFileSelection);
    }
  }

  // 创建自定义 WebView 控制器
  WebViewController _createCustomController(String url) {
    final controller = WebViewController();

    // 检查初始URL是否为本地地址，如果是则启用外域拦截
    final shouldInterceptExternal = _isLocalUrl(url);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            // 仅对配置为本地URL的WebView启用外域拦截
            if (shouldInterceptExternal && !_isLocalUrl(request.url)) {
              debugPrint('Intercepting external URL from custom WebView: ${request.url}');
              _launchInBrowser(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (String pageUrl) {
            _disableZoom(controller);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('Custom WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setMixedContentMode(MixedContentMode.compatibilityMode);
      androidController.setAllowFileAccess(true);
      androidController.setAllowContentAccess(true);
      // 设置文件选择回调
      androidController.setOnShowFileSelector(_handleFileSelection);
    }

    return controller;
  }

  // 获取或创建自定义 WebView 控制器
  WebViewController _getCustomController(String url) {
    // 如果控制器存在但URL已更改，删除旧控制器并创建新的
    if (_customControllers.containsKey(url)) {
      return _customControllers[url]!;
    }

    // 创建新控制器
    _customControllers[url] = _createCustomController(url);
    return _customControllers[url]!;
  }

  // 处理文件选择 (已更新以修复并适配新版 file_picker API)
  Future<List<String>> _handleFileSelection(FileSelectorParams params) async {
    try {
      // 用于存放最终选择的文件列表
      List<PlatformFile> pickedFiles = [];

      // 判断是否接受多个文件
      final bool allowMultiple = params.mode == FileSelectorMode.openMultiple;

      // 提取文件类型与允许的扩展名参数
      FileType pickingType = FileType.any;
      List<String>? allowedExtensions;

      if (params.acceptTypes.isNotEmpty) {
        final acceptTypes = params.acceptTypes;

        // 检查是否只接受图片
        final bool isImageOnly = acceptTypes.every((type) =>
          type.startsWith('image/') ||
          ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(type.toLowerCase())
        );

        // 检查是否只接受视频
        final bool isVideoOnly = acceptTypes.every((type) =>
          type.startsWith('video/') ||
          ['mp4', 'avi', 'mov', 'mkv', 'flv', 'wmv', '.mp4', '.avi', '.mov', '.mkv', '.flv', '.wmv'].contains(type.toLowerCase())
        );

        // 检查是否只接受音频
        final bool isAudioOnly = acceptTypes.every((type) =>
          type.startsWith('audio/') ||
          ['mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac', '.mp3', '.wav', '.ogg', '.flac', '.m4a', '.aac'].contains(type.toLowerCase())
        );

        if (isImageOnly) {
          pickingType = FileType.image;
        } else if (isVideoOnly) {
          pickingType = FileType.video;
        } else if (isAudioOnly) {
          pickingType = FileType.audio;
        } else {
          // 提取所有允许的扩展名
          final List<String> extensions = [];
          for (final type in acceptTypes) {
            // 如果是扩展名格式 (如 .txt, .pdf)
            if (type.startsWith('.')) {
              extensions.add(type.substring(1));
            }
            // 如果是文件扩展名格式 (如 txt, pdf)
            else if (!type.contains('/')) {
              extensions.add(type);
            }
          }

          if (extensions.isNotEmpty) {
            pickingType = FileType.custom;
            allowedExtensions = extensions;
          }
        }
      }

      // 根据是否多选，调用相应的 API
      if (allowMultiple) {
        // 多选情况：直接使用 pickFiles（不再传递已弃用的 allowMultiple 参数）
        final FilePickerResult? result = await FilePicker.pickFiles(
          type: pickingType,
          allowedExtensions: allowedExtensions,
        );
        if (result != null) {
          pickedFiles = result.files;
        }
      } else {
        // 单选情况：使用新 API pickFile()，它返回单个 PlatformFile?
        final PlatformFile? file = await FilePicker.pickFile(
          type: pickingType,
          allowedExtensions: allowedExtensions,
        );
        if (file != null) {
          pickedFiles = [file];
        }
      }

      // 返回选中的文件路径,转换为 file:// URI 格式
      if (pickedFiles.isNotEmpty) {
        final List<String> filePaths = pickedFiles
            .where((file) => file.path != null)
            .map((file) {
              final path = file.path!;
              // 如果路径已经是 file:// 开头,直接返回
              if (path.startsWith('file://')) {
                return path;
              }
              // 否则转换为 file:// URI
              // 在 Windows 上路径可能包含反斜杠,需要替换为正斜杠
              final normalizedPath = path.replaceAll('\\', '/');
              return 'file://$normalizedPath';
            })
            .toList();

        debugPrint('Selected files: $filePaths');
        return filePaths;
      }

      return [];
    } catch (e) {
      debugPrint('File selection error: $e');
      return [];
    }
  }

  void _injectClipboardScript(WebViewController controller) {
    const String jsCode = '''
      const originalReadText = navigator.clipboard.readText;
      navigator.clipboard.readText = function () {
        console.log('Intercepted clipboard read');
        return new Promise((resolve) => {
          Android.postMessage('getClipboardData');
          setTimeout(() => {
            originalReadText.call(navigator.clipboard).then(text => {
              resolve(text);
            }).catch(() => resolve(''));
          }, 100);
        });
      };
    ''';
    controller.runJavaScript(jsCode);
  }

  void _disableZoom(WebViewController controller) {
    const String jsCode = '''
      (function() {
        var meta = document.querySelector('meta[name="viewport"]');
        if (meta) {
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
        } else {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
          document.head.appendChild(meta);
        }

        // 禁用双击缩放
        var lastTouchEnd = 0;
        document.addEventListener('touchend', function(event) {
          var now = Date.now();
          if (now - lastTouchEnd <= 300) {
            event.preventDefault();
          }
          lastTouchEnd = now;
        }, false);

        // 禁用手势缩放
        document.addEventListener('gesturestart', function(event) {
          event.preventDefault();
        }, false);
      })();
    ''';
    controller.runJavaScript(jsCode);
  }

  Future<void> _getClipboardData(WebViewController controller) async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text ?? '';
    controller.runJavaScript('window.clipboardText = "$text";');
  }

  @override
  Widget build(BuildContext context) {
    if (!_maiBotInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Obx(() {
      // 检查 NapCat WebUI 是否启用
      final bool napCatEnabled = homeController.napcatController.napCatWebUiEnabledRx.value;
      final customWebViews = homeController.webviewController.customWebViews;

      // 动态构建页面列表
      final List<Widget> pages = [
        // 1. MaiBot 配置页面
        Visibility(
          visible: _currentIndex == 0,
          maintainState: true,
          child: WebViewWidget(controller: _maiBotController),
        ),

        // 2. NapCat 配置页面（仅在启用时添加）
        if (napCatEnabled)
          Visibility(
            visible: _currentIndex == 1,
            maintainState: true,
            child: WebViewWidget(controller: _napCatController),
          ),

        // 3. 自定义 WebView 页面
        ...List.generate(customWebViews.length, (index) {
          final webview = customWebViews[index];
          final url = webview['url'] ?? '';
          final int pageIndex = index + (napCatEnabled ? 2 : 1);
          return Visibility(
            visible: _currentIndex == pageIndex,
            maintainState: true,
            child: WebViewWidget(
              controller: _getCustomController(url),
            ),
          );
        }),
      ];

      // 计算设置页的索引（终端页在倒数第二，设置页在最后）
      final int settingsIndex = pages.length + 1;
      final int currentNavItemCount = pages.length + 2; // 总导航项数量

      // 最简单的逻辑：导航栏数量变化时，直接锁定焦点到最大值（设置页）
      int validCurrentIndex = _currentIndex;
      if (_previousNavItemCount != 0 && _previousNavItemCount != currentNavItemCount) {
        // 导航栏数量发生变化，锁定到设置页
        validCurrentIndex = settingsIndex;
        _previousNavItemCount = currentNavItemCount;
        // 异步更新状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _currentIndex = settingsIndex;
            });
          }
        });
      } else if (_previousNavItemCount == 0) {
        // 首次加载，记录导航栏数量
        _previousNavItemCount = currentNavItemCount;
      }

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            top: true,
            child: IndexedStack(
              index: validCurrentIndex,
              children: [
                ...pages,

                // 4. 终端页面（使用新的标签页视图）
                const TerminalTabView(),

                // 5. 软件设置页面
                SettingsPage(
                  maiBotController: _maiBotController,
                  napCatController: _napCatController,
                  onNavigate: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                ),
              ],
            ),
          ),
          bottomNavigationBar: WebViewBottomNavBar(
            currentIndex: validCurrentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
        ),
      );
    });
  }
}