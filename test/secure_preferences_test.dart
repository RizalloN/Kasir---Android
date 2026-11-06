import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/services/secure_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SecurePreferences.resetForTesting();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() =>
      messenger.setMockMethodCallHandler(SecurePreferences.channel, null));

  test(
      'Legacy private data is removed only after secure write; old session ID is not trusted',
      () async {
    SharedPreferences.setMockInitialValues({
      'cached_users': 'private-users',
      'cached_transactions': 'sales',
      'saved_active_user_id': 'u_owner_default',
      'unrelated': 'keep'
    });
    Map<String, dynamic>? saved;
    messenger.setMockMethodCallHandler(SecurePreferences.channel, (call) async {
      if (call.method == 'read') return null;
      saved = Map<String, dynamic>.from(
          jsonDecode(call.arguments['data'] as String) as Map);
      return null;
    });
    final store = await SecurePreferences.getInstance();
    expect(saved!['cached_users'], 'private-users');
    expect(saved!.containsKey('saved_active_user_id'), isFalse);
    expect(store.getString('cached_users'), 'private-users');
    final old = await SharedPreferences.getInstance();
    expect(old.containsKey('cached_users'), isFalse);
    expect(old.getString('unrelated'), 'keep');
  });

  test(
      'Decrypt failure never falls back to plaintext and never overwrites source data',
      () async {
    SharedPreferences.setMockInitialValues({'cached_users': 'preserve'});
    var writes = 0;
    messenger.setMockMethodCallHandler(SecurePreferences.channel, (call) async {
      if (call.method == 'write') writes++;
      throw PlatformException(code: 'secure_storage_failed');
    });
    await expectLater(
        SecurePreferences.getInstance(), throwsA(isA<PlatformException>()));
    expect((await SharedPreferences.getInstance()).getString('cached_users'),
        'preserve');
    expect(writes, 0);
  });

  test('Failed migration write preserves all original preferences', () async {
    SharedPreferences.setMockInitialValues({'cached_users': 'preserve'});
    messenger.setMockMethodCallHandler(SecurePreferences.channel, (call) async {
      if (call.method == 'read') return null;
      throw PlatformException(code: 'secure_storage_failed');
    });
    await expectLater(
        SecurePreferences.getInstance(), throwsA(isA<PlatformException>()));
    expect((await SharedPreferences.getInstance()).getString('cached_users'),
        'preserve');
  });

  test(
      'Parallel updates retain each key and failed writes do not commit memory state',
      () async {
    var fail = false;
    Map<String, dynamic>? durable;
    messenger.setMockMethodCallHandler(SecurePreferences.channel, (call) async {
      if (call.method == 'read') return '{}';
      if (fail) throw PlatformException(code: 'secure_storage_failed');
      durable = Map<String, dynamic>.from(
          jsonDecode(call.arguments['data'] as String) as Map);
      return null;
    });
    final store = await SecurePreferences.getInstance();
    await Future.wait([
      store.setInt('a', 1),
      store.setInt('b', 2),
      store.setString('c', 'three')
    ]);
    expect(durable, {'a': 1, 'b': 2, 'c': 'three'});
    fail = true;
    await expectLater(
        store.setInt('a', 999), throwsA(isA<PlatformException>()));
    expect(store.getInt('a'), 1);
    fail = false;
    await store.setInt('d', 4);
    expect(durable!['a'], 1);
    expect(durable!['d'], 4);
  });

  test(
      'A previously committed migration finishes removing leftover plaintext keys',
      () async {
    SharedPreferences.setMockInitialValues(
        {'cached_users': 'leftover', 'printer_device_name': 'private'});
    messenger.setMockMethodCallHandler(SecurePreferences.channel,
        (call) async => '{"cached_users":"secure-copy"}');
    final store = await SecurePreferences.getInstance();
    expect(store.getString('cached_users'), 'secure-copy');
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });
}
