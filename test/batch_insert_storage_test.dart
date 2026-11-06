import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/operational_expense.dart';
import 'package:kasir_super/models/product.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PosDatabaseService.enableTestMode();

  test(
      'A secure-store failure leaves both batches untouched and the same IDs can be retried',
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
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    expect(await pos.login('warloc.owner', 'sukses888'), isNull);
    final initialProducts = db.getProducts().map((p) => p.toMap()).toList();
    final initialStored = stored;
    final products = List.generate(
        2,
        (i) => Product(
              id: 'disk_menu_$i',
              name: 'Kopi $i',
              category: 'Coffee',
              sellPrice: 20000,
              baseCost: 8000,
              stock: 15,
            ));
    final expenses = List.generate(
        2,
        (i) => OperationalExpense(
              id: 'disk_exp_$i',
              title: 'Sachet $i',
              category: 'Lainnya',
              amount: 10000,
              createdAt: DateTime(2026, 11, 6),
              recordedBy: '',
            ));
    failWrites = true;
    await expectLater(
        pos.addNewProducts(products), throwsA(isA<PlatformException>()));
    expect(db.getProducts().map((p) => p.toMap()).toList(), initialProducts);
    expect(stored, initialStored);
    await expectLater(pos.addOperationalExpenses(expenses),
        throwsA(isA<PlatformException>()));
    expect(db.getOperationalExpenses(), isEmpty);
    expect(stored, initialStored);

    failWrites = false;
    await pos.addNewProducts(products);
    await pos.addOperationalExpenses(expenses);
    expect(
        db.getProducts().where((p) => p.id.startsWith('disk_menu_')).length, 2);
    expect(db.getOperationalExpenses().length, 2);
    expect(db.getTransactions(), isEmpty);
    expect(db.getOpenBills(), isEmpty);

    pos.dispose();
    SecurePreferences.resetForTesting();
    await db.resetForTesting();
    await db.restoreSession();
    expect(
        db.getProducts().where((p) => p.id.startsWith('disk_menu_')).length, 2);
    expect(db.getOperationalExpenses().length, 2);
  });
}
