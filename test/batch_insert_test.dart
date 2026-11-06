import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/operational_expense.dart';
import 'package:kasir_super/models/product.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/dialogs/batch_insert_dialog.dart';
import 'package:kasir_super/screens/owner/operational_expenses_screen.dart';
import 'package:kasir_super/screens/owner/stock_management_screen.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';
import 'package:kasir_super/theme/app_theme.dart';
import 'package:kasir_super/widgets/access_denied.dart';

class ControlledBatchProvider extends PosProvider {
  bool failNext = false;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<void> addNewProducts(List<Product> products) async {
    calls++;
    if (failNext) {
      failNext = false;
      throw StateError('Storage unavailable');
    }
    await gate?.future;
    await super.addNewProducts(products);
  }
}

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

  Future<PosProvider> create(String? role,
      {bool fresh = true, PosProvider? custom}) async {
    if (fresh) {
      SharedPreferences.setMockInitialValues({});
      await db.resetForTesting();
    }
    final pos = custom ?? PosProvider();
    providers.add(pos);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    if (role != null) {
      expect(
          await pos.login(
              'warloc.$role',
              {
                'owner': 'sukses888',
                'admin': 'sukses123',
                'kasir': 'sukses000',
              }[role]!),
          isNull);
    }
    return pos;
  }

  Product product(String id) => Product(
      id: id,
      name: 'Kopi $id',
      category: 'Coffee',
      sellPrice: 22000,
      baseCost: 9000,
      stock: 30,
      barcode: 'BC_$id');
  OperationalExpense expense(String id, {String recordedBy = ''}) =>
      OperationalExpense(
          id: id,
          title: 'Sachet $id',
          category: 'Lainnya',
          amount: 15000,
          createdAt: DateTime(2026, 11, 5, 9),
          recordedBy: recordedBy,
          notes: '  stok toko  ');

  test(
      'Menu and expense batches survive restart with exact values and unique IDs',
      () async {
    final pos = await create('owner');
    final initial = pos.products.map((p) => p.toMap()).toList();
    await pos.addNewProducts([
      product('batch_a'),
      product('batch_b').copyWith(isAvailable: false, stock: 0)
    ]);
    await pos.addOperationalExpenses([
      expense('exp_a'),
      expense('exp_b')
          .copyWith(title: '', category: 'Biaya Listrik', amount: 123456.75),
    ]);
    final actorName = pos.currentUser!.displayName;
    providers.remove(pos);
    pos.dispose();
    await db.resetForTesting();
    final restored = await create(null, fresh: false);
    final added =
        restored.products.where((p) => p.id.startsWith('batch_')).toList();
    expect(added.length, 2);
    expect(added.first.sellPrice, 22000);
    expect(added.first.baseCost, 9000);
    expect(added.first.barcode, 'BC_batch_a');
    expect(added.first.minStockThreshold, 5);
    expect(added.last.stock, 0);
    expect(added.last.isAvailable, isFalse);
    expect(added.every((p) => !p.isSynced), isTrue);
    expect(
        restored.products.take(initial.length).map((p) => p.toMap()).toList(),
        initial);
    expect(restored.operationalExpenses.map((e) => e.id).toSet(),
        {'exp_a', 'exp_b'});
    expect(
        restored.operationalExpenses
            .every((e) => e.recordedBy == actorName && !e.isSynced),
        isTrue);
    final electricity =
        restored.operationalExpenses.firstWhere((e) => e.id == 'exp_b');
    expect(electricity.amount, 123456.75);
    expect(electricity.title, 'Biaya Listrik');
    expect(electricity.createdAt, DateTime(2026, 11, 5, 9));
    expect(electricity.notes, 'stok toko');
    expect(restored.transactions, isEmpty);
    expect(restored.openBills, isEmpty);
  });

  test(
      'Invalid later rows and duplicate IDs cannot partially insert or overwrite data',
      () async {
    final pos = await create('owner');
    final prefs = await SharedPreferences.getInstance();
    final ledger = prefs.getString('cached_ledger_v1');
    final initial = pos.products.length;
    for (final batch in [
      [product('good'), product('bad').copyWith(sellPrice: double.nan)],
      [product('good'), product('bad').copyWith(stock: -1)],
      [product('good'), product('bad').copyWith(sellPrice: 0)],
      [product('duplicate'), product('duplicate')],
      [product('good'), pos.products.first],
    ]) {
      await expectLater(pos.addNewProducts(batch),
          throwsA(anyOf(isA<ArgumentError>(), isA<StateError>())));
      expect(db.getProducts().length, initial);
      expect(prefs.getString('cached_ledger_v1'), ledger);
    }
    final recordedBy = pos.currentUser!.displayName;
    await expectLater(
        db.addOperationalExpenses([
          expense('good', recordedBy: recordedBy),
          expense('bad', recordedBy: recordedBy)
              .copyWith(amount: double.infinity),
        ]),
        throwsArgumentError);
    expect(db.getOperationalExpenses(), isEmpty);
    await pos.addOperationalExpenses([expense('exists')]);
    await expectLater(
        pos.addOperationalExpenses([expense('good'), expense('exists')]),
        throwsStateError);
    expect(db.getOperationalExpenses().single.id, 'exists');
    await pos.addNewProducts([product('valid_after_failure')]);
    expect(db.getProducts().length, initial + 1);
  });

  test(
      'Empty and oversized batches are rejected; 100 rows save without ID collisions',
      () async {
    final pos = await create('owner');
    await expectLater(pos.addNewProducts([]), throwsArgumentError);
    await expectLater(pos.addOperationalExpenses([]), throwsArgumentError);
    await expectLater(
        pos.addNewProducts(List.generate(101, (i) => product('menu_$i'))),
        throwsArgumentError);
    await expectLater(
        pos.addOperationalExpenses(
            List.generate(101, (i) => expense('expense_$i'))),
        throwsArgumentError);
    await pos.addNewProducts(List.generate(100, (i) => product('menu_$i')));
    await pos.addOperationalExpenses(
        List.generate(100, (i) => expense('expense_$i')));
    expect(db.getProducts().where((p) => p.id.startsWith('menu_')).length, 100);
    expect(db.getOperationalExpenses().length, 100);
    final prefs = await SharedPreferences.getInstance();
    expect(
        (jsonDecode(prefs.getString('cached_operational_expenses')!) as List)
            .length,
        100);
  });

  test('Concurrent duplicate batches insert once and reject the second request',
      () async {
    final pos = await create('owner');
    final first = pos.addNewProducts([product('concurrent')]);
    final second = expectLater(
        pos.addNewProducts([product('concurrent')]), throwsStateError);
    await first;
    await second;
    expect(db.getProducts().where((p) => p.id == 'concurrent').length, 1);
  });

  for (final role in <String?>[null, 'kasir', 'admin']) {
    test('Batch permissions enforced in provider and storage for $role',
        () async {
      final pos = await create(role);
      if (role == 'admin') {
        await pos.addNewProducts([product('allowed')]);
      } else {
        await expectLater(
            pos.addNewProducts([product('denied')]), throwsStateError);
        await expectLater(
            db.addProducts([product('denied')]), throwsStateError);
      }
      await expectLater(
          pos.addOperationalExpenses([expense('denied')]), throwsStateError);
      await expectLater(
          db.addOperationalExpenses([expense('denied')]), throwsStateError);
      expect(db.getOperationalExpenses(), isEmpty);
    });
  }

  Widget app(PosProvider pos, Widget screen,
          {double scale = 1, double keyboard = 0}) =>
      ChangeNotifierProvider.value(
          value: pos,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  viewInsets: EdgeInsets.only(bottom: keyboard)),
              child: child!,
            ),
            home: screen,
          ));
  Finder field(String suffix, int index) => find
      .byWidgetPredicate((widget) =>
          widget is TextFormField &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.endsWith('_$suffix'))
      .at(index);
  Future<void> fill(
      WidgetTester tester, String suffix, int index, String value) async {
    final target = field(suffix, index);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.enterText(target, value);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, PosProvider pos, bool expenses) async {
    await tester.pumpWidget(app(
        pos,
        expenses
            ? const OperationalExpensesScreen()
            : const StockManagementScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah Sekaligus'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Menu batch validates every row, supports add/remove, and persists all entered values',
      (tester) async {
    final pos = (await tester.runAsync(() => create('admin')))!;
    final before = pos.products.length;
    await open(tester, pos, false);
    await fill(tester, 'name', 0, 'Kopi Susu Gula Aren');
    await fill(tester, 'price', 0, '23000');
    await fill(tester, 'cost', 0, '8500');
    await fill(tester, 'stock', 0, '45');
    await fill(tester, 'minimum', 0, '8');
    await tester.tap(find.text('Simpan 2 Item'));
    await tester.pumpAndSettle();
    expect(pos.products.length, before);
    expect(find.text('Nama menu wajib diisi.'), findsOneWidget);
    await fill(tester, 'name', 1, 'Kopi Hitam');
    await fill(tester, 'price', 1, '15000');
    await tester.tap(find.text('Tambah Baris'));
    await tester.pumpAndSettle();
    expect(find.text('Simpan 3 Item'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Hapus baris 2'));
    await tester.tap(find.byTooltip('Hapus baris 2'));
    await tester.pumpAndSettle();
    await fill(tester, 'name', 1, 'Matcha Latte');
    await fill(tester, 'price', 1, '27000');
    await tester.runAsync(() async {
      await tester.tap(find.text('Simpan 2 Item'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byType(BatchInsertDialog), findsNothing);
    expect(pos.products.length, before + 2);
    final coffee =
        pos.products.firstWhere((p) => p.name == 'Kopi Susu Gula Aren');
    expect([
      coffee.sellPrice,
      coffee.baseCost,
      coffee.stock,
      coffee.minStockThreshold
    ], [
      23000,
      8500,
      45,
      8
    ]);
    expect(pos.products.any((p) => p.name == 'Kopi Hitam'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Expense batch saves categories, notes and amounts from the real screen',
      (tester) async {
    final pos = (await tester.runAsync(() => create('owner')))!;
    await open(tester, pos, true);
    await fill(tester, 'name', 0, 'Tagihan listrik');
    await fill(tester, 'price', 0, '350000');
    await fill(tester, 'notes', 0, 'November');
    await fill(tester, 'name', 1, 'Kantong Plastik dan Sachet');
    await fill(tester, 'price', 1, '25000');
    final dropdown = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kantong Plastik').last);
    await tester.tap(find.text('Kantong Plastik').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Simpan 2 Item'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byType(BatchInsertDialog), findsNothing);
    expect(pos.operationalExpenses.length, 2);
    final electricity =
        pos.operationalExpenses.firstWhere((e) => e.title == 'Tagihan listrik');
    expect(electricity.category, 'Biaya Listrik');
    expect(electricity.amount, 350000);
    expect(electricity.notes, 'November');
    expect(
        pos.operationalExpenses.firstWhere((e) => e.amount == 25000).category,
        'Kantong Plastik');
    expect(pos.todayOperationalExpenseTotal, 375000);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Failed save retains input; retry prevents double submit and dismissal during save',
      (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await db.resetForTesting();
    });
    final pos = ControlledBatchProvider();
    await tester.runAsync(() => create('owner', fresh: false, custom: pos));
    await open(tester, pos, false);
    await tester.ensureVisible(find.byTooltip('Hapus baris 2'));
    await tester.tap(find.byTooltip('Hapus baris 2'));
    await tester.pumpAndSettle();
    await fill(tester, 'name', 0, 'Retry Coffee');
    await fill(tester, 'price', 0, '19000');
    pos.failNext = true;
    await tester.tap(find.text('Simpan 1 Item'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Gagal menyimpan item.'), findsOneWidget);
    expect(tester.widget<TextFormField>(field('name', 0)).controller!.text,
        'Retry Coffee');
    expect(pos.products.any((p) => p.name == 'Retry Coffee'), isFalse);
    pos.gate = Completer<void>();
    await tester.tap(find.text('Simpan 1 Item'));
    await tester.pump();
    expect(find.text('Menyimpan...'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Batal'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Menyimpan...'));
    expect(pos.calls, 2);
    expect(
        await tester.state<NavigatorState>(find.byType(Navigator)).maybePop(),
        isTrue);
    await tester.pump();
    expect(find.byType(BatchInsertDialog), findsOneWidget);
    await tester.runAsync(() async {
      pos.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(pos.products.where((p) => p.name == 'Retry Coffee').length, 1);
    expect(find.byType(BatchInsertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(800, 360),
    const Size(1280, 800)
  ]) {
    for (final expenses in [false, true]) {
      testWidgets(
          'Batch dialog ${expenses ? 'expenses' : 'menu'} fits $size with text scaling and keyboard',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final pos = (await tester.runAsync(() => create('owner')))!;
        await tester.pumpWidget(app(pos, const Scaffold(),
            scale: 1.5, keyboard: size.height > 400 ? 120 : 0));
        final context = tester.element(find.byType(Scaffold));
        unawaited(showDialog<void>(
            context: context,
            builder: (_) => expenses
                ? const BatchInsertDialog.expenses()
                : const BatchInsertDialog.menu()));
        await tester.pumpAndSettle();
        expect(find.text('Simpan 2 Item').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Simpan 2 Item'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(field('price', 1));
        expect(field('price', 1).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'Direct batch dialogs deny cashier access and admin financial access',
      (tester) async {
    final pos = (await tester.runAsync(() => create('kasir')))!;
    await tester.pumpWidget(app(pos, const BatchInsertDialog.menu()));
    await tester.pumpAndSettle();
    expect(find.byType(AccessDenied), findsOneWidget);
    await tester.runAsync(() => pos.login('warloc.admin', 'sukses123'));
    await tester.pumpWidget(app(pos, const BatchInsertDialog.expenses()));
    await tester.pumpAndSettle();
    expect(find.byType(AccessDenied), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
