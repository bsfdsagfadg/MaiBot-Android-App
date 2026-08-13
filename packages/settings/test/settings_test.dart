import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:settings/settings.dart';

void main() {
  setUp(() async {
    await initSettingStore('./settings_test');
  });

  tearDown(() async {
    await box?.close();
    box = null;
    await Hive.deleteBoxFromDisk('setting', path: './settings_test');
  });

  group('Setting', () {
    test('set and get value', () {
      final setting = 'name'.setting;
      setting.value = 'hello';
      expect(setting.value, 'hello');
    });

    test('unset key returns null', () {
      final setting = 'unknown'.setting;
      expect(setting.get(), isNull);
    });

    test('get() with explicit default', () {
      expect(box!.get('missing', defaultValue: 42), 42);
    });

    test('reactive observation', () {
      final setting = 'reactive'.setting;
      final events = <dynamic>[];
      setting.ob.addListener(() => events.add(setting.value));

      setting.value = 'a';
      setting.value = 'b';
      setting.value = 'c';

      expect(events, ['a', 'b', 'c']);
    });

    test('string extension creates Setting', () {
      final setting = 'key'.setting;
      expect(setting, isA<Setting>());
      expect(setting.key, 'key');
    });

    test('SettingNode typedef is deprecated but works', () {
      // ignore: deprecated_member_use
      final node = SettingNode('old_key');
      expect(node, isA<Setting>());
    });
  });
}
