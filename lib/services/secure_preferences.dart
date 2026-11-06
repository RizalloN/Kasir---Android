import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android Keystore encrypted preferences. There is no plaintext error fallback.
class SecurePreferences {
  static const channel = MethodChannel('com.kafekita.pos/secure_store');
  static Future<SecurePreferences>? _instance;
  static bool _testMode = false;
  final SharedPreferences? _test;
  Map<String, dynamic> _data;
  Future<void> _queue = Future.value();

  SecurePreferences._(this._data, [this._test]);

  static void enableTestStorage() {
    assert(() {
      _testMode = true;
      return true;
    }());
  }

  static void resetForTesting() {
    assert(() {
      _instance = null;
      return true;
    }());
  }

  static List<String> _legacyKeys(SharedPreferences prefs) => prefs
      .getKeys()
      .where((key) =>
          key.startsWith('cached_') ||
          key.startsWith('printer_') ||
          key.startsWith('warloc_') ||
          key.startsWith('saved_') ||
          key.startsWith('login_'))
      .toList();

  static Future<SecurePreferences> getInstance() async {
    if (_testMode) {
      return SecurePreferences._({}, await SharedPreferences.getInstance());
    }
    return _instance ??= _load();
  }

  static Future<SecurePreferences> _load() async {
    try {
      final encrypted = await channel.invokeMethod<String>('read');
      if (encrypted != null) {
        final data = Map<String, dynamic>.from(jsonDecode(encrypted) as Map);
        // Complete cleanup if a previous migration was interrupted after commit.
        final old = await SharedPreferences.getInstance();
        for (final key in _legacyKeys(old)) {
          await old.remove(key);
        }
        return SecurePreferences._(data);
      }
      final old = await SharedPreferences.getInstance();
      final data = <String, dynamic>{};
      final keys = _legacyKeys(old);
      for (final key in keys) {
        data[key] = old.get(key);
      }
      // An old editable user ID alone is not sufficient to restore a session.
      data.remove('saved_active_user_id');
      await channel.invokeMethod<void>('write', {'data': jsonEncode(data)});
      for (final key in keys) {
        await old.remove(key);
      }
      return SecurePreferences._(data);
    } catch (_) {
      _instance = null;
      rethrow;
    }
  }

  String? getString(String key) =>
      _test?.getString(key) ?? _data[key] as String?;
  int? getInt(String key) => _test?.getInt(key) ?? _data[key] as int?;
  bool? getBool(String key) => _test?.getBool(key) ?? _data[key] as bool?;

  Future<bool> setString(String key, String value) => _set(key, value);
  Future<bool> setInt(String key, int value) => _set(key, value);
  Future<bool> setBool(String key, bool value) => _set(key, value);
  Future<bool> remove(String key) => _set(key, null);

  Future<bool> _set(String key, Object? value) async {
    final test = _test;
    if (test != null) {
      if (value == null) return test.remove(key);
      if (value is String) return test.setString(key, value);
      if (value is int) return test.setInt(key, value);
      return test.setBool(key, value as bool);
    }
    final operation = _queue.catchError((Object _) {}).then((_) async {
      final next = {..._data};
      if (value == null) {
        next.remove(key);
      } else {
        next[key] = value;
      }
      await channel.invokeMethod<void>('write', {'data': jsonEncode(next)});
      _data = next;
    });
    _queue = operation;
    await operation;
    return true;
  }
}
