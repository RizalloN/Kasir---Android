import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/cart_item.dart';
import 'package:kasir_super/models/product.dart';
import 'package:kasir_super/models/transaction.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/dialogs/transaction_history_dialog.dart';
import 'package:kasir_super/screens/dialogs/edit_product_dialog.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  final db = PosDatabaseService.instance;
  final providers = <PosProvider>[];
  setUpAll(() => initializeDateFormatting('id_ID', null));
  tearDown(() {
    for (final pos in providers) {
      pos.dispose();
    }
    providers.clear();
    PosDatabaseService.enableTestMode();
  });

  Future<PosProvider> fresh([String role = 'owner']) async {
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

  Future<TransactionRecord> sale(PosProvider pos) async {
    final coffee = pos.products.firstWhere((p) => p.id == 'w_1');
    expect(pos.addToCart(coffee, variant: 'ES'), isTrue);
    expect(pos.addToCart(coffee, variant: 'ES'), isTrue);
    return pos.processCheckout(
        paymentMethod: 'Cash', amountPaid: 50000, cashierName: '');
  }

  test(
      'Refund and extra charge update totals, stock, payment and audit; restart preserves them',
      () async {
    final pos = await fresh();
    final sold = await sale(pos);
    expect(sold.totalAmount, 46000);
    expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, 48);
    final corrected = await pos.correctTransaction(
        transactionId: sold.id,
        expectedRevision: sold.revision,
        items: [sold.items.single.copyWith(quantity: 1)],
        amountPaid: 50000,
        reason: 'Terinput dua kali');
    expect(corrected.totalAmount, 23000);
    expect(corrected.totalCost, 9000);
    expect(corrected.totalProfit, 14000);
    expect(corrected.changeAmount, 27000);
    expect(corrected.revision, 1);
    expect(corrected.corrections.single['difference'], -23000);
    expect(corrected.corrections.single['previousAmountPaid'], 50000);
    expect(
        (corrected.corrections.single['previousItems'] as List)
            .single['quantity'],
        2);
    expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, 49);
    final pastry = pos.products.firstWhere((p) => p.id == 'w_6');
    final next = await pos.correctTransaction(
        transactionId: sold.id,
        expectedRevision: corrected.revision,
        items: [...corrected.items, CartItem(product: pastry)],
        amountPaid: 50000,
        reason: 'Tambah pesanan');
    expect(next.totalAmount, 23000 + pastry.sellPrice);
    expect(pos.todayRevenue, next.totalAmount);
    expect(next.changeAmount, 50000 - next.totalAmount);
    expect(next.corrections.last['difference'], pastry.sellPrice);
    expect(next.revision, 2);
    expect(pos.products.firstWhere((p) => p.id == pastry.id).stock,
        pastry.stock - 1);
    expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, 49);
    next.corrections.first['reason'] = 'Modified outside';
    expect(db.getTransactions().single.corrections.first['reason'],
        'Terinput dua kali');
    providers.remove(pos);
    pos.dispose();
    await db.resetForTesting();
    final reopened = PosProvider();
    providers.add(reopened);
    while (!reopened.isInitialized && reopened.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(reopened.transactions.single.revision, 2);
    expect(reopened.transactions.single.corrections.length, 2);
    expect(reopened.transactions.single.totalAmount, next.totalAmount);
    expect(reopened.products.firstWhere((p) => p.id == 'w_1').stock, 49);
    expect(await reopened.voidTransaction(next.id), isTrue);
    expect(reopened.products.firstWhere((p) => p.id == 'w_1').stock, 50);
    expect(reopened.products.firstWhere((p) => p.id == pastry.id).stock,
        pastry.stock);
    expect(reopened.transactions.single.corrections.length, 2);
    expect(reopened.todayRevenue, 0);
  });

  test(
      'Stale revisions, invalid payment, forged prices and insufficient stock never change transaction',
      () async {
    final pos = await fresh();
    final tx = await sale(pos);
    final before = db.getProducts().firstWhere((p) => p.id == 'w_1').stock;
    Future<TransactionRecord> correct(
            {int revision = 0,
            List<CartItem>? items,
            double paid = 50000,
            String reason = 'Double'}) =>
        pos.correctTransaction(
            transactionId: tx.id,
            expectedRevision: revision,
            items: items ?? tx.items,
            amountPaid: paid,
            reason: reason);
    await expectLater(correct(revision: 9), throwsStateError);
    await expectLater(correct(items: []), throwsArgumentError);
    await expectLater(correct(paid: 1), throwsArgumentError);
    await expectLater(correct(reason: ''), throwsArgumentError);
    await expectLater(
        correct(items: [
          tx.items.first
              .copyWith(product: tx.items.first.product.copyWith(sellPrice: 1))
        ]),
        throwsStateError);
    await expectLater(
        correct(
            items: [tx.items.first.copyWith(quantity: 1000)], paid: 100000000),
        throwsStateError);
    expect(db.getTransactions().single.revision, 0);
    expect(db.getTransactions().single.totalAmount, 46000);
    expect(db.getProducts().firstWhere((p) => p.id == 'w_1').stock, before);
    final updated =
        await correct(items: [tx.items.first.copyWith(quantity: 1)]);
    await expectLater(correct(), throwsStateError);
    expect(updated.revision, 1);
  });

  test('Admin corrects cashier transaction; cashier cannot correct it',
      () async {
    final pos = await fresh('kasir');
    final tx = await sale(pos);
    expect(await pos.login('warloc.admin', 'sukses123'), isNull);
    expect(pos.canCorrectTransaction(tx), isTrue);
    final corrected = await pos.correctTransaction(
            transactionId: tx.id,
            expectedRevision: 0,
            items: [tx.items.single.copyWith(quantity: 1)],
            amountPaid: 50000,
            reason: 'Salah');
    expect(corrected.totalAmount, 23000);
    expect(corrected.revision, 1);
    expect(corrected.corrections.single['correctedById'], pos.currentUser!.id);
    expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, 49);
    expect(await pos.login('warloc.kasir', 'sukses000'), isNull);
    await expectLater(pos.correctTransaction(
        transactionId: tx.id,
        expectedRevision: 1,
        items: corrected.items,
        amountPaid: 50000,
        reason: 'Salah'), throwsStateError);
    expect(pos.transactions.single.revision, 1);
  });

  test(
      'Production mode refuses financial correction without Firebase connection',
      () async {
    final pos = await fresh();
    final tx = await sale(pos);
    PosDatabaseService.enableTestMode(enabled: false);
    await expectLater(
        pos.correctTransaction(
            transactionId: tx.id,
            expectedRevision: 0,
            items: [tx.items.single.copyWith(quantity: 1)],
            amountPaid: 50000,
            reason: 'Double'),
        throwsStateError);
    expect(db.getTransactions().single.totalAmount, tx.totalAmount);
    expect(db.getProducts().firstWhere((p) => p.id == 'w_1').stock, 48);
  });

  test('Drink marker supports category defaults and explicit custom overrides',
      () async {
    final pos = await fresh();
    final original = pos.products.firstWhere((p) => p.id == 'w_1');
    expect(original.isDrink, isTrue);
    const custom = Product(
        id: 'custom_drink',
        name: 'Teh Herbal',
        category: 'Teh',
        sellPrice: 12000,
        baseCost: 4000,
        stock: 5,
        drinkOverride: true);
    await pos.addNewProduct(custom);
    expect(pos.products.firstWhere((p) => p.id == custom.id).isDrink, isTrue);
    expect(Product.fromMap(custom.toMap()).isDrink, isTrue);
    expect(
        Product.fromMap(original.copyWith(drinkOverride: false).toMap())
            .isDrink,
        isFalse);
    expect(pos.addToCart(custom, variant: 'ES'), isTrue);
    expect(pos.totalCartAmount, 13000);
    expect(pos.addToCart(original.copyWith(id: custom.id), variant: 'Jumbo'),
        isTrue);
    expect(pos.totalCartAmount, 28000);
  });

  test('QRIS corrections require payment exactly equal to the new total',
      () async {
    final pos = await fresh();
    final coffee = pos.products.firstWhere((p) => p.id == 'w_1');
    pos.addToCart(coffee, variant: 'ES');
    pos.addToCart(coffee, variant: 'ES');
    final tx = await pos.processCheckout(
        paymentMethod: 'QRIS', amountPaid: 46000, cashierName: '');
    final correctedItems = [tx.items.single.copyWith(quantity: 1)];
    await expectLater(
        pos.correctTransaction(
            transactionId: tx.id,
            expectedRevision: 0,
            items: correctedItems,
            amountPaid: 46000,
            reason: 'Duplikat'),
        throwsArgumentError);
    final saved = await pos.correctTransaction(
        transactionId: tx.id,
        expectedRevision: 0,
        items: correctedItems,
        amountPaid: 23000,
        reason: 'Duplikat');
    expect(saved.amountPaid, 23000);
    expect(saved.changeAmount, 0);
    expect(saved.corrections.single['difference'], -23000);
  });

  test('Simultaneous corrections do not both update the same transaction',
      () async {
    final pos = await fresh();
    final tx = await sale(pos);
    Future<TransactionRecord> correct() => pos.correctTransaction(
        transactionId: tx.id,
        expectedRevision: 0,
        items: [tx.items.single.copyWith(quantity: 1)],
        amountPaid: 50000,
        reason: 'Duplikat');
    final first = correct();
    final second = expectLater(correct(), throwsStateError);
    final saved = await first;
    await second;
    expect(saved.revision, 1);
    expect(db.getTransactions().single.corrections.length, 1);
    expect(db.getProducts().firstWhere((p) => p.id == 'w_1').stock, 49);
  });

  test('Corrections aggregate stock across variants of the same menu',
      () async {
    final pos = await fresh();
    final coffee = pos.products.firstWhere((p) => p.id == 'w_1');
    pos.addToCart(coffee, variant: 'Panas');
    pos.addToCart(coffee, variant: 'ES');
    pos.addToCart(coffee, variant: 'ES');
    final sold = await pos.processCheckout(
        paymentMethod: 'Cash', amountPaid: 100000, cashierName: '');
    final jumbo = CartItem(
        product: coffee.copyWith(sellPrice: coffee.sellPrice + 3000),
        note: CartItem.composeNote('Jumbo', null));
    final saved = await pos.correctTransaction(
        transactionId: sold.id,
        expectedRevision: 0,
        items: [sold.items.first, sold.items.last.copyWith(quantity: 1), jumbo],
        amountPaid: 100000,
        reason: 'Varian salah');
    expect(saved.totalAmount, 22000 + 23000 + 25000);
    expect(saved.corrections.single['difference'], 2000);
    expect(pos.products.firstWhere((p) => p.id == coffee.id).stock, 47);
  });

  test(
      'Existing item prices remain historical when the menu price or marker changes',
      () async {
    final pos = await fresh();
    final tx = await sale(pos);
    final coffee = pos.products.firstWhere((p) => p.id == 'w_1');
    await pos.updateExistingProduct(
        coffee.copyWith(sellPrice: 30000, drinkOverride: false));
    final altered = tx.items.single.copyWith(
      quantity: 1,
      product: tx.items.single.product.copyWith(name: 'Nama palsu'),
      note: CartItem.composeNote('ES', 'Catatan palsu'),
    );
    final saved = await pos.correctTransaction(
        transactionId: tx.id,
        expectedRevision: 0,
        items: [altered],
        amountPaid: 50000,
        reason: 'Jumlah salah');
    expect(saved.totalAmount, 23000);
    expect(saved.items.single.product.name, tx.items.single.product.name);
    expect(saved.items.single.customerNote, isNull);
    expect(saved.items.single.drinkVariant, 'ES');
  });

  for (final size in [const Size(320, 568), const Size(800, 360)]) {
    testWidgets('Correction remains usable at $size with large text',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pos = (await tester.runAsync(fresh))!;
      final tx = (await tester.runAsync(() => sale(pos)))!;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: pos,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!),
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                          onPressed: () => showDialog<bool>(
                              context: context,
                              builder: (_) =>
                                  CorrectTransactionDialog(transaction: tx)),
                          child: const Text('Buka'),
                        ))),
          )));
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      expect(find.text('Periksa Koreksi').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Kurangi item 1'));
      await tester.tap(find.byTooltip('Kurangi item 1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Admin edits cashier transaction through history and confirms a refund',
      (tester) async {
    final pos = (await tester.runAsync(() => fresh('kasir')))!;
    await tester.runAsync(() => sale(pos));
    expect(await tester.runAsync(() => pos.login('warloc.admin', 'sukses123')), isNull);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: pos,
        child: const MaterialApp(
            home: Scaffold(body: TransactionHistoryDialog()))));
    await tester.pumpAndSettle();
    expect(find.text('Riwayat Transaksi'), findsOneWidget);
    await tester.ensureVisible(find.text('Koreksi'));
    await tester.tap(find.text('Koreksi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kurangi item 1'));
    await tester.pump();
    expect(
        find.text('Pengembalian kepada pelanggan: Rp 23.000'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('correction-reason-input')), 'Terinput dua kali');
    await tester.ensureVisible(find.text('Periksa Koreksi'));
    await tester.tap(find.text('Periksa Koreksi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kembalikan Rp 23.000'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Simpan Koreksi'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(pos.transactions.single.totalAmount, 23000);
    expect(pos.transactions.single.revision, 1);
    expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, 49);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Menu editor can mark a custom category as a drink',
      (tester) async {
    final pos = (await tester.runAsync(fresh))!;
    const product = Product(
        id: 'custom_tea',
        name: 'Teh Herbal',
        category: 'Teh',
        sellPrice: 12000,
        baseCost: 4000,
        stock: 10);
    Product? result;
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: pos,
        child: MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => EditProductDialog(
                                product: product,
                                onSave: (saved) => result = saved)),
                        child: const Text('Edit menu'),
                      ))),
        )));
    await tester.tap(find.text('Edit menu'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final toggle = find.widgetWithText(SwitchListTile, 'Menu minuman');
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.ensureVisible(find.text('Simpan Perubahan'));
    await tester.tap(find.text('Simpan Perubahan'));
    await tester.pumpAndSettle();
    expect(result?.isDrink, isTrue);
    expect(Product.fromMap(result!.toMap()).isDrink, isTrue);
    expect(tester.takeException(), isNull);
  });
}
