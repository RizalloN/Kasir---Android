import '../../widgets/access_denied.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/user_role.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/product_image_widget.dart';
import 'category_management_dialog.dart';

class EditProductDialog extends StatefulWidget {
  final Product? product;
  final ValueChanged<Product> onSave;
  final VoidCallback? onDelete;

  const EditProductDialog({
    super.key,
    this.product,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<EditProductDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _sellPriceController;
  late final TextEditingController _baseCostController;
  late final TextEditingController _stockController;
  late final TextEditingController _minStockController;
  late final TextEditingController _customUrlController;

  String? _imageUrl;
  late bool _isAvailable;
  String? _validationError;
  bool _showCustomUrlInput = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _categoryController = TextEditingController(text: p?.category ?? 'Coffee');
    _sellPriceController = TextEditingController(
      text: p != null ? p.sellPrice.toStringAsFixed(0) : '',
    );
    _baseCostController = TextEditingController(
      text: p != null ? p.baseCost.toStringAsFixed(0) : '',
    );
    _stockController = TextEditingController(
      text: p != null ? p.stock.toString() : '20',
    );
    _minStockController = TextEditingController(
      text: p != null ? p.minStockThreshold.toString() : '5',
    );
    _imageUrl = p?.imageUrl;
    _customUrlController = TextEditingController(
      text: (p?.imageUrl?.startsWith('http') ?? false) ? p!.imageUrl : '',
    );
    _isAvailable = p?.isAvailable ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _sellPriceController.dispose();
    _baseCostController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    _customUrlController.dispose();
    super.dispose();
  }

  /// Picks and compresses photo into a compact JPEG Base64 data URL (< 60 KB)
  /// so it syncs reliably inside Firebase Cloud Firestore across all devices.
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 480,
        maxHeight: 480,
        imageQuality: 65,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 650000) {
          if (mounted) {
            AppTheme.showToast(
              context,
              message:
                  'Ukuran gambar terlalu besar untuk sinkronisasi cloud. Pilih gambar yang lebih ringan.',
              isWarning: true,
            );
          }
          return;
        }
        final base64String = base64Encode(bytes);
        setState(() {
          _imageUrl = 'data:image/jpeg;base64,$base64String';
          _customUrlController.clear();
          _showCustomUrlInput = false;
        });
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showToast(
          context,
          message: 'Gagal mengambil gambar: $e',
          isError: true,
        );
      }
    }
  }

  void _adjustStockDelta(int delta) {
    final current = int.tryParse(_stockController.text) ?? 0;
    final updated = (current + delta).clamp(0, 99999);
    setState(() {
      _stockController.text = updated.toString();
    });
  }

  void _handleSave() {
    final name = _nameController.text.trim();
    final sellPrice = double.tryParse(_sellPriceController.text.trim()) ?? 0.0;
    final baseCost = double.tryParse(_baseCostController.text.trim()) ?? 0.0;
    final stock = (int.tryParse(_stockController.text.trim()) ?? 0).clamp(
      0,
      99999,
    );
    final minThreshold = (int.tryParse(_minStockController.text.trim()) ?? 5)
        .clamp(0, 9999);
    final category = _categoryController.text.trim().isEmpty
        ? 'Umum'
        : _categoryController.text.trim();

    if (name.isEmpty) {
      setState(() => _validationError = 'Nama menu wajib diisi.');
      return;
    }
    if (sellPrice <= 0) {
      setState(
        () => _validationError = 'Harga jual harus lebih besar dari Rp 0.',
      );
      return;
    }

    final resolvedBarcode =
        (widget.product?.barcode != null &&
            widget.product!.barcode!.trim().isNotEmpty)
        ? widget.product!.barcode!.trim()
        : 'WLC${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    final finalProduct = Product(
      id: widget.product?.id ?? 'w_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      category: category,
      sellPrice: sellPrice,
      baseCost: baseCost.clamp(0.0, double.infinity),
      stock: stock,
      minStockThreshold: minThreshold,
      imageUrl: _imageUrl?.trim().isNotEmpty == true ? _imageUrl!.trim() : null,
      barcode: resolvedBarcode,
      isAvailable: _isAvailable,
      updatedAt: DateTime.now(),
    );

    widget.onSave(finalProduct);
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Hapus Menu Permanen',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Hapus "${widget.product?.name}" dari katalog Warloc? Tindakan ini juga akan menghapus item dari database cloud.',
          style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ya, Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      widget.onDelete?.call();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<PosProvider>();
    if (!access.isAuthenticated || access.requiresPasswordChange || !(access.currentRole.canEditProducts)) return const AccessDenied();
    final pos = context.watch<PosProvider>();
    final isEditing = widget.product != null;
    final sell = double.tryParse(_sellPriceController.text.trim()) ?? 0.0;
    final cost = double.tryParse(_baseCostController.text.trim()) ?? 0.0;
    final estimatedMargin = sell - cost;
    final isHiburanCat =
        _categoryController.text.trim().toLowerCase() == 'hiburan';
    final categories = pos.categories.isNotEmpty
        ? pos.categories
        : ['Coffee', 'Hiburan', 'Makanan', 'Non-Coffee', 'Pastry', 'Snack'];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.accentCopperSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isEditing
                              ? Icons.edit_note_rounded
                              : Icons.add_box_rounded,
                          color: AppTheme.accentAmber,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isEditing
                            ? 'Edit Menu & Inventori'
                            : 'Tambah Menu Baru',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isEditing && widget.onDelete != null)
                        IconButton(
                          onPressed: _confirmDelete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: AppTheme.dangerRed,
                          ),
                          tooltip: 'Hapus Menu',
                          visualDensity: VisualDensity.compact,
                        ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: AppTheme.textMuted,
                        ),
                        tooltip: 'Tutup',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_validationError != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.dangerRed.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppTheme.dangerRed,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _validationError!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.dangerRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Product Name Input
              const Text(
                'Nama Menu / Layanan',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                onChanged: (_) {
                  if (_validationError != null) {
                    setState(() => _validationError = null);
                  }
                },
                decoration: InputDecoration(
                  hintText: isHiburanCat
                      ? 'Contoh: Rental PS4 / Paket VIP...'
                      : 'Masukkan nama menu...',
                  prefixIcon: Icon(
                    isHiburanCat
                        ? Icons.sports_esports_rounded
                        : Icons.coffee_rounded,
                    size: 20,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Category Selector
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Kategori Menu',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                  if (pos.currentRole.canManageCategories)
                    InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => const CategoryManagementDialog(),
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 14,
                              color: AppTheme.accentAmber,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Kelola Kategori',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentAmber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ...categories.map((cat) {
                    final isSelected =
                        _categoryController.text.trim().toLowerCase() ==
                        cat.toLowerCase();
                    return ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      selectedColor: AppTheme.primary,
                      backgroundColor: AppTheme.cardBg,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? Colors.white : AppTheme.textMain,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _categoryController.text = cat;
                            if (!isEditing &&
                                cat.trim().toLowerCase() == 'hiburan') {
                              _stockController.text = '999';
                              _minStockController.text = '0';
                            } else if (!isEditing &&
                                _minStockController.text == '0') {
                              _stockController.text = '20';
                              _minStockController.text = '5';
                            }
                          });
                        }
                      },
                    );
                  }),
                  if (pos.currentRole.canManageCategories)
                    ActionChip(
                      avatar: const Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: AppTheme.primary,
                      ),
                      label: const Text('+ Kategori Baru'),
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                      backgroundColor: AppTheme.surfaceLight,
                      side: const BorderSide(color: AppTheme.borderSubtle),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => const CategoryManagementDialog(),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Photo Section (Synced to Firebase Firestore across devices)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Foto Produk (Sinkron Lintas Perangkat)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                  if (_imageUrl != null && _imageUrl!.isNotEmpty)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_done_outlined,
                          size: 13,
                          color: AppTheme.successGreen,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Siap Cloud Sync',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.successGreen,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSubtle,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: ProductImageWidget(
                        imageUrl: _imageUrl,
                        category: _categoryController.text,
                        borderRadius: BorderRadius.circular(11),
                        width: 72,
                        height: 72,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _pickImage(ImageSource.camera),
                                  icon: const Icon(
                                    Icons.photo_camera_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Kamera',
                                    style: TextStyle(fontSize: 11.5),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _pickImage(ImageSource.gallery),
                                  icon: const Icon(
                                    Icons.photo_library_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Galeri',
                                    style: TextStyle(fontSize: 11.5),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (_imageUrl != null && _imageUrl!.isNotEmpty)
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _imageUrl = null;
                                      _customUrlController.clear();
                                    });
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline_rounded,
                                          size: 14,
                                          color: AppTheme.dangerRed,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Hapus Foto',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.dangerRed,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                const Text(
                                  'Tersimpan otomatis ke Firebase',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              InkWell(
                                onTap: () => setState(
                                  () => _showCustomUrlInput =
                                      !_showCustomUrlInput,
                                ),
                                child: Text(
                                  _showCustomUrlInput
                                      ? 'Sembunyikan URL'
                                      : 'Atau link URL',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.accentAmber,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_showCustomUrlInput) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customUrlController,
                  decoration: const InputDecoration(
                    hintText: 'https://images.unsplash.com/...',
                    prefixIcon: Icon(Icons.link_rounded, size: 18),
                    labelText: 'Link URL Gambar',
                    isDense: true,
                  ),
                  onChanged: (val) {
                    setState(() {
                      _imageUrl = val.trim().isNotEmpty ? val.trim() : null;
                    });
                  },
                ),
              ],
              const SizedBox(height: 16),

              // Sell Price & Base Cost (HPP)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isHiburanCat
                              ? 'Tarif per Jam (Rp)'
                              : 'Harga Jual (Rp)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _sellPriceController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) =>
                              setState(() => _validationError = null),
                          decoration: const InputDecoration(
                            hintText: '0',
                            prefixText: 'Rp ',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Modal HPP (Rp)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _baseCostController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: '0',
                            prefixText: 'Rp ',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (sell > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      estimatedMargin >= 0
                          ? Icons.trending_up_rounded
                          : Icons.warning_amber_rounded,
                      size: 14,
                      color: estimatedMargin >= 0
                          ? AppTheme.successGreen
                          : AppTheme.dangerRed,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      estimatedMargin >= 0
                          ? 'Margin kotor: +${CurrencyFormatter.format(estimatedMargin)} (${((estimatedMargin / sell) * 100).toStringAsFixed(0)}%)'
                          : 'Perhatian: HPP melebihi harga jual (${CurrencyFormatter.format(estimatedMargin)})',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: estimatedMargin >= 0
                            ? AppTheme.successGreen
                            : AppTheme.dangerRed,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // Inventory Stock & Low-Stock Warning Threshold Panel
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stok & Peringatan Inventori Menipis',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _stockController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText: 'Stok Tersedia',
                              suffixText: isHiburanCat ? 'jam' : 'porsi',
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _minStockController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Batas Min. Alert',
                              helperText: 'Isi 0 jika tanpa alert',
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Cepat:',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        _buildQuickAdjustButton(
                          '-10',
                          () => _adjustStockDelta(-10),
                          isNegative: true,
                        ),
                        _buildQuickAdjustButton(
                          '-5',
                          () => _adjustStockDelta(-5),
                          isNegative: true,
                        ),
                        _buildQuickAdjustButton(
                          '+10',
                          () => _adjustStockDelta(10),
                        ),
                        _buildQuickAdjustButton(
                          '+25',
                          () => _adjustStockDelta(25),
                        ),
                        _buildQuickAdjustButton(
                          '+50',
                          () => _adjustStockDelta(50),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isAvailable,
                activeTrackColor: AppTheme.successGreen,
                title: const Text(
                  'Tampilkan di Layar Kasir',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
                subtitle: Text(
                  _isAvailable
                      ? 'Menu aktif dan dapat dipesan oleh Kasir / Barista'
                      : 'Menu diarsipkan sementara dari Kasir',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                  ),
                ),
                onChanged: (val) => setState(() => _isAvailable = val),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        isEditing ? 'Simpan Perubahan' : 'Tambah Menu',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAdjustButton(
    String label,
    VoidCallback onTap, {
    bool isNegative = false,
  }) {
    return Material(
      color: isNegative ? AppTheme.dangerLight : AppTheme.cardBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isNegative
                  ? AppTheme.dangerRed.withValues(alpha: 0.35)
                  : AppTheme.borderStrong,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isNegative ? AppTheme.dangerRed : AppTheme.textMain,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        ),
      ),
    );
  }
}
