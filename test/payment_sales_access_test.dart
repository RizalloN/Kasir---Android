import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/operational_expense.dart';
import 'package:kasir_super/models/transaction.dart';
import 'package:kasir_super/models/user_role.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/barista/cart_bottom_sheet.dart';
import 'package:kasir_super/screens/dialogs/today_sales_dialog.dart';
import 'package:kasir_super/screens/dialogs/transaction_history_dialog.dart';
import 'package:kasir_super/screens/main_wrapper_screen.dart';
import 'package:kasir_super/screens/owner/reports_screen.dart';
import 'package:kasir_super/services/app_release_service.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';
import 'package:kasir_super/theme/app_theme.dart';
import 'package:kasir_super/utils/currency_formatter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  final db = PosDatabaseService.instance;
  final providers = <PosProvider>[];
  setUpAll(() => initializeDateFormatting('id_ID', null));
  tearDown(() {
    for (final pos in providers) {
      pos.dispose();
    }
    providers.clear();
  });

  Future<PosProvider> reopen() async {
    final pos = PosProvider();
    providers.add(pos);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    return pos;
  }

  Future<void> login(PosProvider pos, String role) async {
    expect(await pos.login('warloc.$role', {
      'kasir': 'sukses000', 'admin': 'sukses123', 'owner': 'sukses888',
    }[role]!), isNull);
  }

  Future<PosProvider> fresh([String role = 'owner']) async {
    SharedPreferences.setMockInitialValues({});
    await db.resetForTesting();
    final pos = await reopen();
    await login(pos, role);
    return pos;
  }

  Future<TransactionRecord> sale(PosProvider pos) async {
    expect(pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES'), isTrue);
    return pos.processCheckout(paymentMethod: 'Cash', amountPaid: 50000, cashierName: '');
  }

  Future<PosProvider> restoreSales(PosProvider pos, List<TransactionRecord> sales) async {
    pos.dispose();
    providers.remove(pos);
    final prefs = await SecurePreferences.getInstance();
    final ledger = jsonDecode(prefs.getString('cached_ledger_v1')!) as Map<String, dynamic>;
    ledger['transactions'] = sales.map((tx) => tx.toMap()).toList();
    await prefs.setString('cached_ledger_v1', jsonEncode(ledger));
    await db.resetForTesting();
    return reopen();
  }

  Widget wrap(Widget child, PosProvider pos) => ChangeNotifierProvider.value(
    value: pos, child: MaterialApp(home: Scaffold(body: child)));

  test('Barista cannot correct transactions, including their own recent sale', () async {
    final pos = await fresh('kasir');
    final tx = await sale(pos);
    final id = pos.currentUser!.id;
    final deadline = tx.createdAt.add(const Duration(hours: 24));
    expect(tx.canBeCorrectedBy(role: UserRole.barista, userId: id, now: tx.createdAt), isFalse);
    expect(tx.canBeCorrectedBy(role: UserRole.barista, userId: id, now: deadline), isFalse);
    expect(tx.canBeCorrectedBy(role: UserRole.barista, userId: id,
        now: deadline.add(const Duration(microseconds: 1))), isFalse);
    expect(tx.copyWith(revision: 9).canBeCorrectedBy(role: UserRole.barista, userId: id,
        now: deadline.add(const Duration(seconds: 1))), isFalse);
    expect(tx.canBeCorrectedBy(role: UserRole.barista, userId: 'other', now: deadline), isFalse);
    expect(tx.canBeCorrectedBy(role: UserRole.barista, userId: id,
        now: tx.createdAt.subtract(const Duration(seconds: 1))), isFalse);
    expect(tx.copyWith(isVoided: true).canBeCorrectedBy(role: UserRole.owner, userId: id), isFalse);
  });

  test('Barista edits are rejected by provider and database without changing stock or audit', () async {
    var pos = await fresh('kasir');
    final tx = await sale(pos);
    final expired = tx;
    pos = await restoreSales(pos, [expired]);
    final stock = pos.products.firstWhere((p) => p.id == 'w_1').stock;
    expect(pos.canCorrectTransaction(expired), isFalse);
    Future<TransactionRecord> edit(bool direct) => direct
        ? db.correctTransaction(transactionId: tx.id, expectedRevision: 0,
            items: tx.items, amountPaid: 50000, reason: 'Salah input')
        : pos.correctTransaction(transactionId: tx.id, expectedRevision: 0,
            items: tx.items, amountPaid: 50000, reason: 'Salah input');
    await expectLater(edit(false), throwsStateError);
    await expectLater(edit(true), throwsStateError);
    expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, stock);
    expect(db.getTransactions().single.revision, 0);
    expect(db.getTransactions().single.corrections, isEmpty);
    await login(pos, 'owner');
    final corrected = await edit(false);
    expect(corrected.revision, 1);
    expect(corrected.createdAt, expired.createdAt);
  });

  test('Store daily total includes every cashier, discounts and corrections, excludes unpaid and voids', () async {
    var pos = await fresh();
    final ownerSale = await sale(pos);
    await login(pos, 'admin');
    final adminSale = await sale(pos);
    await login(pos, 'kasir');
    final cashierSale = await sale(pos);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    pos = await restoreSales(pos, [
      ownerSale, adminSale, cashierSale,
      ownerSale.copyWith(id: 'yesterday', createdAt: start.subtract(const Duration(microseconds: 1))),
      ownerSale.copyWith(id: 'tomorrow', createdAt: DateTime(now.year, now.month, now.day + 1)),
      ownerSale.copyWith(id: 'voided', isVoided: true),
    ]);
    expect(pos.transactions.length, 1);
    expect(db.getTransactions().length, 1);
    expect(pos.todayStoreSales, (totalAmount: 69000.0, transactionCount: 3));
    expect(pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES'), isTrue);
    pos.setCustomerName('Meja belum bayar');
    await pos.saveCurrentBill();
    expect(pos.todayStoreSales.totalAmount, 69000);
    pos.resumeOpenBill(pos.openBills.single.id);
    pos.setDiscountAmount(3000);
    final settled = await pos.processCheckout(paymentMethod: 'Cash', amountPaid: 20000, cashierName: '');
    expect(pos.openBills, isEmpty);
    expect(pos.todayStoreSales, (totalAmount: 89000.0, transactionCount: 4));
    await login(pos, 'owner');
    await pos.correctTransaction(transactionId: settled.id, expectedRevision: 0,
        items: [settled.items.single.copyWith(quantity: 2)], amountPaid: 50000, reason: 'Kurang item');
    expect(pos.todayStoreSales, (totalAmount: 112000.0, transactionCount: 4));
    await login(pos, 'admin');
    expect(pos.transactions.length, 7);
    expect(pos.todayRevenue, 112000);
    expect(pos.todayStoreSales.totalAmount, pos.todayRevenue);
    await login(pos, 'owner');
    expect(pos.todayRevenue, 112000);
    await pos.voidTransaction(settled.id);
    expect(pos.todayStoreSales, (totalAmount: 69000.0, transactionCount: 3));
    await pos.logout();
    expect(pos.todayStoreSales, (totalAmount: 0.0, transactionCount: 0));
    expect(db.getTodaySalesSummary, throwsStateError);
  });

  test('Admin views all sales while expense writes, voids and user management remain owner-only', () async {
    final pos = await fresh();
    final tx = await sale(pos);
    await login(pos, 'admin');
    expect(pos.transactions.single.id, tx.id);
    expect(pos.currentRole.canViewFinancialReports, isTrue);
    expect(pos.currentRole.canManageUsers, isFalse);
    expect(pos.canCorrectTransaction(tx), isTrue);
    final expense = OperationalExpense(id: 'expense', title: 'Listrik', category: 'Lainnya',
        amount: 1000, createdAt: DateTime.now(), recordedBy: pos.currentUser!.displayName);
    await expectLater(pos.addOperationalExpense(title: 'Listrik', category: 'Lainnya', amount: 1000), throwsStateError);
    await expectLater(pos.addOperationalExpenses([expense]), throwsStateError);
    await expectLater(pos.updateOperationalExpense(expense), throwsStateError);
    expect(await pos.deleteOperationalExpense('expense'), isFalse);
    await expectLater(db.addOperationalExpense(expense), throwsStateError);
    await expectLater(db.addOperationalExpenses([expense]), throwsStateError);
    await expectLater(db.updateOperationalExpense(expense), throwsStateError);
    await expectLater(db.deleteOperationalExpense('expense'), throwsStateError);
    expect(await pos.voidTransaction(tx.id), isFalse);
  });

  test('Complete daily window is not truncated by the latest 100, and stale snapshots never undo corrections', () async {
    var pos = await fresh();
    final base = await sale(pos);
    final all = List.generate(151, (i) => base.copyWith(id: 'sale-$i', isSynced: true));
    final corrected = all.first.copyWith(revision: 1, totalAmount: 20000);
    final voided = all[1].copyWith(isVoided: true);
    final pending = base.copyWith(id: 'offline', isSynced: false);
    final merged = PosDatabaseService.mergeSalesSnapshots(
      recent: all.skip(51).toList(), daily: all,
      local: [corrected, voided, pending], retainSince: DateTime.now().subtract(const Duration(days: 1)));
    expect(merged.length, 152);
    expect(merged.firstWhere((tx) => tx.id == corrected.id).revision, 1);
    expect(merged.firstWhere((tx) => tx.id == voided.id).isVoided, isTrue);
    pos = await restoreSales(pos, merged);
    expect(pos.todayStoreSales.transactionCount, 151);
    expect(pos.todayStoreSales.totalAmount, 150 * 23000 + 20000);
    final again = PosDatabaseService.mergeSalesSnapshots(recent: all.skip(51).toList(),
        daily: all, local: merged, retainSince: DateTime.now().subtract(const Duration(days: 1)));
    expect(again.firstWhere((tx) => tx.id == corrected.id).totalAmount, 20000);
    expect(again.firstWhere((tx) => tx.id == voided.id).isVoided, isTrue);
  });

  for (final type in ['Dine-In', 'Takeaway']) {
    testWidgets('Unpaid $type requires a customer and settles only once', (tester) async {
      final pos = (await tester.runAsync(() => fresh('kasir')))!;
      pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES');
      pos.setOrderType(type);
      final stock = pos.products.firstWhere((p) => p.id == 'w_1').stock;
      await tester.pumpWidget(wrap(const CartBottomSheet(isTabletSidebar: true), pos));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Unpaid / Open Bill'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpaid / Open Bill'));
      await tester.pumpAndSettle();
      expect(find.text('Uang Pas'), findsNothing);
      expect(find.text('Bayar Sekarang'), findsNothing);
      await tester.ensureVisible(find.text('Simpan Open Bill'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Simpan Open Bill'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(pos.openBills, isEmpty);
      expect(pos.cart, isNotEmpty);
      await tester.ensureVisible(find.widgetWithText(TextField, 'Nama / Meja'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Nama / Meja'), 'Pelanggan $type');
      await tester.ensureVisible(find.text('Simpan Open Bill'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Simpan Open Bill'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(pos.openBills.single.orderType, type);
      expect(pos.transactions, isEmpty);
      expect(pos.todayStoreSales.totalAmount, 0);
      expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, stock);
      final bill = pos.openBills.single;
      await tester.runAsync(() async {
        pos.resumeOpenBill(bill.id);
        await pos.processCheckout(paymentMethod: 'Cash', amountPaid: 23000, cashierName: '');
        await expectLater(pos.processCheckout(paymentMethod: 'Cash', amountPaid: 23000,
            cashierName: ''), throwsStateError);
      });
      await tester.pumpAndSettle();
      expect(pos.transactions.single.orderType, type);
      expect(pos.transactions.single.openBillId, bill.id);
      expect(pos.openBills, isEmpty);
      expect(pos.todayStoreSales, (totalAmount: 23000.0, transactionCount: 1));
      expect(pos.products.firstWhere((p) => p.id == 'w_1').stock, stock - 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Paid $type checks out once through the cart', (tester) async {
      final pos = (await tester.runAsync(() => fresh('kasir')))!;
      pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES');
      pos.setOrderType(type);
      await tester.pumpWidget(wrap(const CartBottomSheet(isTabletSidebar: true), pos));
      await tester.pumpAndSettle();
      expect(find.text('Simpan Pesanan untuk Diperbaiki'), findsNothing);
      await tester.ensureVisible(find.text('Paid / Lunas'));
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Paid / Lunas')).selected, isTrue);
      await tester.ensureVisible(find.text('Bayar Sekarang'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Bayar Sekarang'));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(pos.transactions.single.orderType, type);
      expect(pos.todayStoreSales.totalAmount, 23000);
      expect(pos.openBills, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Payment status labels and checkmarks stay readable throughout both selection transitions', (tester) async {
    final pos = (await tester.runAsync(() => fresh('kasir')))!;
    pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES');
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: pos,
      child: MaterialApp(theme: AppTheme.lightTheme,
        home: const Scaffold(body: CartBottomSheet(isTabletSidebar: true))),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Paid / Lunas'));
    await tester.pumpAndSettle();

    void checkChip(String label) {
      final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
      final background = chip.color!.resolve({if (chip.selected) WidgetState.selected})!;
      final foreground = chip.labelStyle!.color!;
      final a = background.computeLuminance();
      final b = foreground.computeLuminance();
      final contrast = (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: '$label must remain readable during animation');
      expect(chip.checkmarkColor, foreground);
    }

    void checkBoth() { checkChip('Paid / Lunas'); checkChip('Unpaid / Open Bill'); }
    checkBoth();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Paid / Lunas')).labelStyle!.color, Colors.white);
    for (final target in ['Unpaid / Open Bill', 'Paid / Lunas']) {
      await tester.tap(find.text(target));
      await tester.pump();
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        checkBoth();
      }
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, target)).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, target)).labelStyle!.color, Colors.white);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Barista daily summary displays store sales at narrow width and large text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pos = (await tester.runAsync(fresh))!;
    await tester.runAsync(() => sale(pos));
    await tester.runAsync(() => login(pos, 'kasir'));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: pos, child: MaterialApp(
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.5)), child: child!),
      home: const Scaffold(body: TodaySalesDialog()))));
    await tester.pumpAndSettle();
    expect(pos.transactions, isEmpty);
    expect(find.text(CurrencyFormatter.format(23000)), findsOneWidget);
    expect(find.text('1 transaksi lunas seluruh kasir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin can open owner sales reports from the dashboard and return to cashier', (tester) async {
    final pos = (await tester.runAsync(() => fresh('admin')))!;
    final release = AppReleaseService();
    addTearDown(release.dispose);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: pos), ChangeNotifierProvider.value(value: release),
    ], child: const MaterialApp(home: MainWrapperScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dashboard Penjualan'));
    await tester.pumpAndSettle();
    expect(find.text('Ringkasan'), findsOneWidget);
    expect(find.text('Staff'), findsNothing);
    expect(find.widgetWithText(Tab, 'Operasional'), findsNothing);
    await tester.tap(find.text('Histori'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportsScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Buka Kasir'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Dashboard Penjualan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Expired history entry has no edit action', (tester) async {
    var pos = (await tester.runAsync(() => fresh('kasir')))!;
    final tx = (await tester.runAsync(() => sale(pos)))!;
    pos = (await tester.runAsync(() => restoreSales(pos, [tx.copyWith(
        createdAt: DateTime.now().subtract(const Duration(hours: 25)))])))!;
    await tester.pumpWidget(wrap(const TransactionHistoryDialog(), pos));
    await tester.pumpAndSettle();
    expect(find.textContaining('Edit tidak tersedia'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Koreksi'), findsNothing);
    await tester.ensureVisible(find.text('Lihat detail'));
    await tester.tap(find.text('Lihat detail'));
    await tester.pumpAndSettle();
    expect(find.text('Detail Transaksi'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Koreksi Transaksi'), findsNothing);
  });
}
