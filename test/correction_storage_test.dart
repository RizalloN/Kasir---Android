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
      'Failed local save rolls back correction, audit and stock; retry succeeds',
      () async {
    String? stored;
    var failWrites = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SecurePreferences.channel, (call) async {
      if (call.method == 'read') return stored;
      if (call.method == 'write') {
        if (failWrites) throw PlatformException(code: 'storage_unavailable');
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
    expect(await pos.login('warloc.owner', 'sukses888'), isNull);
    final coffee = pos.products.firstWhere((p) => p.id == 'w_1');
    pos.addToCart(coffee, variant: 'ES');
    pos.addToCart(coffee, variant: 'ES');
    final tx = await pos.processCheckout(
        paymentMethod: 'Cash', amountPaid: 50000, cashierName: '');
    final before = stored;
    failWrites = true;
    await expectLater(
        pos.correctTransaction(
            transactionId: tx.id,
            expectedRevision: 0,
            items: [tx.items.single.copyWith(quantity: 1)],
            amountPaid: 50000,
            reason: 'Duplikat'),
        throwsStateError);
    expect(stored, before);
    expect(db.getTransactions().single.totalAmount, 46000);
    expect(db.getTransactions().single.revision, 0);
    expect(db.getProducts().firstWhere((p) => p.id == coffee.id).stock, 48);
    failWrites = false;
    final saved = await pos.correctTransaction(
        transactionId: tx.id,
        expectedRevision: 0,
        items: [tx.items.single.copyWith(quantity: 1)],
        amountPaid: 50000,
        reason: 'Duplikat');
    expect(saved.totalAmount, 23000);
    expect(saved.revision, 1);
    expect(db.getProducts().firstWhere((p) => p.id == coffee.id).stock, 49);
  });
}
