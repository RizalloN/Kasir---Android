import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../models/transaction.dart';
import '../utils/currency_formatter.dart';

class PrintResult {
  final bool success;
  final String message;

  const PrintResult({required this.success, required this.message});
}

class ThermalPrinterService {
  static final ThermalPrinterService instance = ThermalPrinterService._internal();
  ThermalPrinterService._internal();

  CapabilityProfile? _cachedProfile;

  Future<CapabilityProfile> _getProfile() async {
    _cachedProfile ??= await CapabilityProfile.load();
    return _cachedProfile!;
  }

  /// Checks if Bluetooth is enabled on the device
  Future<bool> isBluetoothEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (e) {
      debugPrint('isBluetoothEnabled check error: $e');
      return false;
    }
  }

  /// Checks if Bluetooth permissions are granted
  Future<bool> isPermissionGranted() async {
    try {
      return await PrintBluetoothThermal.isPermissionBluetoothGranted;
    } catch (e) {
      debugPrint('isPermissionGranted check error: $e');
      return false;
    }
  }

  /// Retrieves list of paired Bluetooth devices (thermal printers)
  Future<List<BluetoothInfo>> getPairedPrinters() async {
    try {
      final isEnabled = await isBluetoothEnabled();
      if (!isEnabled) {
        return [];
      }
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (e) {
      debugPrint('getPairedPrinters error: $e');
      return [];
    }
  }

  /// Checks whether a printer is actively connected
  Future<bool> isConnected() async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (e) {
      return false;
    }
  }

  /// Connects to a printer using its MAC address
  Future<PrintResult> connect(String macAddress) async {
    if (macAddress.trim().isEmpty) {
      return const PrintResult(success: false, message: 'Alamat MAC printer tidak valid.');
    }
    try {
      final isEnabled = await isBluetoothEnabled();
      if (!isEnabled) {
        return const PrintResult(
          success: false,
          message: 'Bluetooth perangkat belum aktif. Silakan nyalakan Bluetooth terlebih dahulu.',
        );
      }

      final bool connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: macAddress.trim(),
      );
      if (connected) {
        return const PrintResult(success: true, message: 'Berhasil terhubung ke printer thermal.');
      } else {
        return const PrintResult(
          success: false,
          message: 'Gagal terhubung. Pastikan printer thermal dinyalakan dan dalam jangkauan.',
        );
      }
    } catch (e) {
      return PrintResult(success: false, message: 'Error koneksi printer: $e');
    }
  }

  /// Disconnects from current printer
  Future<PrintResult> disconnect() async {
    try {
      final ok = await PrintBluetoothThermal.disconnect;
      return PrintResult(
        success: ok,
        message: ok ? 'Printer berhasil diputuskan.' : 'Gagal memutuskan printer.',
      );
    } catch (e) {
      return PrintResult(success: false, message: 'Error: $e');
    }
  }

  /// Generates and sends a test ticket to the connected printer
  Future<PrintResult> printTestReceipt({int paperWidth = 58}) async {
    try {
      final connected = await isConnected();
      if (!connected) {
        return const PrintResult(
          success: false,
          message: 'Printer belum terhubung. Silakan pilih dan hubungkan printer terlebih dahulu.',
        );
      }

      final profile = await _getProfile();
      final paperSize = paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
      final generator = Generator(paperSize, profile);

      List<int> bytes = [];
      bytes += generator.reset();

      // Header
      bytes += generator.text(
        'WARLOC',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.text(
        'UJI COBA CETAK STRUK',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        'Thermal Printer ESC/POS ($paperWidth mm)',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.feed(1);
      bytes += generator.hr();

      // Info
      final now = DateTime.now();
      bytes += generator.row([
        PosColumn(text: 'Tanggal', width: 4),
        PosColumn(
          text: CurrencyFormatter.formatDateTime(now),
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Status', width: 4),
        PosColumn(
          text: 'ONLINE / SIAP CETAK',
          width: 8,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Lebar Kertas', width: 6),
        PosColumn(
          text: '$paperWidth mm',
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      bytes += generator.hr();
      bytes += generator.text(
        'Koneksi driver Bluetooth ESC/POS berfungsi normal.',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        'POS Warloc Siap Beroperasi!',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.feed(2);
      bytes += generator.cut();

      final sent = await PrintBluetoothThermal.writeBytes(bytes);
      if (sent) {
        return const PrintResult(success: true, message: 'Struk uji coba berhasil dicetak!');
      } else {
        return const PrintResult(
          success: false,
          message: 'Gagal mengirim data cetak ke printer thermal.',
        );
      }
    } catch (e) {
      return PrintResult(success: false, message: 'Gagal mencetak struk uji coba: $e');
    }
  }

  /// Prints a real transaction receipt
  Future<PrintResult> printTransactionReceipt(
    TransactionRecord transaction, {
    int paperWidth = 58,
  }) async {
    try {
      final connected = await isConnected();
      if (!connected) {
        return const PrintResult(
          success: false,
          message: 'Printer belum terhubung. Buka Pengaturan Printer untuk menghubungkan.',
        );
      }

      final profile = await _getProfile();
      final paperSize = paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
      final generator = Generator(paperSize, profile);

      List<int> bytes = [];
      bytes += generator.reset();

      // Store Title
      bytes += generator.text(
        'WARLOC',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.text(
        'Coffee, Eatery & Entertainment',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        'Jl. Nongkrong Warloc No. 1, Jakarta',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        'Telp: 0812-9988-7766',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.hr();

      if (transaction.isVoided) {
        bytes += generator.text(
          '*** TRANSAKSI DIBATALKAN (VOID) ***',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        bytes += generator.hr();
      }

      // Meta Info
      bytes += generator.row([
        PosColumn(text: 'No. Struk', width: 4),
        PosColumn(
          text: transaction.invoiceNumber,
          width: 8,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Waktu', width: 4),
        PosColumn(
          text: CurrencyFormatter.formatDateTime(transaction.createdAt),
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Kasir', width: 4),
        PosColumn(
          text: transaction.cashierName,
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      if (transaction.customerName != null && transaction.customerName!.trim().isNotEmpty) {
        bytes += generator.row([
          PosColumn(text: 'Pelanggan', width: 4),
          PosColumn(
            text: transaction.customerName!,
            width: 8,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }
      bytes += generator.row([
        PosColumn(text: 'Tipe', width: 4),
        PosColumn(
          text: transaction.orderType,
          width: 8,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Metode', width: 4),
        PosColumn(
          text: transaction.paymentMethod,
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      bytes += generator.hr();

      // Item List
      for (final item in transaction.items) {
        // Item Name line
        bytes += generator.text(
          item.product.name,
          styles: const PosStyles(bold: true),
        );

        // Quantity x Price & Subtotal line
        final qtyPrice = '${item.quantity} x ${CurrencyFormatter.format(item.product.sellPrice)}';
        final subtotal = CurrencyFormatter.format(item.subtotal);
        bytes += generator.row([
          PosColumn(text: '  $qtyPrice', width: 7),
          PosColumn(
            text: subtotal,
            width: 5,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);

        // Note if present
        if (item.note != null && item.note!.trim().isNotEmpty) {
          bytes += generator.text(
            '  * Catatan: ${item.note!.trim()}',
            styles: const PosStyles(fontType: PosFontType.fontB),
          );
        }
      }

      bytes += generator.hr();

      // Totals
      if (transaction.discountAmount > 0) {
        bytes += generator.row([
          PosColumn(text: 'Subtotal', width: 6),
          PosColumn(
            text: CurrencyFormatter.format(transaction.subtotalAmount),
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
        bytes += generator.row([
          PosColumn(text: 'Diskon', width: 6),
          PosColumn(
            text: '-${CurrencyFormatter.format(transaction.discountAmount)}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      bytes += generator.row([
        PosColumn(
          text: 'TOTAL',
          width: 6,
          styles: const PosStyles(bold: true, height: PosTextSize.size2),
        ),
        PosColumn(
          text: CurrencyFormatter.format(transaction.totalAmount),
          width: 6,
          styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2),
        ),
      ]);

      bytes += generator.row([
        PosColumn(text: 'Bayar (${transaction.paymentMethod})', width: 6),
        PosColumn(
          text: CurrencyFormatter.format(transaction.amountPaid),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      bytes += generator.row([
        PosColumn(text: 'Kembalian', width: 6, styles: const PosStyles(bold: true)),
        PosColumn(
          text: CurrencyFormatter.format(transaction.changeAmount),
          width: 6,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);

      bytes += generator.hr();

      // Footer
      bytes += generator.text(
        transaction.isVoided
            ? 'STRUK VOID - STOK DIKEMBALIKAN'
            : 'Terima Kasih Telah Berkunjung',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        'ke Warloc',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        'Selamat Menikmati Hidangan Anda',
        styles: const PosStyles(align: PosAlign.center),
      );

      bytes += generator.feed(2);
      bytes += generator.cut();

      final sent = await PrintBluetoothThermal.writeBytes(bytes);
      if (sent) {
        return const PrintResult(
          success: true,
          message: 'Struk transaksi berhasil dicetak ke printer thermal!',
        );
      } else {
        return const PrintResult(
          success: false,
          message: 'Gagal mengirim data cetak struk ke printer.',
        );
      }
    } catch (e) {
      return PrintResult(success: false, message: 'Gagal mencetak struk: $e');
    }
  }
}
