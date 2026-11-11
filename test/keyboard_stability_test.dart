import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/auth/login_screen.dart';
import 'package:kasir_super/screens/auth/change_password_screen.dart';
import 'package:kasir_super/screens/barista/open_bills_screen.dart';
import 'package:kasir_super/screens/barista/cart_bottom_sheet.dart';
import 'package:kasir_super/screens/dialogs/batch_insert_dialog.dart';
import 'package:kasir_super/screens/dialogs/edit_product_dialog.dart';
import 'package:kasir_super/screens/dialogs/transaction_history_dialog.dart';
import 'package:kasir_super/screens/main_wrapper_screen.dart';
import 'package:kasir_super/services/app_release_service.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';
import 'package:kasir_super/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  setUpAll(() => initializeDateFormatting('id_ID', null));

  Future<PosProvider> fresh([String account = 'kasir']) async {
    SharedPreferences.setMockInitialValues({});
    await PosDatabaseService.instance.resetForTesting();
    final pos = PosProvider();
    addTearDown(pos.dispose);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    expect(
        await pos.login(
            'warloc.$account', account == 'owner' ? 'sukses888' : 'sukses000'),
        isNull);
    return pos;
  }

  Widget app(PosProvider pos, Widget child) => MultiProvider(providers: [
        ChangeNotifierProvider.value(value: pos),
        ChangeNotifierProvider(create: (_) => AppReleaseService()),
      ], child: MaterialApp(theme: AppTheme.lightTheme, home: child));

  void viewport(WidgetTester tester, [Size size = const Size(1024, 800)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
  }

  Future<void> retainsInput(WidgetTester tester, Finder field,
      {String text = 'Kopi susu', double keyboard = 400}) async {
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.showKeyboard(field);
    await tester.pump();
    final editable =
        find.descendant(of: field, matching: find.byType(EditableText));
    final original = tester.state<EditableTextState>(editable);
    final value = TextEditingValue(
        text: text,
        selection: const TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: text.length));
    tester.testTextInput.updateEditingValue(value);
    await tester.pump();
    for (final inset in [60.0, 160.0, keyboard, 160.0, 0.0, keyboard, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      // Check both an intermediate animation frame and the settled layout.
      for (final duration in [
        const Duration(milliseconds: 16),
        const Duration(milliseconds: 160)
      ]) {
        await tester.pump(duration);
        expect(tester.takeException(), isNull,
            reason: 'layout at keyboard inset $inset');
        expect(tester.state<EditableTextState>(editable), same(original),
            reason: 'input recreated at inset $inset');
        expect(original.widget.focusNode.hasFocus, isTrue,
            reason: 'focus lost at inset $inset');
        expect(original.widget.controller.value, value,
            reason: 'editing value changed at inset $inset');
        expect(tester.testTextInput.hasAnyClients, isTrue);
      }
    }
  }

  testWidgets('Login keeps its focused input across keyboard animation',
      (tester) async {
    viewport(tester);
    final pos = (await tester.runAsync(fresh))!;
    await tester.runAsync(pos.logout);
    await tester.pumpWidget(app(pos, const LoginScreen()));
    await tester.pumpAndSettle();
    await retainsInput(tester, find.byType(TextField).first);
  });

  testWidgets(
      'Open Bill search keeps focus when tablet keyboard reduces height',
      (tester) async {
    viewport(tester);
    final pos = (await tester.runAsync(fresh))!;
    await tester.pumpWidget(app(pos, const MainWrapperScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cashier-tab-open-bill')));
    await tester.pumpAndSettle();
    await retainsInput(tester, find.byKey(const ValueKey('open-bill-search')));
  });

  testWidgets('Open Bill cash input keeps focus while its viewport shrinks',
      (tester) async {
    viewport(tester);
    final pos = (await tester.runAsync(fresh))!;
    pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES');
    pos.setCustomerName('Meja Fokus');
    final bill = (await tester.runAsync(pos.saveCurrentBill))!;
    await tester.pumpWidget(
        app(pos, Scaffold(body: OpenBillsScreen(initialBillId: bill.id))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar tagihan'));
    await tester.pumpAndSettle();
    await retainsInput(tester, find.byKey(const ValueKey('open-bill-cash')),
        text: '50000');
    expect(pos.transactions, isEmpty);
    expect(pos.openBills.single.id, bill.id);
  });

  testWidgets(
      'Correction reason keeps the IME connection during keyboard animation',
      (tester) async {
    viewport(tester);
    final pos = (await tester.runAsync(() => fresh('owner')))!;
    pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES');
    final tx = (await tester.runAsync(() => pos.processCheckout(
        paymentMethod: 'Cash', amountPaid: 50000, cashierName: '')))!;
    await tester
        .pumpWidget(app(pos, CorrectTransactionDialog(transaction: tx)));
    await tester.pumpAndSettle();
    await retainsInput(
        tester, find.byKey(const ValueKey('correction-reason-input')));
    expect(pos.transactions.single.revision, tx.revision);
  });

  testWidgets('Catalog search keeps selection and composing while filtering',
      (tester) async {
    viewport(tester);
    final pos = (await tester.runAsync(fresh))!;
    await tester.pumpWidget(app(pos, const MainWrapperScreen()));
    await tester.pumpAndSettle();
    await retainsInput(tester, find.byType(TextField).first);
  });

  testWidgets('Cart customer input survives keyboard and provider rebuilds',
      (tester) async {
    viewport(tester);
    final pos = (await tester.runAsync(fresh))!;
    pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES');
    await tester.pumpWidget(
        app(pos, const Scaffold(body: CartBottomSheet(isTabletSidebar: true))));
    await tester.pumpAndSettle();
    final field = find.byType(TextField).first;
    await retainsInput(tester, field);
    final value = tester.widget<TextField>(field).controller!.value;
    pos.updateQuantity('w_1', 1, variant: 'ES');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.value, value);
  });

  testWidgets('Menu editor input survives keyboard without saving data',
      (tester) async {
    viewport(tester);
    final pos = (await tester.runAsync(() => fresh('owner')))!;
    await tester.pumpWidget(
        app(pos, EditProductDialog(onSave: (_) => fail('Unexpected save'))));
    await tester.pumpAndSettle();
    await retainsInput(tester, find.byType(TextField).first);
  });

  testWidgets('Batch menu input survives keyboard without changing rows',
      (tester) async {
    viewport(tester);
    final pos = (await tester.runAsync(() => fresh('owner')))!;
    await tester.pumpWidget(app(pos, const BatchInsertDialog.menu()));
    await tester.pumpAndSettle();
    await retainsInput(tester, find.byType(TextFormField).first);
  });

  testWidgets('Owner password input keeps its IME connection', (tester) async {
    viewport(tester);
    final pos = (await tester.runAsync(() => fresh('owner')))!;
    await tester.pumpWidget(app(pos, const ChangePasswordScreen()));
    await tester.pumpAndSettle();
    await retainsInput(tester, find.byType(TextField).first, text: 'Password');
  });

  for (final size in [
    const Size(320, 568),
    const Size(800, 360),
    const Size(1280, 800)
  ]) {
    testWidgets('Catalog typing remains stable in $size with a large keyboard',
        (tester) async {
      viewport(tester, size);
      final pos = (await tester.runAsync(fresh))!;
      pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'),
          variant: 'ES');
      await tester.pumpWidget(app(pos, const MainWrapperScreen()));
      await tester.pumpAndSettle();
      await retainsInput(tester, find.byType(TextField).first,
          text: 'Tidak cocok', keyboard: size.height * 0.48);
      expect(pos.cart.single.quantity, 1);
      expect(pos.transactions, isEmpty);
    });
  }
}
