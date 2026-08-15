import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:settings/settings.dart';

/// 预设主题种子色彩定义 (包含 Material You 动态色彩项)
class AppThemeColor {
  final String name;
  final Color? color;
  final bool isDynamic;

  const AppThemeColor(this.name, this.color, {this.isDynamic = false});
}

class ThemeController extends GetxController {
  static const List<AppThemeColor> presetColors = [
    AppThemeColor('系统动态 (Monet)', null, isDynamic: true),
    AppThemeColor('麦麦橙 (Mai Orange)', Color(0xFFFF8C00)),
    AppThemeColor('落日橙 (Sunset)', Color(0xFFF57C00)),
    AppThemeColor('经典蓝 (Classic)', Color(0xFF1976D2)),
    AppThemeColor('深靛蓝 (Indigo)', Color(0xFF3F51B5)),
    AppThemeColor('松石青 (Teal)', Color(0xFF00897B)),
    AppThemeColor('麦苗绿 (Mint)', Color(0xFF00A86B)),
    AppThemeColor('樱花粉 (Pink)', Color(0xFFE91E63)),
    AppThemeColor('优雅紫 (Purple)', Color(0xFF7B1FA2)),
    AppThemeColor('极客绿 (Forest)', Color(0xFF2E7D32)),
    AppThemeColor('岩石灰 (Slate)', Color(0xFF455A64)),
  ];

  final Setting _colorIndexSetting = 'theme_seed_color_index'.setting;
  final Setting _themeModeSetting = 'theme_mode_preference'.setting;
  final Setting _amoledSetting = 'theme_amoled_dark'.setting;

  final RxInt selectedColorIndex = 0.obs;
  final Rx<ThemeMode> currentThemeMode = ThemeMode.system.obs;
  final RxBool isAmoledDark = false.obs;

  // 存储系统 Android 12+ 提供的动态 Monet 配色
  ColorScheme? _systemLightScheme;
  ColorScheme? _systemDarkScheme;

  @override
  void onInit() {
    super.onInit();
    _loadThemeSettings();
  }

  void updateSystemDynamicSchemes(ColorScheme? light, ColorScheme? dark) {
    _systemLightScheme = light;
    _systemDarkScheme = dark;
  }

  void _loadThemeSettings() {
    final colorIdx = _colorIndexSetting.get();
    if (colorIdx is int && colorIdx >= 0 && colorIdx < presetColors.length) {
      selectedColorIndex.value = colorIdx;
    } else {
      selectedColorIndex.value = 0; // 默认使用系统动态 Monet
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

  bool get isDynamicSelected => presetColors[selectedColorIndex.value].isDynamic;

  Color get currentSeedColor {
    return presetColors[selectedColorIndex.value].color ?? const Color(0xFFFF8C00);
  }
  String get currentSeedName => presetColors[selectedColorIndex.value].name;

  void setColorIndex(int index) {
    if (index >= 0 && index < presetColors.length) {
      selectedColorIndex.value = index;
      _colorIndexSetting.set(index);
      Get.forceAppUpdate();
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
    Get.forceAppUpdate();
  }

  /// 构建正统 Material 3 浅色主题
  ThemeData getLightTheme({ColorScheme? dynamicLightScheme}) {
    ColorScheme colorScheme;
    if (isDynamicSelected && (dynamicLightScheme ?? _systemLightScheme) != null) {
      colorScheme = (dynamicLightScheme ?? _systemLightScheme)!;
    } else {
      colorScheme = ColorScheme.fromSeed(
        seedColor: currentSeedColor,
        brightness: Brightness.light,
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: colorScheme.surfaceTint,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 2,
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onSecondaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        elevation: 3,
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        textColor: colorScheme.onSurface,
        iconColor: colorScheme.onSurfaceVariant,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  /// 构建正统 Material 3 深色主题
  ThemeData getDarkTheme({ColorScheme? dynamicDarkScheme}) {
    ColorScheme colorScheme;
    if (isDynamicSelected && (dynamicDarkScheme ?? _systemDarkScheme) != null) {
      colorScheme = (dynamicDarkScheme ?? _systemDarkScheme)!;
    } else {
      colorScheme = ColorScheme.fromSeed(
        seedColor: currentSeedColor,
        brightness: Brightness.dark,
      );
    }

    final isAmoled = isAmoledDark.value;
    if (isAmoled) {
      colorScheme = colorScheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0D0D0D),
        surfaceContainer: const Color(0xFF141414),
        surfaceContainerHigh: const Color(0xFF1C1C1C),
        surfaceContainerHighest: const Color(0xFF262626),
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: colorScheme.surfaceTint,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 2,
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onSecondaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        elevation: 3,
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        textColor: colorScheme.onSurface,
        iconColor: colorScheme.onSurfaceVariant,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
