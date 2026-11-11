import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/open_bill.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/main_wrapper_screen.dart';
import 'package:kasir_super/screens/barista/open_bills_screen.dart';
import 'package:kasir_super/screens/barista/cart_bottom_sheet.dart';
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
    final fonts =
        '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts';
    final regular = File('$fonts/roboto-regular.ttf');
    if (await regular.exists()) {
      await (FontLoader('Roboto')
            ..addFont(regular.readAsBytes().then(ByteData.sublistView))
            ..addFont(File('$fonts/roboto-bold.ttf')
                .readAsBytes()
                .then(ByteData.sublistView)))
          .load();
      // Flutter's default test font is Ahem; use readable glyphs for previews
      // of controls whose platform fallback font is selected by the theme.
      await (FontLoader('Ahem')
            ..addFont(regular.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  tearDown(() {
    for (final pos in providers) {
      pos.dispose();
    }
    providers.clear();
  });

  Future<PosProvider> fresh([String role = 'kasir']) async {
    SharedPreferences.setMockInitialValues({});
    await db.resetForTesting();
    final pos = PosProvider();
    providers.add(pos);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    expect(
        await pos.login(
            'warloc.$role', role == 'owner' ? 'sukses888' : 'sukses000'),
        isNull);
    return pos;
  }

  Future<OpenBill> bill(PosProvider pos, String customer,
      {String product = 'w_1'}) async {
    pos.addToCart(pos.products.firstWhere((p) => p.id == product),
        variant: 'ES');
    pos.setCustomerName(customer);
    return pos.saveCurrentBill();
  }

  Widget app(PosProvider pos, Widget child,
          {double scale = 1, double keyboard = 0}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: pos),
          ChangeNotifierProvider(create: (_) => AppReleaseService())
        ],
        child: RepaintBoundary(
            key: const ValueKey('bill-preview'),
            child: MaterialApp(
                theme: AppTheme.lightTheme,
                debugShowCheckedModeBanner: false,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        viewInsets: EdgeInsets.only(bottom: keyboard)),
                    child: child!),
                home: child)),
      );
  Future<void> screenshot(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('bill-preview')));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/open-bill-ux/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  test(
      'Direct bill payment preserves another cart, settles once and survives restart',
      () async {
    final pos = await fresh();
    final saved = await bill(pos, 'Meja 12');
    final other = pos.products.firstWhere((p) => p.id == 'w_3');
    pos.addToCart(other, variant: 'ES');
    pos.setCustomerName('Pesanan lain');
    pos.setOrderType('Takeaway');
    final before = pos.cart.map((i) => i.toMap()).toList();
    final quote = pos.quoteOpenBill(saved.id);
    expect(pos.cart.map((i) => i.toMap()).toList(), before);
    final first =
        pos.payOpenBill(quote, paymentMethod: 'Cash', amountPaid: 50000);
    await expectLater(
        pos.payOpenBill(quote, paymentMethod: 'Cash', amountPaid: 50000),
        throwsStateError);
    final tx = await first;
    expect(tx.openBillId, saved.id);
    expect(tx.changeAmount, 27000);
    expect(pos.openBills, isEmpty);
    expect(pos.transactions.length, 1);
    expect(pos.cart.map((i) => i.toMap()).toList(), before);
    expect(pos.customerName, 'Pesanan lain');
    expect(pos.orderType, 'Takeaway');
    await expectLater(
        pos.payOpenBill(quote, paymentMethod: 'Cash', amountPaid: 50000),
        throwsStateError);
    await db.resetForTesting();
    expect(await db.authenticate('warloc.kasir', 'sukses000'), isNotNull);
    expect(db.getOpenBills(), isEmpty);
    expect(db.getTransactions().length, 1);
  });

  test(
      'Bill review rejects changed prices, missing stock, active edits and invalid QRIS amount',
      () async {
    final pos = await fresh('owner');
    final saved = await bill(pos, 'Meja Aman');
    final quote = pos.quoteOpenBill(saved.id);
    await expectLater(
        pos.payOpenBill(quote,
            paymentMethod: 'QRIS', amountPaid: quote.total + 1),
        throwsArgumentError);
    final product = pos.products.firstWhere((p) => p.id == 'w_1');
    await pos.updateExistingProduct(
        product.copyWith(sellPrice: product.sellPrice + 5000));
    await expectLater(
        pos.payOpenBill(quote, paymentMethod: 'Cash', amountPaid: 100000),
        throwsStateError);
    expect(pos.openBills.length, 1);
    expect(pos.transactions, isEmpty);
    final freshQuote = pos.quoteOpenBill(saved.id);
    pos.resumeOpenBill(saved.id);
    await expectLater(
        pos.payOpenBill(freshQuote, paymentMethod: 'Cash', amountPaid: 100000),
        throwsStateError);
    pos.clearCart();
    await pos.updateExistingProduct(product.copyWith(stock: 0));
    expect(() => pos.quoteOpenBill(saved.id), throwsStateError);
    expect(pos.openBills.length, 1);
    expect(pos.transactions, isEmpty);
  });

  test('Barista cannot inspect or pay another cashier bill', () async {
    final pos = await fresh('owner');
    final saved = await bill(pos, 'Owner');
    final quote = pos.quoteOpenBill(saved.id);
    await pos.logout();
    expect(await pos.login('warloc.kasir', 'sukses000'), isNull);
    expect(pos.openBills, isEmpty);
    expect(() => pos.quoteOpenBill(saved.id), throwsStateError);
    await expectLater(
        pos.payOpenBill(quote, paymentMethod: 'Cash', amountPaid: 100000),
        throwsStateError);
    expect(pos.transactions, isEmpty);
  });

  test(
      'Deleting a bill blocks concurrent settlement, resume and another delete',
      () async {
    final pos = await fresh();
    final saved = await bill(pos, 'Meja Hapus');
    final quote = pos.quoteOpenBill(saved.id);
    final deleting = pos.deleteOpenBill(saved.id);
    await expectLater(
        pos.payOpenBill(quote, paymentMethod: 'Cash', amountPaid: 50000),
        throwsStateError);
    expect(() => pos.resumeOpenBill(saved.id), throwsStateError);
    await expectLater(pos.deleteOpenBill(saved.id), throwsStateError);
    await deleting;
    expect(pos.openBills, isEmpty);
    expect(pos.transactions, isEmpty);
    expect(pos.cart, isEmpty);
  });

  testWidgets(
      'Selecting a bill opens details; payment stays in the bill workspace without loading the cart',
      (tester) async {
    final pos = (await tester.runAsync(fresh))!;
    final saved = (await tester.runAsync(() => bill(pos, 'Meja 12')))!;
    pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_3'), variant: 'ES');
    final before = pos.cart.map((i) => i.toMap()).toList();
    await tester.pumpWidget(app(pos, const MainWrapperScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cashier-tab-open-bill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('open-bill-${saved.id}')));
    await tester.pumpAndSettle();
    expect(pos.cart.map((i) => i.toMap()).toList(), before);
    expect(pos.activeBillId, isNull);
    expect(find.byType(Dialog), findsNothing);
    await tester.ensureVisible(find.text('Bayar tagihan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar tagihan'));
    await tester.pumpAndSettle();
    expect(find.text('Pembayaran tagihan'), findsOneWidget);
    await tester.ensureVisible(find.text('Konfirmasi pembayaran'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Konfirmasi pembayaran'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    expect(find.text('Tagihan sudah dibayar'), findsOneWidget);
    expect(pos.transactions.single.openBillId, saved.id);
    expect(pos.cart.map((i) => i.toMap()).toList(), before);
    expect(pos.openBills, isEmpty);
  });

  testWidgets(
      'Saving Unpaid opens its detail page; explicit edit updates the same bill',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pos = (await tester.runAsync(fresh))!;
    pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES');
    pos.setCustomerName('Meja 4');
    await tester.pumpWidget(app(pos, const MainWrapperScreen()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Unpaid / Open Bill'));
    await tester.tap(find.text('Unpaid / Open Bill'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Simpan Open Bill'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Simpan Open Bill'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Rincian tagihan'), findsOneWidget);
    final id = pos.openBills.single.id;
    expect(pos.transactions, isEmpty);
    expect(pos.cart, isEmpty);
    await tester.tap(find.text('Edit pesanan'));
    await tester.pumpAndSettle();
    expect(find.text('Mengedit Open Bill'), findsOneWidget);
    expect(pos.activeBillId, id);
    final unpaid = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Unpaid / Open Bill'));
    expect(unpaid.selected, isTrue);
    pos.updateQuantity('w_1', 1, variant: 'ES');
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Perbarui Open Bill'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Perbarui Open Bill'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(pos.openBills.single.id, id);
    expect(pos.openBills.single.revision, 2);
    expect(pos.openBills.single.items.single.quantity, 2);
    expect(pos.transactions, isEmpty);
  });

  testWidgets('QRIS requires receipt confirmation and settles the bill once',
      (tester) async {
    final pos = (await tester.runAsync(fresh))!;
    final saved = (await tester.runAsync(() => bill(pos, 'Meja QRIS')))!;
    await tester.pumpWidget(
        app(pos, Scaffold(body: OpenBillsScreen(initialBillId: saved.id))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bayar tagihan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar tagihan'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('QRIS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QRIS'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Konfirmasi pembayaran'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi pembayaran'));
    await tester.pumpAndSettle();
    expect(pos.transactions, isEmpty);
    expect(pos.openBills.length, 1);
    expect(
        find.text(
            'Pastikan pembayaran QRIS sudah diterima sebelum mengonfirmasi.'),
        findsOneWidget);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Konfirmasi pembayaran'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Konfirmasi pembayaran'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    expect(pos.transactions.single.paymentMethod, 'QRIS');
    expect(pos.transactions.single.changeAmount, 0);
    expect(pos.openBills, isEmpty);
    expect(find.text('Tagihan sudah dibayar'), findsOneWidget);
  });

  testWidgets(
      'Cancelling an edit retains the saved bill and discards only the cart changes',
      (tester) async {
    final pos = (await tester.runAsync(fresh))!;
    final saved = (await tester.runAsync(() => bill(pos, 'Meja Batal')))!;
    pos.resumeOpenBill(saved.id);
    pos.updateQuantity('w_1', 1, variant: 'ES');
    var cancelled = false;
    await tester.pumpWidget(app(
        pos,
        Scaffold(
            body: CartBottomSheet(
                isTabletSidebar: true,
                onBillCancelled: () => cancelled = true))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut edit'));
    await tester.pumpAndSettle();
    expect(pos.cart.single.quantity, 2);
    expect(cancelled, isFalse);
    await tester.tap(find.text('Batal edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Batal edit').last);
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    expect(pos.cart, isEmpty);
    expect(pos.activeBillId, isNull);
    expect(pos.openBills.single.id, saved.id);
    expect(pos.openBills.single.revision, 1);
    expect(pos.openBills.single.items.single.quantity, 1);
    expect(pos.transactions, isEmpty);
  });

  for (final scenario in [
    (size: const Size(320, 568), scale: 1.5, keyboard: 0.0),
    (size: const Size(800, 360), scale: 1.5, keyboard: 120.0),
    (size: const Size(600, 960), scale: 1.5, keyboard: 250.0),
    (size: const Size(1280, 800), scale: 1.0, keyboard: 0.0),
  ]) {
    testWidgets('Bill detail and payment fit $scenario', (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pos = (await tester.runAsync(fresh))!;
      final saved = (await tester.runAsync(
          () => bill(pos, 'Meja keluarga dekat jendela lantai dua')))!;
      await tester.runAsync(() => bill(pos, 'Meja 3', product: 'w_3'));
      await tester.pumpWidget(app(pos, const MainWrapperScreen(),
          scale: scenario.scale, keyboard: scenario.keyboard));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('cashier-tab-open-bill')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(ValueKey('open-bill-${saved.id}')), 100,
          scrollable: find
              .descendant(
                  of: find.byKey(const PageStorageKey('open-bills-list')),
                  matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      await tester.tapAt(
          tester.getTopLeft(find.byKey(ValueKey('open-bill-${saved.id}'))) +
              const Offset(20, 20));
      await tester.pumpAndSettle();
      await screenshot(tester, 'detail-${scenario.size.width.toInt()}');
      await tester.ensureVisible(find.text('Bayar tagihan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bayar tagihan'));
      await tester.pumpAndSettle();
      await screenshot(tester, 'payment-${scenario.size.width.toInt()}');
      await tester.ensureVisible(find.byKey(const ValueKey('open-bill-cash')));
      await tester.enterText(find.byKey(const ValueKey('open-bill-cash')), '1');
      await tester.pump();
      await tester.ensureVisible(find.text('Konfirmasi pembayaran'));
      await tester.tap(find.text('Konfirmasi pembayaran'));
      await tester.pumpAndSettle();
      expect(pos.openBills.length, 2);
      expect(pos.transactions, isEmpty);
      expect(find.text('Nominal yang diterima belum mencukupi total tagihan.'),
          findsOneWidget);
      if (scenario.size.width == 1280) {
        await screenshot(tester, 'payment-workspace');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
