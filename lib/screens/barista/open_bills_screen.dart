import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/open_bill.dart';
import '../../models/cart_item.dart';
import '../../models/transaction.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/access_denied.dart';
import 'receipt_dialog.dart';

class OpenBillsScreen extends StatefulWidget {
  final String? initialBillId;
  final int selectionVersion;
  final VoidCallback? onEdit;
  final VoidCallback? onCreate;
  const OpenBillsScreen(
      {super.key,
      this.initialBillId,
      this.selectionVersion = 0,
      this.onEdit,
      this.onCreate});
  @override
  State<OpenBillsScreen> createState() => _OpenBillsScreenState();
}

class _OpenBillsScreenState extends State<OpenBillsScreen> {
  String? _selectedId;
  String _query = '';
  OpenBillQuote? _reviewed;
  TransactionRecord? _completed;
  final _paid = TextEditingController();
  final _search = TextEditingController();
  final _detailScroll = ScrollController();
  final _listScroll = ScrollController();
  final _errorKey = GlobalKey();
  String _method = 'Cash';
  bool _qrisReceived = false;
  bool _busy = false;
  String? _error;
  bool _justSaved = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialBillId;
  }

  @override
  void didUpdateWidget(covariant OpenBillsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialBillId != oldWidget.initialBillId ||
        widget.selectionVersion != oldWidget.selectionVersion) {
      _selectedId = widget.initialBillId;
      _reviewed = null;
      _completed = null;
      _error = null;
      _query = '';
      _justSaved = true;
      _search.clear();
      _toTop();
    }
  }

  @override
  void dispose() {
    _paid.dispose();
    _search.dispose();
    _detailScroll.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _select(String id) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selectedId = id;
      _reviewed = null;
      _completed = null;
      _error = null;
      _justSaved = false;
      _toTop();
    });
  }

  void _edit(PosProvider pos, OpenBill bill) {
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      if (pos.activeBillId != bill.id) pos.resumeOpenBill(bill.id);
      setState(() {
        _reviewed = null;
        _error = null;
      });
      widget.onEdit?.call();
    } catch (error) {
      _showError(_message(error));
    }
  }

  void _toTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _detailScroll.hasClients) _detailScroll.jumpTo(0);
    });
  }

  void _showError(String message) {
    setState(() => _error = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _errorKey.currentContext != null) {
        Scrollable.ensureVisible(_errorKey.currentContext!,
            duration: const Duration(milliseconds: 150), alignment: 0.1);
      }
    });
  }

  void _startPayment(PosProvider pos, String id) {
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      final quote = pos.quoteOpenBill(id);
      if (pos.activeBillId == id) {
        throw StateError(
            'Simpan perubahan pesanan di Menu sebelum membayar tagihan ini.');
      }
      setState(() {
        _reviewed = quote;
        _paid.text = quote.total.toStringAsFixed(0);
        _method = 'Cash';
        _qrisReceived = false;
        _error = null;
        _justSaved = false;
        _toTop();
      });
    } catch (error) {
      _showError(_message(error));
    }
  }

  Future<void> _pay(PosProvider pos) async {
    if (_busy || _reviewed == null) return;
    final quote = _reviewed!;
    if (_method == 'QRIS' && !_qrisReceived) {
      _showError(
          'Pastikan pembayaran QRIS sudah diterima sebelum mengonfirmasi.');
      return;
    }
    final amount =
        _method == 'QRIS' ? quote.total : double.tryParse(_paid.text);
    if (amount == null || !amount.isFinite || amount < quote.total) {
      _showError('Nominal yang diterima belum mencukupi total tagihan.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final transaction = await pos.payOpenBill(quote,
          paymentMethod: _method, amountPaid: amount);
      if (!mounted) return;
      setState(() {
        _completed = transaction;
        _reviewed = null;
        _selectedId = null;
      });
    } catch (error) {
      if (mounted) _showError(_message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(PosProvider pos, OpenBill bill) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Hapus tagihan belum dibayar?'),
              content: Text(
                  '${bill.customerName}\n\nTagihan ini akan dihapus. Tidak ada pembayaran yang dicatat.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Hapus tagihan'))
              ],
            ));
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await pos.deleteOpenBill(bill.id);
      if (mounted) {
        setState(() {
          _selectedId = null;
          _reviewed = null;
        });
      }
    } catch (error) {
      if (mounted) _showError(_message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) => error is StateError || error is ArgumentError
      ? error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('Invalid argument(s): ', '')
      : 'Tagihan belum berhasil diproses. Data tersimpan tetap tersedia; periksa kembali sebelum mencoba lagi.';

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    if (!pos.isAuthenticated || pos.requiresPasswordChange) {
      return const AccessDenied();
    }
    final bills = pos.openBills.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final selected = bills.where((bill) => bill.id == _selectedId).firstOrNull;
    final filtered = bills
        .where((bill) =>
            '${bill.customerName} ${bill.id} ${bill.items.map((item) => item.product.name).join(' ')}'
                .toLowerCase()
                .contains(_query.trim().toLowerCase()))
        .toList();
    return PopScope(
        canPop: !_busy,
        child: LayoutBuilder(builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final wide = constraints.maxWidth >= 900 * scale &&
              MediaQuery.sizeOf(context).height >= 500;
          final showDetail = _selectedId != null || _completed != null;
          return ColoredBox(
              color: AppTheme.surfaceLight,
              child: Padding(
                padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 24),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                            SizedBox(width: 330, child: _list(bills, filtered)),
                            const SizedBox(width: 24),
                            Expanded(
                                child:
                                    _details(pos, selected, showBack: false)),
                          ])
                    : showDetail
                        ? _details(pos, selected, showBack: true)
                        : _list(bills, filtered),
              ));
        }));
  }

  Widget _list(List<OpenBill> bills, List<OpenBill> filtered) =>
      CustomScrollView(
        key: const PageStorageKey('open-bills-list'),
        controller: _listScroll,
        slivers: [
          SliverToBoxAdapter(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                const Text('Open Bill',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain)),
                const SizedBox(height: 6),
                Text('${bills.length} tagihan belum dibayar',
                    style: const TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 16),
                const Text('Cari tagihan',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                    key: const ValueKey('open-bill-search'),
                    controller: _search,
                    decoration: const InputDecoration(
                        hintText: 'Pelanggan, meja, atau menu',
                        prefixIcon: Icon(Icons.search_rounded)),
                    onChanged: (value) => setState(() => _query = value)),
                const SizedBox(height: 16),
              ])),
          if (filtered.isEmpty)
            SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          size: 44, color: AppTheme.borderStrong),
                      const SizedBox(height: 12),
                      Text(
                          bills.isEmpty
                              ? 'Belum ada tagihan terbuka'
                              : 'Tagihan tidak ditemukan',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                          bills.isEmpty
                              ? 'Simpan pesanan sebagai Unpaid untuk pembayaran nanti.'
                              : 'Coba nama pelanggan, meja, atau menu lain.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppTheme.textMuted, height: 1.5)),
                      if (bills.isEmpty && widget.onCreate != null) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                            onPressed: widget.onCreate,
                            icon: const Icon(Icons.restaurant_menu_rounded),
                            label: const Text('Buka Menu'))
                      ],
                    ])),
          SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final bill = filtered[index];
                final selected = _selectedId == bill.id;
                return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: selected
                          ? AppTheme.accentCopperSoft
                          : AppTheme.cardBg,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                              color: selected
                                  ? AppTheme.accentAmber
                                  : AppTheme.borderSubtle)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('open-bill-${bill.id}'),
                        onTap: _busy ? null : () => _select(bill.id),
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(bill.customerName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: AppTheme.textMain)),
                                  const SizedBox(height: 8),
                                  _BillAmount(bill.totalAmount, size: 20),
                                  const SizedBox(height: 8),
                                  Text(
                                      '${bill.items.fold(0, (n, item) => n + item.quantity)} item \u00b7 ${bill.orderType}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary)),
                                  const SizedBox(height: 4),
                                  Text(
                                      CurrencyFormatter.formatDateTime(
                                          bill.createdAt),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textMuted)),
                                ])),
                      ),
                    ));
              }),
        ],
      );

  Widget _details(PosProvider pos, OpenBill? bill, {required bool showBack}) {
    if (_completed != null) return _success(_completed!, showBack: showBack);
    if (bill == null) {
      return Center(
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.receipt_long_outlined,
            size: 48, color: AppTheme.borderStrong),
        const SizedBox(height: 16),
        Text(
            _selectedId == null
                ? 'Pilih tagihan untuk melihat rincian'
                : 'Tagihan sudah tidak tersedia',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Periksa pesanan, lalu pilih edit atau pembayaran.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted)),
        if (showBack)
          TextButton(
              onPressed: () => setState(() {
                    _selectedId = null;
                    _reviewed = null;
                  }),
              child: const Text('Semua tagihan')),
      ])));
    }
    OpenBillQuote? current;
    String? availabilityError;
    try {
      current = pos.quoteOpenBill(bill.id);
    } catch (error) {
      availabilityError = _message(error);
    }
    final quote = _reviewed ?? current;
    final editing = pos.activeBillId == bill.id;
    final changed = _reviewed != null &&
        (current == null || _reviewed!.signature != current.signature);
    final items = quote?.items ?? bill.items;
    final content = Padding(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (showBack)
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              if (_reviewed != null) {
                                _reviewed = null;
                              } else {
                                _selectedId = null;
                              }
                              _error = null;
                            }),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text(_reviewed == null
                        ? 'Semua tagihan'
                        : 'Rincian tagihan'))),
          Text(_reviewed == null ? 'Rincian tagihan' : 'Pembayaran tagihan',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted)),
          const SizedBox(height: 8),
          Text(bill.customerName,
              maxLines: _reviewed == null ? null : 2,
              overflow: _reviewed == null ? null : TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: _reviewed == null ? 23 : 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain)),
          const SizedBox(height: 12),
          if (_reviewed == null) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              _pill('Belum dibayar'),
              _pill(bill.orderType),
              if (editing) _pill('Sedang diedit di Menu'),
            ]),
            const SizedBox(height: 12),
            Text(CurrencyFormatter.formatDateTime(bill.createdAt),
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(bill.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ] else
            Text(bill.orderType,
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          if (_justSaved) ...[
            const SizedBox(height: 16),
            _notice('Tagihan tersimpan. Pesanan ini belum masuk penjualan.')
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            KeyedSubtree(key: _errorKey, child: _notice(_error!, error: true))
          ],
          if (availabilityError != null) ...[
            const SizedBox(height: 16),
            _notice(availabilityError, error: true)
          ],
          if (changed) ...[
            const SizedBox(height: 16),
            _notice(
                'Tagihan atau harga berubah. Tinjau ulang rincian sebelum membayar.',
                error: true)
          ],
          if (_reviewed == null &&
              current != null &&
              (current.total - bill.totalAmount).abs() > 0.001) ...[
            const SizedBox(height: 16),
            _notice(
                'Harga menu berubah. Total tersimpan ${CurrencyFormatter.format(bill.totalAmount)}; total saat ini ${CurrencyFormatter.format(current.total)}.'),
          ],
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          if (_reviewed == null) ...[
            const Text('Pesanan',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 14),
            for (final item in items) _item(item),
            if ((quote?.discount ?? bill.discountAmount) > 0)
              _line('Diskon', quote?.discount ?? bill.discountAmount),
          ],
          const Text('Total tagihan',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          const SizedBox(height: 6),
          _BillAmount(quote?.total ?? bill.totalAmount, size: 30),
          const SizedBox(height: 12),
          if (_reviewed == null)
            const Text(
                'Harga dan stok diperiksa kembali sebelum pembayaran. Tagihan belum dibayar tidak dihitung sebagai penjualan.',
                style: TextStyle(
                    fontSize: 12, height: 1.5, color: AppTheme.textMuted)),
          if (editing) ...[
            const SizedBox(height: 16),
            _notice('Simpan perubahan di Menu sebelum membayar tagihan ini.')
          ],
          if (_reviewed != null) ...[
            const SizedBox(height: 20),
            _paymentForm(_reviewed!)
          ],
          if (_reviewed == null) ...[
            const SizedBox(height: 24),
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed:
                        _busy || editing ? null : () => _delete(pos, bill),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.dangerRed),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Hapus tagihan')))
          ],
        ]));
    final actions = Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.borderSubtle))),
        child: LayoutBuilder(builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final edit = OutlinedButton(
              onPressed: _busy || pos.isCheckoutInProgress
                  ? null
                  : () => _reviewed == null
                      ? _edit(pos, bill)
                      : setState(() {
                          _reviewed = null;
                          _error = null;
                          _toTop();
                        }),
              child: Text(
                  _reviewed == null
                      ? editing
                          ? 'Kembali ke Menu'
                          : 'Edit pesanan'
                      : 'Kembali',
                  style: const TextStyle(fontFamily: 'Roboto')));
          final pay = ElevatedButton(
              key: const ValueKey('open-bill-pay'),
              onPressed: _busy ||
                      pos.isCheckoutInProgress ||
                      editing ||
                      current == null ||
                      changed
                  ? null
                  : () => _reviewed == null
                      ? _startPayment(pos, bill.id)
                      : _pay(pos),
              child: Text(
                  _busy
                      ? 'Menyimpan...'
                      : _reviewed == null
                          ? 'Bayar tagihan'
                          : 'Konfirmasi pembayaran',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Roboto')));
          if (constraints.maxWidth < 430 * scale) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [pay, const SizedBox(height: 8), edit]);
          }
          return Row(children: [
            Expanded(child: edit),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: pay)
          ]);
        }));
    return Material(
      color: AppTheme.cardBg,
      shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppTheme.borderSubtle),
          borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        // Keep the payment field in the same scroll tree while the IME resizes
        // the available height. Narrow windows use one continuous scroll area.
        if (constraints.maxWidth < 430 * scale || MediaQuery.sizeOf(context).height < 700 * scale) {
          return SingleChildScrollView(
              controller: _detailScroll,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [content, actions]));
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: SingleChildScrollView(
                      controller: _detailScroll, child: content)),
              actions,
            ]);
      }),
    );
  }

  Widget _paymentForm(OpenBillQuote quote) => AbsorbPointer(
      absorbing: _busy,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Metode pembayaran',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final method in ['Cash', 'QRIS'])
            ChoiceChip(
              label: Text(method),
              selected: _method == method,
              selectedColor: AppTheme.accentCopperSoft,
              labelStyle: const TextStyle(
                  color: AppTheme.textMain, fontFamily: 'Roboto'),
              checkmarkColor: AppTheme.accentAmber,
              onSelected: (_) => setState(() {
                _method = method;
                _error = null;
                _qrisReceived = false;
              }),
            )
        ]),
        const SizedBox(height: 18),
        if (_method == 'Cash') ...[
          const Text('Uang diterima',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
              key: const ValueKey('open-bill-cash'),
              controller: _paid,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  prefixIcon:
                      Padding(padding: EdgeInsets.all(14), child: Text('Rp'))),
              onChanged: (_) => setState(() => _error = null)),
          const SizedBox(height: 10),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: () => setState(
                      () => _paid.text = quote.total.toStringAsFixed(0)),
                  child: const Text('Uang pas',
                      style: TextStyle(fontFamily: 'Roboto')))),
          _line(
              'Kembalian',
              ((double.tryParse(_paid.text) ?? 0) - quote.total)
                  .clamp(0, double.infinity)
                  .toDouble()),
        ] else
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Pembayaran QRIS sudah diterima',
                  style: TextStyle(fontSize: 14)),
              value: _qrisReceived,
              onChanged: (value) =>
                  setState(() => _qrisReceived = value ?? false)),
        const SizedBox(height: 12),
        const Text(
            'Konfirmasi setelah uang atau pembayaran QRIS benar-benar diterima.',
            style: TextStyle(
                fontSize: 12, height: 1.5, color: AppTheme.textMuted)),
      ]));

  Widget _success(TransactionRecord transaction, {required bool showBack}) =>
      SingleChildScrollView(
          child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderSubtle)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.check_circle_outline_rounded,
              size: 48, color: AppTheme.successGreen),
          const SizedBox(height: 16),
          const Text('Tagihan sudah dibayar',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(transaction.customerName ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          _BillAmount(transaction.totalAmount, size: 30),
          const SizedBox(height: 12),
          Text(
              '${transaction.paymentMethod} \u00b7 ${transaction.invoiceNumber}',
              style: const TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 20),
          _line('Kembalian', transaction.changeAmount),
          const SizedBox(height: 16),
          ElevatedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ReceiptDialog(transaction: transaction)),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Lihat struk')),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: () => setState(() {
                    _completed = null;
                    _selectedId = null;
                    _error = null;
                    _query = '';
                    _search.clear();
                  }),
              child: const Text('Tagihan berikutnya')),
        ]),
      ));

  Widget _item(CartItem item) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${item.quantity}\u00d7 ${item.product.name}',
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, height: 1.5)),
        if (item.drinkVariant != null)
          Text('Varian: ${item.drinkVariant}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        if (item.customerNote != null)
          Text(item.customerNote!,
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        _BillAmount(item.subtotal, size: 15),
      ]));
  Widget _line(String label, double amount) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        _BillAmount(amount, size: 16),
      ]));
  Widget _pill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
          color: AppTheme.accentCopperSoft,
          borderRadius: BorderRadius.circular(8)),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentAmber)));
  Widget _notice(String text, {bool error = false}) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: error ? AppTheme.dangerLight : AppTheme.accentCopperSoft,
          borderRadius: BorderRadius.circular(10)),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: error ? AppTheme.dangerRed : AppTheme.textSecondary)));
}

class _BillAmount extends StatelessWidget {
  final double amount;
  final double size;
  const _BillAmount(this.amount, {this.size = 18});
  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(CurrencyFormatter.format(amount),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                  fontFeatures: AppTheme.tabularFigures))));
}
