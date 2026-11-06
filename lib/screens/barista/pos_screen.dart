import '../../widgets/access_denied.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/user_role.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_formatter.dart';
import 'cart_bottom_sheet.dart';
import '../dialogs/edit_product_dialog.dart';
import '../dialogs/category_management_dialog.dart';
import '../../widgets/product_image_widget.dart';
import '../../services/app_release_service.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleProductTap(BuildContext context, PosProvider pos, Product product) {
    if (!product.isAvailable) {
      AppTheme.showToast(
        context,
        message: 'Menu "${product.name}" sedang dinonaktifkan.',
        isWarning: true,
      );
      return;
    }
    if (product.isOutOfStock) {
      AppTheme.showToast(
        context,
        message: 'Stok "${product.name}" sedang habis.',
        isWarning: true,
      );
      return;
    }

    final added = pos.addToCart(product);
    if (!added) {
      AppTheme.showToast(
        context,
        message: 'Batas stok tercapai (${product.stock} porsi tersedia).',
        isWarning: true,
      );
    }
  }

  void _openBarcodeLookupDialog(BuildContext context, PosProvider pos) {
    final codeController = TextEditingController();
    final skuProducts = pos.visibleCatalogProducts
        .where((p) => p.barcode != null && p.barcode!.isNotEmpty)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          color: AppTheme.accentAmber,
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Input Cepat Barcode / SKU',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textMain,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) {
                    final matched = pos.findProductByBarcode(value);
                    if (matched != null) {
                      Navigator.of(ctx).pop();
                      _handleProductTap(context, pos, matched);
                    } else {
                      AppTheme.showToast(
                        context,
                        message: 'Kode SKU "$value" tidak ditemukan.',
                        isWarning: true,
                      );
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Ketik atau scan kode (contoh: 8992001)...',
                    prefixIcon: const Icon(Icons.tag_rounded, size: 19),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.keyboard_return_rounded, size: 19),
                      tooltip: 'Cari & Tambah',
                      onPressed: () {
                        final matched = pos.findProductByBarcode(codeController.text);
                        if (matched != null) {
                          Navigator.of(ctx).pop();
                          _handleProductTap(context, pos, matched);
                        } else {
                          AppTheme.showToast(
                            context,
                            message: 'Kode SKU "${codeController.text}" tidak ditemukan.',
                            isWarning: true,
                          );
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Daftar SKU Terdaftar',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: skuProducts.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'Belum ada menu dengan kode barcode.',
                              style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: skuProducts.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final item = skuProducts[i];
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                              title: Text(
                                item.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textMain,
                                ),
                              ),
                              subtitle: Text(
                                'SKU: ${item.barcode} · Stok: ${item.stock}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.textMuted,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                              trailing: Text(
                                CurrencyFormatter.format(item.sellPrice),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.accentAmber,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                              onTap: item.isOutOfStock
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      _handleProductTap(context, pos, item);
                                    },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<PosProvider>();
    if (!access.isAuthenticated || access.requiresPasswordChange || !(true)) return const AccessDenied();
    final pos = context.watch<PosProvider>();
    final products = pos.filteredProducts;

    if (_searchController.text != pos.searchQuery) {
      _searchController.value = TextEditingValue(
        text: pos.searchQuery,
        selection: TextSelection.collapsed(offset: pos.searchQuery.length),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
        final isTablet = constraints.maxWidth >= 960 * scale &&
            constraints.maxHeight + MediaQuery.viewInsetsOf(context).bottom >= 560;

        if (isTablet) {
          return Scaffold(
            backgroundColor: AppTheme.surfaceLight,
            body: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildSearchBar(context, pos),
                      _buildCategoryChips(pos),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _buildProductGrid(
                          context,
                          products,
                          pos,
                          isTablet: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, color: AppTheme.borderSubtle),
                SizedBox(
                  width: 380 * scale,
                  child: const ColoredBox(
                    color: AppTheme.cardBg,
                    child: CartBottomSheet(isTabletSidebar: true),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.surfaceLight,
          body: Column(
            children: [
              _buildSearchBar(context, pos),
              _buildCategoryChips(pos),
              const SizedBox(height: 8),
              Expanded(
                child: _buildProductGrid(
                  context,
                  products,
                  pos,
                  isTablet: false,
                ),
              ),
            ],
          ),
          bottomNavigationBar: pos.cart.isEmpty
              ? null
              : Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    border: const Border(
                      top: BorderSide(color: AppTheme.borderSubtle, width: 1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        offset: const Offset(0, -4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${pos.totalCartItemCount} item dalam pesanan',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                CurrencyFormatter.format(pos.totalCartAmount),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.textMain,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(child: ElevatedButton.icon(
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              useSafeArea: true,
                              builder: (sheetContext) => Padding(
                                padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
                                child: const CartBottomSheet(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.shopping_bag_rounded, size: 18),
                          label: const Text('Rincian & Bayar'),
                        )),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildSearchBar(BuildContext context, PosProvider pos) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: pos.setSearchQuery,
                style: const TextStyle(fontSize: 13.5, color: AppTheme.textMain),
                decoration: InputDecoration(
                  hintText: 'Cari nama menu, kategori, atau barcode...',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.textMuted,
                    size: 20,
                  ),
                  suffixIcon: pos.searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus pencarian',
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppTheme.textMuted,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            pos.setSearchQuery('');
                          },
                        ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
          ),
          if (context.watch<AppReleaseService>().enabled('barcode_lookup')) ...[
          const SizedBox(width: 8),
          Material(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => _openBarcodeLookupDialog(context, pos),
              borderRadius: BorderRadius.circular(12),
              child: Tooltip(
                message: 'Input Barcode / SKU Cepat',
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppTheme.textMain,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryChips(PosProvider pos) {
    final categories = pos.availableCategories;
    final canManage = pos.currentRole.canManageCategories;
    final totalItems = categories.length + (canManage ? 1 : 0);

    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: totalItems,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (canManage && index == categories.length) {
            return ActionChip(
              avatar: const Icon(Icons.tune_rounded, size: 14, color: AppTheme.accentAmber),
              label: const Text('Kelola Kategori'),
              backgroundColor: AppTheme.cardBg,
              side: const BorderSide(color: AppTheme.accentAmber),
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.accentAmber,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const CategoryManagementDialog(),
                );
              },
            );
          }

          final category = categories[index];
          final isSelected = pos.selectedCategory == category;
          final count = pos.countProductsInCategory(category);

          return ChoiceChip(
            showCheckmark: false,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(category),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.2)
                        : AppTheme.surfaceSubtle,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : AppTheme.textMuted,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ),
              ],
            ),
            selected: isSelected,
            selectedColor: AppTheme.primary,
            backgroundColor: AppTheme.cardBg,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
            side: BorderSide(
              color: isSelected ? AppTheme.primary : AppTheme.borderSubtle,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (selected) {
              if (selected) pos.selectCategory(category);
            },
          );
        },
      ),
    );
  }

  Widget _buildProductGrid(
    BuildContext context,
    List<Product> products,
    PosProvider pos, {
    required bool isTablet,
  }) {
    if (products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceSubtle,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_off_rounded,
                  size: 32,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Menu tidak ditemukan',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Coba kata kunci lain atau ubah filter kategori.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
              ),
              if (pos.searchQuery.isNotEmpty || pos.selectedCategory != 'Semua') ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    pos.setSearchQuery('');
                    pos.selectCategory('Semua');
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reset Filter'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return LayoutBuilder(builder: (context, constraints) => GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 6, 16, isTablet ? 20 : 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: ((constraints.maxWidth - 20) / (170 * scale)).floor().clamp(1, 8),
        mainAxisExtent: 230 + (scale - 1) * 120,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return _buildProductCard(context, product, pos);
      },
    ));
  }

  Widget _buildProductCard(BuildContext context, Product product, PosProvider pos) {
    final cartItemIndex = pos.cart.indexWhere((item) => item.product.id == product.id);
    final inCartQty = cartItemIndex != -1 ? pos.cart[cartItemIndex].quantity : 0;
    final isDisabled = product.isOutOfStock || !product.isAvailable;
    final canManage = pos.currentRole.canEditProducts;

    return Opacity(
      opacity: isDisabled ? 0.68 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: inCartQty > 0 ? AppTheme.accentAmber : AppTheme.borderSubtle,
            width: inCartQty > 0 ? 1.6 : 1.0,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _handleProductTap(context, pos, product),
            borderRadius: BorderRadius.circular(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Image Area (Fixed 108px height - balanced proportion)
                Stack(
                  children: [
                    Container(
                      height: 108,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: AppTheme.surfaceSubtle,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(13),
                          topRight: Radius.circular(13),
                        ),
                      ),
                      child: ProductImageWidget(
                        imageUrl: product.imageUrl,
                        category: product.category,
                        width: double.infinity,
                        height: 108,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(13),
                          topRight: Radius.circular(13),
                        ),
                        fallbackWidget: _buildImagePlaceholder(product),
                      ),
                    ),

                    Positioned(
                      top: 8,
                      left: 8,
                      child: Row(
                        children: [
                          _buildStockBadge(product),
                          if (!product.isAvailable) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Arsip',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (canManage)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => EditProductDialog(
                                  product: product,
                                  onSave: (updated) {
                                    pos.updateExistingProduct(updated);
                                    AppTheme.showToast(
                                      context,
                                      message:
                                          'Menu "${updated.name}" berhasil diperbarui.',
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
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.94),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppTheme.borderSubtle),
                                ),
                                child: const Icon(
                                  Icons.edit_rounded,
                                  size: 15,
                                  color: AppTheme.textMain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                // Content Area (Tightly grouped title + bottom price/stepper row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.category.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                            height: 1.2,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  product.isEntertainment
                                      ? '${CurrencyFormatter.format(product.sellPrice)} / jam'
                                      : CurrencyFormatter.format(
                                          product.sellPrice,
                                        ),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.accentAmber,
                                    fontFeatures: AppTheme.tabularFigures,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (inCartQty > 0)
                              Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: () => pos.updateQuantity(product.id, -1),
                                      borderRadius: BorderRadius.circular(8),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        child: Icon(
                                          Icons.remove_rounded,
                                          size: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '$inCartQty',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        fontFeatures: AppTheme.tabularFigures,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        final ok = pos.updateQuantity(product.id, 1);
                                        if (!ok) {
                                          AppTheme.showToast(
                                            context,
                                            message:
                                                'Maksimal ${product.stock} porsi tersedia.',
                                            isWarning: true,
                                          );
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        child: Icon(
                                          Icons.add_rounded,
                                          size: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isDisabled
                                      ? AppTheme.surfaceSubtle
                                      : AppTheme.accentCopperSoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isDisabled
                                      ? Icons.block_rounded
                                      : Icons.add_rounded,
                                  size: 16,
                                  color: isDisabled
                                      ? AppTheme.textMuted
                                      : AppTheme.accentAmber,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder(Product product) {
    IconData icon = Icons.local_cafe_rounded;
    final cat = product.category.toLowerCase();
    final isHiburan = product.isEntertainment;
    if (isHiburan) {
      icon = Icons.sports_esports_rounded;
    } else if (cat.contains('pastry') || cat.contains('roti')) {
      icon = Icons.bakery_dining_rounded;
    } else if (cat.contains('snack') || cat.contains('makan')) {
      icon = Icons.restaurant_rounded;
    } else if (cat.contains('non')) {
      icon = Icons.emoji_food_beverage_rounded;
    }

    return ColoredBox(
      color: isHiburan ? AppTheme.accentCopperSoft : AppTheme.surfaceSubtle,
      child: Center(
        child: Icon(
          icon,
          size: 36,
          color: isHiburan
              ? AppTheme.accentAmber
              : AppTheme.textMuted.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _buildStockBadge(Product product) {
    final stock = product.stock;
    final Color bg;
    final Color text;
    final String label;

    if (product.isEntertainment && product.minStockThreshold == 0 && stock > 0) {
      bg = AppTheme.accentCopperSoft.withValues(alpha: 0.95);
      text = AppTheme.accentAmber;
      label = 'Tarif / Jam';
    } else if (product.isOutOfStock) {
      bg = AppTheme.dangerLight;
      text = AppTheme.dangerRed;
      label = 'Habis';
    } else if (product.isLowStock) {
      bg = AppTheme.warningLight;
      text = AppTheme.warningOrange;
      label = 'Sisa $stock';
    } else {
      bg = Colors.white.withValues(alpha: 0.92);
      text = AppTheme.textMain;
      label = 'Stok $stock';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderSubtle.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: text,
          fontFeatures: AppTheme.tabularFigures,
        ),
      ),
    );
  }
}
