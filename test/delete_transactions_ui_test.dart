import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/transaction.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/barista/receipt_dialog.dart';
import 'package:kasir_super/screens/dialogs/delete_transaction_dialog.dart';
import 'package:kasir_super/services/app_release_service.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';
import 'package:kasir_super/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
    final fonts =
        '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts';
    for (final family in ['Roboto', 'Ahem']) {
      final regular = File('$fonts/roboto-regular.ttf');
      if (await regular.exists()) {
        await (FontLoader(family)
              ..addFont(regular.readAsBytes().then(ByteData.sublistView))
              ..addFont(File('$fonts/roboto-bold.ttf')
                  .readAsBytes()
                  .then(ByteData.sublistView)))
            .load();
      }
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  Future<PosProvider> fresh() async {
    SharedPreferences.setMockInitialValues({});
    await PosDatabaseService.instance.resetForTesting();
    final pos = PosProvider();
    addTearDown(pos.dispose);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    expect(await pos.login('warloc.admin', 'sukses123'), isNull);
    return pos;
  }

  Future<TransactionRecord> sale(PosProvider pos) async {
    pos.addToCart(pos.products.firstWhere((p) => p.id == 'w_1'), variant: 'ES');
    return pos.processCheckout(
        paymentMethod: 'Cash', amountPaid: 50000, cashierName: '');
  }

  Widget app(PosProvider pos, Widget child, {double scale = 1}) =>
      MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: pos),
            ChangeNotifierProvider(create: (_) => AppReleaseService()),
          ],
          child: RepaintBoundary(
              key: const ValueKey('delete-preview'),
              child: MaterialApp(
          theme: AppTheme.lightTheme, debugShowCheckedModeBanner: false,
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: child)));

  for (final scenario in [
    (size: const Size(320, 568), scale: 1.5, keyboard: 250.0),
    (size: const Size(800, 360), scale: 1.5, keyboard: 160.0),
    (size: const Size(600, 960), scale: 1.5, keyboard: 300.0),
    (size: const Size(1280, 800), scale: 1.0, keyboard: 350.0),
  ]) {
    testWidgets(
        'Delete confirmation stays usable and retains input through keyboard animation $scenario',
        (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final pos = (await tester.runAsync(fresh))!;
      final tx = (await tester.runAsync(() => sale(pos)))!;
      await tester.pumpWidget(app(
          pos,
          Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showDeleteTransactionDialog(context, tx),
                      child: const Text('Buka')))),
          scale: scenario.scale));
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('delete-transaction-reason'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.showKeyboard(field);
      await tester.pump();
      final editable =
          find.descendant(of: field, matching: find.byType(EditableText));
      final state = tester.state<EditableTextState>(editable);
      await tester.enterText(field, 'Duplikat pesanan');
      for (final inset in [120.0, scenario.keyboard, 120.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 160));
        expect(tester.takeException(), isNull);
        expect(tester.state<EditableTextState>(editable), same(state));
        expect(state.widget.focusNode.hasFocus, isTrue);
        expect(state.widget.controller.text, 'Duplikat pesanan');
      }
      expect(
          find
              .byKey(const ValueKey('confirm-delete-transaction'))
              .hitTestable(),
          findsOneWidget);
      if (scenario.size.width == 1280) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('delete-preview')));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/delete-transactions/confirmation-desktop.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(pos.transactions.single.id, tx.id);
      expect(pos.deletedTransactions, isEmpty);
    });
  }

  testWidgets(
      'Admin can delete through report receipt and returns cleanly to the underlying page',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pos = (await tester.runAsync(fresh))!;
    final tx = (await tester.runAsync(() => sale(pos)))!;
    await tester.pumpWidget(app(
        pos,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            ReceiptDialog(transaction: tx, allowVoid: true)),
                    child: const Text('Laporan'))))));
    await tester.tap(find.text('Laporan'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hapus transaksi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus transaksi'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('delete-transaction-reason')),
        'Salah input dari laporan');
    await tester.runAsync(() async {
      await tester
          .tap(find.byKey(const ValueKey('confirm-delete-transaction')));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    expect(pos.transactions, isEmpty);
    expect(find.byType(ReceiptDialog), findsNothing);
    expect(find.text('Laporan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
