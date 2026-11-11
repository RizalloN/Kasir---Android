import 'dart:convert';
import 'cart_item.dart';
import 'user_role.dart';

class TransactionRecord {
  final String id;
  final String invoiceNumber;
  final List<CartItem> items;
  final double subtotalAmount;
  final double discountAmount;
  final double totalAmount;
  final double totalCost;
  final double totalProfit;
  final String paymentMethod; // Cash, QRIS
  final double amountPaid;
  final double changeAmount;
  final String cashierName;
  final String? cashierId;
  final String? openBillId;
  final int? openBillRevision;
  final String orderType; // Dine-In, Takeaway
  final String? customerName;
  final DateTime createdAt;
  final bool isSynced;
  final bool isVoided;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedById;
  final String? deletedByName;
  final String? deletionReason;
  final int revision;
  final List<Map<String, dynamic>> _corrections;
  List<Map<String, dynamic>> get corrections => _corrections.map((entry) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(entry)) as Map)).toList(growable: false);

  TransactionRecord({
    required this.id,
    required this.invoiceNumber,
    required this.items,
    double? subtotalAmount,
    this.discountAmount = 0.0,
    required this.totalAmount,
    required this.totalCost,
    required this.totalProfit,
    required this.paymentMethod,
    required this.amountPaid,
    required this.changeAmount,
    required this.cashierName,
    this.cashierId,
    this.openBillId,
    this.openBillRevision,
    this.orderType = 'Dine-In',
    this.customerName,
    required this.createdAt,
    this.isSynced = false,
    this.isVoided = false,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedById,
    this.deletedByName,
    this.deletionReason,
    this.revision = 0,
    List<Map<String, dynamic>> corrections = const [],
  }) : _corrections = corrections.map((entry) =>
          Map<String, dynamic>.from(jsonDecode(jsonEncode(entry)) as Map)).toList(growable: false),
       subtotalAmount = subtotalAmount ?? (totalAmount + discountAmount);

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

  bool canBeCorrectedBy({
    required UserRole role,
    required String userId,
    DateTime? now,
  }) {
    if (isVoided || isDeleted) return false;
    if (role == UserRole.owner) return true;
    if (cashierId != userId) return false;
    if (role != UserRole.barista) return true;
    final age = (now ?? DateTime.now()).difference(createdAt);
    return !age.isNegative && age <= const Duration(hours: 24);
  }

  TransactionRecord copyWith({
    String? id,
    String? invoiceNumber,
    List<CartItem>? items,
    double? subtotalAmount,
    double? discountAmount,
    double? totalAmount,
    double? totalCost,
    double? totalProfit,
    String? paymentMethod,
    double? amountPaid,
    double? changeAmount,
    String? cashierName,
    String? cashierId,
    String? openBillId,
    int? openBillRevision,
    String? orderType,
    String? customerName,
    DateTime? createdAt,
    bool? isSynced,
    bool? isVoided,
    bool? isDeleted,
    DateTime? deletedAt,
    String? deletedById,
    String? deletedByName,
    String? deletionReason,
    int? revision,
    List<Map<String, dynamic>>? corrections,
  }) {
    return TransactionRecord(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      items: items ?? this.items,
      subtotalAmount: subtotalAmount ?? this.subtotalAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      totalCost: totalCost ?? this.totalCost,
      totalProfit: totalProfit ?? this.totalProfit,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      amountPaid: amountPaid ?? this.amountPaid,
      changeAmount: changeAmount ?? this.changeAmount,
      cashierName: cashierName ?? this.cashierName,
      cashierId: cashierId ?? this.cashierId,
      openBillId: openBillId ?? this.openBillId,
      openBillRevision: openBillRevision ?? this.openBillRevision,
      orderType: orderType ?? this.orderType,
      customerName: customerName ?? this.customerName,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
      isVoided: isVoided ?? this.isVoided,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedById: deletedById ?? this.deletedById,
      deletedByName: deletedByName ?? this.deletedByName,
      deletionReason: deletionReason ?? this.deletionReason,
      revision: revision ?? this.revision,
      corrections: corrections ?? this.corrections,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoiceNumber': invoiceNumber,
      'items': items.map((e) => e.toMap()).toList(),
      'subtotalAmount': subtotalAmount,
      'discountAmount': discountAmount,
      'totalAmount': totalAmount,
      'totalCost': totalCost,
      'totalProfit': totalProfit,
      'paymentMethod': paymentMethod,
      'amountPaid': amountPaid,
      'changeAmount': changeAmount,
      'cashierName': cashierName,
      'cashierId': cashierId,
      'openBillId': openBillId,
      'openBillRevision': openBillRevision,
      'orderType': orderType,
      'customerName': customerName,
      'createdAt': createdAt.toIso8601String(),
      'isSynced': isSynced ? 1 : 0,
      'isVoided': isVoided ? 1 : 0,
      if (isDeleted) ...{
        'isDeleted': true,
        'deletedAt': deletedAt?.toIso8601String(),
        'deletedById': deletedById,
        'deletedByName': deletedByName,
        'deletionReason': deletionReason,
      },
      if (revision > 0) 'revision': revision,
      if (corrections.isNotEmpty) 'corrections': corrections,
    };
  }

  factory TransactionRecord.fromMap(Map<String, dynamic> map) {
    final total = ((map['totalAmount'] as num?) ?? 0).toDouble();
    final discount = ((map['discountAmount'] as num?) ?? 0).toDouble();
    final subtotal = ((map['subtotalAmount'] as num?)?.toDouble()) ?? (total + discount);
    final rawItems = (map['items'] as List<dynamic>?) ?? const [];
    final rawCust = map['customerName'] as String?;

    return TransactionRecord(
      id: (map['id'] as String?) ?? 'INV-UNKNOWN',
      invoiceNumber: (map['invoiceNumber'] as String?) ?? 'INV-UNKNOWN',
      items: rawItems
          .map((itemMap) => CartItem.fromMap(Map<String, dynamic>.from(itemMap as Map)))
          .toList(),
      subtotalAmount: subtotal,
      discountAmount: discount,
      totalAmount: total,
      totalCost: ((map['totalCost'] as num?) ?? 0).toDouble(),
      totalProfit: ((map['totalProfit'] as num?) ?? 0).toDouble(),
      paymentMethod: (map['paymentMethod'] as String?) ?? 'Tunai',
      amountPaid: ((map['amountPaid'] as num?) ?? total).toDouble(),
      changeAmount: ((map['changeAmount'] as num?) ?? 0).toDouble(),
      cashierName: (map['cashierName'] as String?) ?? 'Kasir Warloc',
      cashierId: map['cashierId'] as String?,
      openBillId: map['openBillId'] as String?,
      openBillRevision: map['openBillRevision'] as int?,
      orderType: (map['orderType'] as String?) ?? 'Dine-In',
      customerName: (rawCust != null && rawCust.trim().isNotEmpty) ? rawCust.trim() : null,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
      isVoided: map['isVoided'] == 1 || map['isVoided'] == true,
      isDeleted: map['isDeleted'] == 1 || map['isDeleted'] == true,
      deletedAt: map['deletedAt'] is String ? DateTime.tryParse(map['deletedAt'] as String) : null,
      deletedById: map['deletedById'] as String?,
      deletedByName: map['deletedByName'] as String?,
      deletionReason: map['deletionReason'] as String?,
      revision: (map['revision'] as num?)?.toInt() ?? 0,
      corrections: (map['corrections'] as List<dynamic>? ?? const [])
          .map((entry) => Map<String, dynamic>.from(entry as Map)).toList(),
    );
  }
}
