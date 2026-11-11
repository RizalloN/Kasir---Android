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

  test('Failed durable save publishes no checkout, product edit, stock edit or expense; retry uses one sale', () async {
    String? stored;
    var fail = false;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SecurePreferences.channel, (call) async {
      if (call.method == 'read') return stored;
      if (call.method == 'write') {
        if (fail) throw PlatformException(code: 'storage_unavailable');
        stored = (call.arguments as Map)['data'] as String;
        return null;
      }
      throw MissingPluginException();
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SecurePreferences.channel, null));
    SharedPreferences.setMockInitialValues({});
    SecurePreferences.resetForTesting();
    final db = PosDatabaseService.instance;
    await db.resetForTesting();
    final pos = PosProvider();
    addTearDown(pos.dispose);
    while (!pos.isInitialized) { await Future<void>.delayed(const Duration(milliseconds: 5)); }
    expect(await pos.login('warloc.owner', 'sukses888'), isNull);
    final product = pos.products.first;
    pos.addToCart(product);
    final before = stored;
    final originalProducts = jsonEncode(db.getProducts().map((p) => p.toMap()).toList());
    fail = true;
    await expectLater(pos.processCheckout(paymentMethod: 'Cash', amountPaid: 100000, cashierName: ''), throwsA(isA<PlatformException>()));
    await expectLater(db.updateProduct(product.copyWith(name: 'Perubahan')), throwsA(isA<PlatformException>()));
    await expectLater(db.adjustStock(product.id, product.stock + 10), throwsA(isA<PlatformException>()));
    await expectLater(pos.addOperationalExpense(title: 'Listrik', category: 'Lainnya', amount: 1000), throwsA(isA<PlatformException>()));
    expect(stored, before);
    expect(db.getTransactions(), isEmpty);
    expect(db.getOperationalExpenses(), isEmpty);
    expect(jsonEncode(db.getProducts().map((p) => p.toMap()).toList()), originalProducts);
    expect(pos.cart, isNotEmpty);
    fail = false;
    await pos.processCheckout(paymentMethod: 'Cash', amountPaid: 100000, cashierName: '');
    expect(db.getTransactions().length, 1);
    await db.resetForTesting();
    expect(await db.authenticate('warloc.owner', 'sukses888'), isNotNull);
    expect(db.getTransactions().length, 1);
    expect(db.getProducts().firstWhere((p) => p.id == product.id).stock, product.stock - 1);
  });
}
