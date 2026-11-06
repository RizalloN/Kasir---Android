class OperationalExpense {
  static const List<String> defaultCategories = [
    'Biaya Listrik',
    'Biaya Air',
    'Gas LPG',
    'Kantong Plastik',
    'Sedotan',
    'Es Batu',
    'ATK',
    'Kebersihan & Sanitasi',
    'Perawatan & Servis',
    'Lainnya',
  ];

  final String id;
  final String title;
  final String category;
  final double amount;
  final DateTime createdAt;
  final String recordedBy;
  final String? notes;
  final bool isSynced;

  const OperationalExpense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.createdAt,
    required this.recordedBy,
    this.notes,
    this.isSynced = false,
  });

  OperationalExpense copyWith({
    String? id,
    String? title,
    String? category,
    double? amount,
    DateTime? createdAt,
    String? recordedBy,
    String? notes,
    bool? isSynced,
  }) {
    return OperationalExpense(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      createdAt: createdAt ?? this.createdAt,
      recordedBy: recordedBy ?? this.recordedBy,
      notes: notes ?? this.notes,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'amount': amount,
      'createdAt': createdAt.toIso8601String(),
      'recordedBy': recordedBy,
      'notes': notes,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory OperationalExpense.fromMap(Map<String, dynamic> map) {
    final rawNotes = map['notes'] as String?;
    return OperationalExpense(
      id: (map['id'] as String?) ?? 'exp_unknown',
      title: (map['title'] as String?) ?? 'Biaya Operasional',
      category: (map['category'] as String?) ?? 'Lainnya',
      amount: ((map['amount'] as num?) ?? 0).toDouble(),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      recordedBy: (map['recordedBy'] as String?) ?? 'Owner Warloc',
      notes: (rawNotes != null && rawNotes.trim().isNotEmpty)
          ? rawNotes.trim()
          : null,
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
    );
  }
}
