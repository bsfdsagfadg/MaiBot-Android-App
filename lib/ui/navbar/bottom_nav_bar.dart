import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/home_controller.dart';

class WebViewBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const WebViewBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final HomeController homeController = Get.find<HomeController>();

    // 使用 Obx 来响应式监听变化
    return Obx(() {
      // 检查 NapCat WebUI 是否启用
      final bool napCatEnabled =
          homeController.napcatController.napCatWebUiEnabledRx.value;

      // 获取自定义 WebView 列表
      final customWebViews = homeController.webviewController.customWebViews;

      // 动态构建导航栏项目
      final List<BottomNavigationBarItem> navItems = [
        const BottomNavigationBarItem(
          icon: Icon(Icons.smart_toy_outlined),
          activeIcon: Icon(Icons.smart_toy_rounded),
          label: 'MaiBot',
        ),
        if (napCatEnabled)
          const BottomNavigationBarItem(
            icon: Icon(Icons.pets_outlined),
            activeIcon: Icon(Icons.pets_rounded),
            label: 'NapCat',
          ),
        // 添加自定义 WebView 项
        ...customWebViews.map((webview) => BottomNavigationBarItem(
              icon: const Icon(Icons.language_outlined),
              activeIcon: const Icon(Icons.language_rounded),
              label: webview['title'] ?? 'WebUI',
            )),
        const BottomNavigationBarItem(
          icon: Icon(Icons.terminal_outlined),
          activeIcon: Icon(Icons.terminal_rounded),
          label: '终端',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings_rounded),
          label: '设置',
        ),
      ];

      final theme = Theme.of(context);
      final primaryColor = theme.colorScheme.primary;

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: Colors.black.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex >= navItems.length
              ? navItems.length - 1
              : currentIndex,
          onTap: onTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedItemColor: primaryColor,
          unselectedItemColor: Colors.black45,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          items: navItems,
        ),
      );
    });
  }
}
