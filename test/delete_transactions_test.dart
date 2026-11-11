import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/transaction.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/dialogs/delete_transaction_dialog.dart';
import 'package:kasir_super/screens/dialogs/transaction_history_dialog.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';
import 'package:kasir_super/widgets/access_denied.dart';
import 'package:kasir_super/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  final db = PosDatabaseService.instance;
  setUpAll(() => initializeDateFormatting('id_ID', null));
  final providers = <PosProvider>[];
  tearDown(() {
    for (final pos in providers) {
      pos.dispose();
    }
    providers.clear();
  });

  Future<void> login(PosProvider pos, String account) async {
    expect(
        await pos.login(
            'warloc.$account',
            {
              'owner': 'sukses888',
              'admin': 'sukses123',
              'kasir': 'sukses000'
            }[account]!),
        isNull);
  }

  Future<PosProvider> fresh([String account = 'owner']) async {
    SharedPreferences.setMockInitialValues({});
    await db.resetForTesting();
    final pos = PosProvider();
    providers.add(pos);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    await login(pos, account);
    return pos;
  }

  Future<TransactionRecord> sale(PosProvider pos) async {
    pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES');
    return pos.processCheckout(
        paymentMethod: 'Cash', amountPaid: 50000, cashierName: '');
  }

  Widget app(PosProvider pos, Widget child, {double scale = 1}) =>
      ChangeNotifierProvider.value(
          value: pos,
          child: MaterialApp(
              theme: AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: child));

  for (final account in ['owner', 'admin']) {
    test(
        '$account deletes another cashier sale, restores stock once and retains audit after restart',
        () async {
      final pos = await fresh('kasir');
      final original = pos.products.firstWhere((p) => p.id == 'w_1').stock;
      final tx = await sale(pos);
      await pos.logout();
      await login(pos, account);
      expect(pos.todayStoreSales.transactionCount, 1);
      final first = pos.deleteTransaction(
          transactionId: tx.id,
          expectedRevision: tx.revision,
          reason: 'Input transaksi ganda');
      await expectLater(
          pos.deleteTransaction(
              transactionId: tx.id,
              expectedRevision: tx.revision,
              reason: 'Klik ganda'),
          throwsStateError);
      final deleted = await first;
      expect(deleted.isDeleted, isTrue);
      expect(deleted.isVoided, isTrue);
      expect(deleted.deletedById, pos.currentUser!.id);
      expect(deleted.deletionReason, 'Input transaksi ganda');
      expect(deleted.deletedAt, isNotNull);
      expect(deleted.revision, tx.revision + 1);
      expect(pos.transactions, isEmpty);
      expect(pos.todayStoreSales, (totalAmount: 0.0, transactionCount: 0));
      expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, original);
      expect(pos.deletedTransactions.single.id, tx.id);
      expect(db.pendingDeletedTransactionCount, 1);
      await expectLater(
          db.deleteTransaction(
              transactionId: tx.id,
              expectedRevision: deleted.revision,
              reason: 'Ulang hapus'),
          throwsStateError);
      await expectLater(
          pos.correctTransaction(
              transactionId: tx.id,
              expectedRevision: deleted.revision,
              items: tx.items,
              amountPaid: 50000,
              reason: 'Tidak boleh hidup lagi'),
          throwsStateError);
      await db.resetForTesting();
      expect(
          await db.authenticate('warloc.$account',
              account == 'owner' ? 'sukses888' : 'sukses123'),
          isNotNull);
      expect(db.getTransactions(), isEmpty);
      expect(db.getDeletedTransactions().single.deletionReason,
          'Input transaksi ganda');
      expect(db.getProducts().firstWhere((p) => p.id == 'w_1').stock, original);
    });
  }

  test(
      'Barista is denied by provider and service; reason and revision are enforced',
      () async {
    final pos = await fresh('kasir');
    final tx = await sale(pos);
    await expectLater(
        pos.deleteTransaction(
            transactionId: tx.id, expectedRevision: 0, reason: 'Salah input'),
        throwsStateError);
    await expectLater(
        db.deleteTransaction(
            transactionId: tx.id, expectedRevision: 0, reason: 'Salah input'),
        throwsStateError);
    expect(db.getDeletedTransactions, throwsStateError);
    expect(pos.deletedTransactions, isEmpty);
    await pos.logout();
    await login(pos, 'admin');
    await expectLater(
        pos.deleteTransaction(
            transactionId: tx.id, expectedRevision: 99, reason: 'Salah input'),
        throwsStateError);
    await expectLater(
        pos.deleteTransaction(
            transactionId: tx.id, expectedRevision: 0, reason: ' '),
        throwsArgumentError);
    expect(pos.transactions.single.id, tx.id);
    expect(pos.todayStoreSales.transactionCount, 1);
  });

  test(
      'Deleting an already voided transaction does not restore stock a second time',
      () async {
    final pos = await fresh();
    final original = pos.products.firstWhere((p) => p.id == 'w_1').stock;
    final tx = await sale(pos);
    expect(await pos.voidTransaction(tx.id), isTrue);
    await pos.deleteTransaction(
        transactionId: tx.id,
        expectedRevision: tx.revision,
        reason: 'Bersihkan transaksi batal');
    expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, original);
    expect(pos.transactions, isEmpty);
  });

  test(
      'Deletion restores corrected quantities and retains the correction audit',
      () async {
    final pos = await fresh();
    final original = pos.products.firstWhere((p) => p.id == 'w_1').stock;
    final tx = await sale(pos);
    final corrected = await pos.correctTransaction(
        transactionId: tx.id,
        expectedRevision: 0,
        items: [tx.items.single.copyWith(quantity: 2)],
        amountPaid: 50000,
        reason: 'Jumlah kurang');
    expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, original - 2);
    await pos.deleteTransaction(
        transactionId: tx.id,
        expectedRevision: corrected.revision,
        reason: 'Seluruh transaksi ganda');
    expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, original);
    expect(pos.deletedTransactions.single.corrections.length, 1);
  });

  test('Missing menu or overflowing stock rejects deletion without losing sale',
      () async {
    final pos = await fresh();
    final tx = await sale(pos);
    final product = pos.products.firstWhere((p) => p.id == 'w_1');
    await pos.updateExistingProduct(product.copyWith(stock: 99999));
    await expectLater(
        pos.deleteTransaction(
            transactionId: tx.id, expectedRevision: 0, reason: 'Periksa stok'),
        throwsStateError);
    expect(pos.transactions.single.id, tx.id);
    expect(pos.deletedTransactions, isEmpty);
    await pos.deleteExistingProduct(product.id);
    await expectLater(
        pos.deleteTransaction(
            transactionId: tx.id,
            expectedRevision: 0,
            reason: 'Menu sudah hilang'),
        throwsStateError);
    expect(pos.transactions.single.id, tx.id);
  });

  test('Different drink variants restore their combined quantity exactly once',
      () async {
    final pos = await fresh();
    final product = pos.products.firstWhere((p) => p.id == 'w_1');
    pos.addToCart(product, variant: 'ES');
    pos.addToCart(product, variant: 'Panas');
    final tx = await pos.processCheckout(
        paymentMethod: 'Cash', amountPaid: 100000, cashierName: '');
    expect(tx.items.length, 2);
    expect(pos.products.firstWhere((p) => p.id == product.id).stock,
        product.stock - 2);
    await pos.deleteTransaction(
        transactionId: tx.id,
        expectedRevision: 0,
        reason: 'Input ganda varian');
    expect(pos.products.firstWhere((p) => p.id == product.id).stock,
        product.stock);
  });

  test('Deleting a rental transaction preserves unlimited service capacity',
      () async {
    final pos = await fresh();
    final product = pos.products
        .firstWhere((p) => p.isEntertainment && p.minStockThreshold == 0);
    pos.addToCart(product);
    final tx = await pos.processCheckout(
        paymentMethod: 'Cash', amountPaid: 100000, cashierName: '');
    await pos.deleteTransaction(
        transactionId: tx.id,
        expectedRevision: 0,
        reason: 'Salah input rental');
    expect(pos.products.firstWhere((p) => p.id == product.id).stock,
        product.stock);
    expect(pos.todayStoreSales.transactionCount, 0);
  });

  test(
      'Deletion round-trips audit metadata and remains terminal against stale snapshots',
      () async {
    final pos = await fresh();
    final tx = await sale(pos);
    final deleted = await pos.deleteTransaction(
        transactionId: tx.id,
        expectedRevision: 0,
        reason: 'Duplikat transaksi');
    expect(TransactionRecord.fromMap(deleted.toMap()).toMap(), deleted.toMap());
    final merged = PosDatabaseService.mergeSalesSnapshots(
        recent: [tx.copyWith(revision: 999)],
        daily: [tx],
        local: [deleted],
        retainSince: DateTime.now().add(const Duration(days: 30)));
    expect(merged.single.isDeleted, isTrue);
    final acknowledged = deleted.copyWith(isSynced: true);
    final again = PosDatabaseService.mergeSalesSnapshots(
        recent: [acknowledged],
        daily: [tx],
        local: [deleted],
        retainSince: DateTime.now());
    expect(again.single.isDeleted, isTrue);
    expect(again.single.isSynced, isTrue);
  });

  for (final account in ['owner', 'admin', 'kasir']) {
    testWidgets(
        '$account history exposes deletion only when allowed; cancel preserves sale',
        (tester) async {
      final pos = (await tester.runAsync(() => fresh(account)))!;
      final tx = (await tester.runAsync(() => sale(pos)))!;
      await tester
          .pumpWidget(app(pos, const Scaffold(body: TransactionHistoryView())));
      await tester.pumpAndSettle();
      final button = find.byKey(ValueKey('delete-transaction-${tx.id}'));
      if (account == 'kasir') {
        expect(button, findsNothing);
        expect(find.text('Terhapus'), findsNothing);
        await tester
            .pumpWidget(app(pos, DeleteTransactionDialog(transaction: tx)));
        await tester.pumpAndSettle();
        expect(find.byType(AccessDenied), findsOneWidget);
        return;
      }
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(pos.transactions.single.id, tx.id);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('confirm-delete-transaction')));
      await tester.pumpAndSettle();
      expect(find.text('Isi alasan penghapusan, minimal 3 karakter.'),
          findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('delete-transaction-reason')),
          'Transaksi terinput ganda');
      await tester.runAsync(() async {
        await tester
            .tap(find.byKey(const ValueKey('confirm-delete-transaction')));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(pos.transactions, isEmpty);
      await tester.ensureVisible(find.text('Terhapus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terhapus'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Transaksi terinput ganda'), findsOneWidget);
      expect(find.text('Dihapus'), findsOneWidget);
    });
  }
}
