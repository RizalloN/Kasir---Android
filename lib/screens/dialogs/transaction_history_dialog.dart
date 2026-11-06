import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/cart_item.dart';
import '../../models/product.dart';
import '../../models/transaction.dart';
import '../../providers/pos_provider.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/access_denied.dart';

class TransactionHistoryDialog extends StatelessWidget {
  const TransactionHistoryDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    if (!pos.isAuthenticated || pos.requiresPasswordChange) {
      return const AccessDenied();
    }
    final transactions = pos.transactions;
    return AlertDialog(
      title: const Text('Riwayat Transaksi'),
      content: SizedBox(
        width: 500,
        height: 420,
        child: transactions.isEmpty
            ? const Center(child: Text('Belum ada transaksi.'))
            : ListView.separated(
                itemCount: transactions.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final tx = transactions[index];
                  return ListTile(
                    title: Text(tx.invoiceNumber),
                    subtitle: Text(
                        '${CurrencyFormatter.formatDateTime(tx.createdAt)} · ${tx.isVoided ? 'Dibatalkan' : 'Ketuk untuk koreksi'}${tx.revision > 0 ? ' · Dikoreksi ${tx.revision}x' : ''}'),
                    trailing: Text(CurrencyFormatter.format(tx.totalAmount)),
                    onTap: tx.isVoided
                        ? null
                        : () => showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) =>
                                  CorrectTransactionDialog(transaction: tx),
                            ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Tutup'))
      ],
    );
  }
}

class CorrectTransactionDialog extends StatefulWidget {
  final TransactionRecord transaction;
  const CorrectTransactionDialog({super.key, required this.transaction});

  @override
  State<CorrectTransactionDialog> createState() =>
      _CorrectTransactionDialogState();
}

class _CorrectTransactionDialogState extends State<CorrectTransactionDialog> {
  late final List<CartItem> _items;
  late final TextEditingController _payment;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = widget.transaction.items.map((item) => item.copyWith()).toList();
    _payment = TextEditingController(
        text: widget.transaction.amountPaid.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _payment.dispose();
    _reason.dispose();
    super.dispose();
  }

  double get _subtotal => _items.fold(0, (sum, item) => sum + item.subtotal);
  double get _total => _subtotal - widget.transaction.discountAmount;
  double get _difference => _total - widget.transaction.totalAmount;

  Future<void> _addItem() async {
    final pos = context.read<PosProvider>();
    final selected = await showDialog<Product>(
      context: context,
      builder: (dialogContext) {
        var query = '';
        return StatefulBuilder(builder: (context, setDialogState) {
          final products = pos.visibleCatalogProducts
              .where((p) =>
                  p.isAvailable &&
                  p.name.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return AlertDialog(
            title: const Text('Tambah Item'),
            content: SizedBox(
                width: 420,
                height: 360,
                child: Column(children: [
                  TextField(
                      decoration: const InputDecoration(labelText: 'Cari menu'),
                      onChanged: (value) =>
                          setDialogState(() => query = value)),
                  Expanded(
                      child: ListView.builder(
                    itemCount: products.length,
                    itemBuilder: (_, index) => ListTile(
                      title: Text(products[index].name),
                      subtitle: Text(
                          CurrencyFormatter.format(products[index].sellPrice)),
                      onTap: () =>
                          Navigator.pop(dialogContext, products[index]),
                    ),
                  )),
                ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Batal'))
            ],
          );
        });
      },
    );
    if (!mounted || selected == null) return;
    String? variant;
    if (selected.isDrink) {
      variant = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Varian ${selected.name}'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final entry in CartItem.variantPrices.entries)
              ListTile(
                  title: Text(entry.key),
                  trailing: Text(CurrencyFormatter.format(widget
                          .transaction.items
                          .where((item) =>
                              item.product.id == selected.id &&
                              item.drinkVariant == entry.key)
                          .firstOrNull
                          ?.product
                          .sellPrice ??
                      selected.sellPrice + entry.value)),
                  onTap: () => Navigator.pop(dialogContext, entry.key)),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal'))
          ],
        ),
      );
      if (!mounted || variant == null) return;
    }
    setState(() {
      final index = _items.indexWhere((item) =>
          item.product.id == selected.id && item.drinkVariant == variant);
      if (index >= 0) {
        _items[index].quantity++;
      } else {
        final previous = widget.transaction.items
            .where((item) =>
                item.product.id == selected.id && item.drinkVariant == variant)
            .firstOrNull;
        _items.add(previous?.copyWith(quantity: 1) ??
            CartItem(
              product: selected.copyWith(
                  sellPrice: selected.sellPrice +
                      (CartItem.variantPrices[variant] ?? 0)),
              note: CartItem.composeNote(variant, null),
            ));
      }
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final amount = double.tryParse(_payment.text.trim());
    if (_items.isEmpty ||
        _reason.text.trim().isEmpty ||
        _total < 0 ||
        amount == null ||
        !amount.isFinite ||
        amount < _total ||
        (widget.transaction.paymentMethod == 'QRIS' && amount != _total)) {
      setState(() => _error =
          'Isi alasan dan pembayaran akhir yang mencukupi. Sisakan item; total tidak boleh lebih kecil dari diskon. Pembayaran QRIS harus sama dengan total.');
      return;
    }
    final difference = _difference;
    final description = difference > 0
        ? 'Tagih tambahan ${CurrencyFormatter.format(difference)}.'
        : difference < 0
            ? 'Kembalikan ${CurrencyFormatter.format(-difference)} kepada pelanggan.'
            : 'Tidak ada selisih tagihan.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Konfirmasi Koreksi'),
        content: Text(
            '$description\n\nPastikan selisih telah diselesaikan. Pembayaran akhir ${CurrencyFormatter.format(amount)}, kembalian ${CurrencyFormatter.format(amount - _total)}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Kembali')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Simpan Koreksi')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<PosProvider>().correctTransaction(
            transactionId: widget.transaction.id,
            expectedRevision: widget.transaction.revision,
            items: _items,
            amountPaid: amount,
            reason: _reason.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error
              .toString()
              .replaceFirst('Bad state: ', '')
              .replaceFirst('Invalid argument(s): ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    if (!pos.isAuthenticated ||
        pos.requiresPasswordChange ||
        !pos.transactions.any((tx) => tx.id == widget.transaction.id)) {
      return const AccessDenied();
    }
    final differenceLabel = _difference > 0
        ? 'Tambahan yang ditagih'
        : _difference < 0
            ? 'Pengembalian kepada pelanggan'
            : 'Selisih';
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Expanded(
                  child: SingleChildScrollView(
                      child: AbsorbPointer(
                absorbing: _saving,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Koreksi Transaksi',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(widget.transaction.invoiceNumber),
                      const SizedBox(height: 8),
                      const Text(
                          'Perbaiki item dan jumlah. Transaksi awal tetap tercatat dalam riwayat koreksi.'),
                      if (widget.transaction.corrections.isNotEmpty)
                        ExpansionTile(
                          title: Text(
                              'Riwayat koreksi (${widget.transaction.corrections.length})'),
                          children: [
                            for (final correction
                                in widget.transaction.corrections.reversed)
                              ListTile(
                                title: Text(
                                    'Revisi ${correction['revision']} · ${correction['correctedBy']}'),
                                subtitle: Text([
                                  'Alasan: ${correction['reason']}',
                                  'Waktu: ${correction['correctedAt']}',
                                  'Total: ${CurrencyFormatter.format((correction['previousTotal'] as num?) ?? 0)} → ${CurrencyFormatter.format((correction['newTotal'] as num?) ?? 0)}',
                                  'Pembayaran: ${CurrencyFormatter.format((correction['previousAmountPaid'] as num?) ?? 0)} → ${CurrencyFormatter.format((correction['newAmountPaid'] as num?) ?? 0)}',
                                  'Sebelumnya: ${((correction['previousItems'] as List?) ?? const []).map((value) {
                                    final item = CartItem.fromMap(
                                        Map<String, dynamic>.from(
                                            value as Map));
                                    return '${item.product.name}${item.drinkVariant == null ? '' : ' (${item.drinkVariant})'} × ${item.quantity}';
                                  }).join(', ')}',
                                ].join('\n')),
                              ),
                          ],
                        ),
                      for (var index = 0; index < _items.length; index++)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(_items[index].product.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      if (_items[index].drinkVariant != null)
                                        Text(
                                            'Varian: ${_items[index].drinkVariant}'),
                                      if (_items[index].customerNote != null)
                                        Text(
                                            'Catatan: ${_items[index].customerNote}'),
                                      Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            IconButton(
                                                tooltip:
                                                    'Kurangi item ${index + 1}',
                                                icon: const Icon(Icons
                                                    .remove_circle_outline),
                                                onPressed: () => setState(() {
                                                      if (_items[index]
                                                              .quantity ==
                                                          1) {
                                                        _items.removeAt(index);
                                                      } else {
                                                        _items[index]
                                                            .quantity--;
                                                      }
                                                    })),
                                            Text('${_items[index].quantity}'),
                                            IconButton(
                                                tooltip:
                                                    'Tambah jumlah item ${index + 1}',
                                                icon: const Icon(
                                                    Icons.add_circle_outline),
                                                onPressed: () => setState(() =>
                                                    _items[index].quantity++)),
                                            Text(
                                                '${CurrencyFormatter.format(_items[index].product.sellPrice)} × ${_items[index].quantity} = ${CurrencyFormatter.format(_items[index].subtotal)}'),
                                          ]),
                                    ]))),
                      OutlinedButton.icon(
                          onPressed: _addItem,
                          icon: const Icon(Icons.add),
                          label: const Text('Tambah Item')),
                      const SizedBox(height: 12),
                      Text(
                          'Total sebelumnya: ${CurrencyFormatter.format(widget.transaction.totalAmount)}'),
                      if (widget.transaction.discountAmount > 0)
                        Text(
                            'Diskon tetap: ${CurrencyFormatter.format(widget.transaction.discountAmount)}'),
                      Text(
                          'Total setelah koreksi: ${CurrencyFormatter.format(_total)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                          '$differenceLabel: ${CurrencyFormatter.format(_difference.abs())}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _payment,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: const InputDecoration(
                              labelText: 'Pembayaran akhir', prefixText: 'Rp '),
                          onChanged: (_) => setState(() {})),
                      if (double.tryParse(_payment.text) != null && _total >= 0)
                        Text(
                            'Kembalian akhir: ${CurrencyFormatter.format(((double.tryParse(_payment.text) ?? 0) - _total).clamp(0, double.infinity))}'),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _reason,
                          maxLength: 200,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                              labelText: 'Alasan koreksi',
                              hintText: 'Contoh: item terinput dua kali')),
                      if (_error != null)
                        Text(_error!,
                            style: const TextStyle(color: Colors.red)),
                    ]),
              ))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Batal')),
                ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    child: Text(_saving ? 'Menyimpan...' : 'Periksa Koreksi')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
