import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';
import 'package:kasir_super/services/firestore_sync_safety.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  final db = PosDatabaseService.instance;
  final providers = <PosProvider>[];
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    for (final pos in providers) {
      pos.dispose();
    }
    providers.clear();
    FirestoreSyncSafety.instance.connectionBlocked = false;
    FirestoreSyncSafety.instance.notice = null;
  });

  Future<PosProvider> open() async {
    final pos = PosProvider();
    providers.add(pos);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    return pos;
  }

  test(
      'Overlapping startup calls share initialization and preserve existing credentials',
      () async {
    final resetting = db.resetForTesting();
    final first = db.initialize();
    final second = db.initialize();
    expect(identical(first, second), isTrue);
    await Future.wait([resetting, first, second]);
    final pos = await open();
    expect(await pos.login('warloc.owner', 'sukses888'), isNull);
    final before = {for (final u in pos.users) u.id: u.passwordHash};
    await Future.wait(List.generate(100, (_) => db.initialize()));
    expect({for (final u in pos.users) u.id: u.passwordHash}, before);
  });

  test(
      'Concurrent offline deletes retain the right IDs and durable retry intents through restart',
      () async {
    await db.resetForTesting();
    var pos = await open();
    expect(await pos.login('warloc.owner', 'sukses888'), isNull);
    expect(pos.isOnline, isFalse);
    final ids = pos.products.take(2).map((p) => p.id).toList();
    final unaffected = pos.products[2].id;
    final expense = await pos.addOperationalExpense(
        title: 'Listrik', category: 'Lainnya', amount: 1000);
    final deleted = await Future.wait([
      db.deleteProduct(ids[0]),
      db.deleteProduct(ids[1]),
      db.deleteUser('u_barista_default'),
      db.deleteOperationalExpense(expense.id),
    ]);
    expect(deleted.every((ok) => ok), isTrue);
    expect(db.getProducts().any((p) => ids.contains(p.id)), isFalse);
    expect(db.getProducts().any((p) => p.id == unaffected), isTrue);
    expect(db.pendingDeletionCount, 4);
    final prefs = await SecurePreferences.getInstance();
    final expected = {
      'products/${ids[0]}',
      'products/${ids[1]}',
      'users/u_barista_default',
      'operational_expenses/${expense.id}'
    };
    expect(
        (jsonDecode(prefs.getString('firestore_pending_deletes_v1')!) as List)
            .toSet(),
        expected);
    pos.dispose();
    providers.remove(pos);
    await db.resetForTesting();
    pos = await open();
    expect(db.pendingDeletionCount, 4);
    expect(pos.products.any((p) => ids.contains(p.id)), isFalse);
    expect(pos.products.any((p) => p.id == unaffected), isTrue);
    expect(pos.users.any((u) => u.id == 'u_barista_default'), isFalse);
    expect(pos.operationalExpenses.any((e) => e.id == expense.id), isFalse);
  });

  test('Offline status follows the service without a user-controlled network mode', () async {
    await db.resetForTesting();
    final pos = await open();
    expect(await pos.login('warloc.owner', 'sukses888'), isNull);
    expect(pos.isOnline, isFalse);
    expect(db.isOnline, isFalse);
  });
}
