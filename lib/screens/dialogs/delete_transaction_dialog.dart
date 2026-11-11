import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/transaction.dart';
import '../../models/user_role.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/access_denied.dart';

Future<bool> showDeleteTransactionDialog(
    BuildContext context, TransactionRecord transaction) async {
  final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteTransactionDialog(transaction: transaction));
  if (deleted == true && context.mounted) {
    AppTheme.showToast(context,
        message:
            'Transaksi dihapus. Perubahan disimpan dan disinkronkan otomatis.');
  }
  return deleted == true;
}

class DeleteTransactionDialog extends StatefulWidget {
  final TransactionRecord transaction;
  const DeleteTransactionDialog({super.key, required this.transaction});
  @override
  State<DeleteTransactionDialog> createState() =>
      _DeleteTransactionDialogState();
}

class _DeleteTransactionDialogState extends State<DeleteTransactionDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy) return;
    if (_reason.text.trim().length < 3) {
      setState(() => _error = 'Isi alasan penghapusan, minimal 3 karakter.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<PosProvider>().deleteTransaction(
          transactionId: widget.transaction.id,
          expectedRevision: widget.transaction.revision,
          reason: _reason.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError || error is ArgumentError
            ? error
                .toString()
                .replaceFirst('Bad state: ', '')
                .replaceFirst('Invalid argument(s): ', '')
            : 'Penghapusan belum berhasil. Transaksi dan stok tetap tersedia; coba kembali.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    if (!pos.isAuthenticated || !pos.currentRole.canDeleteTransactions) {
      return const AccessDenied();
    }
    final tx = widget.transaction;
    final current =
        pos.transactions.where((sale) => sale.id == tx.id).firstOrNull;
    final changed = current == null ||
        current.revision != tx.revision ||
        current.isVoided != tx.isVoided;
    return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          scrollable: true,
          title: const Text('Hapus transaksi?',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain)),
          content: SizedBox(
              width: 440,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(tx.invoiceNumber,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(CurrencyFormatter.formatDateTime(tx.createdAt),
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text('Kasir: ${tx.cashierName}',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    Text(CurrencyFormatter.format(tx.totalAmount),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    Text(
                        tx.isVoided
                            ? 'Transaksi akan dihapus dari riwayat aktif. Stok sudah dikembalikan saat void dan tidak ditambah lagi.'
                            : 'Transaksi akan dikeluarkan dari penjualan dan stok barang dikembalikan satu kali. Tindakan ini tidak memproses pengembalian uang kepada pelanggan.',
                        style: const TextStyle(fontSize: 13, height: 1.5)),
                    const SizedBox(height: 8),
                    const Text(
                        'Jejak penghapusan tersimpan pada filter Terhapus. Penghapusan tidak dapat dibatalkan dari aplikasi.',
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: AppTheme.textMuted)),
                    const SizedBox(height: 20),
                    const Text('Alasan penghapusan',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                        key: const ValueKey('delete-transaction-reason'),
                        controller: _reason,
                        enabled: !_busy,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 200,
                        decoration: const InputDecoration(
                            hintText: 'Contoh: transaksi terinput dua kali'),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        }),
                    if (!_busy && changed)
                      const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                              'Transaksi sudah berubah atau dihapus. Tutup dan buka kembali detailnya.',
                              style: TextStyle(
                                  color: AppTheme.dangerRed, fontSize: 12))),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppTheme.dangerRed, fontSize: 12))),
                  ])),
          actions: [
            OutlinedButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Batal',
                    style: TextStyle(fontFamily: 'Roboto'))),
            FilledButton.icon(
                key: const ValueKey('confirm-delete-transaction'),
                onPressed: _busy || changed ? null : _delete,
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.dangerRed,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 46),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(_busy ? 'Menghapus...' : 'Hapus transaksi',
                    style: const TextStyle(fontFamily: 'Roboto'))),
          ],
        ));
  }
}
