import 'package:kasir_super/services/secure_preferences.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/app_release_service.dart';
import 'package:kasir_super/screens/main_wrapper_screen.dart';
import 'package:kasir_super/screens/barista/cart_bottom_sheet.dart';
import 'package:kasir_super/screens/dialogs/app_update_dialog.dart';
import 'package:kasir_super/theme/app_theme.dart';
import 'package:kasir_super/screens/auth/login_screen.dart';
import 'package:kasir_super/screens/owner/owner_dashboard_screen.dart';
import 'package:kasir_super/models/user_profile.dart';
import 'package:kasir_super/models/user_role.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  setUpAll(() => initializeDateFormatting('id_ID', null));

  Future<PosProvider> createPos(String role) async {
    SharedPreferences.setMockInitialValues({});
    await PosDatabaseService.instance.resetForTesting();
    final pos = PosProvider();
    while (!pos.isInitialized) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final passwords = {
      'kasir': 'sukses000',
      'admin': 'sukses123',
      'owner': 'sukses888'
    };
    expect(await pos.login('warloc.$role', passwords[role]!), isNull);
    return pos;
  }

  Widget app(
    PosProvider pos,
    AppReleaseService release, {
    Widget child = const MainWrapperScreen(),
    double scale = 1,
    List<ui.DisplayFeature> features = const [],
    double keyboard = 0,
  }) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: pos),
          ChangeNotifierProvider.value(value: release)
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                displayFeatures: features,
                viewInsets: EdgeInsets.only(bottom: keyboard)),
            child: DisplayFeatureSubScreen(child: child!),
          ),
          home: child,
        ),
      );

  test(
      'User snapshots seed only missing accounts and preserve rotated passwords',
      () {
    final initial = UserProfile.create(
        id: 'default-owner',
        username: 'warloc.owner',
        displayName: 'Owner',
        role: UserRole.owner,
        plainPassword: 'initial');
    final rotated = initial.withUpdatedPassword('ChangedByOwner!');
    expect(PosDatabaseService.usersMissingFromSnapshot([initial], [rotated]),
        isEmpty);
    expect(rotated.verifyPassword('ChangedByOwner!'), isTrue);
    final migrated = UserProfile.create(
        id: 'migrated-owner',
        username: 'warloc.owner',
        displayName: 'Owner',
        role: UserRole.owner,
        plainPassword: 'custom');
    expect(PosDatabaseService.usersMissingFromSnapshot([initial], [migrated]),
        isEmpty);
    final missing = PosDatabaseService.usersMissingFromSnapshot([initial], []);
    expect(missing.single.passwordHash, initial.passwordHash);
    expect(PosDatabaseService.usersMissingFromSnapshot([initial], missing),
        isEmpty);
  });

  test('Release metadata rejects unsafe URLs and malformed controls', () {
    for (final url in [
      'http://example.com/a.apk',
      'file:///a.apk',
      'https://user:pass@example.com/a.apk',
      'javascript:alert(1)'
    ]) {
      expect(() => AppRelease.fromMap({'downloadUrl': url}),
          throwsFormatException);
    }
    expect(
        () => AppRelease.fromMap({'versionCode': 1.5}), throwsFormatException);
    expect(
        () => AppRelease.fromMap({
              'features': {'barcode_lookup': 'false'}
            }),
        throwsFormatException);
    final release = AppRelease.fromMap({
      'versionCode': 2,
      'downloadUrl': 'https://example.com/warloc.apk',
      'features': {'barcode_lookup': false}
    });
    expect(release.enabled('barcode_lookup'), isFalse);
    expect(release.enabled('unknown'), isTrue);
  });

  test('Update compares build code and opens only a newer published release',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppReleaseService.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppReleaseService.channel, null));
    final service = AppReleaseService()..installedCode = 4;
    service.release = AppRelease.fromMap(
        {'versionCode': 3, 'downloadUrl': 'https://example.com/warloc.apk'});
    expect(service.updateAvailable, isFalse);
    await expectLater(service.downloadUpdate(), throwsStateError);
    service.release = AppRelease.fromMap(
        {'versionCode': 5, 'downloadUrl': 'https://example.com/warloc.apk'});
    expect(service.updateAvailable, isTrue);
    await service.downloadUpdate();
    expect(calls.single.method, 'openDownload');
    expect(calls.single.arguments['url'], 'https://example.com/warloc.apk');
    service.dispose();
  });

  test('Checkout rejects empty, invalid, underpaid and simultaneous requests',
      () async {
    final pos = await createPos('kasir');
    addTearDown(pos.dispose);
    Future<dynamic> checkout(double paid) => pos.processCheckout(
        paymentMethod: 'Cash', amountPaid: paid, cashierName: 'Kasir');
    await expectLater(checkout(100000), throwsStateError);
    pos.addToCart(pos.products.first);
    await expectLater(checkout(double.nan), throwsArgumentError);
    await expectLater(checkout(0), throwsArgumentError);
    final first = checkout(100000);
    await expectLater(checkout(100000), throwsStateError);
    await first;
    expect(pos.transactions.length, 1);
    expect(pos.cart, isEmpty);
  });

  test('Offline session, sale and deducted stock survive a local restart',
      () async {
    final pos = await createPos('kasir');
    final product = pos.products.first;
    pos.addToCart(product);
    final transaction = await pos.processCheckout(
        paymentMethod: 'Cash',
        amountPaid: product.sellPrice,
        cashierName: 'Kasir');
    expect(transaction.isSynced, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_active_user_id'), pos.currentUser!.id);
    pos.dispose();
    await PosDatabaseService.instance.resetForTesting();
    final reopened = PosProvider();
    while (!reopened.isInitialized) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    addTearDown(reopened.dispose);
    expect(reopened.isAuthenticated, isTrue);
    expect(reopened.transactions.single.id, transaction.id);
    expect(reopened.products.firstWhere((p) => p.id == product.id).stock,
        product.stock - 1);
  });

  for (final role in ['kasir', 'admin', 'owner']) {
    for (final size in [
      const Size(320, 568),
      const Size(360, 800),
      const Size(800, 360),
      const Size(600, 960),
      const Size(1280, 800)
    ]) {
      testWidgets('$role layout ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final pos = await tester.runAsync(() => createPos(role));
        final release = AppReleaseService();
        await tester.pumpWidget(app(pos!, release));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (role != 'owner') {
          pos.addToCart(pos.products.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        pos.dispose();
        release.dispose();
      });
    }
  }

  testWidgets('Fold hinge avoids controls and resizing preserves cart',
      (tester) async {
    tester.view.physicalSize = const Size(1350, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pos = (await tester.runAsync(() => createPos('admin')))!;
    final release = AppReleaseService();
    pos.addToCart(pos.products.first);
    await tester.pumpWidget(app(pos, release, features: [
      const ui.DisplayFeature(
          bounds: Rect.fromLTWH(660, 0, 30, 900),
          type: ui.DisplayFeatureType.hinge,
          state: ui.DisplayFeatureState.postureHalfOpened)
    ]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(AppBar)).right, lessThanOrEqualTo(660));
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(app(pos, release));
    await tester.pumpAndSettle();
    expect(pos.totalCartItemCount, 1);
    expect(find.byType(CartBottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    pos.dispose();
    release.dispose();
  });

  testWidgets('Large text and keyboard keep payment usable', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pos = (await tester.runAsync(() => createPos('kasir')))!;
    final release = AppReleaseService();
    pos.addToCart(pos.products.first);
    await tester.pumpWidget(app(pos, release, scale: 1.5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Rincian & Bayar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(pos, release, scale: 1.5, keyboard: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Bayar Sekarang'), 180,
        scrollable: find
            .descendant(
                of: find.byType(CartBottomSheet),
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    expect(find.text('Bayar Sekarang'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pos.dispose();
    release.dispose();
  });

  testWidgets('Release notification and remotely disabled barcode',
      (tester) async {
    final pos = (await tester.runAsync(() => createPos('kasir')))!;
    final release = AppReleaseService()..installedCode = 1;
    release.release = AppRelease.fromMap({
      'versionCode': 2,
      'versionName': '1.1.0',
      'downloadUrl': 'https://example.com/app.apk',
      'features': {'barcode_lookup': false}
    });
    await tester.pumpWidget(app(pos, release));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Input Barcode / SKU Cepat'), findsNothing);
    expect(find.text('Warloc 1.1.0 tersedia'), findsOneWidget);
    await tester.tap(find.text('Lihat'));
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsOneWidget);
    expect(find.text('Unduh APK'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    pos.dispose();
    release.dispose();
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('Owner tabs and large text $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pos = (await tester.runAsync(() => createPos('owner')))!;
      final release = AppReleaseService();
      await tester.pumpWidget(app(pos, release, scale: scale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final controller = tester.widget<TabBar>(find.byType(TabBar)).controller!;
      for (var index = 1; index < 5; index++) {
        controller.animateTo(index);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'Tab $index scale $scale');
      }
      expect(find.byType(OwnerDashboardScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      pos.dispose();
      release.dispose();
    });
  }

  testWidgets('Login large text and tabletop fold remain within usable display',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pos = (await tester.runAsync(() => createPos('kasir')))!;
    final release = AppReleaseService();
    await tester.pumpWidget(
        app(pos, release, scale: 1.5, child: const LoginScreen(), features: [
      const ui.DisplayFeature(
          bounds: Rect.fromLTWH(0, 590, 900, 20),
          type: ui.DisplayFeatureType.hinge,
          state: ui.DisplayFeatureState.postureHalfOpened)
    ]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        tester.getRect(find.byType(Scaffold)).bottom, lessThanOrEqualTo(590));
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpWidget(app(pos, release,
        scale: 1.5, child: const LoginScreen(), keyboard: 250));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    pos.dispose();
    release.dispose();
  });
}
