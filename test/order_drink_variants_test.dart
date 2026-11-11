import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/cart_item.dart';
import 'package:kasir_super/models/transaction.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/barista/pos_screen.dart';
import 'package:kasir_super/screens/barista/cart_bottom_sheet.dart';
import 'package:kasir_super/screens/dialogs/open_bills_dialog.dart';
import 'package:kasir_super/services/app_release_service.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID', null));
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  final db = PosDatabaseService.instance;
  final providers = <PosProvider>[];
  tearDown(() {
    for (final provider in providers) {
      provider.dispose();
    }
    providers.clear();
  });

  Future<PosProvider> setup() async {
    SharedPreferences.setMockInitialValues({});
    await db.resetForTesting();
    final pos = PosProvider();
    providers.add(pos);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    expect(await pos.login('warloc.owner', 'sukses888'), isNull);
    return pos;
  }

  test('Mixed variants, notes and corrections survive saved order and checkout',
      () async {
    final pos = await setup();
    final coffee = pos.products.firstWhere((p) => p.id == 'w_1');
    final originalStock = coffee.stock;
    expect(pos.addToCart(coffee, variant: 'Panas', note: 'Tanpa gula'), isTrue);
    expect(pos.addToCart(coffee, variant: 'ES'), isTrue);
    expect(pos.addToCart(coffee, variant: 'Jumbo'), isTrue);
    expect(pos.cart.map((i) => i.product.sellPrice), [22000, 23000, 25000]);
    expect(pos.subtotalCartAmount, 70000);
    expect(pos.cart.first.customerNote, 'Tanpa gula');
    pos.setCustomerName('Meja 7');
    await pos.saveCurrentBill();
    expect(pos.transactions, isEmpty);
    expect(
        pos.products.firstWhere((p) => p.id == coffee.id).stock, originalStock);
    final saved = pos.openBills.single;
    expect(saved.totalAmount, 70000);
    expect(saved.items.map((i) => i.drinkVariant), ['Panas', 'ES', 'Jumbo']);
    pos.resumeOpenBill(saved.id);
    expect(pos.updateQuantity(coffee.id, -1, variant: 'ES'), isTrue);
    expect(pos.updateQuantity(coffee.id, 1, variant: 'Jumbo'), isTrue);
    expect(pos.totalCartAmount, 72000);
    await pos.saveCurrentBill();
    expect(pos.openBills.single.revision, 2);
    pos.resumeOpenBill(saved.id);
    final tx = await pos.processCheckout(
        paymentMethod: 'Cash', amountPaid: 100000, cashierName: '');
    expect(tx.subtotalAmount, 72000);
    expect(tx.totalCost, 27000);
    expect(tx.totalProfit, 45000);
    expect(tx.changeAmount, 28000);
    expect(tx.items.map((i) => i.drinkVariant), ['Panas', 'Jumbo']);
    expect(tx.items.first.customerNote, 'Tanpa gula');
    expect(pos.products.firstWhere((p) => p.id == coffee.id).stock,
        originalStock - 3);
    expect(pos.openBills, isEmpty);
    final restored = TransactionRecord.fromMap(tx.toMap());
    expect(restored.items.map((i) => i.drinkVariant), ['Panas', 'Jumbo']);
    expect(restored.items.map((i) => i.subtotal), [22000, 50000]);
    expect(await pos.voidTransaction(tx.id), isTrue);
    expect(
        pos.products.firstWhere((p) => p.id == coffee.id).stock, originalStock);
  });

  test('Variants share stock; exact row changes do not modify another variant',
      () async {
    final pos = await setup();
    final coffee = pos.products.firstWhere((p) => p.id == 'w_1');
    await pos.adjustProductStock(coffee.id, 2);
    expect(pos.addToCart(coffee, variant: 'ES'), isTrue);
    expect(pos.addToCart(coffee), isTrue);
    expect(pos.addToCart(coffee, variant: 'Jumbo'), isFalse);
    expect(pos.updateQuantity(coffee.id, 1, variant: 'ES'), isFalse);
    pos.updateItemNote(coffee.id, 'Baris biasa', variant: null);
    expect(pos.cart.first.customerNote, isNull);
    expect(pos.cart.last.customerNote, 'Baris biasa');
    expect(pos.updateQuantity(coffee.id, -1, variant: null), isTrue);
    expect(pos.cart.single.drinkVariant, 'ES');
    expect(pos.addToCart(coffee, variant: 'Jumbo'), isTrue);
    expect(pos.addToCart(coffee, variant: 'Tidak valid'), isFalse);
  });

  test(
      'An unpaid order with different variants survives restart and remains editable',
      () async {
    final pos = await setup();
    final coffee = pos.products.firstWhere((p) => p.id == 'w_1');
    pos.addToCart(coffee, variant: 'ES', note: 'Sedikit gula');
    pos.addToCart(coffee, variant: 'Jumbo');
    pos.setCustomerName('Meja 9');
    await pos.saveCurrentBill();
    final id = pos.openBills.single.id;
    providers.remove(pos);
    pos.dispose();
    await db.resetForTesting();
    final restored = PosProvider();
    providers.add(restored);
    while (!restored.isInitialized && restored.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(restored.openBills.single.id, id);
    restored.resumeOpenBill(id);
    expect(restored.cart.map((i) => i.drinkVariant), ['ES', 'Jumbo']);
    expect(restored.cart.first.customerNote, 'Sedikit gula');
    expect(restored.totalCartAmount, 48000);
    expect(restored.updateQuantity(coffee.id, -1, variant: 'ES'), isTrue);
    await restored.saveCurrentBill();
    expect(restored.openBills.single.totalAmount, 25000);
    expect(restored.transactions, isEmpty);
  });

  test(
      'Catalog price changes recalculate each surcharge and legacy notes remain unchanged',
      () async {
    final pos = await setup();
    final coffee = pos.products.firstWhere((p) => p.id == 'w_1');
    expect(pos.addToCart(coffee, variant: 'ES', note: 'Less sugar'), isTrue);
    expect(pos.addToCart(coffee, variant: 'Jumbo'), isTrue);
    await pos.updateExistingProduct(coffee.copyWith(sellPrice: 30000));
    expect(pos.cart.map((i) => i.product.sellPrice), [31000, 33000]);
    expect(pos.totalCartAmount, 64000);
    final legacy = CartItem.fromMap({
      'productId': 'legacy',
      'productName': 'Kopi',
      'category': 'Coffee',
      'sellPrice': 22000,
      'baseCost': 9000,
      'quantity': 1,
      'note': 'Panas (Hot)'
    });
    expect(legacy.drinkVariant, isNull);
    expect(legacy.customerNote, 'Panas (Hot)');
    expect(legacy.subtotal, 22000);
  });

  test('Service rejects forged variant price and aggregate stock excess',
      () async {
    final pos = await setup();
    final coffee = pos.products.firstWhere((p) => p.id == 'w_1');
    await pos.adjustProductStock(coffee.id, 1);
    final user = pos.currentUser!;
    TransactionRecord build(List<CartItem> items, double subtotal) =>
        TransactionRecord(
            id: 'INV-TEST',
            invoiceNumber: 'INV-TEST',
            items: items,
            subtotalAmount: subtotal,
            totalAmount: subtotal,
            totalCost: 9000,
            totalProfit: subtotal - 9000,
            paymentMethod: 'Cash',
            amountPaid: subtotal,
            changeAmount: 0,
            cashierName: user.displayName,
            cashierId: user.id,
            createdAt: DateTime.now());
    final forged = CartItem(
        product: coffee.copyWith(sellPrice: 22000),
        note: CartItem.composeNote('ES', null));
    await expectLater(
        db.processTransaction(build([forged], 22000)), throwsStateError);
    final hot =
        CartItem(product: coffee, note: CartItem.composeNote('Panas', null));
    final ice = CartItem(
        product: coffee.copyWith(sellPrice: 23000),
        note: CartItem.composeNote('ES', null));
    await expectLater(
        db.processTransaction(build([hot, ice], 45000)), throwsStateError);
    expect(db.getTransactions(), isEmpty);
    expect(db.getProducts().firstWhere((p) => p.id == coffee.id).stock, 1);
  });

  testWidgets('Cashier selects ES from menu with visible surcharge',
      (tester) async {
    final pos = (await tester.runAsync(setup))!;
    final release = AppReleaseService();
    addTearDown(release.dispose);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: pos),
      ChangeNotifierProvider.value(value: release),
    ], child: const MaterialApp(home: Scaffold(body: PosScreen()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopi Susu Warloc Gula Aren').first);
    await tester.pumpAndSettle();
    expect(find.text('Panas'), findsOneWidget);
    expect(find.text('ES'), findsOneWidget);
    expect(find.text('Jumbo'), findsOneWidget);
    expect(find.text('+ Rp 1.000'), findsOneWidget);
    expect(find.text('+ Rp 3.000'), findsOneWidget);
    await tester.tap(find.text('ES'));
    await tester.pumpAndSettle();
    expect(pos.cart.single.drinkVariant, 'ES');
    expect(pos.totalCartAmount, 23000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kasir saves an unpaid order and reopens it for correction',
      (tester) async {
    final pos = (await tester.runAsync(setup))!;
    await tester.runAsync(() => pos.login('warloc.kasir', 'sukses000'));
    final coffee = pos.products.firstWhere((p) => p.id == 'w_1');
    final originalStock = coffee.stock;
    expect(pos.addToCart(coffee, variant: 'ES'), isTrue);
    expect(pos.addToCart(coffee, variant: 'ES'), isTrue);
    final release = AppReleaseService();
    addTearDown(release.dispose);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: pos),
          ChangeNotifierProvider.value(value: release),
        ],
        child: const MaterialApp(
            home: Scaffold(body: CartBottomSheet(isTabletSidebar: true)))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Nama / Meja'), 'Meja 8');
    await tester.ensureVisible(find.text('Unpaid / Open Bill'));
    await tester.tap(find.text('Unpaid / Open Bill'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Simpan Open Bill'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Simpan Open Bill'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(pos.openBills.single.items.single.quantity, 2);
    expect(pos.transactions, isEmpty);
    expect(
        pos.products.firstWhere((p) => p.id == coffee.id).stock, originalStock);
    final context = tester.element(find.byType(Scaffold).first);
    showDialog<void>(context: context, builder: (_) => const OpenBillsDialog());
    await tester.pumpAndSettle();
    expect(find.text('Open Bill'), findsOneWidget);
    await tester.tap(find.text('Meja 8'));
    await tester.pumpAndSettle();
    expect(pos.cart, isEmpty);
    await tester.ensureVisible(find.text('Edit pesanan'));
    await tester.tap(find.text('Edit pesanan'));
    await tester.pumpAndSettle();
    expect(pos.cart.single.drinkVariant, 'ES');
    expect(pos.updateQuantity(coffee.id, -1, variant: 'ES'), isTrue);
    await tester.runAsync(() => pos.saveCurrentBill());
    expect(pos.openBills.single.items.single.quantity, 1);
    expect(pos.transactions, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
