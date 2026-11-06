import 'cart_item.dart';

class OpenBill {
  final String id;
  final String customerName;
  final String orderType;
  final String createdBy;
  final DateTime createdAt;
  final int revision;
  final double discountAmount;
  final List<CartItem> _items;

  OpenBill({
    required this.id,
    required this.customerName,
    required this.orderType,
    required this.createdBy,
    required this.createdAt,
    required List<CartItem> items,
    this.revision = 1,
    this.discountAmount = 0,
  }) : _items = items.map((i) => i.copyWith()).toList();

  List<CartItem> get items =>
      List.unmodifiable(_items.map((i) => i.copyWith()));
  double get totalAmount =>
      (_items.fold(0.0, (sum, item) => sum + item.subtotal) - discountAmount)
          .clamp(0, double.infinity);

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerName': customerName,
        'orderType': orderType,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'revision': revision,
        'discountAmount': discountAmount,
        'items': _items.map((i) => i.toMap()).toList(),
      };

  factory OpenBill.fromMap(Map<String, dynamic> map) => OpenBill(
        id: map['id'] as String,
        customerName: map['customerName'] as String,
        orderType: map['orderType'] as String,
        createdBy: map['createdBy'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        revision: map['revision'] as int? ?? 1,
        discountAmount: (map['discountAmount'] as num?)?.toDouble() ?? 0,
        items: (map['items'] as List)
            .map((i) => CartItem.fromMap(Map<String, dynamic>.from(i as Map)))
            .toList(),
      );
}
