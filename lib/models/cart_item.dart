import 'product.dart';

class CartItem {
  static const Object _unset = Object();

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
