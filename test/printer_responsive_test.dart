import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/cart_item.dart';
import 'package:kasir_super/models/product.dart';
import 'package:kasir_super/models/transaction.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/barista/receipt_dialog.dart';
import 'package:kasir_super/screens/dialogs/printer_settings_dialog.dart';
import 'package:kasir_super/services/app_release_service.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  setUpAll(() => initializeDateFormatting('id_ID', null));

  for (final size in [
    const Size(320, 568),
    const Size(800, 360),
    const Size(600, 960)
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
          'Receipt and printer settings fit ${size.width}x${size.height} at $scale',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final pos = await tester.runAsync(() async {
          await PosDatabaseService.instance.resetForTesting();
          final result = PosProvider();
          while (!result.isInitialized) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(await result.login('warloc.owner', 'sukses888'), isNull);
          return result;
        });
        final release = AppReleaseService();
        final tx = TransactionRecord(
            id: 'test',
            invoiceNumber: 'INV-01',
            items: [
              CartItem(
                  product: const Product(
                      id: 'p',
                      name: 'Kopi',
                      category: 'Coffee',
                      sellPrice: 23000,
                      baseCost: 8000,
                      stock: 5))
            ],
            totalAmount: 23000,
            totalCost: 8000,
            totalProfit: 15000,
            paymentMethod: 'Cash',
            amountPaid: 25000,
            changeAmount: 2000,
            cashierName: 'Kasir',
            createdAt: DateTime(2026, 11, 9));
        Widget app(Widget child) => MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: pos!),
                  ChangeNotifierProvider.value(value: release),
                ],
                child: MaterialApp(
                    builder: (context, widget) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: widget!),
                    home: Scaffold(body: child)));
        await tester
            .pumpWidget(app(ReceiptDialog(transaction: tx, allowVoid: true)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Kedungmulyo, Kutorejo, Kab. Mojokerto'),
            findsOneWidget);
        expect(find.textContaining('0812-9988-7766'), findsNothing);
        if (size.width == 600 && scale == 1.0) {
          await tester.ensureVisible(
              find.text('Void / Batalkan Transaksi & Kembalikan Stok'));
          await tester
              .tap(find.text('Void / Batalkan Transaksi & Kembalikan Stok'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Ya, Void Transaksi'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(ReceiptDialog), findsOneWidget);
          expect(
              find.text(
                  'Transaksi tidak dapat dibatalkan. Periksa kembali riwayat transaksi.'),
              findsOneWidget);
        }
        await tester.pumpWidget(app(const PrinterSettingsDialog()));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        pos!.dispose();
        release.dispose();
      });
    }
  }
}
