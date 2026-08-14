import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:settings/settings.dart';

/// 预设主题种子色彩定义
class AppThemeColor {
  final String name;
  final Color color;

  const AppThemeColor(this.name, this.color);
}

class ThemeController extends GetxController {
  static const List<AppThemeColor> presetColors = [
    AppThemeColor('经典蓝', Color(0xFF1976D2)),
    AppThemeColor('麦麦绿', Color(0xFF00A86B)),
    AppThemeColor('深靛蓝', Color(0xFF3F51B5)),
    AppThemeColor('松石青', Color(0xFF00897B)),
    AppThemeColor('落日橙', Color(0xFFF57C00)),
    AppThemeColor('樱花粉', Color(0xFFE91E63)),
    AppThemeColor('优雅紫', Color(0xFF7B1FA2)),
    AppThemeColor('极客绿', Color(0xFF2E7D32)),
    AppThemeColor('岩石灰', Color(0xFF455A64)),
    AppThemeColor('朱砂红', Color(0xFFD32F2F)),
  ];

  final Setting _colorIndexSetting = 'theme_seed_color_index'.setting;
  final Setting _themeModeSetting = 'theme_mode_preference'.setting;
  final Setting _amoledSetting = 'theme_amoled_dark'.setting;

  final RxInt selectedColorIndex = 0.obs;
  final Rx<ThemeMode> currentThemeMode = ThemeMode.system.obs;
  final RxBool isAmoledDark = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadThemeSettings();
  }

  void _loadThemeSettings() {
    final colorIdx = _colorIndexSetting.get();
    if (colorIdx is int && colorIdx >= 0 && colorIdx < presetColors.length) {
      selectedColorIndex.value = colorIdx;
    } else {
      selectedColorIndex.value = 1; // 默认麦麦绿
    }

    final modeVal = _themeModeSetting.get();
    if (modeVal == 'light') {
      currentThemeMode.value = ThemeMode.light;
    } else if (modeVal == 'dark') {
      currentThemeMode.value = ThemeMode.dark;
    } else {
      currentThemeMode.value = ThemeMode.system;
    }

    isAmoledDark.value = _amoledSetting.get() ?? false;
  }

  Color get currentSeedColor => presetColors[selectedColorIndex.value].color;
  String get currentSeedName => presetColors[selectedColorIndex.value].name;

  void setColorIndex(int index) {
    if (index >= 0 && index < presetColors.length) {
      selectedColorIndex.value = index;
      _colorIndexSetting.set(index);
      Get.changeTheme(getLightTheme());
      Get.changeThemeMode(currentThemeMode.value);
    }
  }

  void setThemeMode(ThemeMode mode) {
    currentThemeMode.value = mode;
    if (mode == ThemeMode.light) {
      _themeModeSetting.set('light');
    } else if (mode == ThemeMode.dark) {
      _themeModeSetting.set('dark');
    } else {
      _themeModeSetting.set('system');
    }
    Get.changeThemeMode(mode);
  }

  void setAmoledDark(bool value) {
    isAmoledDark.value = value;
    _amoledSetting.set(value);
    Get.changeTheme(getLightTheme());
    Get.changeThemeMode(currentThemeMode.value);
  }

  ThemeData getLightTheme() {
    final seed = currentSeedColor;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF7F9FC),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.black.withValues(alpha: 0.06),
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
    );
  }

  ThemeData getDarkTheme() {
    final seed = currentSeedColor;
    final isAmoled = isAmoledDark.value;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );

    final bg = isAmoled ? Colors.black : const Color(0xFF14171A);
    final cardBg = isAmoled ? const Color(0xFF121212) : const Color(0xFF1E2228);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        surface: bg,
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: bg,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 3,
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.08),
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
    );
  }
}
