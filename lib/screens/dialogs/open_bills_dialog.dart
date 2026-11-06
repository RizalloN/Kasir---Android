import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_provider.dart';
import '../../utils/currency_formatter.dart';
import '../../theme/app_theme.dart';

class OpenBillsDialog extends StatelessWidget {
  final VoidCallback? onResumed;
  const OpenBillsDialog({super.key, this.onResumed});
  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    return AlertDialog(
      title: const Text('Riwayat Pesanan Belum Dibayar'),
      content: SizedBox(
          width: 500,
          height: 420,
          child: pos.openBills.isEmpty
              ? const Center(child: Text('Belum ada pesanan tersimpan. Simpan pesanan dari keranjang agar dapat diperbaiki sebelum pembayaran.'))
              : ListView.separated(
                  itemCount: pos.openBills.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final bill = pos.openBills[index];
                    return ListTile(
                      title: Text(bill.customerName),
                      subtitle: Text(
                          '${bill.items.length} menu · ${CurrencyFormatter.format(bill.totalAmount)}\n${bill.orderType} · Ketuk untuk memperbaiki'),
                      isThreeLine: true,
                      trailing: IconButton(
                          tooltip: 'Hapus tagihan',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                      title: const Text(
                                          'Hapus tagihan belum dibayar?'),
                                      content: Text(bill.customerName),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Batal')),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('Hapus')),
                                      ],
                                    ));
                            if (confirmed != true || !context.mounted) return;
                            try {
                              await pos.deleteOpenBill(bill.id);
                            } catch (_) {
                              if (context.mounted) {
                                AppTheme.showToast(context,
                                    message: 'Tagihan tidak dapat dihapus.',
                                    isError: true);
                              }
                            }
                          }),
                      onTap: () {
                        try {
                          pos.resumeOpenBill(bill.id);
                          Navigator.pop(context);
                          onResumed?.call();
                          AppTheme.showToast(context,
                              message:
                                  'Tagihan dibuka. Harga dan stok mengikuti katalog saat ini.');
                        } catch (e) {
                          AppTheme.showToast(context,
                              message:
                                  e.toString().replaceFirst('Bad state: ', ''),
                              isError: true);
                        }
                      },
                    );
                  },
                )),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Tutup'))
      ],
    );
  }
}
