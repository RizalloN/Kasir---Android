import 'product.dart';

class CartItem {
  static const Object _unset = Object();
  static const variantPrices = <String, double>{'Panas': 0, 'ES': 1000, 'Jumbo': 3000};
  static final _variantPattern = RegExp(r'^\[KAFE_VARIAN_v1:(Panas|ES|Jumbo)\](?:\n|$)');

  Product product;
  int quantity;
  String? note;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.note,
  });

  double get subtotal => product.sellPrice * quantity;
  double get subtotalCost => product.baseCost * quantity;
  double get subtotalProfit => subtotal - subtotalCost;

  String? get drinkVariant => _variantPattern.firstMatch(note ?? '')?.group(1);
  String? get customerNote {
    final value = (note ?? '').replaceFirst(_variantPattern, '').trim();
    return value.isEmpty ? null : value;
  }

  static String? composeNote(String? variant, String? customerNote) {
    final clean = customerNote?.trim() ?? '';
    if (variant == null) return clean.isEmpty ? null : clean;
    if (!variantPrices.containsKey(variant)) throw ArgumentError('Varian minuman tidak valid.');
    return '[KAFE_VARIAN_v1:$variant]${clean.isEmpty ? '' : '\n$clean'}';
  }

  CartItem copyWith({
    Product? product,
    int? quantity,
    Object? note = _unset,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      note: identical(note, _unset) ? this.note : note as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': product.id,
      'productName': product.name,
      'category': product.category,
      'sellPrice': product.sellPrice,
      'baseCost': product.baseCost,
      'quantity': quantity,
      'note': note,
      'subtotal': subtotal,
      'subtotalProfit': subtotalProfit,
    };
  }

  factory CartItem.fromMap(Map<String, dynamic> map) {
    final rawNote = map['note'] as String?;
    return CartItem(
      product: Product(
        id: (map['productId'] as String?) ?? 'w_unknown',
        name: (map['productName'] as String?) ?? 'Item Menu',
        category: (map['category'] as String?) ?? 'Umum',
        sellPrice: ((map['sellPrice'] as num?) ?? 0).toDouble(),
        baseCost: ((map['baseCost'] as num?) ?? 0).toDouble(),
        stock: 999,
      ),
      quantity: ((map['quantity'] as num?) ?? 1).toInt(),
      note: (rawNote != null && rawNote.trim().isNotEmpty) ? rawNote.trim() : null,
    );
  }
}
