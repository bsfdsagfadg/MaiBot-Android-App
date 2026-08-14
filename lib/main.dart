import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';
import 'dart:async';

import 'generated/l10n.dart';
import 'core/config/app_config.dart';
import 'core/services/env_bootstrapper.dart';
import 'core/services/foreground_service.dart';
import 'ui/routes/app_routes.dart';
import 'ui/controllers/home_controller.dart';
import 'ui/controllers/theme_controller.dart';

// Notice: behavior will submit Device

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 隐藏系统 UI
  // Hide system UI
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [
    SystemUiOverlay.top,
    // SystemUiOverlay.bottom,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // Android 状态栏图标为白色
    statusBarBrightness: Brightness.dark, // iOS 状态栏图标为白色
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  RuntimeEnvir.initEnvirWithPackageName(Config.packageName);
  await initSettingStore(RuntimeEnvir.configPath);

  // 初始化运行环境（释放原生二进制链接，防止由于拉起服务过快导致无 proot 可执行）
  await EnvBootstrapper.initEnvir();

  // 初始化前台服务
  ForegroundServiceManager.init();


  runApp(
    Builder(builder: (context) {
      return ViewMetric(
        uiWidth: 375,
        screenWidth: MediaQuery.of(context).size.width,
        child: const MaiBot(),
      );
    }),
  );
}

class MaiBot extends StatefulWidget {
  const MaiBot({super.key});

  @override
  State<MaiBot> createState() => _MaiBotState();
}

class _MaiBotState extends State<MaiBot> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 当应用完全退出时，确保清理所有资源
    if (state == AppLifecycleState.detached) {
      Log.i('应用正在退出，清理所有资源...', tag: 'MaiBot');
      try {
        // 尝试获取并清理 HomeController
        if (Get.isRegistered<HomeController>()) {
          Get.delete<HomeController>(force: true);
        }
      } catch (e) {
        Log.e('清理资源时出错: $e', tag: 'MaiBot');
      }
    }
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    final ThemeController themeController = Get.put(ThemeController(), permanent: true);

    return Obx(() {
      return GetMaterialApp(
        title: 'MaiBot Android',
        theme: themeController.getLightTheme(),
        darkTheme: themeController.getDarkTheme(),
        themeMode: themeController.currentThemeMode.value,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        initialRoute: AppRoutes.terminal,
        getPages: AppRoutes.routes,
      );
    });
  }
}
