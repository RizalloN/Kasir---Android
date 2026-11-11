import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/transaction.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/main_wrapper_screen.dart';
import 'package:kasir_super/screens/dialogs/transaction_history_dialog.dart';
import 'package:kasir_super/services/app_release_service.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';
import 'package:kasir_super/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  final db = PosDatabaseService.instance;
  final providers = <PosProvider>[];
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
    // Use the SDK's actual fonts for visual review without adding app assets.
    final fonts = '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts';
    final regular = File('$fonts/roboto-regular.ttf');
    if (await regular.exists()) {
      final loader = FontLoader('Roboto')
        ..addFont(regular.readAsBytes().then((bytes) => ByteData.sublistView(bytes)))
        ..addFont(File('$fonts/roboto-bold.ttf').readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
      await loader.load();
      // Explicit button styles without a font family inherit the test font.
      await (FontLoader('Ahem')
        ..addFont(regular.readAsBytes().then((bytes) => ByteData.sublistView(bytes)))
        ..addFont(File('$fonts/roboto-bold.ttf').readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDown(() { for (final pos in providers) { pos.dispose(); } providers.clear(); });

  Future<PosProvider> fresh() async {
    SharedPreferences.setMockInitialValues({});
    await db.resetForTesting();
    final pos = PosProvider(); providers.add(pos);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    expect(await pos.login('warloc.kasir', 'sukses000'), isNull);
    return pos;
  }

  Future<TransactionRecord> sale(PosProvider pos) async {
    for (final product in pos.products.where((p) => p.isDrink).take(3)) {
      expect(pos.addToCart(product, variant: 'ES'), isTrue);
    }
    return pos.processCheckout(paymentMethod: 'Cash', amountPaid: 100000,
      cashierName: '', customerName: 'Meja Jendela');
  }

  Widget app(PosProvider pos, Widget child, {double scale = 1, double keyboard = 0}) => MultiProvider(
    providers: [ChangeNotifierProvider.value(value: pos),
      ChangeNotifierProvider(create: (_) => AppReleaseService())],
    child: RepaintBoundary(key: const ValueKey('history-ui-preview'), child: MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale), viewInsets: EdgeInsets.only(bottom: keyboard)), child: child!),
      home: child,
    )),
  );

  Future<void> screenshot(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('history-ui-preview')));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/history-layout-polish/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('Menu and Transaksi toolbar preserves the active cart and only exposes cashier data', (tester) async {
    final pos = (await tester.runAsync(fresh))!;
    await tester.runAsync(() => sale(pos));
    expect(pos.addToCart(pos.products.first, variant: 'ES'), isTrue);
    final cart = pos.cart.map((i) => (i.product.id, i.quantity)).toList();
    await tester.pumpWidget(app(pos, const MainWrapperScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cashier-tab-menu')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('cashier-tab-transaksi')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cashier-tab-transaksi')));
    await tester.pumpAndSettle();
    expect(find.text('Riwayat Transaksi'), findsOneWidget);
    expect(find.byKey(const ValueKey('transaction-search-input')), findsOneWidget);
    expect(find.text('Dashboard Penjualan'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('cashier-tab-menu')));
    await tester.pumpAndSettle();
    expect(pos.cart.map((i) => (i.product.id, i.quantity)).toList(), cart);
    expect(find.text('Riwayat Transaksi'), findsNothing);
  });

  testWidgets('History searches local customer/menu data and filters by correction eligibility', (tester) async {
    final pos = (await tester.runAsync(fresh))!;
    final tx = (await tester.runAsync(() => sale(pos)))!;
    await tester.runAsync(() => db.insertHistoricalTransactionForTesting(tx.copyWith(
      id: 'INV-EXPIRED', invoiceNumber: 'INV-EXPIRED',
      createdAt: DateTime.now().subtract(const Duration(hours: 25)), customerName: 'Meja Lama')));
    await tester.pumpWidget(app(pos, const Scaffold(body: TransactionHistoryView())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('transaction-search-input')), 'Meja Jendela');
    await tester.pumpAndSettle();
    expect(find.text(tx.invoiceNumber), findsOneWidget);
    expect(find.text('INV-EXPIRED'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('transaction-search-input')), 'tidak ditemukan');
    await tester.pumpAndSettle();
    expect(find.text('Transaksi tidak ditemukan.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('transaction-search-input')), '');
    await tester.tap(find.text('Bisa Diedit'));
    await tester.pumpAndSettle();
    expect(find.text('INV-EXPIRED'), findsNothing);
    expect(find.text(tx.invoiceNumber), findsOneWidget);
  });

  for (final size in [const Size(320, 568), const Size(800, 360), const Size(600, 960), const Size(1280, 800)]) {
    testWidgets('History and correction are arranged within $size at large text', (tester) async {
      tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final pos = (await tester.runAsync(fresh))!;
      final tx = (await tester.runAsync(() => sale(pos)))!;
      final scale = size.width == 1280 ? 1.0 : 1.5;
      await tester.pumpWidget(app(pos, const MainWrapperScreen(), scale: scale));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cashier-tab-transaksi')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Koreksi'), 180,
        scrollable: find.descendant(of: find.byType(TransactionHistoryView), matching: find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width == 1280) await screenshot(tester, 'history-1280x800');
      await tester.tap(find.text('Koreksi'));
      await tester.pumpAndSettle();
      expect(find.text('Koreksi Transaksi'), findsOneWidget);
      expect(find.text('Periksa Koreksi').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width == 1280) await screenshot(tester, 'correction-1280x800');
      final firstCard = find.ancestor(of: find.text(tx.items.first.product.name).last,
        matching: find.byType(Container)).first;
      expect(tester.getSize(firstCard).width, greaterThan(180));
      await tester.ensureVisible(find.byTooltip('Tambah jumlah item 1'));
      await tester.tap(find.byTooltip('Tambah jumlah item 1'));
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Kurangi item 1'));
      await tester.tap(find.byTooltip('Kurangi item 1'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Review points to the required reason and the form remains scrollable with a keyboard', (tester) async {
    tester.view.physicalSize = const Size(360, 640); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final pos = (await tester.runAsync(fresh))!;
    final tx = (await tester.runAsync(() => sale(pos)))!;
    await tester.pumpWidget(app(pos, Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showDialog<void>(context: context, builder: (_) => CorrectTransactionDialog(transaction: tx)),
      child: const Text('Buka')))), keyboard: 180));
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    expect(find.text('Periksa Koreksi').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Periksa Koreksi'));
    await tester.pumpAndSettle();
    expect(find.text('Alasan koreksi wajib diisi.'), findsOneWidget);
    expect(find.byKey(const ValueKey('correction-reason-input')).hitTestable(), findsOneWidget);
    expect(pos.transactions.single.revision, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Wide correction aligns equal columns and keeps labels outside the input borders', (tester) async {
    tester.view.physicalSize = const Size(1280, 800); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final pos = (await tester.runAsync(fresh))!;
    final tx = (await tester.runAsync(() => sale(pos)))!;
    await tester.pumpWidget(app(pos, Scaffold(body: CorrectTransactionDialog(transaction: tx))));
    await tester.pumpAndSettle();
    final item = tester.getRect(find.byKey(const ValueKey('correction-item-0')));
    final summary = tester.getRect(find.byKey(const ValueKey('correction-summary')));
    expect(item.top, closeTo(summary.top, 0.5));
    expect(item.width, closeTo(summary.width, 0.5));
    for (final id in ['correction-payment', 'correction-reason']) {
      final field = find.byKey(ValueKey('$id-input'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      final labelRect = tester.getRect(find.byKey(ValueKey('$id-label')));
      final inputRect = tester.getRect(field);
      expect(inputRect.top - labelRect.bottom, greaterThanOrEqualTo(8));
      final widget = tester.widget<TextField>(field);
      expect(widget.decoration!.label, isNull);
      expect(widget.decoration!.labelText, isNull);
      expect(inputRect.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('correction-footer'))).top));
    }
    await screenshot(tester, 'correction-labels-separated');
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (size: const Size(320, 568), scale: 2.0, keyboard: 0.0),
    (size: const Size(390, 844), scale: 1.5, keyboard: 260.0),
    (size: const Size(800, 360), scale: 1.5, keyboard: 160.0),
    (size: const Size(889, 837), scale: 1.0, keyboard: 0.0),
    (size: const Size(1024, 600), scale: 1.5, keyboard: 0.0),
    (size: const Size(1280, 800), scale: 2.0, keyboard: 0.0),
  ]) {
    testWidgets('Long menu names, large amounts and fields fit $scenario', (tester) async {
      tester.view.physicalSize = scenario.size; tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final pos = (await tester.runAsync(fresh))!;
      final tx = (await tester.runAsync(() => sale(pos)))!;
      final item = tx.items.first.copyWith(quantity: 99999, product: tx.items.first.product.copyWith(
        name: List.filled(6, 'Kopi Susu Gula Aren Spesial Warloc').join(' '), sellPrice: 999999));
      final fixture = tx.copyWith(id: 'INV-LONG-${List.filled(60, '9').join()}',
        invoiceNumber: 'INV-LONG-${List.filled(60, '9').join()}', items: [item],
        subtotalAmount: item.subtotal, totalAmount: item.subtotal,
        amountPaid: item.subtotal, changeAmount: 0, customerName: List.filled(8, 'Pelanggan Warloc').join(' '));
      await tester.runAsync(() => db.insertHistoricalTransactionForTesting(fixture));
      await tester.pumpWidget(app(pos, Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showDialog<void>(context: context, builder: (_) => CorrectTransactionDialog(transaction: fixture)),
        child: const Text('Buka')))), scale: scenario.scale, keyboard: scenario.keyboard));
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      expect(find.text('Periksa Koreksi').hitTestable(), findsOneWidget);
      final reviewText = tester.renderObject<RenderParagraph>(find.text('Periksa Koreksi'));
      expect(reviewText.didExceedMaxLines, isFalse, reason: 'The primary action must not wrap or truncate');
      await tester.ensureVisible(find.byKey(const ValueKey('correction-payment-input')));
      await tester.pumpAndSettle();
      final label = tester.getRect(find.byKey(const ValueKey('correction-payment-label')));
      final input = tester.getRect(find.byKey(const ValueKey('correction-payment-input')));
      expect(input.top - label.bottom, greaterThanOrEqualTo(8));
      await tester.ensureVisible(find.byKey(const ValueKey('correction-reason-input')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('correction-reason-input')), 'Periksa tampilan tanpa menyimpan transaksi');
      await tester.pumpAndSettle();
      expect(find.text('Periksa Koreksi').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
