import 'dart:convert';
import 'dart:async';
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
      'Failed deletion persistence leaves sale, inventory, audit and cart unchanged; retry commits once',
      () async {
    String? stored;
    var fail = false;
    var hold = false;
    final saving = Completer<void>();
    final release = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SecurePreferences.channel, (call) async {
      if (call.method == 'read') return stored;
      if (call.method == 'write') {
        if (fail) throw PlatformException(code: 'storage_unavailable');
        if (hold) {
          saving.complete();
          await release.future;
        }
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
    expect(await pos.login('warloc.owner', 'sukses888'), isNull);
    final product = pos.products.firstWhere((p) => p.id == 'w_1');
    pos.addToCart(product, variant: 'ES');
    final tx = await pos.processCheckout(
        paymentMethod: 'Cash', amountPaid: 50000, cashierName: '');
    pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_3'), variant: 'ES');
    pos.setCustomerName('Pesanan lain');
    final before = stored;
    final cart = jsonEncode(pos.cart.map((item) => item.toMap()).toList());
    fail = true;
    await expectLater(
        pos.deleteTransaction(
            transactionId: tx.id,
            expectedRevision: 0,
            reason: 'Transaksi ganda'),
        throwsA(isA<PlatformException>()));
    expect(stored, before);
    expect(pos.transactions.single.id, tx.id);
    expect(pos.deletedTransactions, isEmpty);
    expect(pos.products.firstWhere((p) => p.id == product.id).stock,
        product.stock - 1);
    expect(db.pendingDeletedTransactionCount, 0);
    expect(pos.isCheckoutInProgress, isFalse);
    expect(jsonEncode(pos.cart.map((item) => item.toMap()).toList()), cart);
    fail = false;
    hold = true;
    final deleting = pos.deleteTransaction(
        transactionId: tx.id, expectedRevision: 0, reason: 'Transaksi ganda');
    await saving.future;
    await expectLater(db.voidTransaction(tx.id), throwsStateError);
    await expectLater(
        db.correctTransaction(
            transactionId: tx.id,
            expectedRevision: 0,
            items: tx.items,
            amountPaid: 50000,
            reason: 'Koreksi bersamaan'),
        throwsStateError);
    await expectLater(
        db.processTransaction(
            tx.copyWith(id: 'parallel_sale', invoiceNumber: 'parallel_sale')),
        throwsStateError);
    await expectLater(pos.saveCurrentBill(), throwsStateError);
    hold = false;
    release.complete();
    await deleting;
    expect(pos.transactions, isEmpty);
    expect(pos.products.firstWhere((p) => p.id == product.id).stock,
        product.stock);
    expect(pos.deletedTransactions.single.id, tx.id);
    expect(pos.customerName, 'Pesanan lain');
    expect(jsonEncode(pos.cart.map((item) => item.toMap()).toList()), cart);
    await db.resetForTesting();
    await db.authenticate('warloc.owner', 'sukses888');
    expect(db.getTransactions(), isEmpty);
    expect(db.getDeletedTransactions().single.id, tx.id);
    expect(db.getProducts().firstWhere((p) => p.id == product.id).stock,
        product.stock);
  });
}
