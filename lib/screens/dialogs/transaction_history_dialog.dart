import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/cart_item.dart';
import '../../models/product.dart';
import '../../models/transaction.dart';
import '../../providers/pos_provider.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/access_denied.dart';
import '../../theme/app_theme.dart';
import '../../models/user_role.dart';
import 'delete_transaction_dialog.dart';

class TransactionHistoryDialog extends StatelessWidget {
  const TransactionHistoryDialog({super.key});

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 760),
      child: Column(children: [
        Align(alignment: Alignment.centerRight, child: IconButton(
          tooltip: 'Tutup riwayat', icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context))),
        const Expanded(child: TransactionHistoryView()),
      ]),
    ),
  );
}

class TransactionHistoryView extends StatefulWidget {
  const TransactionHistoryView({super.key});
  @override
  State<TransactionHistoryView> createState() => _TransactionHistoryViewState();
}

class _TransactionHistoryViewState extends State<TransactionHistoryView> {
  String _query = '';
  String _filter = 'Semua';

  Future<void> _correct(TransactionRecord transaction) async {
    await showDialog<bool>(context: context, barrierDismissible: false,
      builder: (_) => CorrectTransactionDialog(transaction: transaction));
  }

  Future<void> _details(TransactionRecord transaction) async {
    final action = await showDialog<String>(context: context, builder: (dialogContext) {
      final pos = dialogContext.watch<PosProvider>();
      if (!pos.isAuthenticated || pos.requiresPasswordChange) return const AccessDenied();
      final tx = [...pos.transactions, ...pos.deletedTransactions].where((t) => t.id == transaction.id).firstOrNull;
      if (tx == null) return const AccessDenied();
      return AlertDialog(
        title: const Text('Detail Transaksi'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SelectableText(tx.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(CurrencyFormatter.formatDateTime(tx.createdAt), style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 8),
            Text('${tx.cashierName} \u00b7 ${tx.orderType} \u00b7 ${tx.paymentMethod}'),
            if (tx.customerName != null) Text('Pelanggan / meja: ${tx.customerName}'),
            const Divider(height: 28),
            for (final item in tx.items) Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (item.drinkVariant != null) Text('Varian: ${item.drinkVariant}'),
                if (item.customerNote != null) Text('Catatan: ${item.customerNote}'),
                Text('${item.quantity} \u00d7 ${CurrencyFormatter.format(item.product.sellPrice)} = ${CurrencyFormatter.format(item.subtotal)}'),
              ])),
            if (tx.discountAmount > 0) Text('Diskon: ${CurrencyFormatter.format(tx.discountAmount)}'),
            const Divider(),
            Text('Total: ${CurrencyFormatter.format(tx.totalAmount)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('Pembayaran: ${CurrencyFormatter.format(tx.amountPaid)}'),
            Text('Kembalian: ${CurrencyFormatter.format(tx.changeAmount)}'),
            if (tx.isDeleted) ...[
              const Divider(height: 28),
              const Text('Transaksi dihapus', style: TextStyle(color: AppTheme.dangerRed, fontWeight: FontWeight.w700)),
              Text('Dihapus oleh: ${tx.deletedByName ?? "Tidak tersedia"}'),
              if (tx.deletedAt != null) Text(CurrencyFormatter.formatDateTime(tx.deletedAt!)),
              Text('Alasan: ${tx.deletionReason ?? "Tidak tersedia"}'),
            ],
            const SizedBox(height: 12),
            Text(tx.isDeleted ? tx.isSynced ? 'Penghapusan tersinkron' : 'Penghapusan menunggu sinkronisasi otomatis'
              : tx.isVoided ? 'Transaksi dibatalkan' : tx.isSynced ? 'Tersinkron' : 'Menunggu sinkronisasi otomatis',
              style: const TextStyle(color: AppTheme.textMuted)),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup')),
          if (pos.canCorrectTransaction(tx)) ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'edit'),
            icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Koreksi Transaksi')),
          if (pos.currentRole.canDeleteTransactions && !tx.isDeleted) TextButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'delete'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.dangerRed),
            icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('Hapus transaksi')),
        ],
      );
    });
    if (mounted && action == 'edit') await _correct(transaction);
    if (mounted && action == 'delete') await showDeleteTransactionDialog(context, transaction);
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    if (!pos.isAuthenticated || pos.requiresPasswordChange) return const AccessDenied();
    final today = DateTime.now();
    final query = _query.trim().toLowerCase();
    final showDeleted = _filter == 'Terhapus' && pos.currentRole.canDeleteTransactions;
    final transactions = (showDeleted ? pos.deletedTransactions : pos.transactions).where((tx) {
      final sameDay = tx.createdAt.year == today.year && tx.createdAt.month == today.month && tx.createdAt.day == today.day;
      final matchesFilter = showDeleted || _filter == 'Semua' || (_filter == 'Hari Ini' && sameDay) || (_filter == 'Bisa Diedit' && pos.canCorrectTransaction(tx));
      final search = '${tx.invoiceNumber} ${tx.customerName ?? ''} ${tx.items.map((i) => i.product.name).join(' ')}'.toLowerCase();
      return matchesFilter && (query.isEmpty || search.contains(query));
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return LayoutBuilder(builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final compact = constraints.maxWidth < 760 * scale || MediaQuery.sizeOf(context).height < 400;
      final padding = compact ? 16.0 : 24.0;
      return ColoredBox(color: AppTheme.surfaceLight, child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1160),
        child: CustomScrollView(key: const PageStorageKey('transaction-history-scroll'), slivers: [
          SliverPadding(padding: EdgeInsets.fromLTRB(padding, padding, padding, 16), sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Riwayat Transaksi', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textMain)),
              const SizedBox(height: 4),
              Text(pos.currentRole.canViewFinancialReports ? 'Telusuri penjualan dan periksa transaksi.' : 'Periksa pesanan Anda dan koreksi jika ada kesalahan input.',
                style: const TextStyle(color: AppTheme.textSecondary, height: 1.5)),
              const SizedBox(height: 18),
              _HistoryInput(id: 'transaction-search', label: 'Cari transaksi', hint: 'Invoice, pelanggan, atau nama menu',
                prefix: const Icon(Icons.search_rounded),
                onChanged: (value) => setState(() => _query = value)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [for (final filter in ['Semua', 'Hari Ini', 'Bisa Diedit', if (pos.currentRole.canDeleteTransactions) 'Terhapus'])
                ChoiceChip(label: Text(filter), selected: _filter == filter, showCheckmark: false,
                  selectedColor: AppTheme.accentCopperSoft,
                  labelStyle: TextStyle(color: _filter == filter ? AppTheme.accentAmber : AppTheme.textSecondary,
                    fontWeight: _filter == filter ? FontWeight.w800 : FontWeight.w500),
                  side: BorderSide(color: _filter == filter ? AppTheme.accentAmber : AppTheme.borderSubtle),
                  onSelected: (_) => setState(() => _filter = filter)),
              ]),
              const SizedBox(height: 12),
              Text(showDeleted ? '${transactions.length} transaksi dihapus; tidak dihitung dalam penjualan' : '${transactions.length} transaksi ditampilkan dari riwayat perangkat', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ]),
          )),
          if (transactions.isEmpty) SliverFillRemaining(hasScrollBody: false, child: Padding(
            padding: EdgeInsets.all(padding), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.receipt_long_outlined, size: 46, color: AppTheme.borderStrong),
              const SizedBox(height: 12),
              Text(showDeleted ? 'Belum ada transaksi terhapus yang cocok.' : pos.transactions.isEmpty ? 'Belum ada transaksi.' : 'Transaksi tidak ditemukan.',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(pos.transactions.isEmpty ? 'Pesanan yang sudah dibayar akan muncul di sini.' : 'Coba kata pencarian atau filter lain.',
                textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted)),
            ]))),
          SliverPadding(padding: EdgeInsets.fromLTRB(padding, 0, padding, padding), sliver: SliverList.builder(
            itemCount: transactions.length, itemBuilder: (context, index) {
              final tx = transactions[index];
              final previous = index == 0 ? null : transactions[index - 1].createdAt;
              final newDay = previous == null || previous.year != tx.createdAt.year || previous.month != tx.createdAt.month || previous.day != tx.createdAt.day;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (newDay) Padding(padding: const EdgeInsets.only(top: 8, bottom: 10), child: Text(
                  CurrencyFormatter.formatDateOnly(tx.createdAt), style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
                _transactionRow(tx, pos, compact),
              ]);
            },
          )),
        ]),
      )));
    });
  }

  Widget _transactionRow(TransactionRecord tx, PosProvider pos, bool compact) {
    final canEdit = pos.canCorrectTransaction(tx);
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Material(
      color: AppTheme.cardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.borderSubtle)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: () => _details(tx), child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: AppTheme.surfaceSubtle, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.receipt_long_outlined, size: 20, color: AppTheme.accentAmber)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Tooltip(message: tx.invoiceNumber, child: Text(tx.invoiceNumber, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textMain))),
              const SizedBox(height: 4),
              Text(CurrencyFormatter.formatTimeOnly(tx.createdAt), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ])),
            if (!compact) ...[const SizedBox(width: 16), SizedBox(width: 230, child: _HistoryAmount(tx.totalAmount, fontSize: 19))],
          ]),
          const SizedBox(height: 12),
          if (compact) Padding(padding: const EdgeInsets.only(bottom: 10),
            child: _HistoryAmount(tx.totalAmount, fontSize: 22, alignment: Alignment.centerLeft)),
          Text(tx.items.map((i) => '${i.quantity}\u00d7 ${i.product.name}${i.drinkVariant == null ? '' : ' (${i.drinkVariant})'}').join(' \u00b7 '),
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textSecondary, height: 1.45)),
          if (tx.customerName != null) Padding(padding: const EdgeInsets.only(top: 4), child: Tooltip(message: tx.customerName!,
            child: Text('Pelanggan / meja: ${tx.customerName}', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textSecondary)))),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _HistoryPill(tx.isDeleted ? 'Dihapus' : tx.isVoided ? 'Dibatalkan' : 'Lunas', color: tx.isVoided ? AppTheme.dangerRed : AppTheme.successGreen,
              background: tx.isVoided ? AppTheme.dangerLight : AppTheme.successGreenLight),
            _HistoryPill('${tx.orderType} \u00b7 ${tx.paymentMethod}'),
            if (!tx.isSynced) const _HistoryPill('Menunggu sinkronisasi', color: AppTheme.warningOrange, background: AppTheme.warningLight),
            if (!tx.isDeleted && tx.revision > 0) _HistoryPill('Dikoreksi ${tx.revision}x'),
          ]),
          if (tx.isDeleted) Padding(padding: const EdgeInsets.only(top: 8), child: Text(
            'Dihapus oleh ${tx.deletedByName ?? "Tidak tersedia"}\nAlasan: ${tx.deletionReason ?? "Tidak tersedia"}',
            style: const TextStyle(fontSize: 12, height: 1.5, color: AppTheme.textSecondary))),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final detail = TextButton.icon(onPressed: () => _details(tx), icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text('Lihat detail', maxLines: 1, style: TextStyle(fontFamily: 'Roboto')));
            final correction = canEdit ? OutlinedButton.icon(onPressed: () => _correct(tx),
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Koreksi', maxLines: 1, style: TextStyle(fontFamily: 'Roboto')))
              : Text(tx.isVoided ? 'Transaksi dibatalkan' : 'Edit tidak tersedia',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted));
            final deletion = pos.currentRole.canDeleteTransactions && !tx.isDeleted ? TextButton.icon(
              key: ValueKey('delete-transaction-${tx.id}'), onPressed: () => showDeleteTransactionDialog(context, tx),
              style: TextButton.styleFrom(foregroundColor: AppTheme.dangerRed), icon: const Icon(Icons.delete_outline_rounded, size: 17),
              label: const Text('Hapus', maxLines: 1, style: TextStyle(fontFamily: 'Roboto'))) : null;
            if (constraints.maxWidth < (deletion == null ? 380 : 540) * scale) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                detail, const SizedBox(height: 8), correction,
                if (deletion != null) ...[const SizedBox(height: 8), deletion],
              ]);
            }
            return Row(children: [detail, const Spacer(), const SizedBox(width: 16), correction,
              if (deletion != null) ...[const SizedBox(width: 12), deletion]]);
          }),
          if (canEdit && pos.currentRole == UserRole.barista) Padding(padding: const EdgeInsets.only(top: 6), child: Text(
            'Bisa diedit hingga ${CurrencyFormatter.formatDateTime(tx.createdAt.add(const Duration(hours: 24)))}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))),
        ],
      ))),
    ));
  }
}

class _HistoryPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  const _HistoryPill(this.label, {this.color = AppTheme.textSecondary, this.background = AppTheme.surfaceSubtle});
  @override
  Widget build(BuildContext context) => Tooltip(message: label, child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(7)),
    child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600))));
}

class _HistoryInput extends StatelessWidget {
  final String id;
  final String label;
  final String? hint;
  final String? helper;
  final String? error;
  final TextEditingController? controller;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final Widget? prefix;
  final int? minLines;
  final int maxLines;
  final int? maxLength;
  const _HistoryInput({super.key, required this.id, required this.label, required this.onChanged,
    this.hint, this.helper, this.error, this.controller, this.keyboardType, this.formatters,
    this.prefix, this.minLines, this.maxLines = 1, this.maxLength});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(label, key: ValueKey('$id-label'), style: const TextStyle(fontSize: 13,
      fontWeight: FontWeight.w700, height: 1.4, color: AppTheme.textMain)),
    const SizedBox(height: 8),
    Semantics(label: label, child: TextField(key: ValueKey('$id-input'), controller: controller,
      keyboardType: keyboardType, inputFormatters: formatters,
      minLines: minLines, maxLines: maxLines, maxLength: maxLength,
      textCapitalization: maxLines > 1 ? TextCapitalization.sentences : TextCapitalization.none,
      style: const TextStyle(fontSize: 14, height: 1.5, color: AppTheme.textMain),
      decoration: InputDecoration(hintText: hint, prefixIcon: prefix,
        filled: true, fillColor: AppTheme.cardBg, isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        counterText: maxLength == null ? null : '',
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: error == null ? AppTheme.borderStrong : AppTheme.dangerRed)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: error == null ? AppTheme.accentAmber : AppTheme.dangerRed, width: 1.5)),
      ), onChanged: onChanged)),
    if (helper != null || maxLength != null) ...[
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(helper ?? '', style: const TextStyle(fontSize: 12,
          height: 1.5, color: AppTheme.textMuted))),
        if (maxLength != null) ...[const SizedBox(width: 12), Text('${controller?.text.length ?? 0}/$maxLength',
          style: const TextStyle(fontSize: 11, height: 1.6, color: AppTheme.textMuted))],
      ]),
    ],
    if (error != null) ...[const SizedBox(height: 6), Semantics(liveRegion: true,
      child: Text(error!, style: const TextStyle(fontSize: 12, height: 1.5, color: AppTheme.dangerRed)))],
  ]);
}

class _HistoryAmount extends StatelessWidget {
  final double amount;
  final double fontSize;
  final Alignment alignment;
  const _HistoryAmount(this.amount, {this.fontSize = 16, this.alignment = Alignment.centerRight});
  @override
  Widget build(BuildContext context) => Align(alignment: alignment, child: FittedBox(fit: BoxFit.scaleDown,
    alignment: alignment, child: Text(CurrencyFormatter.format(amount), maxLines: 1, softWrap: false,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800,
        color: AppTheme.textMain, fontFeatures: AppTheme.tabularFigures))));
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
  bool _showErrors = false;
  final _itemsKey = GlobalKey();
  final _paymentKey = GlobalKey();
  final _reasonKey = GlobalKey();
  final _itemsScroll = ScrollController();
  final _paymentScroll = ScrollController();
  final _formScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _items = widget.transaction.items.map((item) => item.copyWith()).toList();
    _payment = TextEditingController(
        text: widget.transaction.amountPaid.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _itemsScroll.dispose();
    _paymentScroll.dispose();
    _formScroll.dispose();
    _payment.dispose();
    _reason.dispose();
    super.dispose();
  }

  double get _subtotal => _items.fold(0, (sum, item) => sum + item.subtotal);
  double get _total => _subtotal - widget.transaction.discountAmount;
  double get _difference => _total - widget.transaction.totalAmount;

  String? get _paymentError {
    final amount = double.tryParse(_payment.text.trim());
    if (amount == null || !amount.isFinite) return 'Isi nominal pembayaran yang valid.';
    if (amount < _total) return 'Pembayaran kurang dari total setelah koreksi.';
    if (widget.transaction.paymentMethod == 'QRIS' && amount != _total) return 'Pembayaran QRIS harus sama dengan total.';
    return null;
  }

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
          return Dialog(insetPadding: const EdgeInsets.all(16), child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
            child: Padding(padding: const EdgeInsets.all(18), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [const Expanded(child: Text('Tambah Item', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  IconButton(tooltip: 'Tutup daftar menu', onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded))]),
                const SizedBox(height: 12),
                _HistoryInput(id: 'correction-menu-search', label: 'Cari menu', prefix: const Icon(Icons.search_rounded),
                  onChanged: (value) => setDialogState(() => query = value)),
                const SizedBox(height: 12),
                Expanded(child: products.isEmpty ? const Center(child: Text('Menu tidak ditemukan.')) : ListView.separated(
                  itemCount: products.length, separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) => ListTile(contentPadding: EdgeInsets.zero,
                    title: Text(products[index].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(CurrencyFormatter.format(products[index].sellPrice)),
                    trailing: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.accentAmber),
                    onTap: () => Navigator.pop(dialogContext, products[index])),
                )),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal'))),
              ],
            )),
          ));
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
      setState(() {
        _showErrors = true;
        _error = _items.isEmpty ? 'Tambahkan minimal satu item pesanan.'
            : _total < 0 ? 'Total item tidak boleh lebih kecil dari diskon.'
            : _reason.text.trim().isEmpty ? 'Isi alasan koreksi sebelum melanjutkan.' : _paymentError;
      });
      final target = _items.isEmpty || _total < 0 ? _itemsKey : _reason.text.trim().isEmpty ? _reasonKey : _paymentKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && target.currentContext != null) {
          Scrollable.ensureVisible(target.currentContext!, duration: const Duration(milliseconds: 180), alignment: 0.15);
        }
      });
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
          _error = error is StateError || error is ArgumentError
              ? error.toString().replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', '')
              : 'Koreksi belum dapat dipastikan. Periksa koneksi dan buka kembali riwayat sebelum mencoba lagi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    if (!pos.isAuthenticated || pos.requiresPasswordChange ||
        !pos.transactions.any((tx) => tx.id == widget.transaction.id && pos.canCorrectTransaction(tx))) {
      return const AccessDenied();
    }
    return PopScope(canPop: !_saving, child: Dialog(
      insetPadding: const EdgeInsets.all(16), clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 880),
        child: LayoutBuilder(builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final inset = constraints.maxWidth < 500 ? 16.0 : 24.0;
          final wide = constraints.maxWidth - inset * 2 >= 700 * scale && MediaQuery.sizeOf(context).height >= 532;
          final tiny = constraints.maxHeight < 260;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: EdgeInsets.fromLTRB(inset, tiny ? 8 : 16, inset, tiny ? 8 : 16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Koreksi Transaksi', style: TextStyle(fontSize: tiny ? 16 : 20,
                    fontWeight: FontWeight.w800, height: 1.25, color: AppTheme.textMain))),
                  const SizedBox(width: 12),
                  IconButton(tooltip: 'Tutup koreksi', onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded), visualDensity: VisualDensity.compact),
                ]),
                if (!tiny) Tooltip(message: widget.transaction.invoiceNumber, child: Text(widget.transaction.invoiceNumber,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.5, color: AppTheme.textMuted))),
              ])),
            const Divider(height: 1),
            Expanded(child: ColoredBox(color: AppTheme.surfaceLight, child: AbsorbPointer(absorbing: _saving,
              child: _correctionBody(pos, wide: wide, inset: inset)))),
            _footer(wide: wide, inset: inset, scale: scale),
          ]);
        }),
      ),
    ));
  }

  Widget _correctionBody(PosProvider pos, {required bool wide, required double inset}) {
    final notice = _notice(pos.currentRole == UserRole.barista
      ? 'Batas koreksi: ${CurrencyFormatter.formatDateTime(widget.transaction.createdAt.add(const Duration(hours: 24)))}. Transaksi awal tetap tercatat.'
      : 'Transaksi awal tetap tercatat dalam riwayat koreksi. Alasan perubahan wajib diisi.');
    if (wide) {
      return ScrollbarTheme(data: ScrollbarTheme.of(context).copyWith(
        thumbColor: const WidgetStatePropertyAll(AppTheme.borderStrong),
        thickness: const WidgetStatePropertyAll(3), radius: const Radius.circular(4)),
        child: Padding(padding: EdgeInsets.all(inset), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        notice, const SizedBox(height: 20),
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Scrollbar(controller: _itemsScroll, thumbVisibility: true, child: SingleChildScrollView(
            key: const ValueKey('correction-items-scroll'), controller: _itemsScroll,
            padding: const EdgeInsets.only(right: 6, bottom: 8), child: _itemSection()))),
          const SizedBox(width: 18),
          Expanded(child: Scrollbar(controller: _paymentScroll, thumbVisibility: true, child: SingleChildScrollView(
            key: const ValueKey('correction-payment-scroll'), controller: _paymentScroll,
            padding: const EdgeInsets.only(right: 6, bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: _notice(_error!, isError: true)),
              _paymentSection(),
              if (widget.transaction.corrections.isNotEmpty) ...[const SizedBox(height: 24), _auditSection()],
            ])))),
        ])),
      ])));
    }
    return Scrollbar(controller: _formScroll, child: SingleChildScrollView(controller: _formScroll,
      padding: EdgeInsets.all(inset), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        notice, const SizedBox(height: 20),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: _notice(_error!, isError: true)),
        _itemSection(), const SizedBox(height: 24), _paymentSection(),
        if (widget.transaction.corrections.isNotEmpty) ...[const SizedBox(height: 24), _auditSection()],
      ])));
  }

  Widget _footer({required bool wide, required double inset, required double scale}) => Container(
    key: const ValueKey('correction-footer'), padding: EdgeInsets.symmetric(horizontal: inset, vertical: 12),
    decoration: const BoxDecoration(color: AppTheme.cardBg, border: Border(top: BorderSide(color: AppTheme.borderSubtle))),
    child: LayoutBuilder(builder: (context, constraints) {
      final cancel = OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Batal', maxLines: 1, style: TextStyle(fontFamily: 'Roboto', fontSize: 13, fontWeight: FontWeight.w700)));
      if (constraints.maxWidth < 340 && scale > 1.2) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _reviewButton(), const SizedBox(height: 8), cancel,
        ]);
      }
      return Row(children: [
        if (wide && scale <= 1.2) Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total setelah koreksi', style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.textMuted)),
          const SizedBox(height: 4),
          _HistoryAmount(_total, fontSize: 20, alignment: Alignment.centerLeft),
        ])),
        if (!wide || scale > 1.2) ...[Expanded(child: cancel), const SizedBox(width: 12), Expanded(flex: 2, child: _reviewButton())]
        else ...[SizedBox(width: 120, child: cancel), const SizedBox(width: 12), SizedBox(width: 180, child: _reviewButton())],
      ]);
    }),
  );

  Widget _reviewButton() => ElevatedButton(
    style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
    onPressed: _saving ? null : () { FocusManager.instance.primaryFocus?.unfocus(); _submit(); },
    child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
      : const Text('Periksa Koreksi', maxLines: 1, softWrap: false, textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Roboto', fontSize: 13, fontWeight: FontWeight.w700)),
  );

  Widget _sectionHeading(String title, {Widget? trailing}) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 30), child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
        height: 1.4, color: AppTheme.textMain))),
      if (trailing != null) ...[const SizedBox(width: 12), trailing],
    ]));

  Widget _notice(String text, {bool isError = false}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: isError ? AppTheme.dangerLight : AppTheme.accentCopperSoft, borderRadius: BorderRadius.circular(10)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
        size: 18, color: isError ? AppTheme.dangerRed : AppTheme.accentAmber),
      const SizedBox(width: 9),
      Expanded(child: Text(text, style: TextStyle(fontSize: 12, height: 1.5,
        color: isError ? AppTheme.dangerRed : AppTheme.textSecondary))),
    ]),
  );

  Widget _panel({Key? key, required Widget child}) => Container(key: key, width: double.infinity, padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.borderSubtle)), child: child);

  Widget _itemSection() => Column(key: _itemsKey, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _sectionHeading('Item pesanan', trailing: _HistoryPill('${_items.length} item')),
    const SizedBox(height: 12),
    if (_items.isEmpty) _panel(child: const Text('Belum ada item. Tambahkan menu agar transaksi dapat disimpan.',
      style: TextStyle(color: AppTheme.textMuted))),
    for (var index = 0; index < _items.length; index++) Padding(padding: const EdgeInsets.only(bottom: 12),
      child: _itemRow(index)),
    OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), backgroundColor: AppTheme.cardBg),
      onPressed: _addItem, icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Tambah Item')),
  ]);

  Widget _itemRow(int index) {
    final item = _items[index];
    return _panel(key: ValueKey('correction-item-$index'), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(item.product.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.4, color: AppTheme.textMain))),
        const SizedBox(width: 8),
        IconButton(tooltip: 'Hapus item ${index + 1}', key: ValueKey('remove-correction-item-$index'),
          visualDensity: VisualDensity.compact, color: AppTheme.dangerRed,
          onPressed: () => setState(() { _items.removeAt(index); _error = null; }),
          icon: const Icon(Icons.delete_outline_rounded, size: 18)),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (item.drinkVariant != null) _HistoryPill('Varian: ${item.drinkVariant}'),
        Text('${CurrencyFormatter.format(item.product.sellPrice)} / ${item.product.unitLabel}',
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      ]),
      if (item.customerNote != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Catatan: ${item.customerNote}',
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final controls = Container(decoration: BoxDecoration(color: AppTheme.surfaceLight,
          border: Border.all(color: AppTheme.borderSubtle), borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Kurangi item ${index + 1}', icon: const Icon(Icons.remove_rounded, size: 18),
              onPressed: item.quantity <= 1 ? null : () => setState(() { item.quantity--; _error = null; })),
            ConstrainedBox(constraints: const BoxConstraints(minWidth: 32), child: Text('${item.quantity}', textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, fontFeatures: AppTheme.tabularFigures))),
            IconButton(tooltip: 'Tambah jumlah item ${index + 1}', icon: const Icon(Icons.add_rounded, size: 18),
              onPressed: () => setState(() { item.quantity++; _error = null; })),
          ]));
        if (constraints.maxWidth < 320 * scale) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.centerLeft, child: controls), const SizedBox(height: 12),
            _HistoryAmount(item.subtotal),
          ]);
        }
        return Row(children: [controls, const SizedBox(width: 16), Expanded(child: _HistoryAmount(item.subtotal))]);
      }),
    ]));
  }

  Widget _paymentSection() {
    final differenceLabel = _difference > 0 ? 'Tambahan yang ditagih' : _difference < 0 ? 'Pengembalian kepada pelanggan' : 'Selisih';
    final amount = double.tryParse(_payment.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionHeading('Ringkasan koreksi'), const SizedBox(height: 12),
      _panel(key: const ValueKey('correction-summary'), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _moneyRow('Total sebelumnya', widget.transaction.totalAmount),
        if (widget.transaction.discountAmount > 0) _moneyRow('Diskon tetap', widget.transaction.discountAmount),
        const Divider(height: 20),
        _moneyRow('Total setelah koreksi', _total, emphasized: true),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(
          color: _difference == 0 ? AppTheme.surfaceSubtle : AppTheme.warningLight, borderRadius: BorderRadius.circular(10)),
          child: Text('$differenceLabel: ${CurrencyFormatter.format(_difference.abs())}', style: TextStyle(fontSize: 13,
            height: 1.5, fontWeight: FontWeight.w700, color: _difference == 0 ? AppTheme.textSecondary : AppTheme.warningOrange))),
      ])),
      const SizedBox(height: 24),
      _sectionHeading('Pembayaran & alasan'), const SizedBox(height: 12),
      _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _HistoryInput(key: _paymentKey, id: 'correction-payment', label: 'Pembayaran akhir', controller: _payment,
          keyboardType: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly],
          prefix: const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Center(widthFactor: 1,
            child: Text('Rp', style: TextStyle(fontSize: 14, color: AppTheme.textMuted)))),
          helper: widget.transaction.paymentMethod == 'QRIS' ? 'QRIS harus sama dengan total setelah koreksi.' : 'Nominal yang diterima setelah koreksi.',
          error: _showErrors ? _paymentError : null, onChanged: (_) => setState(() => _error = null)),
        if (amount != null && _total >= 0) ...[const SizedBox(height: 12),
          _moneyRow('Kembalian akhir', (amount - _total).clamp(0, double.infinity).toDouble())],
        const SizedBox(height: 24),
        _HistoryInput(key: _reasonKey, id: 'correction-reason', label: 'Alasan koreksi', controller: _reason,
          maxLength: 200, minLines: 2, maxLines: 3, hint: 'Contoh: item terinput dua kali',
          helper: 'Wajib diisi. Alasan dicatat dalam riwayat transaksi.',
          error: _showErrors && _reason.text.trim().isEmpty ? 'Alasan koreksi wajib diisi.' : null,
          onChanged: (_) => setState(() => _error = null)),
      ])),
    ]);
  }

  Widget _moneyRow(String label, double amount, {bool emphasized = false}) => Padding(padding: const EdgeInsets.only(bottom: 8),
    child: LayoutBuilder(builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
      final labelWidget = Text(label, style: TextStyle(fontSize: emphasized ? 13 : 12, height: 1.5,
        fontWeight: emphasized ? FontWeight.w700 : FontWeight.w400,
        color: emphasized ? AppTheme.textMain : AppTheme.textMuted));
      if (constraints.maxWidth < 300 * scale) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          labelWidget, const SizedBox(height: 6), _HistoryAmount(amount, fontSize: emphasized ? 24 : 14),
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: labelWidget), const SizedBox(width: 16),
        Expanded(child: _HistoryAmount(amount, fontSize: emphasized ? 24 : 14)),
      ]);
    }));

  Widget _auditSection() => _panel(child: ExpansionTile(tilePadding: EdgeInsets.zero, childrenPadding: EdgeInsets.zero,
    title: Text('Riwayat koreksi (${widget.transaction.corrections.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    children: [for (final correction in widget.transaction.corrections.reversed) Padding(padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Revisi ${correction['revision']} \u00b7 ${correction['correctedBy']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text([
          'Alasan: ${correction['reason']}', 'Waktu: ${correction['correctedAt']}',
          'Total: ${CurrencyFormatter.format((correction['previousTotal'] as num?) ?? 0)} \u2192 ${CurrencyFormatter.format((correction['newTotal'] as num?) ?? 0)}',
          'Pembayaran: ${CurrencyFormatter.format((correction['previousAmountPaid'] as num?) ?? 0)} \u2192 ${CurrencyFormatter.format((correction['newAmountPaid'] as num?) ?? 0)}',
          'Sebelumnya: ${((correction['previousItems'] as List?) ?? const []).map((value) {
            final item = CartItem.fromMap(Map<String, dynamic>.from(value as Map));
            return '${item.product.name}${item.drinkVariant == null ? '' : ' (${item.drinkVariant})'} \u00d7 ${item.quantity}';
          }).join(', ')}',
        ].join('\n'), style: const TextStyle(fontSize: 12, height: 1.5, color: AppTheme.textSecondary)),
      ]))],
  ));
}
