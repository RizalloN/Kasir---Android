import '../../models/user_role.dart';
import '../../widgets/access_denied.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../dialogs/edit_product_dialog.dart';
import '../dialogs/batch_insert_dialog.dart';
import '../dialogs/category_management_dialog.dart';
import '../dialogs/low_stock_alert_dialog.dart';
import '../../widgets/product_image_widget.dart';

class StockManagementScreen extends StatefulWidget {
  const StockManagementScreen({super.key});

  @override
  State<StockManagementScreen> createState() => _StockManagementScreenState();
}

class _StockManagementScreenState extends State<StockManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _stockFilter = 'Semua'; // Semua, Menipis, Habis, Hiburan, Arsip

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<PosProvider>();
    if (!access.isAuthenticated || !access.currentRole.canEditProducts) return const AccessDenied();
    final pos = context.watch<PosProvider>();
    final query = _searchController.text.trim().toLowerCase();
    final lowStock = pos.lowStockProducts;
    final outCount = pos.outOfStockAlertProducts.length;
    final warnCount = pos.warningStockAlertProducts.length;

    final filtered = pos.products.where((p) {
      final matchesSearch =
          query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          p.category.toLowerCase().contains(query) ||
          (p.barcode != null && p.barcode!.toLowerCase().contains(query));
      if (!matchesSearch) return false;

      switch (_stockFilter) {
        case 'Menipis':
          return p.isLowStock;
        case 'Habis':
          return p.isOutOfStock;
        case 'Hiburan':
          return p.isEntertainment;
        case 'Arsip':
          return !p.isAvailable;
        default:
          return true;
      }
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.surfaceLight,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: Column(children: [
          // Top Header & Add Menu Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Inventori & Katalog Warloc',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${pos.products.length} item · Modal stok ${CurrencyFormatter.formatShort(pos.totalInventoryCostValue)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const CategoryManagementDialog(),
                    );
                  },
                  icon: const Icon(Icons.category_rounded, size: 16),
                  label: const Text('Kategori'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => EditProductDialog(
                        onSave: (newProduct) {
                          pos.addNewProduct(newProduct);
                          AppTheme.showToast(
                            context,
                            message:
                                'Menu "${newProduct.name}" berhasil ditambahkan.',
                          );
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Tambah Menu'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final count = await showDialog<int>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const BatchInsertDialog.menu(),
                    );
                    if (context.mounted && count != null) {
                      AppTheme.showToast(context, message: '$count menu tersimpan di perangkat. Sinkronisasi mengikuti status koneksi.');
                    }
                  },
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: const Text('Tambah Sekaligus'),
                ),
              ],
            ),
          ),

          // Actionable Low Stock Alert Banner
          if (lowStock.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => const LowStockAlertDialog(),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: outCount > 0
                        ? AppTheme.dangerLight
                        : AppTheme.warningLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          (outCount > 0
                                  ? AppTheme.dangerRed
                                  : AppTheme.warningOrange)
                              .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_active_rounded,
                        size: 19,
                        color: outCount > 0
                            ? AppTheme.dangerRed
                            : AppTheme.warningOrange,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Peringatan Stok: $outCount habis & $warnCount menipis di bawah batas minimum.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: outCount > 0
                                ? AppTheme.dangerRed
                                : AppTheme.warningOrange,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Restock Cepat',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: outCount > 0
                                ? AppTheme.dangerRed
                                : AppTheme.warningOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Search & Quick Stock Filter Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Cari menu, layanan PS, atau kode SKU...',
                        fillColor: AppTheme.cardBg,
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: AppTheme.textMuted,
                        ),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 17),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          SizedBox(
            height: 36,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in [
                  'Semua',
                  'Menipis',
                  'Habis',
                  'Hiburan',
                  'Arsip',
                ]) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Text(f),
                      selected: _stockFilter == f,
                      selectedColor: AppTheme.primary,
                      backgroundColor: AppTheme.cardBg,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: _stockFilter == f
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _stockFilter == f
                            ? Colors.white
                            : AppTheme.textSecondary,
                      ),
                      onSelected: (_) => setState(() => _stockFilter = f),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Product Inventory List
          ])),
          if (filtered.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: Center(
                    child: Text(
                      'Tidak ada item inventori yang cocok dengan filter.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ))
          else
            SliverPadding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final product = filtered[index];
                      return _buildInventoryRow(context, pos, product);
                    },
                  )),
        ],
      ),
    );
  }

  Widget _buildInventoryRow(
    BuildContext context,
    PosProvider pos,
    Product product,
  ) {
    final needsRestock = product.needsRestock;
    final isOut = product.isOutOfStock;
    final statusColor = isOut ? AppTheme.dangerRed : AppTheme.warningOrange;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: needsRestock
              ? statusColor.withValues(alpha: 0.55)
              : AppTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          // Product Thumbnail
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppTheme.surfaceSubtle,
              borderRadius: BorderRadius.circular(11),
            ),
            child: ProductImageWidget(
              imageUrl: product.imageUrl,
              category: product.category,
              width: 50,
              height: 50,
              borderRadius: BorderRadius.circular(11),
              fallbackWidget: _buildFallbackIcon(product),
            ),
          ),
          const SizedBox(width: 12),

          // Product Meta & Pricing
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                    ),
                    if (needsRestock) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isOut
                              ? AppTheme.dangerLight
                              : AppTheme.warningLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isOut ? 'HABIS' : 'MENIPIS',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                    if (!product.isAvailable) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Arsip',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    Text(
                      product.isEntertainment
                          ? 'Tarif ${CurrencyFormatter.format(product.sellPrice)} / jam'
                          : 'Jual ${CurrencyFormatter.format(product.sellPrice)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                    if (!product.isEntertainment)
                      Text(
                        'HPP ${CurrencyFormatter.format(product.baseCost)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    Text(
                      product.minStockThreshold > 0
                          ? 'Min. stok: ${product.minStockThreshold}'
                          : 'Non-stok fisik',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Inline Quick Stock Stepper
          Container(
            decoration: BoxDecoration(
              color: needsRestock
                  ? (isOut ? AppTheme.dangerLight : AppTheme.warningLight)
                  : AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: needsRestock
                    ? statusColor.withValues(alpha: 0.35)
                    : AppTheme.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: product.stock <= 0
                      ? null
                      : () => pos.adjustProductStock(
                          product.id,
                          product.stock - 1,
                        ),
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(
                      Icons.remove_rounded,
                      size: 15,
                      color: AppTheme.textMain,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 28),
                  child: Text(
                    '${product.stock}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: isOut
                          ? AppTheme.dangerRed
                          : (product.isLowStock
                                ? AppTheme.warningOrange
                                : AppTheme.textMain),
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () =>
                      pos.adjustProductStock(product.id, product.stock + 5),
                  borderRadius: BorderRadius.circular(10),
                  child: const Tooltip(
                    message: 'Tambah +5 stok cepat',
                    child: Padding(
                      padding: EdgeInsets.all(7),
                      child: Icon(
                        Icons.add_rounded,
                        size: 15,
                        color: AppTheme.textMain,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),

          // Full Edit Modal Button
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => EditProductDialog(
                  product: product,
                  onSave: (updated) {
                    pos.updateExistingProduct(updated);
                    AppTheme.showToast(
                      context,
                      message: 'Menu "${updated.name}" berhasil diperbarui.',
                    );
                  },
                  onDelete: () {
                    pos.deleteExistingProduct(product.id);
                    AppTheme.showToast(
                      context,
                      message: 'Menu "${product.name}" telah dihapus.',
                      isWarning: true,
                    );
                  },
                ),
              );
            },
            icon: const Icon(
              Icons.tune_rounded,
              size: 20,
              color: AppTheme.textMain,
            ),
            tooltip: 'Edit Detail, Harga & Stok',
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackIcon(Product product) {
    return Center(
      child: Icon(
        product.isEntertainment
            ? Icons.sports_esports_rounded
            : Icons.local_cafe_outlined,
        size: 22,
        color: AppTheme.accentAmber,
      ),
    );
  }
}
