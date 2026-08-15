import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// 根据当前 Material 3 主题动态生成终端色彩配置（支持浅色/深色/AMOLED自适应）
TerminalTheme getAppTerminalTheme(BuildContext context) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  if (isDark) {
    return TerminalTheme(
      cursor: theme.colorScheme.primary,
      selection: theme.colorScheme.primary.withValues(alpha: 0.35),
      foreground: const Color(0xFFECEFF4),
      background: theme.colorScheme.surface,
      black: const Color(0xFF3B4252),
      white: const Color(0xFFE5E9F0),
      red: const Color(0xFFFF6B6B),
      green: const Color(0xFF51CF66),
      yellow: const Color(0xFFFCC419),
      blue: const Color(0xFF339AF0),
      magenta: const Color(0xFFCC5DE8),
      cyan: const Color(0xFF22B8CF),
      brightBlack: const Color(0xFF868E96),
      brightRed: const Color(0xFFFF8787),
      brightGreen: const Color(0xFF69DB7C),
      brightYellow: const Color(0xFFFFD43B),
      brightBlue: const Color(0xFF4DABF7),
      brightMagenta: const Color(0xFFDA77F2),
      brightCyan: const Color(0xFF3BC9DB),
      brightWhite: const Color(0xFFFFFFFF),
      searchHitBackground: theme.colorScheme.primary,
      searchHitBackgroundCurrent: theme.colorScheme.secondary,
      searchHitForeground: Colors.black,
    );
  } else {
    return TerminalTheme(
      cursor: theme.colorScheme.primary,
      selection: theme.colorScheme.primary.withValues(alpha: 0.25),
      foreground: const Color(0xFF212529),
      background: theme.colorScheme.surface,
      black: const Color(0xFF212529),
      white: const Color(0xFF868E96),
      red: const Color(0xFFE03131),
      green: const Color(0xFF2F9E44),
      yellow: const Color(0xFFE67700),
      blue: const Color(0xFF1971C2),
      magenta: const Color(0xFF9C36B5),
      cyan: const Color(0xFF0C8599),
      brightBlack: const Color(0xFF495057),
      brightRed: const Color(0xFFC92A2A),
      brightGreen: const Color(0xFF2B8A3E),
      brightYellow: const Color(0xFFD9480F),
      brightBlue: const Color(0xFF1864AB),
      brightMagenta: const Color(0xFF862E9C),
      brightCyan: const Color(0xFF0B7285),
      brightWhite: const Color(0xFF1A1D20),
      searchHitBackground: theme.colorScheme.primary,
      searchHitBackgroundCurrent: theme.colorScheme.secondary,
      searchHitForeground: Colors.white,
    );
  }
}

class ManjaroTerminalTheme extends TerminalTheme {
  const ManjaroTerminalTheme({
    super.cursor = const Color(0xaaf6f5f4),
    super.selection = const Color(0XAAAEAFAD),
    super.foreground = const Color(0xffe5e5e5),
    super.background = const Color(0xff1c1c1e),
    super.black = const Color(0xff241f31),
    super.white = const Color(0xffc0bfbc),
    super.red = const Color(0xffc01c28),
    super.green = const Color(0xff2ec27e),
    super.yellow = const Color(0xfff5c211),
    super.blue = const Color(0xff1e78e4),
    super.magenta = const Color(0xff9841bb),
    super.cyan = const Color(0xff0ab9dc),
    super.brightBlack = const Color(0xff5e5c64),
    super.brightRed = const Color(0xffed333b),
    super.brightGreen = const Color(0xff57e389),
    super.brightYellow = const Color(0xfff8e45c),
    super.brightBlue = const Color(0xff51a1ff),
    super.brightMagenta = const Color(0xffc061cb),
    super.brightCyan = const Color(0xff4fd2fd),
    super.brightWhite = const Color(0xfff6f5f4),
    super.searchHitBackground = const Color(0XFF000000),
    super.searchHitBackgroundCurrent = const Color(0XFF31FF26),
    super.searchHitForeground = const Color(0XFF000000),
  });
}
