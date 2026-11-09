import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_super/models/cart_item.dart';
import 'package:kasir_super/models/product.dart';
import 'package:kasir_super/models/transaction.dart';
import 'package:kasir_super/services/thermal_printer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID', null));

  TransactionRecord receipt({bool voided = false}) => TransactionRecord(
        id: 'invoice-01',
        invoiceNumber: 'INV-01',
        items: [
          CartItem(
              product: const Product(
                  id: 'p1',
                  name: 'Kopi ☕',
                  category: 'Coffee',
                  sellPrice: 23000,
                  baseCost: 8000,
                  stock: 5),
              quantity: 2,
              note: CartItem.composeNote('ES', 'Gula sedikit 😊'))
        ],
        subtotalAmount: 46000,
        discountAmount: 1000,
        totalAmount: 45000,
        totalCost: 16000,
        totalProfit: 29000,
        paymentMethod: 'Cash',
        amountPaid: 50000,
        changeAmount: 5000,
        cashierName: 'Kasir 😀',
        orderType: 'Dine-In',
        customerName: 'Pelanggan 🎉',
        createdAt: DateTime(2026, 11, 9, 10),
        isVoided: voided,
      );

  for (final width in [58, 80]) {
    test(
        'Actual $width mm receipt contains variant, final prices and safe text',
        () async {
      final bytes = await ThermalPrinterService.instance
          .buildTransactionReceiptBytes(receipt(), paperWidth: width);
      final contents = latin1.decode(bytes);
      expect(contents, contains('Kedungmulyo, Kutorejo,'));
      expect(contents, contains('Kab. Mojokerto'));
      expect(contents, isNot(contains('0812-9988-7766')));
      expect(contents, contains('INV-01'));
      expect(contents, contains('Kopi ?'));
      expect(contents, contains('Varian: ES'));
      expect(contents, contains('Gula sedikit ?'));
      expect(contents, contains('23.000'));
      expect(contents, contains('46.000'));
      expect(contents, contains('45.000'));
      expect(contents, contains('50.000'));
      expect(contents, contains('5.000'));
      expect(contents, isNot(contains('KAFE_VARIAN_v1')));
      final voidBytes = await ThermalPrinterService.instance
          .buildTransactionReceiptBytes(receipt(voided: true),
              paperWidth: width);
      expect(latin1.decode(voidBytes), contains('TRANSAKSI DIBATALKAN'));
    });
  }
}
