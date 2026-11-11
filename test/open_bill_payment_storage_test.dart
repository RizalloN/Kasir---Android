import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PosDatabaseService.enableTestMode();

  test(
      'Bill create, edit and delete publish only after durable storage succeeds',
      () async {
    String? stored;
    var fail = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SecurePreferences.channel, (call) async {
      if (call.method == 'read') return stored;
      if (call.method == 'write') {
        if (fail) throw PlatformException(code: 'storage_unavailable');
        stored = (call.arguments as Map)['data'] as String;
        return null;
      }
      throw MissingPluginException();
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SecurePreferences.channel, null));
    SharedPreferences.setMockInitialValues({});
    SecurePreferences.resetForTesting();
    final db = PosDatabaseService.instance;
    await db.resetForTesting();
    final pos = PosProvider();
    addTearDown(pos.dispose);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    expect(await pos.login('warloc.kasir', 'sukses000'), isNull);
    pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES');
    pos.setCustomerName('Meja 1');
    fail = true;
    await expectLater(pos.saveCurrentBill(), throwsA(isA<PlatformException>()));
    expect(db.getOpenBills(), isEmpty);
    expect(pos.cart.single.quantity, 1);
    fail = false;
    final bill = await pos.saveCurrentBill();
    pos.resumeOpenBill(bill.id);
    pos.updateQuantity('w_1', 1, variant: 'ES');
    fail = true;
    await expectLater(pos.saveCurrentBill(), throwsA(isA<PlatformException>()));
    expect(db.getOpenBills().single.revision, 1);
    expect(db.getOpenBills().single.items.single.quantity, 1);
    expect(pos.cart.single.quantity, 2);
    expect(pos.activeBillId, bill.id);
    fail = false;
    await pos.saveCurrentBill();
    expect(pos.openBills.single.revision, 2);
    expect(pos.openBills.single.items.single.quantity, 2);
    fail = true;
    await expectLater(
        pos.deleteOpenBill(bill.id), throwsA(isA<PlatformException>()));
    expect(db.getOpenBills().single.id, bill.id);
    fail = false;
    await pos.deleteOpenBill(bill.id);
    expect(db.getOpenBills(), isEmpty);
    expect(pos.transactions, isEmpty);
    await db.resetForTesting();
    expect(await db.authenticate('warloc.kasir', 'sukses000'), isNotNull);
    expect(db.getOpenBills(), isEmpty);
    expect(db.getTransactions(), isEmpty);
  });

  test(
      'Failed bill payment keeps bill, stock and other cart intact; retry persists exactly one sale',
      () async {
    String? stored;
    var fail = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SecurePreferences.channel, (call) async {
      if (call.method == 'read') return stored;
      if (call.method == 'write') {
        if (fail) throw PlatformException(code: 'storage_unavailable');
        stored = (call.arguments as Map)['data'] as String;
        return null;
      }
      throw MissingPluginException();
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SecurePreferences.channel, null));
    SharedPreferences.setMockInitialValues({});
    SecurePreferences.resetForTesting();
    final db = PosDatabaseService.instance;
    await db.resetForTesting();
    final pos = PosProvider();
    addTearDown(pos.dispose);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    expect(await pos.login('warloc.kasir', 'sukses000'), isNull);
    final product = pos.products.firstWhere((p) => p.id == 'w_1');
    pos.addToCart(product, variant: 'ES');
    pos.setCustomerName('Meja Tersimpan');
    final bill = await pos.saveCurrentBill();
    final quote = pos.quoteOpenBill(bill.id);
    pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_3'), variant: 'ES');
    pos.setCustomerName('Pesanan Lain');
    final before = stored;
    final cart = jsonEncode(pos.cart.map((item) => item.toMap()).toList());
    fail = true;
    await expectLater(
        pos.payOpenBill(quote, paymentMethod: 'Cash', amountPaid: 50000),
        throwsA(isA<PlatformException>()));
    expect(pos.isCheckoutInProgress, isFalse);
    expect(stored, before);
    expect(pos.transactions, isEmpty);
    expect(db.getTransactions(), isEmpty);
    expect(pos.openBills.single.id, bill.id);
    expect(db.getOpenBills().single.id, bill.id);
    expect(db.getProducts().firstWhere((p) => p.id == product.id).stock,
        product.stock);
    expect(jsonEncode(pos.cart.map((item) => item.toMap()).toList()), cart);
    fail = false;
    await pos.payOpenBill(quote, paymentMethod: 'Cash', amountPaid: 50000);
    expect(pos.transactions.length, 1);
    expect(pos.openBills, isEmpty);
    expect(jsonEncode(pos.cart.map((item) => item.toMap()).toList()), cart);
    expect(pos.customerName, 'Pesanan Lain');
    await expectLater(
        pos.payOpenBill(quote, paymentMethod: 'Cash', amountPaid: 50000),
        throwsStateError);
    await db.resetForTesting();
    expect(await db.authenticate('warloc.kasir', 'sukses000'), isNotNull);
    expect(db.getTransactions().single.openBillId, bill.id);
    expect(db.getOpenBills(), isEmpty);
    expect(db.getProducts().firstWhere((p) => p.id == product.id).stock,
        product.stock - 1);
  });
}
