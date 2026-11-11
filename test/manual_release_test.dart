import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/services/app_release_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  var installedReads = 0;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installedReads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppReleaseService.channel, (call) async {
      if (call.method == 'installedVersion') {
        installedReads++;
        return {'versionCode': 10, 'versionName': '1.2.7'};
      }
      throw MissingPluginException();
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppReleaseService.channel, null);
  });

  testWidgets(
      'Startup and app resume do not check Firestore; cached feature settings survive',
      (tester) async {
    final prefs = await SecurePreferences.getInstance();
    await prefs.setString(
        'cached_release_metadata_v1',
        jsonEncode({
          'versionCode': 11,
          'versionName': '1.2.8',
          'downloadUrl': 'https://example.com/app.apk',
          'features': {'barcode_lookup': false},
        }));
    final service = AppReleaseService();
    addTearDown(service.dispose);
    await service.initialize();
    expect(service.installedCode, 10);
    expect(service.enabled('barcode_lookup'), isFalse);
    expect(service.error, isNull);
    expect(service.hasChecked, isFalse);
    expect(installedReads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(installedReads, 1);
    expect(service.hasChecked, isFalse);
    expect(service.error, isNull);
  });

  test(
      'Manual checking is throttled and never discards cached configuration on failure',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = AppReleaseService();
    addTearDown(service.dispose);
    service.release = const AppRelease(features: {'thermal_printer': false});
    await service.refresh();
    await service.refresh();
    await service.refresh();
    expect(installedReads, 1);
    expect(service.error, isNotNull);
    expect(service.enabled('thermal_printer'), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}
