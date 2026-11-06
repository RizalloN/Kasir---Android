import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/cart_item.dart';
import '../../models/user_role.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_formatter.dart';
import 'receipt_dialog.dart';

class CartBottomSheet extends StatefulWidget {
  final bool isTabletSidebar;

  const CartBottomSheet({
    super.key,
    this.isTabletSidebar = false,
  });

  @override
  State<CartBottomSheet> createState() => _CartBottomSheetState();
}

class _CartBottomSheetState extends State<CartBottomSheet> {
  String _selectedPaymentMethod = 'Cash';
  bool _isExactCash = true;
  double _customCashPaid = 0.0;
  bool _checkingOut = false;
  final TextEditingController _customerController = TextEditingController();

  static const List<String> _notePresets = [
    'Less Sugar',
    'Normal Sugar',
    'Less Ice',
    'Extra Ice',
    'Panas (Hot)',
    'Pisah Es',
  ];

  static const List<String> _entertainmentNotePresets = [
    'TV 1',
    'TV 2',
    'TV 3',
    'TV 4',
    'Tambah Stik',
    'Bayar di Awal',
  ];

  @override
  void initState() {
    super.initState();
    final pos = context.read<PosProvider>();
    _customerController.text = pos.customerName;
  }

  @override
  void dispose() {
    _customerController.dispose();
    super.dispose();
  }

  List<double> _buildSmartCashOptions(double total) {
    final candidates = <double>{50000, 100000, 200000};
    final roundedUp20k = ((total / 20000).ceil() * 20000).toDouble();
    final roundedUp50k = ((total / 50000).ceil() * 50000).toDouble();
    if (roundedUp20k > total) candidates.add(roundedUp20k);
    if (roundedUp50k > total) candidates.add(roundedUp50k);
    final sorted = candidates.where((v) => v >= total).toList()..sort();
    return sorted.take(3).toList();
  }

  void _openItemNoteDialog(BuildContext context, PosProvider pos, CartItem item) {
    final noteCtrl = TextEditingController(text: item.note ?? '');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catatan · ${item.product.name}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          (item.product.isEntertainment
                                  ? _entertainmentNotePresets
                                  : _notePresets)
                              .map((preset) {
                        final active = noteCtrl.text
                            .toLowerCase()
                            .contains(preset.toLowerCase());
                        return FilterChip(
                          label: Text(preset),
                          selected: active,
                          showCheckmark: false,
                          selectedColor: AppTheme.accentCopperSoft,
                          labelStyle: TextStyle(
                            fontSize: 11.5,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            color: active ? AppTheme.accentAmber : AppTheme.textSecondary,
                          ),
                          side: BorderSide(
                            color: active ? AppTheme.accentAmber : AppTheme.borderSubtle,
                          ),
                          onSelected: (_) {
                            final current = noteCtrl.text.trim();
                            if (active) {
                              final parts = current
                                  .split(',')
                                  .map((e) => e.trim())
                                  .where((e) =>
                                      e.isNotEmpty &&
                                      e.toLowerCase() != preset.toLowerCase())
                                  .toList();
                              noteCtrl.text = parts.join(', ');
                            } else {
                              noteCtrl.text =
                                  current.isEmpty ? preset : '$current, $preset';
                            }
                            setDialogState(() {});
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Ketik catatan khusus pesanan...',
                        prefixIcon: Icon(Icons.edit_note_rounded, size: 19),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (item.note != null && item.note!.isNotEmpty) ...[
                          TextButton(
                            onPressed: () {
                              pos.updateItemNote(item.product.id, null);
                              Navigator.of(ctx).pop();
                            },
                            child: const Text(
                              'Hapus',
                              style: TextStyle(color: AppTheme.dangerRed),
                            ),
                          ),
                          const Spacer(),
                        ] else
                          const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Batal'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            pos.updateItemNote(item.product.id, noteCtrl.text);
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('Simpan'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openCustomCashDialog(BuildContext context, double total) {
    final cashCtrl = TextEditingController(
      text: _isExactCash
          ? total.toStringAsFixed(0)
          : _customCashPaid.toStringAsFixed(0),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Input Uang Tunai Diterima',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tagihan: ${CurrencyFormatter.format(total)}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: cashCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                prefixText: 'Rp ',
                hintText: 'Masukkan nominal uang diterima',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              final parsed = CurrencyFormatter.parseDigits(cashCtrl.text);
              setState(() {
                _isExactCash = false;
                _customCashPaid = parsed;
              });
              Navigator.of(ctx).pop();
            },
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );
  }

  void _openDiscountDialog(BuildContext context, PosProvider pos) {
    final discCtrl = TextEditingController(
      text: pos.discountAmount > 0 ? pos.discountAmount.toStringAsFixed(0) : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Potongan / Diskon Pesanan',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subtotal: ${CurrencyFormatter.format(pos.subtotalCartAmount)}',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textMuted,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: discCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                prefixText: 'Rp ',
                hintText: 'Nominal potongan (Rp)',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label: const Text('10%', style: TextStyle(fontSize: 11.5)),
                  onPressed: () {
                    discCtrl.text =
                        (pos.subtotalCartAmount * 0.10).round().toString();
                  },
                ),
                ActionChip(
                  label: const Text('20%', style: TextStyle(fontSize: 11.5)),
                  onPressed: () {
                    discCtrl.text =
                        (pos.subtotalCartAmount * 0.20).round().toString();
                  },
                ),
                if (pos.discountAmount > 0)
                  ActionChip(
                    label: const Text(
                      'Reset',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.dangerRed),
                    ),
                    onPressed: () {
                      discCtrl.text = '0';
                    },
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = CurrencyFormatter.parseDigits(discCtrl.text);
              pos.setDiscountAmount(val);
              Navigator.of(ctx).pop();
            },
            child: const Text('Simpan Diskon'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showQrisConfirmationModal(BuildContext context, double total) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.qr_code_2_rounded, color: AppTheme.primary, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Pembayaran QRIS Warloc',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textMain,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'WARLOC MOJOKERTO',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'NMID : ID1026543299238 · A01',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => _showFullscreenQrisCard(context, total),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.borderSubtle),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0A000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.asset(
                                  'assets/images/qris_warloc.png',
                                  width: 172,
                                  height: 172,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.zoom_in_rounded, size: 14, color: AppTheme.primary),
                                  SizedBox(width: 4),
                                  Text(
                                    'Ketuk untuk perbesar / banner lengkap',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Total Tagihan QRIS',
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyFormatter.format(total),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textMain,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.successGreen,
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Dana Masuk'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return result == true;
  }

  void _showFullscreenQrisCard(BuildContext context, double total) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 3.5,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/qris_warloc_card.png',
                            fit: BoxFit.contain,
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            color: AppTheme.surfaceLight,
                            child: Column(
                              children: [
                                const Text(
                                  'Total Tagihan QRIS:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  CurrencyFormatter.format(total),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primary,
                                    fontFeatures: AppTheme.tabularFigures,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final subtotal = pos.subtotalCartAmount;
    if (_customerController.text != pos.customerName) {
      _customerController.value = TextEditingValue(
        text: pos.customerName,
        selection: TextSelection.collapsed(offset: pos.customerName.length),
      );
    }
    if (pos.cart.isEmpty) _isExactCash = true;
    final discount = pos.effectiveDiscount;
    final total = pos.totalCartAmount;
    final isCash = _selectedPaymentMethod == 'Cash';
    final effectiveCashPaid = _isExactCash ? total : _customCashPaid;
    final cashDiff = effectiveCashPaid - total;
    final isCashShort = isCash && !_isExactCash && cashDiff < 0;
    final cashierName =
        pos.currentUser?.displayName ?? 'Kasir ${pos.currentRole.shortName}';

    if (pos.cart.isEmpty && _customerController.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && pos.cart.isEmpty) {
          _customerController.clear();
          _isExactCash = true;
        }
      });
    }

    final smartPresets = _buildSmartCashOptions(total);

    return LayoutBuilder(builder: (context, constraints) => Container(
      height: widget.isTabletSidebar
          ? double.infinity
          : MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: widget.isTabletSidebar
            ? BorderRadius.zero
            : const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
              ),
      ),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: Column(children: [
          if (!widget.isTabletSidebar)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderStrong,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Flexible(child: Text(
                  widget.isTabletSidebar ? 'Pesanan Aktif' : 'Rincian Pesanan',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                  ),
                )),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCopperSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${pos.totalCartItemCount}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accentAmber,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ),
                const Spacer(),
                if (pos.cart.isNotEmpty)
                  IconButton(tooltip: 'Simpan Tagihan', icon: const Icon(Icons.save_outlined), onPressed: _checkingOut ? null : () async {
                    try {
                      await pos.saveCurrentBill();
                      if (!context.mounted) return;
                      AppTheme.showToast(context, message: 'Tagihan disimpan. Stok dan pendapatan belum berubah.');
                      if (!widget.isTabletSidebar) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) AppTheme.showToast(context, message: e.toString().replaceFirst('Bad state: ', ''), isError: true);
                    }
                  }),
                if (pos.cart.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppTheme.dangerRed,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    onPressed: () {
                      pos.clearCart();
                      _customerController.clear();
                      setState(() => _isExactCash = true);
                      if (!widget.isTabletSidebar) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                    label: const Text('Reset', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),

          // Dine-In / Takeaway & Customer Bar (Shown when cart has items)
          if (pos.cart.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 8,
                children: [
                  _buildOrderTypeToggle(pos, 'Dine-In', Icons.storefront_rounded),
                  _buildOrderTypeToggle(pos, 'Takeaway', Icons.shopping_bag_outlined),
                  SizedBox(
                    width: constraints.maxWidth - 32,
                    child: SizedBox(
                      height: 40 * MediaQuery.textScalerOf(context).scale(1),
                      child: TextField(
                        controller: _customerController,
                        onChanged: pos.setCustomerName,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMain),
                        decoration: InputDecoration(
                          hintText: 'Nama / Meja',
                          hintStyle: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                          prefixIcon: const Icon(
                            Icons.person_outline_rounded,
                            size: 16,
                            color: AppTheme.textMuted,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                            borderSide: const BorderSide(color: AppTheme.borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                            borderSide: const BorderSide(color: AppTheme.borderSubtle),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 1),
          ])),

          // One scroll surface keeps all controls reachable with a keyboard or short window.
          if (pos.cart.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: AppTheme.surfaceLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.receipt_long_outlined,
                              size: 34,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Belum ada item dipilih',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textMain,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Ketuk menu pada katalog untuk memulai transaksi baru.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ))
          else
            SliverPadding(padding: const EdgeInsets.all(14), sliver: SliverList.separated(
                    itemCount: pos.cart.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = pos.cart[index];
                      final hasNote = item.note != null && item.note!.isNotEmpty;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textMain),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${CurrencyFormatter.format(item.product.sellPrice)} / ${item.product.unitLabel}',
                              style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontFeatures: AppTheme.tabularFigures),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: 'Catatan item',
                                  onPressed: () => _openItemNoteDialog(context, pos, item),
                                  icon: Icon(hasNote ? Icons.sticky_note_2_rounded : Icons.note_add_outlined, size: 17, color: AppTheme.accentAmber),
                                ),
                                _buildStepperButton(icon: Icons.remove_rounded, onTap: () => pos.updateQuantity(item.product.id, -1)),
                                Text('${item.quantity}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                                _buildStepperButton(
                                  icon: Icons.add_rounded,
                                  onTap: () {
                                    final ok = pos.updateQuantity(item.product.id, 1);
                                    if (!ok) AppTheme.showToast(context, message: 'Stok maksimal (${item.product.stock}) tercapai.', isWarning: true);
                                  },
                                ),
                                Text(CurrencyFormatter.format(item.subtotal), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textMain, fontFeatures: AppTheme.tabularFigures)),
                              ],
                            ),
                            if (hasNote) ...[
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () => _openItemNoteDialog(context, pos, item),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentCopperSoft,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.notes_rounded,
                                        size: 12,
                                        color: AppTheme.accentAmber,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          item.note!,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.accentAmber,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  )),

          // Payment & Checkout Footer
          if (pos.cart.isNotEmpty)
            SliverToBoxAdapter(child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: const BoxDecoration(
                color: AppTheme.cardBg,
                border: Border(
                  top: BorderSide(color: AppTheme.borderSubtle, width: 1),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subtotal / Discount Summary Link
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        InkWell(
                          onTap: () => _openDiscountDialog(context, pos),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.local_offer_outlined,
                                  size: 14,
                                  color: AppTheme.accentAmber,
                                ),
                                const SizedBox(width: 4),
                                Flexible(child: Text(
                                  discount > 0
                                      ? 'Diskon: -${CurrencyFormatter.format(discount)}'
                                      : 'Tambah Diskon / Promo',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: discount > 0
                                        ? AppTheme.successGreen
                                        : AppTheme.accentAmber,
                                    fontFeatures: AppTheme.tabularFigures,
                                  ),
                                )),
                              ],
                            ),
                          ),
                        ),
                        if (discount > 0)
                          Text(
                            'Subtotal ${CurrencyFormatter.format(subtotal)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                              decoration: TextDecoration.lineThrough,
                              fontFeatures: AppTheme.tabularFigures,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Payment Method Chips (Cash & QRIS Only)
                    Row(
                      children: [
                        _buildPaymentChip('Cash', Icons.payments_outlined),
                        const SizedBox(width: 8),
                        _buildPaymentChip('QRIS', Icons.qr_code_2_rounded),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Cash Denominations & Change Calculation
                    if (isCash) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildCashPresetButton(
                            label: 'Uang Pas',
                            isSelected: _isExactCash,
                            onTap: () => setState(() => _isExactCash = true),
                          ),
                          for (final val in smartPresets) ...[
                            _buildCashPresetButton(
                              label: CurrencyFormatter.formatShort(val)
                                  .replaceFirst('Rp ', ''),
                              isSelected: !_isExactCash && _customCashPaid == val,
                              onTap: () => setState(() {
                                _isExactCash = false;
                                _customCashPaid = val;
                              }),
                            ),
                          ],
                          _buildCashPresetButton(
                            label: 'Lainnya',
                            isSelected: !_isExactCash &&
                                !smartPresets.contains(_customCashPaid),
                            onTap: () => _openCustomCashDialog(context, total),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: Text(
                            isCashShort
                                ? 'Kurang Bayar:'
                                : 'Diterima ${CurrencyFormatter.format(effectiveCashPaid)} · Kembalian:',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isCashShort
                                  ? AppTheme.dangerRed
                                  : AppTheme.textMuted,
                              fontFeatures: AppTheme.tabularFigures,
                            ),
                          )),
                          Text(
                            CurrencyFormatter.format(cashDiff.abs()),
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: isCashShort
                                  ? AppTheme.dangerRed
                                  : AppTheme.successGreen,
                              fontFeatures: AppTheme.tabularFigures,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Final Total & Checkout CTA
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total Tagihan',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  CurrencyFormatter.format(total),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textMain,
                                    fontFeatures: AppTheme.tabularFigures,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 6,
                          child: ElevatedButton.icon(
                            onPressed: isCashShort || _checkingOut
                                ? null
                                : () async {
                                    setState(() => _checkingOut = true);
                                    try {
                                    if (_selectedPaymentMethod == 'QRIS') {
                                      final confirmed =
                                          await _showQrisConfirmationModal(
                                        context,
                                        total,
                                      );
                                      if (!confirmed || !context.mounted) return;
                                    }

                                    final finalPaid =
                                        isCash ? effectiveCashPaid : total;

                                    final transaction = await pos.processCheckout(
                                      paymentMethod: _selectedPaymentMethod,
                                      amountPaid: finalPaid,
                                      cashierName: cashierName,
                                      customerName: _customerController.text,
                                    );

                                    if (!context.mounted) return;
                                    _customerController.clear();
                                    setState(() => _isExactCash = true);
                                    await showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (_) => ReceiptDialog(
                                        transaction: transaction,
                                      ),
                                    );
                                    if (!widget.isTabletSidebar && context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                    } catch (_) {
                                      if (context.mounted) {
                                        AppTheme.showToast(context, message: 'Pembayaran belum berhasil. Periksa pesanan lalu coba lagi.', isError: true);
                                      }
                                    } finally {
                                      if (mounted) setState(() => _checkingOut = false);
                                    }
                                  },
                            icon: Icon(
                              _selectedPaymentMethod == 'QRIS'
                                  ? Icons.qr_code_scanner_rounded
                                  : Icons.check_circle_outline_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _selectedPaymentMethod == 'QRIS'
                                  ? 'Tampilkan QRIS'
                                  : 'Bayar Sekarang',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )),
        ],
      ),
    ));
  }

  Widget _buildOrderTypeToggle(PosProvider pos, String label, IconData icon) {
    final selected = pos.orderType == label;
    return Material(
      color: selected ? AppTheme.primary : AppTheme.surfaceSubtle,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: () => pos.setOrderType(label),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.cardBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.borderStrong),
          ),
          child: Icon(icon, size: 15, color: AppTheme.textMain),
        ),
      ),
    );
  }

  Widget _buildPaymentChip(String title, IconData icon) {
    final isSelected = _selectedPaymentMethod == title;
    return Expanded(
      child: Material(
        color: isSelected ? AppTheme.primary : AppTheme.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => setState(() => _selectedPaymentMethod = title),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppTheme.primary : AppTheme.borderSubtle,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : AppTheme.textMain,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCashPresetButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
        color: isSelected ? AppTheme.accentCopperSoft : AppTheme.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? AppTheme.accentAmber : AppTheme.borderSubtle,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppTheme.accentAmber : AppTheme.textMain,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
          ),
        ),
    );
  }
}
