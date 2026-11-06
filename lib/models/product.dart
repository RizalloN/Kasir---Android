class Product {
  static const Object _unset = Object();

  final String id;
  final String name;
  final String category;
  final double sellPrice;
  final double baseCost; // HPP (Harga Pokok Penjualan)
  final int stock;
  final int minStockThreshold;
  final String? barcode;
  final String? imageUrl;
  final bool isAvailable;
  final DateTime? updatedAt;
  final bool isSynced;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.sellPrice,
    required this.baseCost,
    required this.stock,
    this.minStockThreshold = 5,
    this.barcode,
    this.imageUrl,
    this.isAvailable = true,
    this.updatedAt,
    this.isSynced = true,
  });

  double get profitMargin => sellPrice - baseCost;

  double get marginPercentage {
    if (sellPrice <= 0) return 0.0;
    return ((sellPrice - baseCost) / sellPrice) * 100;
  }

  bool get isEntertainment {
    final cat = category.trim().toLowerCase();
    final lowerName = name.trim().toLowerCase();
    return cat == 'hiburan' ||
        lowerName.contains('rental ps') ||
        lowerName.startsWith('ps3') ||
        lowerName.startsWith('ps4');
  }

  String get unitLabel => isEntertainment ? 'jam' : 'porsi';

  bool get isOutOfStock => stock <= 0;

  bool get isLowStock =>
      isAvailable && minStockThreshold > 0 && stock > 0 && stock <= minStockThreshold;

  bool get needsRestock =>
      isAvailable && minStockThreshold > 0 && stock <= minStockThreshold;

  Product copyWith({
    String? id,
    String? name,
    String? category,
    double? sellPrice,
    double? baseCost,
    int? stock,
    int? minStockThreshold,
    Object? barcode = _unset,
    Object? imageUrl = _unset,
    bool? isAvailable,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      sellPrice: sellPrice ?? this.sellPrice,
      baseCost: baseCost ?? this.baseCost,
      stock: stock ?? this.stock,
      minStockThreshold: minStockThreshold ?? this.minStockThreshold,
      barcode: identical(barcode, _unset) ? this.barcode : barcode as String?,
      imageUrl: identical(imageUrl, _unset) ? this.imageUrl : imageUrl as String?,
      isAvailable: isAvailable ?? this.isAvailable,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'sellPrice': sellPrice,
      'baseCost': baseCost,
      'stock': stock,
      'minStockThreshold': minStockThreshold,
      'barcode': barcode,
      'imageUrl': imageUrl,
      'isAvailable': isAvailable ? 1 : 0,
      'updatedAt': updatedAt?.toIso8601String(),
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    final rawAvail = map['isAvailable'];
    final bool available = rawAvail == null
        ? true
        : (rawAvail == 1 || rawAvail == true);

    final rawSynced = map['isSynced'];
    final bool synced = rawSynced == null
        ? true
        : (rawSynced == 1 || rawSynced == true);

    final resolvedCategory = (map['category'] as String?) ?? 'Umum';
    final isHiburan = resolvedCategory.trim().toLowerCase() == 'hiburan';
    final defaultThreshold = isHiburan ? 0 : 5;

    return Product(
      id: (map['id'] as String?) ?? 'w_unknown',
      name: (map['name'] as String?) ?? 'Menu Warloc',
      category: resolvedCategory,
      sellPrice: ((map['sellPrice'] as num?) ?? 0).toDouble(),
      baseCost: ((map['baseCost'] as num?) ?? 0).toDouble(),
      stock: ((map['stock'] as num?) ?? 0).toInt(),
      minStockThreshold:
          ((map['minStockThreshold'] as num?) ?? defaultThreshold).toInt(),
      barcode: (map['barcode'] as String?)?.trim().isEmpty == true
          ? null
          : map['barcode'] as String?,
      imageUrl: (map['imageUrl'] as String?)?.trim().isEmpty == true
          ? null
          : map['imageUrl'] as String?,
      isAvailable: available,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
      isSynced: synced,
    );
  }
}
