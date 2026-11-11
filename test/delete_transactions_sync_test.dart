import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/cart_item.dart';
import 'package:kasir_super/models/product.dart';
import 'package:kasir_super/models/transaction.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';
import 'package:kasir_super/services/firestore_sync_safety.dart';
import 'automatic_replay_test.dart' show MemoryCloud;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  final db = PosDatabaseService.instance;
  late MemoryCloud server;
  late Product product;

  Future<TransactionRecord> sell(String id) =>
      db.processTransaction(TransactionRecord(
          id: id,
          invoiceNumber: id,
          items: [CartItem(product: product)],
          totalAmount: product.sellPrice,
          totalCost: product.baseCost,
          totalProfit: product.sellPrice - product.baseCost,
          paymentMethod: 'Cash',
          amountPaid: product.sellPrice,
          changeAmount: 0,
          cashierName: 'Owner Warloc',
          cashierId: 'u_owner_default',
          createdAt: DateTime.now()));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FirestoreSyncSafety.instance.connectionBlocked = false;
    FirestoreSyncSafety.instance.pendingDocuments.clear();
    await db.resetForTesting();
    expect(await db.authenticate('warloc.owner', 'sukses888'), isNotNull);
    server = MemoryCloud();
    for (final p in db.getProducts()) {
      server.data['products/${p.id}'] = p.toMap();
    }
    for (final u in db.getUsers()) {
      server.data['users/${u.id}'] = u.toMap();
    }
    server.data['meta/categories'] = {'list': db.getCategories()};
    product = db.getProducts().firstWhere((p) => p.id == 'w_1');
  });

  test(
      'Delete before initial upload writes only an audit tombstone and never changes server stock',
      () async {
    final tx = await sell('never_uploaded');
    await db.deleteTransaction(
        transactionId: tx.id,
        expectedRevision: tx.revision,
        reason: 'Input ganda offline');
    await db.resetForTesting();
    await db.authenticate('warloc.owner', 'sukses888');
    await db.connectForTesting(server);
    await db.flushForTesting();
    expect(server.data['transactions/${tx.id}']!['isDeleted'], isTrue);
    expect(server.data['products/${product.id}']!['stock'], product.stock);
    expect(db.getDeletedTransactions().single.isSynced, isTrue);
    expect(db.getTransactions(), isEmpty);
    final counts = (server.reads, server.writes);
    for (var i = 0; i < 50; i++) {
      await db.flushForTesting();
    }
    expect((server.reads, server.writes), counts);
  });

  test(
      'Uploaded sale deletion restores server stock once; lost acknowledgement never repeats the write',
      () async {
    final tx = await sell('uploaded_sale');
    await db.connectForTesting(server);
    await db.flushForTesting();
    expect(server.data['products/${product.id}']!['stock'], product.stock - 1);
    final writesBefore = server.writes;
    await db.deleteTransaction(
        transactionId: tx.id, expectedRevision: 0, reason: 'Salah transaksi');
    server.loseAcknowledgement = true;
    await db.flushForTesting();
    expect(server.data['products/${product.id}']!['stock'], product.stock);
    expect(server.writes - writesBefore, 2);
    expect(db.pendingDeletedTransactionCount, 1);
    await db.resetForTesting();
    await db.authenticate('warloc.owner', 'sukses888');
    await db.connectForTesting(server);
    await db.flushForTesting();
    expect(server.writes - writesBefore, 2);
    expect(db.pendingDeletedTransactionCount, 0);
    expect(db.getProducts().firstWhere((p) => p.id == product.id).stock,
        product.stock);
  });

  test(
      'Deleting an uploaded void writes audit only and does not add stock again',
      () async {
    final tx = await sell('voided_sale');
    await db.connectForTesting(server);
    await db.flushForTesting();
    await db.voidTransaction(tx.id);
    await db.flushForTesting();
    final writesBefore = server.writes;
    await db.deleteTransaction(
        transactionId: tx.id,
        expectedRevision: 0,
        reason: 'Rapikan transaksi batal');
    await db.flushForTesting();
    expect(server.writes - writesBefore, 1);
    expect(server.data['products/${product.id}']!['stock'], product.stock);
    expect(db.pendingDeletedTransactionCount, 0);
  });

  test(
      'Concurrent correction conflicts retain deletion pending and never overwrite server sale or stock',
      () async {
    final tx = await sell('changed_sale');
    await db.connectForTesting(server);
    await db.flushForTesting();
    final changed = tx.copyWith(
        revision: 1, customerName: 'Diubah perangkat lain', isSynced: true);
    server.data['transactions/${tx.id}'] = changed.toMap();
    final writesBefore = server.writes;
    await db.deleteTransaction(
        transactionId: tx.id, expectedRevision: 0, reason: 'Salah input');
    await db.flushForTesting();
    expect(server.writes, writesBefore);
    expect(db.pendingDeletedTransactionCount, 1);
    expect(server.data['transactions/${tx.id}']!['customerName'],
        'Diubah perangkat lain');
    expect(server.data['products/${product.id}']!['stock'], product.stock - 1);
  });

  test(
      'A second device deletion is terminal even against a stale active record with a higher revision',
      () async {
    final tx = await sell('already_deleted');
    final deleted = await db.deleteTransaction(
        transactionId: tx.id, expectedRevision: 0, reason: 'Input ganda');
    final plan = PosDatabaseService.planCheckoutSync(
        local: tx.copyWith(revision: 99),
        remote: deleted.copyWith(isSynced: true),
        localProducts: {product.id: product},
        remoteProducts: {product.id: product});
    expect(plan.sale.isDeleted, isTrue);
    expect(plan.writeSale, isFalse);
    expect(plan.products, isEmpty);
  });
}
