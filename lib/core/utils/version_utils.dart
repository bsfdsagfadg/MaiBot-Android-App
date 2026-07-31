import 'package:package_info_plus/package_info_plus.dart';

// 获取应用版本号（从 pubspec.yaml）
// Get app version from pubspec.yaml
Future<String> getAppVersion() async {
  final packageInfo = await PackageInfo.fromPlatform();
  return packageInfo.version;
}

/// 比较语义化版本号，返回 v1 > v2 时为 1，v1 < v2 时为 -1，相等为 0
int compareVersions(String v1, String v2) {
  String clean(String v) {
    v = v.replaceFirst('v', '').trim();
    if (v.contains('-')) v = v.split('-')[0];
    if (v.contains('+')) v = v.split('+')[0];
    return v;
  }

  final parts1 = clean(v1).split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final parts2 = clean(v2).split('.').map((e) => int.tryParse(e) ?? 0).toList();

  for (int i = 0; i < 3; i++) {
    final p1 = i < parts1.length ? parts1[i] : 0;
    final p2 = i < parts2.length ? parts2[i] : 0;
    if (p1 > p2) return 1;
    if (p1 < p2) return -1;
  }
  return 0;
}
