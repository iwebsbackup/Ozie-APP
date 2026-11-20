import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Test mode switch (login page toggle). ON  -> login limited to
/// retailer / distributor / delivery boy and the "Test" tab shows.
/// OFF -> normal app flow, no Test tab. Saved on device.
class TestMode {
  TestMode._();
  static const String _key = 'ozie_test_mode';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// Roles allowed to log in while test mode is ON (delivery boy has own login).
  static const Set<String> mainRoles = {'retailer', 'distributor'};

  static Future<void> load() async {
    try {
      enabled.value = (await _storage.read(key: _key)) == '1';
    } catch (_) {}
  }

  static Future<void> set(bool v) async {
    enabled.value = v;
    try {
      await _storage.write(key: _key, value: v ? '1' : '0');
    } catch (_) {}
  }
}
