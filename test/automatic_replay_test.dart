import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart' as cloud;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/cart_item.dart';
import 'package:kasir_super/models/product.dart';
import 'package:kasir_super/models/operational_expense.dart';
import 'package:kasir_super/models/transaction.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';
import 'package:kasir_super/services/firestore_sync_safety.dart';

Map<String, dynamic> clone(Map<String, dynamic> value) => Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

class MemoryCloud extends Fake implements cloud.FirebaseFirestore {
  final data = <String, Map<String, dynamic>>{};
  int reads = 0;
  int writes = 0;
  bool loseAcknowledgement = false;
  int networkEnables = 0;
  int networkDisables = 0;
  @override
  Future<void> enableNetwork() async { networkEnables++; }
  @override
  Future<void> disableNetwork() async { networkDisables++; }
  @override
  Future<void> waitForPendingWrites() async {}
  @override
  cloud.DocumentReference<Map<String, dynamic>> doc(String path) => MemoryRef(this, path);
  @override
  cloud.WriteBatch batch() => MemoryBatch(this);
  @override
  Future<T> runTransaction<T>(cloud.TransactionHandler<T> transactionHandler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) async {
    final transaction = MemoryTransaction(this);
    final result = await transactionHandler(transaction);
    for (final entry in transaction.changes.entries) { data[entry.key] = clone(entry.value); writes++; }
    if (loseAcknowledgement) { loseAcknowledgement = false; throw StateError('Commit accepted; acknowledgement lost'); }
    return result;
  }
}

// Test doubles only: no platform implementation is exported to the application.
// ignore: subtype_of_sealed_class
class MemoryRef extends Fake implements cloud.DocumentReference<Map<String, dynamic>> {
  final MemoryCloud store;
  @override
  final String path;
  MemoryRef(this.store, this.path);
  @override
  Future<cloud.DocumentSnapshot<Map<String, dynamic>>> get([cloud.GetOptions? options]) async {
    store.reads++;
    return MemorySnapshot(store.data[path]);
  }
  @override
  Future<void> delete() async { store.data.remove(path); store.writes++; }
}

// ignore: subtype_of_sealed_class
class MemorySnapshot extends Fake implements cloud.DocumentSnapshot<Map<String, dynamic>> {
  final Map<String, dynamic>? value;
  MemorySnapshot(this.value);
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic>? data() => value == null ? null : clone(value!);
}

class MemoryTransaction extends Fake implements cloud.Transaction {
  final MemoryCloud store;
  final changes = <String, Map<String, dynamic>>{};
  MemoryTransaction(this.store);
  @override
  Future<cloud.DocumentSnapshot<T>> get<T extends Object?>(cloud.DocumentReference<T> documentReference) async {
    expect(changes, isEmpty, reason: 'All Firestore transaction reads precede writes');
    store.reads++;
    return MemorySnapshot(store.data[documentReference.path]) as cloud.DocumentSnapshot<T>;
  }
  @override
  cloud.Transaction set<T>(cloud.DocumentReference<T> documentReference, T data, [cloud.SetOptions? options]) {
    changes[documentReference.path] = clone(data as Map<String, dynamic>);
    return this;
  }
}

class MemoryBatch extends Fake implements cloud.WriteBatch {
  final MemoryCloud store;
  final changes = <String, Map<String, dynamic>>{};
  MemoryBatch(this.store);
  @override
  void set<T>(cloud.DocumentReference<T> document, T data, [cloud.SetOptions? options]) {
    changes[document.path] = clone(data as Map<String, dynamic>);
  }
  @override
  Future<void> commit() async {
    for (final entry in changes.entries) { store.data[entry.key] = clone(entry.value); store.writes++; }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  final db = PosDatabaseService.instance;
  late MemoryCloud server;
  late Product product;

  Future<void> login() async {
    expect(await db.authenticate('warloc.owner', 'sukses888'), isNotNull);
  }
  Future<TransactionRecord> sell(String id) {
    product = db.getProducts().firstWhere((p) => p.id == product.id);
    return db.processTransaction(TransactionRecord(id: id, invoiceNumber: id,
      items: [CartItem(product: product, quantity: 1)], totalAmount: product.sellPrice,
      totalCost: product.baseCost, totalProfit: product.sellPrice - product.baseCost,
      paymentMethod: 'Cash', amountPaid: product.sellPrice, changeAmount: 0,
      cashierName: 'Owner Warloc', cashierId: 'u_owner_default', createdAt: DateTime.now()));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final safety = FirestoreSyncSafety.instance;
    safety.connectionBlocked = false;
    safety.pendingDocuments.clear();
    await db.resetForTesting();
    await login();
    server = MemoryCloud();
    for (final p in db.getProducts()) { server.data['products/${p.id}'] = p.toMap(); }
    for (final u in db.getUsers()) { server.data['users/${u.id}'] = u.toMap(); }
    server.data['meta/categories'] = {'list': db.getCategories()};
    product = db.getProducts().firstWhere((p) => !p.isEntertainment && p.stock > 4);
  });

  test('Offline sales survive restart, drain once and idle produces zero further reads/writes', () async {
    final originalStock = product.stock;
    await sell('sale_one'); await sell('sale_two'); await sell('sale_three');
    expect(server.writes, 0);
    await db.resetForTesting(); await login();
    expect(db.getTransactions().where((t) => !t.isSynced).length, 3);
    await db.connectForTesting(server);
    await Future.wait(List.generate(100, (_) => db.flushForTesting()));
    expect(server.data.keys.where((k) => k.startsWith('transactions/')).length, 3);
    expect(server.data['products/${product.id}']!['stock'], originalStock - 3);
    expect(db.getTransactions().every((t) => t.isSynced), isTrue);
    final counts = (server.reads, server.writes);
    for (var i = 0; i < 100; i++) { await db.flushForTesting(); }
    expect((server.reads, server.writes), counts);
  });

  test('Lost commit acknowledgement and restart do not deduct stock or write the sale twice', () async {
    final stock = product.stock;
    await sell('ambiguous_commit');
    await db.connectForTesting(server);
    server.loseAcknowledgement = true;
    await db.flushForTesting();
    expect(server.writes, 2);
    expect(server.data['products/${product.id}']!['stock'], stock - 1);
    await db.resetForTesting(); await login();
    await db.connectForTesting(server);
    await db.flushForTesting();
    expect(server.writes, 2);
    expect(server.data['products/${product.id}']!['stock'], stock - 1);
    expect(db.getTransactions().single.isSynced, isTrue);
  });

  test('Offline void before upload changes no server stock; uploaded void restores stock once', () async {
    final stock = product.stock;
    await sell('cancel_offline');
    expect(await db.voidTransaction('cancel_offline'), isTrue);
    await db.connectForTesting(server); await db.flushForTesting();
    expect(server.data['products/${product.id}']!['stock'], stock);
    await sell('cancel_uploaded'); await db.flushForTesting();
    expect(server.data['products/${product.id}']!['stock'], stock - 1);
    expect(await db.voidTransaction('cancel_uploaded'), isTrue);
    await db.flushForTesting();
    expect(server.data['products/${product.id}']!['stock'], stock);
    final count = server.writes;
    await db.flushForTesting();
    expect(server.writes, count);
  });

  test('Pending accounts and categories survive restart and acknowledge only real changes', () async {
    final user = db.getUsers().firstWhere((u) => u.id == 'u_barista_default');
    expect(await db.saveUser(user.copyWith(displayName: 'Kasir Baru')), isNull);
    expect(await db.addCategory('Menu Baru'), isNull);
    expect(db.pendingMetadataCount, 2);
    await db.resetForTesting(); await login();
    expect(db.getUsers().firstWhere((u) => u.id == user.id).displayName, 'Kasir Baru');
    expect(db.getCategories(), contains('Menu Baru'));
    await db.connectForTesting(server); await db.flushForTesting();
    expect(db.pendingMetadataCount, 0);
    expect(server.data['users/${user.id}']!['displayName'], 'Kasir Baru');
    expect(server.writes, 2);
    final reads = server.reads;
    await db.flushForTesting();
    expect(server.writes, 2); expect(server.reads, reads);
  });

  test('Stock is calculated against server changes, and conflicting oversold data stays pending', () async {
    final stock = product.stock;
    await sell('other_device_sale');
    server.data['products/${product.id}']!['stock'] = stock - 2;
    await db.connectForTesting(server); await db.flushForTesting();
    expect(server.data['products/${product.id}']!['stock'], stock - 3);
    expect(db.getProducts().firstWhere((p) => p.id == product.id).stock, stock - 3);
    await sell('oversold');
    server.data['products/${product.id}']!['stock'] = 0;
    await db.flushForTesting();
    expect(server.data.containsKey('transactions/oversold'), isFalse);
    expect(db.getTransactions().firstWhere((t) => t.id == 'oversold').isSynced, isFalse);
    expect(server.data['products/${product.id}']!['stock'], 0);
  });

  test('Quota cooldown cannot be bypassed; automatic recovery resumes when its persisted deadline expires', () async {
    await sell('quota_retained');
    await db.connectForTesting(server);
    final safety = FirestoreSyncSafety.instance;
    await safety.suspendForQuota(server);
    expect(server.networkDisables, 1);
    final prefs = await SecurePreferences.getInstance();
    for (var i = 0; i < 100; i++) { expect(await db.automaticAttemptForTesting(), isFalse); }
    expect(server.reads, 0); expect(server.writes, 0); expect(server.networkEnables, 0);
    await prefs.setInt('firestore_blocked_until', DateTime.now().subtract(const Duration(seconds: 1)).millisecondsSinceEpoch);
    expect(await db.automaticAttemptForTesting(), isTrue);
    expect(server.networkEnables, 1);
    expect(safety.connectionBlocked, isFalse);
    expect(server.data.containsKey('transactions/quota_retained'), isTrue);
    expect(db.getTransactions().single.isSynced, isTrue);
  });

  test('Menu and expense acknowledgement lost after commit causes no repeated document writes', () async {
    await db.updateProduct(product.copyWith(name: 'Nama baru'));
    await db.connectForTesting(server);
    server.loseAcknowledgement = true;
    await db.flushForTesting();
    expect(server.writes, 1);
    await db.resetForTesting(); await login(); await db.connectForTesting(server);
    await db.flushForTesting();
    expect(server.writes, 1);
    await db.addOperationalExpense(OperationalExpense(id: 'stable_expense', title: 'Listrik', category: 'Lainnya',
      amount: 1000, createdAt: DateTime.now(), recordedBy: 'Owner Warloc'));
    server.loseAcknowledgement = true;
    await db.flushForTesting();
    expect(server.writes, 2);
    await db.resetForTesting(); await login(); await db.connectForTesting(server);
    await db.flushForTesting();
    expect(server.writes, 2);
  });

  test('Concurrent timeout and quota errors never shorten the one-hour quota protection', () async {
    final safety = FirestoreSyncSafety.instance;
    final before = DateTime.now();
    await Future.wait([safety.suspendForQuota(server), safety.suspendUnconfirmed(server)]);
    final prefs = await SecurePreferences.getInstance();
    expect(prefs.getInt('firestore_blocked_until'), greaterThanOrEqualTo(before.add(const Duration(hours: 1)).millisecondsSinceEpoch));
    expect(safety.notice, contains('Kuota Firebase'));
    expect(safety.connectionBlocked, isTrue);
  });
}
