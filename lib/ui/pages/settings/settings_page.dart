import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:global_repository/global_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../controllers/home_controller.dart';
import '../../../core/constants/scripts.dart' as scripts;
import '../../../core/config/app_config.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/utils/version_utils.dart';
import 'dialogs/update_dialogs.dart';
import 'dialogs/webview_crud_dialogs.dart';
import 'dialogs/quick_login_dialog.dart';
import 'dialogs/git_clone_dialog.dart';
import 'keep_alive_settings_page.dart';
import 'maintenance_actions.dart';

class SettingsPage extends StatefulWidget {
  final WebViewController maiBotController;
  final WebViewController napCatController;
  final Function(int) onNavigate;

  const SettingsPage({
    super.key,
    required this.maiBotController,
    required this.napCatController,
    required this.onNavigate,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '';
  final HomeController homeController = Get.find<HomeController>();
  final UpdateChecker _updateChecker = UpdateChecker();

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final version = await getAppVersion();
    setState(() {
      _appVersion = version;
    });
  }

  // 打开文件管理器并导航到 MaiBot Ubuntu 文件系统位置
  Future<void> _openFileManager() async {
    try {
      // 使用 DocumentsProvider 的 content URI 打开文件管理器
      // authority: com.maibot.maibot_android.documents
      // rootId: ubuntu_root
      final contentUri = Uri.parse(
        'content://${Config.packageName}.documents/root/ubuntu_root',
      );

      if (await canLaunchUrl(contentUri)) {
        await launchUrl(
          contentUri,
          mode: LaunchMode.externalApplication,
        );

        Get.snackbar(
          '已打开',
          '已在文件管理器中打开 MaiBot Ubuntu 文件系统',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2),
        );
      } else {
        // 如果无法打开，提供备选方案
        Get.dialog(
          AlertDialog(
            title: const Text('打开文件系统'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ubuntu 文件系统已挂载至系统"文件"应用的侧栏，名称为:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text(
                  'MaiBot Ubuntu',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '你可以手动打开系统"文件"应用，在侧栏中找到"MaiBot Ubuntu"来访问。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  '或使用 MT 文件管理器等应用，添加以下路径至侧栏:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  scripts.ubuntuPath,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: scripts.ubuntuPath));
                  Get.back();
                  Get.snackbar(
                    '已复制',
                    '路径已复制到剪贴板',
                    snackPosition: SnackPosition.BOTTOM,
                    duration: const Duration(seconds: 2),
                  );
                },
                child: const Text('复制路径'),
              ),
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      Log.e('[MaiBot] ${'打开文件管理器失败: $e'}');
      Get.snackbar(
        '打开失败',
        '无法打开文件管理器: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            '设置',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('软件版本'),
          subtitle: Text(
            _appVersion.isEmpty ? '加载中...' : '$_appVersion（点击检查更新）',
          ),
          onTap: () => _updateChecker.checkForUpdates(),
        ),
        ListTile(
          leading: const Icon(Icons.home),
          title: const Text('回到 MaiBot 主页'),
          subtitle: const Text('重置并刷新 MaiBot 页面'),
          onTap: () {
            // 重置 MaiBot WebView URL 并刷新
            widget.maiBotController.loadRequest(
              Uri.parse('http://127.0.0.1:${Ports.maibotWeb}'),
            );

            // 跳转到 MaiBot 标签页（索引 0）
            widget.onNavigate(0);

            Get.snackbar(
              '已跳转',
              'MaiBot 页面已重置并刷新',
              snackPosition: SnackPosition.BOTTOM,
              duration: const Duration(seconds: 2),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: const Text('更新或重装 MaiBot'),
          subtitle: const Text('清除 MaiBot 组件并重新安装最新版本'),
          onTap: MaintenanceActions.reinstallMaiBot,
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('更新或重装 NapcatQQ'),
          subtitle: const Text('清除 NapcatQQ 组件并重新安装最新版本'),
          onTap: MaintenanceActions.reinstallNapcat,
        ),
        ListTile(
          leading: const Icon(Icons.backup),
          title: const Text('备份 MaiBot 数据'),
          subtitle: const Text('备份 MaiBot 配置和数据到手机存储'),
          onTap: () async {
            await BackupService.performBackup(showLoadingDialog: true);
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete),
          title: const Text('清除 MaiBot 数据'),
          subtitle: const Text('彻底清除 MaiBot 所有数据和本地配置，\n重启时自动从备份恢复或全新干净初始化'),
          onTap: MaintenanceActions.clearMaiBotData,
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('重置 Python 环境'),
          subtitle: const Text('删除虚拟环境并重启应用，启动时将自动重建'),
          onTap: MaintenanceActions.resetPythonEnv,
        ),
        ListTile(
          leading: const Icon(Icons.login),
          title: const Text('快速登录 QQ'),
          subtitle: const Text('配置自动登录的QQ账号'),
          onTap: () => showQuickLoginDialog(),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              const Text(
                '自定义 WebView',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                onPressed: () =>
                    showAddWebViewDialog(homeController.webviewController),
                tooltip: '添加自定义 WebView',
              ),
            ],
          ),
        ),
        Obx(() {
          final customWebViews =
              homeController.webviewController.customWebViews;
          if (customWebViews.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  '访问插件的 WebUI 面板\n点击右上角"+"添加',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            children: List.generate(customWebViews.length, (index) {
              final webview = customWebViews[index];
              return ListTile(
                leading: const Icon(Icons.language),
                title: Text(webview['title'] ?? 'WebUI'),
                subtitle: Text(webview['url'] ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => showEditWebViewDialog(
                          homeController.webviewController, index, webview),
                      tooltip: '编辑',
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete,
                        size: 20,
                        color: Colors.red,
                      ),
                      onPressed: () => showConfirmDeleteWebView(
                        homeController.webviewController,
                        index,
                        webview['title'] ?? 'WebUI',
                      ),
                      tooltip: '删除',
                    ),
                  ],
                ),
              );
            }),
          );
        }),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            '高级设置',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.security),
          title: const Text('后台保活设置'),
          subtitle: const Text('电池优化、前台服务以及后台锁提示'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Get.to(() => const KeepAliveSettingsPage());
          },
        ),
        ListTile(
          leading: const Icon(Icons.web),
          title: const Text('NapCat WebUI'),
          subtitle: const Text('显示或隐藏 NapCat 网页控制面板（默认隐藏）'),
          trailing: Switch(
            value: homeController.napcatController.napCatWebUiEnabled.get() ??
                false,
            onChanged: (bool value) {
              // 使用新的方法来同步更新响应式变量
              homeController.napcatController.setNapCatWebUiEnabled(value);

              Get.snackbar(
                value ? 'WebUI 已启用' : 'WebUI 已禁用',
                value ? 'NapCat 标签页已显示，可以立即访问控制面板' : 'NapCat 标签页已隐藏',
                snackPosition: SnackPosition.BOTTOM,
                duration: const Duration(seconds: 2),
              );
            },
          ),
        ),
        Obx(() {
          final token = homeController.napcatController.napCatWebUiToken.value;
          return ListTile(
            leading: const Icon(Icons.vpn_key),
            title: const Text('NapCat 登录 token'),
            subtitle: Text(token.isEmpty ? '暂未获取到token' : token),
            onTap: token.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: token));
                    Get.snackbar(
                      '已复制',
                      'NapCat Token 已复制到剪贴板',
                      snackPosition: SnackPosition.BOTTOM,
                      duration: const Duration(seconds: 2),
                    );
                  },
          );
        }),
        Obx(() {
          final token = homeController.napcatController.maiBotWebUiToken.value;
          return ListTile(
            leading: const Icon(Icons.key),
            title: const Text('MaiBot 登录 token'),
            subtitle: Text(token.isEmpty ? '暂未获取到token' : token),
            onTap: token.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: token));
                    Get.snackbar(
                      '已复制',
                      'MaiBot Token 已复制到剪贴板',
                      snackPosition: SnackPosition.BOTTOM,
                      duration: const Duration(seconds: 2),
                    );
                  },
          );
        }),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('自定义 Git Clone 命令'),
          subtitle: const Text('自定义 MaiBot 的获取方式'),
          onTap: () => showCustomGitCloneDialog(),
        ),
        ListTile(
          leading: const Icon(Icons.folder),
          title: const Text('文件系统'),
          subtitle: const Text(
            '内置 Ubuntu 文件系统已挂载至 \'文件\'\n可添加至 MT 文件管理器侧栏以快捷访问',
          ),
          onTap: () => _openFileManager(),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('清空 WebView 缓存'),
          subtitle: const Text('清理所有 WebView 缓存'),
          onTap: () async {
            try {
              await widget.maiBotController.clearCache();
              await widget.napCatController.clearCache();
              if (context.mounted) {
                Get.snackbar(
                  '成功',
                  'WebView 缓存已清理',
                  snackPosition: SnackPosition.BOTTOM,
                );
              }
            } catch (e) {
              if (context.mounted) {
                Get.snackbar(
                  '清理失败',
                  e.toString(),
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('隐私政策'),
          subtitle: const Text('查看应用隐私政策'),
          onTap: () async {
            try {
              final privacyContent =
                  await rootBundle.loadString('assets/privacy_policy.md');
              if (context.mounted) {
                Get.dialog(
                  Dialog(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              const Text(
                                '隐私政策',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Get.back(),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16.0),
                            child: MarkdownBody(
                              data: privacyContent,
                              styleSheet: MarkdownStyleSheet(
                                h1: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                h2: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                h3: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                p: const TextStyle(fontSize: 14),
                                listBullet: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                Get.snackbar(
                  '加载失败',
                  '无法加载隐私政策: $e',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            }
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.exit_to_app, color: Colors.red),
          title: const Text(
            '退出应用',
            style: TextStyle(color: Colors.red),
          ),
          subtitle: const Text('退出 MaiBot 应用'),
          onTap: MaintenanceActions.exitApp,
        ),
      ],
    );
  }
}
