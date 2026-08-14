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

import '../../controllers/theme_controller.dart';
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
      Log.e('打开文件管理器失败: $e', tag: 'MaiBot');
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
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final ThemeController themeController = Get.find<ThemeController>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: _buildHeaderCard(primaryColor),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSectionHeader('界面与主题', Icons.palette_rounded),
                _buildThemeCard(themeController),
                const SizedBox(height: 16),
                _buildSectionHeader('常用操作', Icons.tune_rounded),
                _buildCard([
                  _buildSettingTile(
                    icon: Icons.home_rounded,
                    iconColor: Colors.blue,
                    title: '回到 MaiBot 主页',
                    subtitle: '重置并刷新 MaiBot 页面',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: () {
                      widget.maiBotController.loadRequest(
                        Uri.parse('http://127.0.0.1:${Ports.maibotWeb}'),
                      );
                      widget.onNavigate(0);
                      Get.snackbar(
                        '已跳转',
                        'MaiBot 页面已重置并刷新',
                        snackPosition: SnackPosition.BOTTOM,
                        duration: const Duration(seconds: 2),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingTile(
                    icon: Icons.account_circle_rounded,
                    iconColor: Colors.indigo,
                    title: '快速登录 QQ',
                    subtitle: '配置自动免扫码登录的 QQ 账号',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: () => showQuickLoginDialog(),
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingTile(
                    icon: Icons.folder_open_rounded,
                    iconColor: Colors.amber.shade800,
                    title: '查看数据目录与文件',
                    subtitle: '通过系统文件管理或 MT 管理器浏览 Ubuntu 环境目录',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: () => _openFileManager(),
                  ),
                ]),
                const SizedBox(height: 16),
                _buildSectionHeader('控制面板与令牌', Icons.dashboard_rounded),
                _buildCard([
                  Obx(() {
                    final enabled = homeController.napcatController.napCatWebUiEnabledRx.value;
                    return SwitchListTile(
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.web_rounded, color: Colors.teal, size: 22),
                      ),
                      title: const Text('NapCat 控制面板', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      subtitle: Text(
                        enabled ? '已开启：可在底部导航栏访问 NapCat 控制台' : '已关闭：底部导航栏不显示 NapCat 面板',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      value: enabled,
                      activeThumbColor: primaryColor,
                      onChanged: (bool value) {
                        homeController.napcatController.setNapCatWebUiEnabled(value);
                        Get.snackbar(
                          value ? 'WebUI 已启用' : 'WebUI 已禁用',
                          value ? 'NapCat 标签页已显示，可直接访问控制面板' : 'NapCat 标签页已隐藏',
                          snackPosition: SnackPosition.BOTTOM,
                          duration: const Duration(seconds: 2),
                        );
                      },
                    );
                  }),
                  const Divider(height: 1, indent: 56),
                  Obx(() {
                    final token = homeController.napcatController.maiBotWebUiToken.value;
                    return _buildTokenTile(
                      icon: Icons.key_rounded,
                      iconColor: Colors.purple,
                      title: 'MaiBot 登录 Token',
                      token: token,
                    );
                  }),
                  const Divider(height: 1, indent: 56),
                  Obx(() {
                    final token = homeController.napcatController.napCatWebUiToken.value;
                    return _buildTokenTile(
                      icon: Icons.vpn_key_rounded,
                      iconColor: Colors.deepPurple,
                      title: 'NapCat 登录 Token',
                      token: token,
                    );
                  }),
                  const Divider(height: 1, indent: 56),
                  _buildCustomWebViewsSection(),
                ]),
                const SizedBox(height: 16),
                _buildSectionHeader('系统与网络', Icons.settings_suggest_rounded),
                _buildCard([
                  _buildSettingTile(
                    icon: Icons.battery_charging_full_rounded,
                    iconColor: Colors.green,
                    title: '后台保活设置',
                    subtitle: '电池优化、WLAN 保持连接及后台运行配置',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: () {
                      Get.to(() => const KeepAliveSettingsPage());
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingTile(
                    icon: Icons.code_rounded,
                    iconColor: Colors.cyan.shade700,
                    title: '自定义 Git Clone 链接',
                    subtitle: '配置自定义或 Fork 的 MaiBot 仓库地址',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: () => showCustomGitCloneDialog(),
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingTile(
                    icon: Icons.cleaning_services_rounded,
                    iconColor: Colors.orange,
                    title: '清空 WebView 缓存',
                    subtitle: '清理内置网页与控制台的临时缓存',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
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
                ]),
                const SizedBox(height: 16),
                _buildSectionHeader('维护与环境重置', Icons.build_circle_rounded, isDanger: true),
                _buildCard([
                  _buildSettingTile(
                    icon: Icons.backup_rounded,
                    iconColor: Colors.blue.shade700,
                    title: '备份 MaiBot 数据',
                    subtitle: '打包本地配置、插件及数据至手机下载目录',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: () async {
                      await BackupService.performBackup(showLoadingDialog: true);
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingTile(
                    icon: Icons.restart_alt_rounded,
                    iconColor: Colors.orange.shade800,
                    title: '重置 Python 环境',
                    subtitle: '删除虚拟环境并在启动时重新构建依赖',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: MaintenanceActions.resetPythonEnv,
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingTile(
                    icon: Icons.refresh_rounded,
                    iconColor: Colors.deepOrange,
                    title: '重新安装 NapCat 组件',
                    subtitle: '清除 NapCat 文件并触发重新安装',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: MaintenanceActions.reinstallNapcat,
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingTile(
                    icon: Icons.system_update_alt_rounded,
                    iconColor: Colors.deepOrange.shade700,
                    title: '重新安装 MaiBot',
                    subtitle: '重新拉取并安装 MaiBot 代码',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: MaintenanceActions.reinstallMaiBot,
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingTile(
                    icon: Icons.delete_forever_rounded,
                    iconColor: Colors.red,
                    title: '清除 MaiBot 数据',
                    subtitle: '清除本地数据与配置，恢复初始状态',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: MaintenanceActions.clearMaiBotData,
                  ),
                ], backgroundColor: Colors.red.withValues(alpha: 0.02), borderColor: Colors.red.withValues(alpha: 0.15)),
                const SizedBox(height: 16),
                _buildSectionHeader('关于与支持', Icons.info_outline_rounded),
                _buildCard([
                  _buildSettingTile(
                    icon: Icons.verified_rounded,
                    iconColor: primaryColor,
                    title: '软件版本',
                    subtitle: _appVersion.isEmpty ? '加载中...' : 'v$_appVersion（点击检查更新）',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('检查更新', style: TextStyle(fontSize: 12, color: primaryColor, fontWeight: FontWeight.bold)),
                    ),
                    onTap: () => _updateChecker.checkForUpdates(),
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingTile(
                    icon: Icons.privacy_tip_rounded,
                    iconColor: Colors.blueGrey,
                    title: '隐私政策',
                    subtitle: '查看应用隐私保护与开源协议条款',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: () async {
                      try {
                        final privacyContent =
                            await rootBundle.loadString('assets/privacy_policy.md');
                        if (context.mounted) {
                          Get.dialog(
                            Dialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Row(
                                      children: [
                                        const Text(
                                          '隐私政策',
                                          style: TextStyle(
                                            fontSize: 18,
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
                                  Flexible(
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.all(16.0),
                                      child: MarkdownBody(
                                        data: privacyContent,
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
                          Get.snackbar('加载失败', '无法加载隐私政策: $e', snackPosition: SnackPosition.BOTTOM);
                        }
                      }
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingTile(
                    icon: Icons.power_settings_new_rounded,
                    iconColor: Colors.redAccent,
                    title: '退出应用',
                    subtitle: '完全终止前台守护服务与容器进程',
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: MaintenanceActions.exitApp,
                  ),
                ]),
                const SizedBox(height: 36),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withValues(alpha: 0.82)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MaiBot Android',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _appVersion.isEmpty ? '加载中...' : '版本: v$_appVersion',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF69F0AE),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '服务运行中',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {bool isDanger = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isDanger ? Colors.red.shade700 : Colors.black54),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDanger ? Colors.red.shade700 : Colors.black54,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children, {Color? backgroundColor, Color? borderColor}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = backgroundColor ?? (isDark ? const Color(0xFF1E2228) : Colors.white);
    final borderCol = borderColor ?? (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05));

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderCol,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildThemeCard(ThemeController controller) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return _buildCard([
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.color_lens_rounded, color: theme.colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 14),
                const Text(
                  '主题色调',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const Spacer(),
                Obx(() => Text(
                      controller.currentSeedName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: controller.currentSeedColor,
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 14),
            // 色彩选择器横向列表
            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: ThemeController.presetColors.length,
                itemBuilder: (context, index) {
                  final item = ThemeController.presetColors[index];
                  return Obx(() {
                    final isSelected = controller.selectedColorIndex.value == index;
                    return GestureDetector(
                      onTap: () => controller.setColorIndex(index),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: item.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: item.color.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  });
                },
              ),
            ),
          ],
        ),
      ),
      const Divider(height: 1, indent: 56),
      // 主题模式选择
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.brightness_medium_rounded, color: Colors.amber, size: 22),
            ),
            const SizedBox(width: 14),
            const Text(
              '显示模式',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const Spacer(),
            Obx(() {
              final mode = controller.currentThemeMode.value;
              return SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.auto_mode_rounded, size: 16), label: Text('自动', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded, size: 16), label: Text('浅色', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded, size: 16), label: Text('深色', style: TextStyle(fontSize: 12))),
                ],
                selected: {mode},
                onSelectionChanged: (Set<ThemeMode> newSelection) {
                  controller.setThemeMode(newSelection.first);
                },
              );
            }),
          ],
        ),
      ),
      Obx(() {
        final mode = controller.currentThemeMode.value;
        final isSystemDark = mode == ThemeMode.system && isDark;
        if (mode == ThemeMode.dark || isSystemDark) {
          return Column(
            children: [
              const Divider(height: 1, indent: 56),
              SwitchListTile(
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.contrast_rounded, color: Colors.blueGrey, size: 22),
                ),
                title: const Text('AMOLED 纯黑暗色', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                subtitle: const Text('纯黑底色背景，降低 OLED 屏幕功耗', style: TextStyle(fontSize: 12, color: Colors.black54)),
                value: controller.isAmoledDark.value,
                activeThumbColor: theme.colorScheme.primary,
                onChanged: (bool value) => controller.setAmoledDark(value),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      }),
    ]);
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildTokenTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String token,
  }) {
    final bool hasToken = token.isNotEmpty;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        hasToken ? (token.length > 20 ? '${token.substring(0, 16)}••••' : token) : '暂未捕获到 Token',
        style: TextStyle(
          fontSize: 12,
          color: hasToken ? Colors.black87 : Colors.black38,
          fontFamily: hasToken ? 'monospace' : null,
        ),
      ),
      trailing: hasToken
          ? OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.copy_rounded, size: 14),
              label: const Text('复制', style: TextStyle(fontSize: 12)),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                Get.snackbar(
                  '已复制',
                  '$title 已复制到剪贴板',
                  snackPosition: SnackPosition.BOTTOM,
                  duration: const Duration(seconds: 2),
                );
              },
            )
          : null,
      onTap: hasToken
          ? () async {
              await Clipboard.setData(ClipboardData(text: token));
              Get.snackbar(
                '已复制',
                '$title 已复制到剪贴板',
                snackPosition: SnackPosition.BOTTOM,
                duration: const Duration(seconds: 2),
              );
            }
          : null,
    );
  }

  Widget _buildCustomWebViewsSection() {
    return Obx(() {
      final customWebViews = homeController.webviewController.customWebViews;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.language_rounded, color: Colors.blue, size: 22),
                ),
                const SizedBox(width: 14),
                const Text(
                  '自定义 WebView 面板',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('添加', style: TextStyle(fontSize: 12)),
                  onPressed: () => showAddWebViewDialog(homeController.webviewController),
                ),
              ],
            ),
          ),
          if (customWebViews.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                '可添加外部插件的 Web 控制面板并显示在底部导航栏',
                style: TextStyle(color: Colors.black38, fontSize: 12),
              ),
            )
          else
            ...List.generate(customWebViews.length, (index) {
              final webview = customWebViews[index];
              return Column(
                children: [
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    title: Text(webview['title'] ?? 'WebUI', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text(webview['url'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black45)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.black54),
                          onPressed: () => showEditWebViewDialog(homeController.webviewController, index, webview),
                          tooltip: '编辑',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                          onPressed: () => showConfirmDeleteWebView(homeController.webviewController, index, webview['title'] ?? 'WebUI'),
                          tooltip: '删除',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
        ],
      );
    });
  }
}
