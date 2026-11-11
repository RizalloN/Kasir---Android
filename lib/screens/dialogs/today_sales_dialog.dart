import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_provider.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/access_denied.dart';

class TodaySalesDialog extends StatelessWidget {
  const TodaySalesDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    if (!pos.isAuthenticated) return const AccessDenied();
    final sales = pos.todayStoreSales;
    return AlertDialog(
      title: const Text('Penjualan Hari Ini'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(CurrencyFormatter.formatDateOnly(DateTime.now())),
              const SizedBox(height: 12),
              Text(CurrencyFormatter.format(sales.totalAmount),
                  key: const ValueKey('today-store-revenue'),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('${sales.transactionCount} transaksi lunas seluruh kasir'),
              const SizedBox(height: 12),
              const Text('Total setelah diskon dan koreksi. Open bill dan transaksi dibatalkan tidak dihitung.'),
              const SizedBox(height: 8),
              Text(pos.isOnline
                  ? 'Mengikuti data yang tersinkron pada perangkat ini.'
                  : 'Offline: berdasarkan data tersimpan di perangkat ini.'),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
    );
  }
}
