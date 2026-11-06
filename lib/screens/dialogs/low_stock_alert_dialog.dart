import '../../widgets/access_denied.dart';
import '../../models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/product_image_widget.dart';
import 'edit_product_dialog.dart';

class LowStockAlertDialog extends StatelessWidget {
  const LowStockAlertDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final access = context.watch<PosProvider>();
    if (!access.isAuthenticated || access.requiresPasswordChange || !(access.currentRole.canEditProducts)) return const AccessDenied();
    final pos = context.watch<PosProvider>();
    final alerts = pos.lowStockProducts;
    final outCount = pos.outOfStockAlertProducts.length;
    final lowCount = pos.warningStockAlertProducts.length;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: alerts.isEmpty
                          ? AppTheme.successGreenLight
                          : (outCount > 0
                                ? AppTheme.dangerLight
                                : AppTheme.warningLight),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      alerts.isEmpty
                          ? Icons.verified_rounded
                          : Icons.notifications_active_rounded,
                      size: 21,
                      color: alerts.isEmpty
                          ? AppTheme.successGreen
                          : (outCount > 0
                                ? AppTheme.dangerRed
                                : AppTheme.warningOrange),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Peringatan Inventori Warloc',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          alerts.isEmpty
                              ? 'Seluruh stok menu aman di atas batas minimum'
                              : '$outCount habis · $lowCount menipis perlu restock segera',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                            fontFeatures: AppTheme.tabularFigures,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppTheme.textMuted,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),

              Flexible(
                child: alerts.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: const BoxDecoration(
                                  color: AppTheme.successGreenLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.inventory_rounded,
                                  size: 30,
                                  color: AppTheme.successGreen,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Stok Inventori Aman',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textMain,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tidak ada produk yang menyentuh batas stok minimum.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: alerts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = alerts[index];
                          return _buildAlertItemCard(context, pos, item);
                        },
                      ),
              ),

              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup Panel Peringatan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertItemCard(
    BuildContext context,
    PosProvider pos,
    Product item,
  ) {
    final isOut = item.isOutOfStock;
    final statusColor = isOut ? AppTheme.dangerRed : AppTheme.warningOrange;
    final statusBg = isOut ? AppTheme.dangerLight : AppTheme.warningLight;
    final maxSafe = (item.minStockThreshold * 3).clamp(10, 9999);
    final ratio = (item.stock / maxSafe).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProductImageWidget(
                imageUrl: item.imageUrl,
                category: item.category,
                width: 44,
                height: 44,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            isOut ? 'HABIS' : 'MENIPIS',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Sisa ${item.stock} ${item.unitLabel} · Batas minimum ${item.minStockThreshold} ${item.unitLabel}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit Menu & Batas Stok',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => EditProductDialog(
                      product: item,
                      onSave: (updated) {
                        pos.updateExistingProduct(updated);
                        AppTheme.showToast(
                          context,
                          message: 'Stok "${updated.name}" diperbarui.',
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Restock Cepat:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
              const Spacer(),
              _buildQuickAddChip(
                context,
                label: '+10',
                onTap: () {
                  pos.adjustProductStock(item.id, item.stock + 10);
                  AppTheme.showToast(
                    context,
                    message:
                        '+10 stok ditambahkan ke "${item.name}" (Total: ${item.stock + 10}).',
                  );
                },
              ),
              const SizedBox(width: 6),
              _buildQuickAddChip(
                context,
                label: '+25',
                isPrimary: true,
                onTap: () {
                  pos.adjustProductStock(item.id, item.stock + 25);
                  AppTheme.showToast(
                    context,
                    message:
                        '+25 stok ditambahkan ke "${item.name}" (Total: ${item.stock + 25}).',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAddChip(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return Material(
      color: isPrimary ? AppTheme.primary : AppTheme.cardBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isPrimary ? AppTheme.primary : AppTheme.borderStrong,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: isPrimary ? Colors.white : AppTheme.textMain,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        ),
      ),
    );
  }
}
