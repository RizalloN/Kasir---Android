enum UserRole {
  barista,
  admin,
  owner,
}

extension UserRoleExtension on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.barista:
        return 'Barista (Kasir)';
      case UserRole.admin:
        return 'Admin Toko';
      case UserRole.owner:
        return 'Owner (Pemilik)';
    }
  }

  String get shortName {
    switch (this) {
      case UserRole.barista:
        return 'Barista';
      case UserRole.admin:
        return 'Admin';
      case UserRole.owner:
        return 'Owner';
    }
  }

  String get subtitle {
    switch (this) {
      case UserRole.barista:
        return 'Operasional Kasir & Cetak Struk';
      case UserRole.admin:
        return 'Kasir, Kelola Stok & Katalog Menu';
      case UserRole.owner:
        return 'Kontrol Penuh: Keuangan, Stok & Staff';
    }
  }

  String get permissionSummary {
    switch (this) {
      case UserRole.barista:
        return 'Transaksi Kasir & Struk';
      case UserRole.admin:
        return 'Kasir + Inventori & Harga';
      case UserRole.owner:
        return 'Akses Penuh (Full Control)';
    }
  }

  bool get canEditProducts => this == UserRole.admin || this == UserRole.owner;
  bool get canManageCategories => this == UserRole.admin || this == UserRole.owner;
  bool get canAdjustStock => this == UserRole.admin || this == UserRole.owner;
  bool get canViewFinancialReports => this == UserRole.owner;
  bool get canChangePrices => this == UserRole.admin || this == UserRole.owner;
  bool get canManageUsers => this == UserRole.owner;
  bool get canVoidTransactions => this == UserRole.owner;
}
