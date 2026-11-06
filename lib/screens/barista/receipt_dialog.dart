import '../../widgets/access_denied.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/transaction.dart';
import '../../models/user_role.dart';
import '../../providers/pos_provider.dart';
import '../../services/thermal_printer_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../dialogs/printer_settings_dialog.dart';
import '../../services/app_release_service.dart';

class ReceiptDialog extends StatefulWidget {
  final TransactionRecord transaction;
  final bool allowVoid;

  const ReceiptDialog({
    super.key,
    required this.transaction,
    this.allowVoid = false,
  });

  @override
  State<ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<ReceiptDialog> {
  bool _isPrinting = false;

  TransactionRecord get transaction => widget.transaction;
  bool get allowVoid => widget.allowVoid;

  Future<void> _handlePrint(BuildContext context, PosProvider pos, int paperWidth) async {
    if (!(context.read<AppReleaseService?>()?.enabled('thermal_printer') ?? true)) {
      AppTheme.showToast(context, message: 'Fitur printer dinonaktifkan sementara.', isWarning: true);
      return;
    }
    if (!pos.isPrinterConnected) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.print_disabled_rounded, color: AppTheme.warningOrange, size: 22),
              SizedBox(width: 8),
              Text('Printer Belum Terhubung', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Printer thermal Bluetooth belum terhubung. Buka Pengaturan Printer untuk memilih dan menghubungkan printer kasir Anda.',
            style: TextStyle(fontSize: 13, color: AppTheme.textMain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Nanti'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                showDialog(
                  context: context,
                  builder: (_) => const PrinterSettingsDialog(),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Buka Pengaturan Printer'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isPrinting = true);
    final res = await ThermalPrinterService.instance.printTransactionReceipt(
      transaction,
      paperWidth: paperWidth,
    );
    if (!mounted) return;
    setState(() => _isPrinting = false);

    if (context.mounted) {
      AppTheme.showToast(
        context,
        message: res.message,
        icon: res.success ? Icons.receipt_long_rounded : Icons.error_outline_rounded,
        isError: !res.success,
      );
    }
  }

  Future<void> _confirmVoid(BuildContext context, PosProvider pos) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Batalkan (Void) Transaksi?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Membatalkan struk ${transaction.invoiceNumber} akan mengembalikan stok seluruh item pada transaksi ini dan mengecualikannya dari laporan omset.',
          style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Kembali'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ya, Void Transaksi'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final ok = await pos.voidTransaction(transaction.id);
      if (context.mounted) {
        Navigator.of(context).pop();
        if (ok) {
          AppTheme.showToast(
            context,
            message:
                'Transaksi ${transaction.invoiceNumber} dibatalkan & stok telah dikembalikan.',
            isWarning: true,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<PosProvider>();
    if (!access.isAuthenticated || access.requiresPasswordChange ||
        (!access.currentRole.canViewFinancialReports && transaction.cashierId != access.currentUser?.id)) { return const AccessDenied(); }
    final pos = context.watch<PosProvider>();
    final paperWidth = pos.printerPaperWidth;
    final maxReceiptWidth = paperWidth == 80 ? 450.0 : 365.0;
    final isVoided = transaction.isVoided;
    final canVoidNow =
        allowVoid && pos.currentRole.canVoidTransactions && !isVoided;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxReceiptWidth,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status Header Banner
              Container(
                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                decoration: BoxDecoration(
                  color: isVoided ? AppTheme.dangerRed : AppTheme.successGreen,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isVoided ? Icons.cancel_rounded : Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isVoided
                            ? 'Transaksi Dibatalkan (VOID)'
                            : 'Transaksi Warloc Berhasil',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable Thermal Receipt Body
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(paperWidth == 80 ? 22 : 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'WARLOC',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Coffee, Eatery & Entertainment\nJl. Nongkrong Warloc No. 1, Jakarta\nTelp: 0812-9988-7766',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),

                      _buildDashedLine(),
                      const SizedBox(height: 10),

                      _buildMetaRow('No. Struk', transaction.invoiceNumber),
                      _buildMetaRow(
                        'Waktu',
                        CurrencyFormatter.formatDateTime(transaction.createdAt),
                      ),
                      _buildMetaRow('Kasir', transaction.cashierName),
                      _buildMetaRow('Layanan', transaction.orderType),
                      if (transaction.customerName != null &&
                          transaction.customerName!.isNotEmpty)
                        _buildMetaRow('Pelanggan', transaction.customerName!),
                      _buildMetaRow('Pembayaran', transaction.paymentMethod),

                      const SizedBox(height: 10),
                      _buildDashedLine(),
                      const SizedBox(height: 10),

                      ...transaction.items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.name,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textMain,
                                      ),
                                    ),
                                    if (item.note != null && item.note!.isNotEmpty)
                                      Text(
                                        'Catatan: ${item.note}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: AppTheme.accentAmber,
                                        ),
                                      ),
                                    Text(
                                      '${item.quantity} x ${CurrencyFormatter.format(item.product.sellPrice)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted,
                                        fontFeatures: AppTheme.tabularFigures,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                CurrencyFormatter.format(item.subtotal),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textMain,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                      const SizedBox(height: 10),
                      _buildDashedLine(),
                      const SizedBox(height: 10),

                      if (transaction.discountAmount > 0) ...[
                        _buildTotalRow(
                          'Subtotal',
                          CurrencyFormatter.format(transaction.subtotalAmount),
                        ),
                        const SizedBox(height: 4),
                        _buildTotalRow(
                          'Diskon Promo',
                          '-${CurrencyFormatter.format(transaction.discountAmount)}',
                          isHighlight: true,
                        ),
                        const SizedBox(height: 6),
                      ],

                      _buildTotalRow(
                        'TOTAL',
                        CurrencyFormatter.format(transaction.totalAmount),
                        isBold: true,
                      ),
                      const SizedBox(height: 4),
                      _buildTotalRow(
                        'Bayar (${transaction.paymentMethod})',
                        CurrencyFormatter.format(transaction.amountPaid),
                      ),
                      const SizedBox(height: 4),
                      _buildTotalRow(
                        'Kembalian',
                        CurrencyFormatter.format(transaction.changeAmount),
                        isHighlight: !isVoided,
                      ),

                      const SizedBox(height: 14),
                      _buildDashedLine(),
                      const SizedBox(height: 12),

                      Text(
                        isVoided
                            ? 'STRUK INI TELAH DIBATALKAN (VOID)'
                            : 'Terima Kasih Telah Berkunjung ke Warloc\nSelamat Menikmati Layanan Kami',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isVoided ? FontWeight.w800 : FontWeight.w500,
                          color: isVoided ? AppTheme.dangerRed : AppTheme.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Pinned Bottom Action Bar
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  border: Border(
                    top: BorderSide(color: AppTheme.borderSubtle, width: 1),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isPrinting
                                ? null
                                : () => _handlePrint(context, pos, paperWidth),
                            icon: _isPrinting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.print_rounded, size: 17),
                            label: Text('Cetak (${paperWidth}mm)'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Selesai'),
                          ),
                        ),
                      ],
                    ),
                    if (canVoidNow) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () => _confirmVoid(context, pos),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.dangerRed,
                          ),
                          icon: const Icon(Icons.undo_rounded, size: 16),
                          label: const Text('Void / Batalkan Transaksi & Kembalikan Stok'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMain,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    String value, {
    bool isBold = false,
    bool isHighlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 13.5 : 12,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
            color: isHighlight ? AppTheme.successGreen : AppTheme.textMain,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 15.5 : 12,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
            color: isHighlight ? AppTheme.successGreen : AppTheme.textMain,
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
      ],
    );
  }

  Widget _buildDashedLine() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 5.0;
        const dashSpace = 3.0;
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor().clamp(1, 200);
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: dashWidth,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppTheme.borderStrong),
              ),
            );
          }),
        );
      },
    );
  }
}
