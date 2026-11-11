import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../services/secure_preferences.dart';
import '../models/user_role.dart';
import '../models/user_profile.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../models/transaction.dart';
import '../models/operational_expense.dart';
import '../models/open_bill.dart';
import '../services/pos_database_service.dart';
import '../services/thermal_printer_service.dart';

class TopProductStat {
  final String productId;
  final String name;
  final String category;
  final int quantitySold;
  final double revenue;

  const TopProductStat({
    required this.productId,
    required this.name,
    required this.category,
    required this.quantitySold,
    required this.revenue,
  });
}

class AnalyticsPoint {
  final String label;
  final String subtitle;
  final double value;
  final double secondaryValue;

  const AnalyticsPoint({
    required this.label,
    required this.subtitle,
    required this.value,
    this.secondaryValue = 0.0,
  });
}

class CategorySliceStat {
  final String category;
  final double revenue;
  final int quantity;

  const CategorySliceStat({
    required this.category,
    required this.revenue,
    required this.quantity,
  });
}

class OperationalProfitSummary {
  final DateTime startDate;
  final DateTime endDate;
  final double totalRevenue;
  final double totalCogs;
  final double grossProfit;
  final double operationalExpenses;
  final double netProfit;
  final int transactionCount;
  final int expenseCount;
  final Map<String, double> expenseCategoryBreakdown;
  final double grossMarginPct;
  final double netMarginPct;

  const OperationalProfitSummary({
    required this.startDate,
    required this.endDate,
    required this.totalRevenue,
    required this.totalCogs,
    required this.grossProfit,
    required this.operationalExpenses,
    required this.netProfit,
    required this.transactionCount,
    required this.expenseCount,
    required this.expenseCategoryBreakdown,
    required this.grossMarginPct,
    required this.netMarginPct,
  });

  bool get isProfitable => netProfit >= 0;
}

class RevenueComparisonSummary {
  final DateTime referenceDate;
  final DateTime prevMonthLastDate;
  final DateTime prevMonthSameDate;

  /// True when today is the last day of the current month (e.g. 31 Oct)
  /// or when clamping puts MTM on the exact same date as MTD (prevMonthLastDate).
  /// When true, UI shows MTD only and omits duplicate MTM.
  final bool collapseMtmIntoMtd;

  // Daily metrics
  final double todayRevenue;
  final double todayGrossProfit;
  final double todayOperationalExpense;
  final int todayTransactionCount;
  final double mtdPrevMonthLastDayRevenue;
  final double mtmPrevMonthSameDayRevenue;

  // Monthly cumulative metrics
  final double currentMonthRevenue;
  final double currentMonthGrossProfit;
  final double currentMonthOperationalExpense;
  final int currentMonthTransactionCount;
  final double prevMonthFullRevenue;
  final double prevMonthMtmCumulativeRevenue;

  const RevenueComparisonSummary({
    required this.referenceDate,
    required this.prevMonthLastDate,
    required this.prevMonthSameDate,
    required this.collapseMtmIntoMtd,
    required this.todayRevenue,
    required this.todayGrossProfit,
    required this.todayOperationalExpense,
    required this.todayTransactionCount,
    required this.mtdPrevMonthLastDayRevenue,
    required this.mtmPrevMonthSameDayRevenue,
    required this.currentMonthRevenue,
    required this.currentMonthGrossProfit,
    required this.currentMonthOperationalExpense,
    required this.currentMonthTransactionCount,
    required this.prevMonthFullRevenue,
    required this.prevMonthMtmCumulativeRevenue,
  });

  double get todayNetProfit => todayGrossProfit - todayOperationalExpense;
  double get currentMonthNetProfit =>
      currentMonthGrossProfit - currentMonthOperationalExpense;

  double get todayVsMtdDelta => todayRevenue - mtdPrevMonthLastDayRevenue;
  double? get todayVsMtdPct =>
      _computePct(todayRevenue, mtdPrevMonthLastDayRevenue);

  double get todayVsMtmDelta => todayRevenue - mtmPrevMonthSameDayRevenue;
  double? get todayVsMtmPct =>
      _computePct(todayRevenue, mtmPrevMonthSameDayRevenue);

  double get monthVsMtdDelta => currentMonthRevenue - prevMonthFullRevenue;
  double? get monthVsMtdPct =>
      _computePct(currentMonthRevenue, prevMonthFullRevenue);

  double get monthVsMtmDelta =>
      currentMonthRevenue - prevMonthMtmCumulativeRevenue;
  double? get monthVsMtmPct =>
      _computePct(currentMonthRevenue, prevMonthMtmCumulativeRevenue);

  static double? _computePct(double current, double baseline) {
    if (baseline <= 0) return null;
    return ((current - baseline) / baseline) * 100.0;
  }
}

class OpenBillQuote {
  final OpenBill bill;
  final List<CartItem> _items;
  final double discount;
  OpenBillQuote({required this.bill, required List<CartItem> items, required this.discount})
      : _items = items.map((item) => item.copyWith()).toList();
  List<CartItem> get items => List.unmodifiable(_items.map((item) => item.copyWith()));
  double get subtotal => _items.fold(0, (sum, item) => sum + item.subtotal);
  double get total => subtotal - discount;
  double get cost => _items.fold(0, (sum, item) => sum + item.subtotalCost);
  String get signature => jsonEncode({'id': bill.id, 'revision': bill.revision,
    'discount': discount, 'items': _items.map((item) => item.toMap()).toList()});
}

class PosProvider extends ChangeNotifier {
  final PosDatabaseService _db = PosDatabaseService.instance;

  bool _isInitialized = false;
  String? initializationError;
  bool _disposed = false;
  Timer? _sessionTimer;
  DateTime? _sessionExpiresAt;
  bool _changingOwnPassword = false;
  bool get requiresPasswordChange => false;
  bool get isInitialized => _isInitialized;

  UserProfile? _currentUser;
  UserProfile? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null &&
      (_sessionExpiresAt == null || DateTime.now().isBefore(_sessionExpiresAt!));

  UserRole get currentRole => _currentUser?.role ?? UserRole.barista;

  List<Product> _products = [];
  List<Product> get products => List.unmodifiable(_products);

  List<TransactionRecord> _transactions = [];
  List<TransactionRecord> get transactions => List.unmodifiable(
    (currentRole.canViewFinancialReports && isAuthenticated ? _transactions :
      _transactions.where((t) => t.cashierId == _currentUser?.id && isAuthenticated))
      .map((t) => t.copyWith(items: t.items.map((i) => i.copyWith()).toList())),
  );

  List<OperationalExpense> _operationalExpenses = [];
  List<OperationalExpense> get operationalExpenses =>
      isAuthenticated && currentRole.canViewFinancialReports ? List.unmodifiable(_operationalExpenses) : const [];

  List<UserProfile> _users = [];
  List<UserProfile> get users => isAuthenticated && currentRole.canManageUsers ? List.unmodifiable(_users) : const [];

  List<String> _categories = [];
  List<String> get categories => List.unmodifiable(_categories);

  final List<CartItem> _cart = [];
  List<OpenBill> _openBills = [];
  String? _activeBillId;
  String? get activeBillId => _activeBillId;
  bool get isCheckoutInProgress => _checkoutInProgress;
  int? _activeBillRevision;
  bool _savingBill = false;
  StreamSubscription? _billsSub;
  List<OpenBill> get openBills => !isAuthenticated ? const [] : List.unmodifiable(
    _openBills.where((b) => currentRole != UserRole.barista || b.createdBy == _currentUser!.id));

  Future<OpenBill> saveCurrentBill() async {
    if (_savingBill) throw StateError('Tagihan sedang disimpan.');
    _savingBill = true;
    try { return await _saveCurrentBill(); } finally { _savingBill = false; }
  }

  Future<OpenBill> _saveCurrentBill() async {
    _requirePermission(true);
    if (_checkoutInProgress || _cart.isEmpty) throw StateError('Pesanan kosong atau sedang diproses.');
    if (_customerName.trim().isEmpty) throw StateError('Isi nama pelanggan / meja sebelum menyimpan tagihan.');
    final existing = _activeBillId == null ? null : openBills.where((b) => b.id == _activeBillId).firstOrNull;
    if (_activeBillId != null && existing == null) throw StateError('Tagihan tidak dapat diakses.');
    final bill = OpenBill(
      id: _activeBillId ?? 'BILL-${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff)}',
      customerName: _customerName.trim(), orderType: _orderType,
      createdBy: existing?.createdBy ?? _currentUser!.id,
      createdAt: existing?.createdAt ?? DateTime.now(),
      revision: (existing?.revision ?? 0) + 1,
      discountAmount: effectiveDiscount, items: _cart,
    );
    await _db.saveOpenBill(bill, expectedRevision: _activeBillRevision);
    _openBills = _db.getOpenBills();
    _resetCart();
    return bill;
  }

  OpenBillQuote quoteOpenBill(String id) {
    _requirePermission(true);
    final bill = openBills.where((bill) => bill.id == id).firstOrNull;
    if (bill == null) throw StateError('Tagihan tidak ditemukan atau akses ditolak.');
    if (bill.items.isEmpty || !bill.discountAmount.isFinite || bill.discountAmount < 0) {
      throw StateError('Data tagihan tidak valid. Periksa kembali pesanan.');
    }
    final items = <CartItem>[];
    final quantities = <String, int>{};
    for (final item in bill.items) {
      final live = _products.where((product) => product.id == item.product.id).firstOrNull;
      final quantity = (quantities[item.product.id] ?? 0) + item.quantity;
      if (live == null || !live.isAvailable || item.quantity < 1 || quantity > live.stock ||
          (item.drinkVariant != null && !live.isDrink) || !live.sellPrice.isFinite ||
          live.sellPrice < 0 || !live.baseCost.isFinite || live.baseCost < 0) {
        throw StateError('Menu atau stok tagihan berubah. Periksa menu sebelum melanjutkan.');
      }
      quantities[live.id] = quantity;
      items.add(item.copyWith(product: live.copyWith(
        sellPrice: live.sellPrice + (CartItem.variantPrices[item.drinkVariant] ?? 0))));
    }
    final subtotal = items.fold(0.0, (sum, item) => sum + item.subtotal);
    if (!subtotal.isFinite) throw StateError('Nominal tagihan tidak valid.');
    return OpenBillQuote(bill: bill, items: items, discount: bill.discountAmount.clamp(0, subtotal).toDouble());
  }

  Future<TransactionRecord> payOpenBill(OpenBillQuote reviewed, {
    required String paymentMethod, required double amountPaid,
  }) async {
    _requirePermission(true);
    if (_checkoutInProgress || _savingBill) throw StateError('Pembayaran atau penyimpanan sedang diproses.');
    if (_activeBillId == reviewed.bill.id) throw StateError('Simpan perubahan pesanan di Menu sebelum membayar tagihan ini.');
    if (!['Cash', 'QRIS'].contains(paymentMethod)) throw ArgumentError('Metode pembayaran tidak valid.');
    final current = quoteOpenBill(reviewed.bill.id);
    if (current.signature != reviewed.signature) throw StateError('Tagihan atau harga berubah. Tinjau ulang sebelum membayar.');
    if (!amountPaid.isFinite || amountPaid < current.total || (paymentMethod == 'QRIS' && amountPaid != current.total)) {
      throw ArgumentError('Nominal pembayaran tidak sesuai dengan total tagihan.');
    }
    _checkoutInProgress = true;
    try {
      final now = DateTime.now();
      final id = 'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff)}';
      final saved = await _db.processTransaction(TransactionRecord(
        id: id, invoiceNumber: id, items: current.items,
        subtotalAmount: current.subtotal, discountAmount: current.discount,
        totalAmount: current.total, totalCost: current.cost, totalProfit: current.total - current.cost,
        paymentMethod: paymentMethod, amountPaid: amountPaid, changeAmount: amountPaid - current.total,
        cashierName: _currentUser!.displayName, cashierId: _currentUser!.id,
        openBillId: current.bill.id, openBillRevision: current.bill.revision,
        orderType: current.bill.orderType, customerName: current.bill.customerName, createdAt: now,
      ));
      _products = _db.getProducts();
      _transactions = _db.getTransactions();
      _openBills = _db.getOpenBills();
      notifyListeners();
      return saved;
    } finally { _checkoutInProgress = false; }
  }

  void resumeOpenBill(String id) {
    _requirePermission(true);
    if (_cart.isNotEmpty || _checkoutInProgress || _savingBill) throw StateError('Simpan atau kosongkan pesanan aktif terlebih dahulu.');
    final bill = openBills.where((b) => b.id == id).firstOrNull;
    if (bill == null) throw StateError('Tagihan tidak ditemukan atau akses ditolak.');
    final resolved = <CartItem>[];
    final quantities = <String, int>{};
    for (final item in bill.items) {
      final live = _products.where((p) => p.id == item.product.id).firstOrNull;
      final total = (quantities[item.product.id] ?? 0) + item.quantity;
      if (live == null || !live.isAvailable || total > live.stock || item.quantity < 1) {
        throw StateError('Stok/menu tagihan berubah. Periksa inventori terlebih dahulu.');
      }
      quantities[item.product.id] = total;
      resolved.add(item.copyWith(product: live.copyWith(sellPrice: live.sellPrice + (CartItem.variantPrices[item.drinkVariant] ?? 0))));
    }
    _cart.addAll(resolved);
    _customerName = bill.customerName;
    _orderType = bill.orderType;
    _discountAmount = bill.discountAmount;
    _activeBillId = bill.id;
    _activeBillRevision = bill.revision;
    notifyListeners();
  }

  Future<void> deleteOpenBill(String id) async {
    _requirePermission(true);
    if (!openBills.any((b) => b.id == id)) throw StateError('Akses ditolak.');
    if (_activeBillId == id || _checkoutInProgress || _savingBill) throw StateError('Tagihan sedang digunakan.');
    _savingBill = true;
    try {
      await _db.deleteOpenBill(id);
      _openBills = _db.getOpenBills();
      notifyListeners();
    } finally { _savingBill = false; }
  }
  List<CartItem> get cart => List.unmodifiable(_cart.map((i) => i.copyWith()));

  // Order Metadata
  String _orderType = 'Dine-In';
  String get orderType => _orderType;

  String _customerName = '';
  String get customerName => _customerName;

  double _discountAmount = 0.0;
  double get discountAmount => _discountAmount;

  String _selectedCategory = 'Semua';
  String get selectedCategory => _selectedCategory;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  // Printer Configuration (Persisted)
  int _printerPaperWidth = 58;
  int get printerPaperWidth => _printerPaperWidth;

  String _selectedPrinterName = '';
  String get selectedPrinterName => _selectedPrinterName;

  String _selectedPrinterMac = '';
  String get selectedPrinterMac => _selectedPrinterMac;

  bool _isPrinterConnected = false;
  bool get isPrinterConnected => _isPrinterConnected;

  StreamSubscription? _productsSub;
  StreamSubscription? _transactionsSub;
  StreamSubscription? _usersSub;
  StreamSubscription? _categoriesSub;
  StreamSubscription? _expensesSub;
  StreamSubscription<bool>? _connectionSub;

  PosProvider() {
    _init();
  }

  Future<void> _init() async {
    try { await _load(); } catch (_) {
      if (!_disposed) {
        initializationError = 'Penyimpanan aplikasi tidak dapat dibuka. Data tetap dipertahankan. Tutup dan buka kembali aplikasi.';
        notifyListeners();
      }
    }
  }

  Future<void> _load() async {
    await _db.initialize();
    _isOnline = _db.isOnline;
    _connectionSub = _db.connectionStream.listen((online) {
      _isOnline = online;
      if (!_disposed) notifyListeners();
    });
    _products = _db.getProducts();
    _transactions = _db.getTransactions();
    _users = _db.getUsers();
    _categories = _db.getCategories();
    _operationalExpenses = _db.getOperationalExpenses();
    _openBills = _db.getOpenBills();
    _billsSub = _db.openBillsStream.listen((bills) { _openBills = bills; notifyListeners(); });

    final prefs = await SecurePreferences.getInstance();

    // Restore printer preferences
    _printerPaperWidth = prefs.getInt('printer_paper_width') ?? 58;
    _selectedPrinterName = prefs.getString('printer_device_name') ?? '';
    _selectedPrinterMac = prefs.getString('printer_device_mac') ?? '';

    try {
      _isPrinterConnected = await ThermalPrinterService.instance.isConnected();
    } catch (_) {
      _isPrinterConnected = false;
    }

    // Restore active session if valid & active
    _currentUser = await _db.restoreSession();
    if (_currentUser != null) {
      _sessionExpiresAt = DateTime.fromMillisecondsSinceEpoch(prefs.getInt('saved_session_expires_at')!);
      _scheduleSessionExpiry();
      _refreshFromDatabase();
    }
    if (_disposed) return;

    _productsSub = _db.productsStream.listen((updatedList) {
      _products = updatedList;
      _reconcileCartWithCatalog();
      notifyListeners();
    });

    _transactionsSub = _db.transactionsStream.listen((updatedList) {
      _transactions = updatedList;
      notifyListeners();
    });

    _expensesSub = _db.operationalExpensesStream.listen((updatedList) {
      _operationalExpenses = updatedList;
      notifyListeners();
    });

    _usersSub = _db.usersStream.listen((updatedList) {
      _users = updatedList;
      if (_currentUser != null) {
        final currentId = _currentUser!.id;
        final refreshed = updatedList.where((u) => u.id == currentId).toList();
        if (refreshed.isEmpty || !refreshed.first.isActive || (!_changingOwnPassword &&
            (refreshed.first.passwordHash != _currentUser!.passwordHash || refreshed.first.salt != _currentUser!.salt))) {
          logout();
          return;
        }
        _currentUser = refreshed.first;
      }
      notifyListeners();
    });

    _categoriesSub = _db.categoriesStream.listen((updatedList) {
      _categories = updatedList;
      if (_selectedCategory != 'Semua' &&
          !availableCategories.contains(_selectedCategory)) {
        _selectedCategory = 'Semua';
      }
      notifyListeners();
    });

    _isInitialized = true;
    notifyListeners();
  }

  /// Ensures cart items reflect live catalog prices, stock ceilings, and availability
  void _reconcileCartWithCatalog() {
    if (_cart.isEmpty) return;
    final byId = {for (final p in _products) p.id: p};
    final remaining = {for (final p in _products) p.id: p.stock};
    for (int i = _cart.length - 1; i >= 0; i--) {
      final live = byId[_cart[i].product.id];
      if (live == null || !live.isAvailable || (remaining[live.id] ?? 0) <= 0) {
        _cart.removeAt(i);
      } else {
        _cart[i].product = live.copyWith(sellPrice: live.sellPrice + (CartItem.variantPrices[_cart[i].drinkVariant] ?? 0));
        if (_cart[i].quantity > remaining[live.id]!) {
          _cart[i].quantity = remaining[live.id]!;
        }
        remaining[live.id] = remaining[live.id]! - _cart[i].quantity;
      }
    }
    if (_selectedCategory != 'Semua' &&
        !availableCategories.contains(_selectedCategory)) {
      _selectedCategory = 'Semua';
    }
  }

  // Authentication & Session Management
  bool _loginInProgress = false;
  int _sessionGeneration = 0;
  Future<String?> login(String username, String password) async {
    if (_loginInProgress) return 'Login sedang diproses.';
    if (!_isInitialized) return 'Aplikasi belum siap.';
    _loginInProgress = true;
    try { return await _login(username, password, _sessionGeneration); }
    finally { _loginInProgress = false; }
  }

  Future<String?> _login(String username, String password, int generation) async {
    if (_checkoutInProgress) return 'Pembayaran sedang diproses.';
    final cleanUsername = username.trim().toLowerCase();
    final cleanPassword = password;

    if (cleanUsername.isEmpty) return 'Masukkan username terlebih dahulu.';
    if (cleanPassword.isEmpty) return 'Masukkan password terlebih dahulu.';

    final prefs = await SecurePreferences.getInstance();
    UserProfile? authenticated;
    try { authenticated = await _db.authenticateAsync(cleanUsername, cleanPassword); }
    catch (_) { return 'Terlalu banyak percobaan. Coba lagi dalam 30 detik.'; }
    if (_disposed || generation != _sessionGeneration) { _db.endSession(); return 'Sesi sudah berubah.'; }
    if (authenticated == null) return 'Username/password tidak valid atau akun tidak aktif.';

    final updated = authenticated.copyWith(lastLoginAt: DateTime.now());
    _resetCart(silent: true);
    _currentUser = updated;
    await _db.recordLogin(updated);

    await prefs.setString('saved_active_user_id', updated.id);
    _sessionExpiresAt = DateTime.now().add(const Duration(hours: 12));
    await prefs.setInt('saved_session_expires_at', _sessionExpiresAt!.millisecondsSinceEpoch);
    _scheduleSessionExpiry();
    _refreshFromDatabase();
    _openBills = _db.getOpenBills();

    notifyListeners();
    return null;
  }

  Future<void> logout() async {
    _sessionGeneration++;
    _sessionTimer?.cancel();
    _db.endSession();
    _currentUser = null;
    _resetCart(silent: true);
    _selectedCategory = 'Semua';
    _searchQuery = '';
    final prefs = await SecurePreferences.getInstance();
    await prefs.remove('saved_active_user_id');
    await prefs.remove('saved_session_expires_at');
    notifyListeners();
  }

  void _scheduleSessionExpiry() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(_sessionExpiresAt!.difference(DateTime.now()), () { unawaited(logout()); });
  }

  Future<void> changeOwnPassword(String oldPassword, String newPassword) async {
    if (!isAuthenticated || !currentRole.canChangeOwnPassword) throw StateError('Akses ditolak.');
    if (_changingOwnPassword) throw StateError('Perubahan password sedang diproses.');
    _changingOwnPassword = true;
    try {
      final changed = await _db.changeOwnPassword(oldPassword, newPassword);
      _currentUser = changed;
      _users = _db.getUsers();
      notifyListeners();
    } finally { _changingOwnPassword = false; }
  }

  void _refreshFromDatabase() {
    _products = _db.getProducts();
    _transactions = _db.getTransactions();
    _users = _db.getUsers();
    _categories = _db.getCategories();
    _operationalExpenses = _db.getOperationalExpenses();
    _openBills = _db.getOpenBills();
    _reconcileCartWithCatalog();
  }

  // Staff & User Management (Owner Access)
  Future<String?> saveUserProfile(UserProfile user) async {
    if (!isAuthenticated || !currentRole.canManageUsers) return 'Akses ditolak.';
    final existing = _users.where((u) => u.id == user.id).firstOrNull;
    if (existing != null && (existing.id == _currentUser!.id || existing.username == 'warloc.owner') &&
        (!user.isActive || user.role != UserRole.owner || user.username != existing.username)) {
      return 'Akun owner utama atau akun sendiri tidak boleh dinonaktifkan/demotasikan.';
    }
    final error = await _db.saveUser(user);
    if (error != null) return error;

    _users = _db.getUsers();
    if (_currentUser?.id == user.id) {
      _currentUser = user;
    }
    notifyListeners();
    return null;
  }

  Future<bool> deleteUserProfile(String userId) async {
    if (!isAuthenticated || !currentRole.canManageUsers) return false;
    if (_currentUser?.id == userId) return false;
    final success = await _db.deleteUser(userId);
    _users = _db.getUsers();
    notifyListeners();
    return success;
  }


  // Printer Preferences
  Future<void> setPrinterPaperWidth(int width) async {
    _printerPaperWidth = width;
    notifyListeners();
    final prefs = await SecurePreferences.getInstance();
    await prefs.setInt('printer_paper_width', width);
  }

  Future<void> setSelectedPrinter(String name, String mac) async {
    _selectedPrinterName = name;
    _selectedPrinterMac = mac;
    notifyListeners();
    final prefs = await SecurePreferences.getInstance();
    await prefs.setString('printer_device_name', name);
    await prefs.setString('printer_device_mac', mac);
  }

  Future<void> setSelectedPrinterName(String name, {String mac = ''}) async {
    _selectedPrinterName = name;
    _selectedPrinterMac = mac;
    notifyListeners();
    final prefs = await SecurePreferences.getInstance();
    await prefs.setString('printer_device_name', name);
    await prefs.setString('printer_device_mac', mac);
  }

  Future<void> setPrinterConnected(bool connected) async {
    _isPrinterConnected = connected;
    notifyListeners();
    final prefs = await SecurePreferences.getInstance();
    await prefs.setBool('printer_connected', connected);
  }

  Future<void> checkPrinterConnection() async {
    try {
      _isPrinterConnected = await ThermalPrinterService.instance.isConnected();
    } catch (_) {
      _isPrinterConnected = false;
    }
    notifyListeners();
  }

  // Category Management (Admin & Owner)
  Future<String?> addCategory(String category) async {
    if (!isAuthenticated || !currentRole.canManageCategories) {
      return 'Akses ditolak: Hanya Admin atau Owner yang dapat menambah kategori.';
    }
    final error = await _db.addCategory(category);
    if (error == null) {
      _categories = _db.getCategories();
      notifyListeners();
    }
    return error;
  }

  Future<String?> updateCategory(String oldCategory, String newCategory) async {
    if (!isAuthenticated || !currentRole.canManageCategories) {
      return 'Akses ditolak: Hanya Admin atau Owner yang dapat mengedit kategori.';
    }
    final error = await _db.updateCategory(oldCategory, newCategory);
    if (error == null) {
      _categories = _db.getCategories();
      _products = _db.getProducts();
      if (_selectedCategory == oldCategory) {
        _selectedCategory = newCategory.trim();
      }
      notifyListeners();
    }
    return error;
  }

  Future<String?> deleteCategory(String category) async {
    if (!isAuthenticated || !currentRole.canManageCategories) {
      return 'Akses ditolak: Hanya Admin atau Owner yang dapat menghapus kategori.';
    }
    final error = await _db.deleteCategory(category);
    if (error == null) {
      _categories = _db.getCategories();
      _products = _db.getProducts();
      if (_selectedCategory == category) {
        _selectedCategory = 'Semua';
      }
      notifyListeners();
    }
    return error;
  }

  int get pendingSyncCount {
    final unsyncedTx = _transactions.where((t) => !t.isSynced).length;
    final unsyncedProd = _products.where((p) => !p.isSynced).length;
    final unsyncedExp = _operationalExpenses.where((e) => !e.isSynced).length;
    return unsyncedTx + unsyncedProd + unsyncedExp + _db.pendingDeletionCount + _db.pendingMetadataCount + _db.pendingDeletedTransactionCount;
  }

  // Catalog Filtering
  void selectCategory(String category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  List<Product> get visibleCatalogProducts {
    if (currentRole.canEditProducts) {
      return _products;
    }
    return _products.where((p) => p.isAvailable).toList();
  }

  List<Product> get filteredProducts {
    final source = visibleCatalogProducts;
    final query = _searchQuery.trim().toLowerCase();

    return source.where((p) {
      final matchesCategory =
          _selectedCategory == 'Semua' || p.category == _selectedCategory;
      final matchesSearch =
          query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          p.category.toLowerCase().contains(query) ||
          (p.barcode != null && p.barcode!.toLowerCase().contains(query));
      return matchesCategory && matchesSearch;
    }).toList();
  }

  List<String> get availableCategories {
    final Set<String> all = {'Semua', ..._categories};
    for (final p in visibleCatalogProducts) {
      if (p.category.trim().isNotEmpty) {
        all.add(p.category.trim());
      }
    }
    final sorted = all.where((c) => c != 'Semua').toList()..sort();
    return ['Semua', ...sorted];
  }

  int countProductsInCategory(String category) {
    final source = visibleCatalogProducts;
    if (category == 'Semua') return source.length;
    return source.where((p) => p.category == category).length;
  }

  Product? findProductByBarcode(String barcode) {
    final clean = barcode.trim().toLowerCase();
    if (clean.isEmpty) return null;
    for (final p in visibleCatalogProducts) {
      if (p.barcode != null && p.barcode!.trim().toLowerCase() == clean) {
        return p;
      }
    }
    return null;
  }

  // Order & Cart Operations
  void setOrderType(String type) {
    if (_checkoutInProgress || _savingBill) return;
    if (!['Dine-In', 'Takeaway'].contains(type)) throw ArgumentError('Tipe pesanan tidak valid.');
    if (_orderType == type) return;
    _orderType = type;
    notifyListeners();
  }

  void setCustomerName(String name) {
    if (_checkoutInProgress || _savingBill) return;
    _customerName = name;
  }

  void setDiscountAmount(double discount) {
    if (_checkoutInProgress || _savingBill) return;
    if (!discount.isFinite || discount < 0) throw ArgumentError('Diskon tidak valid.');
    final clamped = discount.clamp(0.0, subtotalCartAmount);
    if (_discountAmount == clamped) return;
    _discountAmount = clamped;
    notifyListeners();
  }

  /// Adds product to cart. Returns false if unavailable or stock limit reached.
  bool addToCart(Product product, {String? note, String? variant}) {
    if (!isAuthenticated || _checkoutInProgress || _savingBill) return false;
    final catalog = _products.where((p) => p.id == product.id).firstOrNull;
    if (catalog == null) return false;
    product = catalog;
    if (variant != null && (!CartItem.variantPrices.containsKey(variant) || !product.isDrink)) return false;
    if (!product.isAvailable || product.stock <= 0) return false;

    final totalQuantity = _cart.where((item) => item.product.id == product.id).fold<int>(0, (sum, item) => sum + item.quantity);
    if (totalQuantity >= product.stock) return false;

    final existingIndex = _cart.indexWhere(
      (item) => item.product.id == product.id && item.drinkVariant == variant,
    );
    if (existingIndex != -1) {
      if (_cart[existingIndex].quantity >= product.stock) {
        return false;
      }
      _cart[existingIndex].quantity++;
      if (note != null && note.trim().isNotEmpty) {
        _cart[existingIndex].note = CartItem.composeNote(variant, note);
      }
    } else {
      _cart.add(
        CartItem(
          product: product.copyWith(sellPrice: product.sellPrice + (CartItem.variantPrices[variant] ?? 0)),
          quantity: 1,
          note: CartItem.composeNote(variant, note),
        ),
      );
    }
    notifyListeners();
    return true;
  }

  static const _anyVariant = Object();

  /// Adjusts cart item quantity by [delta]. Returns false if capped by stock.
  bool updateQuantity(String productId, int delta, {Object? variant = _anyVariant}) {
    if (!isAuthenticated || _checkoutInProgress || _savingBill) return false;
    final index = _cart.indexWhere((item) => item.product.id == productId && (identical(variant, _anyVariant) || item.drinkVariant == variant));
    if (index == -1) return false;

    final liveProduct = _products.firstWhere(
      (p) => p.id == productId,
      orElse: () => _cart[index].product,
    );
    _cart[index].product = liveProduct.copyWith(sellPrice: liveProduct.sellPrice + (CartItem.variantPrices[_cart[index].drinkVariant] ?? 0));

    final newQty = _cart[index].quantity + delta;
    if (newQty <= 0) {
      _cart.removeAt(index);
      if (_cart.isEmpty) _discountAmount = 0.0;
      notifyListeners();
      return true;
    }

    final otherQuantity = _cart.where((item) => item.product.id == productId).fold<int>(0, (sum, item) => sum + item.quantity) - _cart[index].quantity;
    if (newQty + otherQuantity > liveProduct.stock) {
      return false;
    }

    _cart[index].quantity = newQty;
    notifyListeners();
    return true;
  }

  bool setDrinkVariant(String productId, String? currentVariant, String variant) {
    if (!isAuthenticated || _checkoutInProgress || _savingBill || !CartItem.variantPrices.containsKey(variant)) return false;
    final index = _cart.indexWhere((item) => item.product.id == productId && item.drinkVariant == currentVariant);
    if (index < 0 || !_cart[index].product.isDrink) return false;
    final item = _cart[index];
    if (currentVariant == variant) return true;
    final target = _cart.indexWhere((other) => other.product.id == productId && other.drinkVariant == variant);
    if (target >= 0 && _cart[target].customerNote != item.customerNote) return false;
    final live = _products.where((p) => p.id == productId).firstOrNull;
    if (live == null) return false;
    if (target >= 0) {
      _cart[target].quantity += item.quantity;
      _cart.removeAt(index);
    } else {
      item.note = CartItem.composeNote(variant, item.customerNote);
      item.product = live.copyWith(sellPrice: live.sellPrice + CartItem.variantPrices[variant]!);
    }
    notifyListeners();
    return true;
  }

  void updateItemNote(String productId, String? note, {Object? variant = _anyVariant}) {
    if (_checkoutInProgress || _savingBill) return;
    final index = _cart.indexWhere((item) => item.product.id == productId && (identical(variant, _anyVariant) || item.drinkVariant == variant));
    if (index == -1) return;
    final trimmed = note?.trim();
    _cart[index].note = CartItem.composeNote(_cart[index].drinkVariant, trimmed);
    notifyListeners();
  }

  void removeFromCart(String productId) {
    if (_checkoutInProgress || _savingBill) return;
    _cart.removeWhere((item) => item.product.id == productId);
    if (_cart.isEmpty) _discountAmount = 0.0;
    notifyListeners();
  }

  void clearCart({bool silent = false}) {
    if (_checkoutInProgress || _savingBill) return;
    _resetCart(silent: silent);
  }

  void _resetCart({bool silent = false}) {
    _cart.clear();
    _discountAmount = 0.0;
    _customerName = '';
    _orderType = 'Dine-In';
    _activeBillId = null;
    _activeBillRevision = null;
    if (!silent) notifyListeners();
  }

  double get subtotalCartAmount {
    return _cart.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  double get effectiveDiscount {
    return _discountAmount.clamp(0.0, subtotalCartAmount);
  }

  double get totalCartAmount {
    return (subtotalCartAmount - effectiveDiscount).clamp(0.0, double.infinity);
  }

  int get totalCartItemCount {
    return _cart.fold(0, (sum, item) => sum + item.quantity);
  }

  static String normalizePaymentMethod(String method) {
    final lower = method.trim().toLowerCase();
    if (lower == 'qris') return 'QRIS';
    return 'Cash';
  }

  bool _checkoutInProgress = false;

  Future<TransactionRecord> processCheckout({
    required String paymentMethod,
    required double amountPaid,
    required String cashierName,
    String? customerName,
  }) async {
    if (_checkoutInProgress) throw StateError('Pembayaran sedang diproses.');
    if (_savingBill) throw StateError('Tagihan sedang disimpan.');
    if (!isAuthenticated) throw StateError('Silakan masuk terlebih dahulu.');
    if (_cart.isEmpty) throw StateError('Pesanan masih kosong.');
    if (!['Cash', 'QRIS'].contains(paymentMethod)) throw ArgumentError('Metode pembayaran tidak valid.');
    final quantities = <String, int>{};
    for (final item in _cart) {
      final live = _products.where((p) => p.id == item.product.id).firstOrNull;
      final total = (quantities[item.product.id] ?? 0) + item.quantity;
      if (live == null || !live.isAvailable || item.quantity < 1 || total > live.stock ||
          !live.sellPrice.isFinite || live.sellPrice < 0 || !live.baseCost.isFinite || live.baseCost < 0) {
        throw StateError('Produk/stok berubah. Periksa kembali pesanan.');
      }
      quantities[item.product.id] = total;
      item.product = live.copyWith(sellPrice: live.sellPrice + (CartItem.variantPrices[item.drinkVariant] ?? 0));
    }
    if (!amountPaid.isFinite || amountPaid < totalCartAmount) {
      throw ArgumentError('Nominal pembayaran tidak mencukupi atau tidak valid.');
    }
    _checkoutInProgress = true;
    try {
      return await _processCheckout(
        paymentMethod: paymentMethod,
        amountPaid: amountPaid,
        cashierName: cashierName,
        customerName: customerName,
      );
    } finally {
      _checkoutInProgress = false;
    }
  }

  Future<TransactionRecord> _processCheckout({
    required String paymentMethod,
    required double amountPaid,
    required String cashierName,
    String? customerName,
  }) async {
    final subtotal = subtotalCartAmount;
    final discount = effectiveDiscount;
    final total = totalCartAmount;
    final totalCost = _cart.fold(
      0.0,
      (sum, item) => sum + (item.product.baseCost * item.quantity),
    );
    final totalProfit = total - totalCost;
    final changeAmount = (amountPaid - total).clamp(0.0, double.infinity);
    final now = DateTime.now();
    final suffix = now.microsecondsSinceEpoch.toString();
    final invoiceId =
        'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-$suffix';

    final resolvedCustomer = (customerName ?? _customerName).trim();
    final normalizedMethod = normalizePaymentMethod(paymentMethod);

    final transaction = TransactionRecord(
      id: invoiceId,
      invoiceNumber: invoiceId,
      items: _cart.map((c) => c.copyWith()).toList(),
      subtotalAmount: subtotal,
      discountAmount: discount,
      totalAmount: total,
      totalCost: totalCost,
      totalProfit: totalProfit,
      paymentMethod: normalizedMethod,
      amountPaid: amountPaid,
      changeAmount: changeAmount,
      cashierName: _currentUser!.displayName,
      cashierId: _currentUser!.id,
      openBillId: _activeBillId,
      openBillRevision: _activeBillRevision,
      orderType: _orderType,
      customerName: resolvedCustomer.isNotEmpty ? resolvedCustomer : null,
      createdAt: now,
      isSynced: _isOnline,
    );

    final saved = await _db.processTransaction(transaction);
    _products = _db.getProducts();
    _transactions = _db.getTransactions();
    _openBills = _db.getOpenBills();
    _resetCart();
    return saved;
  }

  Future<bool> voidTransaction(String transactionId) async {
    if (_checkoutInProgress) throw StateError('Transaksi sedang diproses.');
    if (!isAuthenticated || !currentRole.canVoidTransactions) return false;
    final ok = await _db.voidTransaction(transactionId);
    _products = _db.getProducts();
    _transactions = _db.getTransactions();
    notifyListeners();
    return ok;
  }

  Future<TransactionRecord> correctTransaction({
    required String transactionId,
    required int expectedRevision,
    required List<CartItem> items,
    required double amountPaid,
    required String reason,
  }) async {
    _requirePermission(true);
    if (_checkoutInProgress) throw StateError('Transaksi sedang diproses.');
    final saved = await _db.correctTransaction(
      transactionId: transactionId, expectedRevision: expectedRevision,
      items: items, amountPaid: amountPaid, reason: reason,
    );
    _products = _db.getProducts();
    _transactions = _db.getTransactions();
    _reconcileCartWithCatalog();
    notifyListeners();
    return saved;
  }

  bool canCorrectTransaction(TransactionRecord transaction) =>
      isAuthenticated && transaction.canBeCorrectedBy(
        role: currentRole, userId: _currentUser!.id);

  List<TransactionRecord> get deletedTransactions => isAuthenticated && currentRole.canDeleteTransactions
      ? _db.getDeletedTransactions() : const [];
  bool isTransactionDeleted(String id) => isAuthenticated && _db.isTransactionDeleted(id);

  Future<TransactionRecord> deleteTransaction({required String transactionId, required int expectedRevision, required String reason}) async {
    _requirePermission(currentRole.canDeleteTransactions);
    if (_checkoutInProgress || _savingBill) throw StateError('Transaksi atau tagihan sedang diproses.');
    _checkoutInProgress = true;
    try {
      final deleted = await _db.deleteTransaction(transactionId: transactionId, expectedRevision: expectedRevision, reason: reason);
      _products = _db.getProducts();
      _transactions = _db.getTransactions();
      _reconcileCartWithCatalog();
      notifyListeners();
      return deleted;
    } finally { _checkoutInProgress = false; notifyListeners(); }
  }

  ({double totalAmount, int transactionCount}) get todayStoreSales =>
      isAuthenticated ? _db.getTodaySalesSummary() : (totalAmount: 0, transactionCount: 0);

  // Inventory & Product Management
  Future<void> addNewProducts(List<Product> products) async {
    _requirePermission(currentRole.canEditProducts);
    for (final product in products) {
      _validateProduct(product);
    }
    await _db.addProducts(products);
    _products = _db.getProducts();
    notifyListeners();
  }

  Future<void> addNewProduct(Product product) async {
    _requirePermission(currentRole.canEditProducts);
    _validateProduct(product);
    if (product.category.trim().isNotEmpty) {
      await _db.addCategory(product.category);
    }
    await _db.addProduct(product);
    _products = _db.getProducts();
    _categories = _db.getCategories();
    notifyListeners();
  }

  Future<void> updateExistingProduct(Product product) async {
    _requirePermission(currentRole.canEditProducts);
    _validateProduct(product);
    if (product.category.trim().isNotEmpty) {
      await _db.addCategory(product.category);
    }
    await _db.updateProduct(product);
    _products = _db.getProducts();
    _categories = _db.getCategories();
    _reconcileCartWithCatalog();
    notifyListeners();
  }

  Future<bool> deleteExistingProduct(String productId) async {
    if (!isAuthenticated || !currentRole.canEditProducts) return false;
    final ok = await _db.deleteProduct(productId);
    _products = _db.getProducts();
    if (ok) {
      removeFromCart(productId);
    } else {
      notifyListeners();
    }
    return ok;
  }

  Future<void> adjustProductStock(String productId, int newStock) async {
    _requirePermission(currentRole.canAdjustStock);
    if (newStock < 0 || newStock > 99999) throw ArgumentError('Stok tidak valid.');
    await _db.adjustStock(productId, newStock);
    _products = _db.getProducts();
    _reconcileCartWithCatalog();
    notifyListeners();
  }

  // Operational Expenses Management (Owner)
  Future<void> addOperationalExpenses(List<OperationalExpense> expenses) async {
    _requirePermission(currentRole.canManageOperationalExpenses);
    final normalized = expenses.map((expense) => OperationalExpense(
      id: expense.id,
      title: expense.title.trim().isEmpty ? expense.category.trim() : expense.title.trim(),
      category: expense.category.trim().isEmpty ? 'Lainnya' : expense.category.trim(),
      amount: expense.amount,
      createdAt: expense.createdAt,
      recordedBy: _currentUser!.displayName,
      notes: expense.notes?.trim().isNotEmpty == true ? expense.notes!.trim() : null,
    )).toList();
    await _db.addOperationalExpenses(normalized);
    _operationalExpenses = _db.getOperationalExpenses();
    notifyListeners();
  }

  Future<OperationalExpense> addOperationalExpense({
    required String title,
    required String category,
    required double amount,
    DateTime? createdAt,
    String? notes,
  }) async {
    _requirePermission(currentRole.canManageOperationalExpenses);
    if (!amount.isFinite || amount <= 0) throw ArgumentError('Nominal biaya harus positif.');
    final now = createdAt ?? DateTime.now();
    final expense = OperationalExpense(
      id: 'exp_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff)}',
      title: title.trim().isEmpty ? category.trim() : title.trim(),
      category: category.trim().isEmpty ? 'Lainnya' : category.trim(),
      amount: amount.clamp(0.0, double.infinity),
      createdAt: now,
      recordedBy: _currentUser?.displayName ?? 'Owner Warloc',
      notes: (notes != null && notes.trim().isNotEmpty) ? notes.trim() : null,
      isSynced: _isOnline,
    );
    final saved = await _db.addOperationalExpense(expense);
    _operationalExpenses = _db.getOperationalExpenses();
    notifyListeners();
    return saved;
  }

  Future<OperationalExpense?> updateOperationalExpense(
    OperationalExpense expense,
  ) async {
    _requirePermission(currentRole.canManageOperationalExpenses);
    if (!expense.amount.isFinite || expense.amount <= 0) throw ArgumentError('Nominal biaya harus positif.');
    final saved = await _db.updateOperationalExpense(expense);
    _operationalExpenses = _db.getOperationalExpenses();
    notifyListeners();
    return saved;
  }

  Future<bool> deleteOperationalExpense(String expenseId) async {
    if (!isAuthenticated || !currentRole.canManageOperationalExpenses) return false;
    final ok = await _db.deleteOperationalExpense(expenseId);
    _operationalExpenses = _db.getOperationalExpenses();
    notifyListeners();
    return ok;
  }

  void _requirePermission(bool permitted) {
    if (!isAuthenticated || !permitted) throw StateError('Akses ditolak.');
  }

  void _validateProduct(Product product) {
    if (product.id.isEmpty || product.id.contains('/') || product.name.trim().isEmpty ||
        product.category.trim().isEmpty || !product.sellPrice.isFinite || product.sellPrice < 0 ||
        !product.baseCost.isFinite || product.baseCost < 0 || product.stock < 0 || product.stock > 99999 ||
        product.minStockThreshold < 0) { throw ArgumentError('Data produk tidak valid.'); }
  }

  double get todayOperationalExpenseTotal {
    final now = DateTime.now();
    return operationalExpenses
        .where(
          (e) =>
              e.createdAt.year == now.year &&
              e.createdAt.month == now.month &&
              e.createdAt.day == now.day,
        )
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double get currentMonthOperationalExpenseTotal {
    final now = DateTime.now();
    return operationalExpenses
        .where(
          (e) => e.createdAt.year == now.year && e.createdAt.month == now.month,
        )
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  Map<String, double> operationalExpenseBreakdown({bool monthly = true}) {
    final now = DateTime.now();
    final map = <String, double>{
      for (final c in OperationalExpense.defaultCategories) c: 0.0,
    };
    for (final exp in operationalExpenses) {
      final include = monthly
          ? (exp.createdAt.year == now.year && exp.createdAt.month == now.month)
          : (exp.createdAt.year == now.year &&
                exp.createdAt.month == now.month &&
                exp.createdAt.day == now.day);
      if (include) {
        map[exp.category] = (map[exp.category] ?? 0.0) + exp.amount;
      }
    }
    return map;
  }

  // Owner Financial Analytics (Active non-voided transactions only)
  List<TransactionRecord> get activeTransactions {
    return transactions.where((t) => !t.isVoided).toList();
  }

  List<TransactionRecord> get todayActiveTransactions {
    final now = DateTime.now();
    return activeTransactions
        .where(
          (t) =>
              t.createdAt.year == now.year &&
              t.createdAt.month == now.month &&
              t.createdAt.day == now.day,
        )
        .toList();
  }

  List<TransactionRecord> get currentMonthActiveTransactions {
    final now = DateTime.now();
    return activeTransactions
        .where(
          (t) => t.createdAt.year == now.year && t.createdAt.month == now.month,
        )
        .toList();
  }

  double get todayRevenue {
    return todayActiveTransactions.fold(0.0, (sum, t) => sum + t.totalAmount);
  }

  double get todayProfit {
    return todayActiveTransactions.fold(0.0, (sum, t) => sum + t.totalProfit);
  }

  double get todayNetOperationalProfit =>
      todayProfit - todayOperationalExpenseTotal;

  int get todayTransactionCount => todayActiveTransactions.length;

  double get todayAverageTicket {
    final count = todayTransactionCount;
    if (count == 0) return 0.0;
    return todayRevenue / count;
  }

  double get currentMonthRevenue {
    return currentMonthActiveTransactions.fold(
      0.0,
      (sum, t) => sum + t.totalAmount,
    );
  }

  double get currentMonthGrossProfit {
    return currentMonthActiveTransactions.fold(
      0.0,
      (sum, t) => sum + t.totalProfit,
    );
  }

  double get currentMonthNetOperationalProfit =>
      currentMonthGrossProfit - currentMonthOperationalExpenseTotal;

  /// Computes exact Operational Profit Summary for any arbitrary date range
  OperationalProfitSummary computeOperationalProfitSummary({
    required DateTime start,
    required DateTime end,
  }) {
    final rangeStart = DateTime(start.year, start.month, start.day, 0, 0, 0);
    final rangeEnd = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

    double rev = 0.0;
    double cogs = 0.0;
    double gross = 0.0;
    int txCount = 0;

    for (final tx in activeTransactions) {
      if (!tx.createdAt.isBefore(rangeStart) && !tx.createdAt.isAfter(rangeEnd)) {
        rev += tx.totalAmount;
        cogs += tx.totalCost;
        gross += tx.totalProfit;
        txCount++;
      }
    }

    double ops = 0.0;
    int expCount = 0;
    final breakdown = <String, double>{
      for (final c in OperationalExpense.defaultCategories) c: 0.0,
    };

    for (final exp in operationalExpenses) {
      if (!exp.createdAt.isBefore(rangeStart) && !exp.createdAt.isAfter(rangeEnd)) {
        ops += exp.amount;
        expCount++;
        breakdown[exp.category] = (breakdown[exp.category] ?? 0.0) + exp.amount;
      }
    }

    final net = gross - ops;
    final grossPct = rev > 0 ? (gross / rev) * 100.0 : 0.0;
    final netPct = rev > 0 ? (net / rev) * 100.0 : 0.0;

    return OperationalProfitSummary(
      startDate: rangeStart,
      endDate: rangeEnd,
      totalRevenue: rev,
      totalCogs: cogs,
      grossProfit: gross,
      operationalExpenses: ops,
      netProfit: net,
      transactionCount: txCount,
      expenseCount: expCount,
      expenseCategoryBreakdown: breakdown,
      grossMarginPct: grossPct,
      netMarginPct: netPct,
    );
  }

  /// Computes comprehensive Daily & Monthly metrics including MTD (last day of previous month)
  /// and MTM (same day of previous month), automatically collapsing MTM into MTD when
  /// [referenceDate] is the end of the month (e.g., 31 Oct) or coincides with [prevMonthLastDate].
  RevenueComparisonSummary computeRevenueComparison({DateTime? referenceDate}) {
    final ref = referenceDate ?? DateTime.now();
    final lastDayOfCurrentMonth = DateTime(ref.year, ref.month + 1, 0).day;
    final prevMonthLastDate = DateTime(ref.year, ref.month, 0);
    final clampedPrevDay = ref.day.clamp(1, prevMonthLastDate.day);
    final prevMonthSameDate = DateTime(
      prevMonthLastDate.year,
      prevMonthLastDate.month,
      clampedPrevDay,
    );

    final collapseMtmIntoMtd =
        ref.day == lastDayOfCurrentMonth ||
        prevMonthSameDate.day == prevMonthLastDate.day;

    double todayRev = 0.0;
    double todayProf = 0.0;
    int todayCount = 0;

    double mtdLastDayPrevRev = 0.0;
    double mtmSameDayPrevRev = 0.0;

    double currMonthRev = 0.0;
    double currMonthProf = 0.0;
    int currMonthCount = 0;

    double prevMonthFullRev = 0.0;
    double prevMonthMtmCumRev = 0.0;

    for (final tx in activeTransactions) {
      final dt = tx.createdAt;
      if (dt.year == ref.year && dt.month == ref.month) {
        if (dt.day <= ref.day) {
          currMonthRev += tx.totalAmount;
          currMonthProf += tx.totalProfit;
          currMonthCount++;
        }
        if (dt.day == ref.day) {
          todayRev += tx.totalAmount;
          todayProf += tx.totalProfit;
          todayCount++;
        }
      } else if (dt.year == prevMonthLastDate.year &&
          dt.month == prevMonthLastDate.month) {
        prevMonthFullRev += tx.totalAmount;
        if (dt.day <= prevMonthSameDate.day) {
          prevMonthMtmCumRev += tx.totalAmount;
        }
        if (dt.day == prevMonthLastDate.day) {
          mtdLastDayPrevRev += tx.totalAmount;
        }
        if (dt.day == prevMonthSameDate.day) {
          mtmSameDayPrevRev += tx.totalAmount;
        }
      }
    }

    double todayExp = 0.0;
    double currMonthExp = 0.0;
    for (final exp in operationalExpenses) {
      final dt = exp.createdAt;
      if (dt.year == ref.year && dt.month == ref.month) {
        if (dt.day <= ref.day) {
          currMonthExp += exp.amount;
        }
        if (dt.day == ref.day) {
          todayExp += exp.amount;
        }
      }
    }

    return RevenueComparisonSummary(
      referenceDate: ref,
      prevMonthLastDate: prevMonthLastDate,
      prevMonthSameDate: prevMonthSameDate,
      collapseMtmIntoMtd: collapseMtmIntoMtd,
      todayRevenue: todayRev,
      todayGrossProfit: todayProf,
      todayOperationalExpense: todayExp,
      todayTransactionCount: todayCount,
      mtdPrevMonthLastDayRevenue: mtdLastDayPrevRev,
      mtmPrevMonthSameDayRevenue: mtmSameDayPrevRev,
      currentMonthRevenue: currMonthRev,
      currentMonthGrossProfit: currMonthProf,
      currentMonthOperationalExpense: currMonthExp,
      currentMonthTransactionCount: currMonthCount,
      prevMonthFullRevenue: prevMonthFullRev,
      prevMonthMtmCumulativeRevenue: prevMonthMtmCumRev,
    );
  }

  /// Builds 12 two-hour buckets (00:00..22:00) covering 24h for daily time-series chart
  List<AnalyticsPoint> buildDailyHourlySeries({DateTime? date}) {
    final target = date ?? DateTime.now();
    final buckets = List<double>.filled(12, 0.0);
    final profits = List<double>.filled(12, 0.0);
    final ops = List<double>.filled(12, 0.0);

    for (final tx in activeTransactions) {
      final dt = tx.createdAt;
      if (dt.year == target.year &&
          dt.month == target.month &&
          dt.day == target.day) {
        final slot = (dt.hour ~/ 2).clamp(0, 11);
        buckets[slot] += tx.totalAmount;
        profits[slot] += tx.totalProfit;
      }
    }

    for (final exp in operationalExpenses) {
      final dt = exp.createdAt;
      if (dt.year == target.year &&
          dt.month == target.month &&
          dt.day == target.day) {
        final slot = (dt.hour ~/ 2).clamp(0, 11);
        ops[slot] += exp.amount;
      }
    }

    return List.generate(12, (i) {
      final startHour = (i * 2).toString().padLeft(2, '0');
      final endHour = ((i * 2 + 2) % 24).toString().padLeft(2, '0');
      return AnalyticsPoint(
        label: '$startHour:00',
        subtitle: 'Jam $startHour:00 – $endHour:00',
        value: buckets[i],
        secondaryValue: profits[i] - ops[i],
      );
    });
  }

  /// Builds daily series across all days in [monthDate] for monthly time-series chart
  List<AnalyticsPoint> buildMonthlyDailySeries({DateTime? monthDate}) {
    final ref = monthDate ?? DateTime.now();
    final daysInMonth = DateTime(ref.year, ref.month + 1, 0).day;
    final dailyRev = List<double>.filled(daysInMonth, 0.0);
    final dailyProf = List<double>.filled(daysInMonth, 0.0);
    final dailyOps = List<double>.filled(daysInMonth, 0.0);

    for (final tx in activeTransactions) {
      final dt = tx.createdAt;
      if (dt.year == ref.year && dt.month == ref.month) {
        final idx = (dt.day - 1).clamp(0, daysInMonth - 1);
        dailyRev[idx] += tx.totalAmount;
        dailyProf[idx] += tx.totalProfit;
      }
    }

    for (final exp in operationalExpenses) {
      final dt = exp.createdAt;
      if (dt.year == ref.year && dt.month == ref.month) {
        final idx = (dt.day - 1).clamp(0, daysInMonth - 1);
        dailyOps[idx] += exp.amount;
      }
    }

    return List.generate(daysInMonth, (i) {
      final dayNum = i + 1;
      return AnalyticsPoint(
        label: '$dayNum',
        subtitle:
            'Tanggal $dayNum/${ref.month.toString().padLeft(2, '0')}/${ref.year}',
        value: dailyRev[i],
        secondaryValue: dailyProf[i] - dailyOps[i],
      );
    });
  }

  /// Builds category revenue share for Donut Chart
  List<CategorySliceStat> buildCategoryRevenueBreakdown({
    required bool monthly,
    DateTime? referenceDate,
  }) {
    final ref = referenceDate ?? DateTime.now();
    final map = <String, CategorySliceStat>{};

    for (final tx in activeTransactions) {
      final dt = tx.createdAt;
      final include = monthly
          ? (dt.year == ref.year && dt.month == ref.month)
          : (dt.year == ref.year && dt.month == ref.month && dt.day == ref.day);
      if (!include) continue;

      for (final item in tx.items) {
        final cat = item.product.category.trim().isEmpty
            ? 'Umum'
            : item.product.category.trim();
        final prev = map[cat];
        map[cat] = CategorySliceStat(
          category: cat,
          revenue: (prev?.revenue ?? 0.0) + item.subtotal,
          quantity: (prev?.quantity ?? 0) + item.quantity,
        );
      }
    }

    final list = map.values.where((s) => s.revenue > 0).toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    return list;
  }

  List<Product> get lowStockProducts {
    return _products.where((p) => p.needsRestock).toList()..sort((a, b) {
      final aOut = a.isOutOfStock ? 0 : 1;
      final bOut = b.isOutOfStock ? 0 : 1;
      if (aOut != bOut) return aOut.compareTo(bOut);
      return a.stock.compareTo(b.stock);
    });
  }

  List<Product> get outOfStockAlertProducts =>
      lowStockProducts.where((p) => p.isOutOfStock).toList();

  List<Product> get warningStockAlertProducts =>
      lowStockProducts.where((p) => p.isLowStock).toList();

  double get totalInventoryCostValue {
    return _products
        .where((p) => !p.isEntertainment)
        .fold(0.0, (sum, p) => sum + (p.baseCost * p.stock));
  }

  double get totalInventoryRetailValue {
    return _products
        .where((p) => !p.isEntertainment)
        .fold(0.0, (sum, p) => sum + (p.sellPrice * p.stock));
  }

  List<TopProductStat> topSellingProductsFor({
    bool? monthly,
    DateTime? referenceDate,
  }) {
    final ref = referenceDate ?? DateTime.now();
    final map = <String, TopProductStat>{};
    for (final tx in activeTransactions) {
      if (monthly != null) {
        final dt = tx.createdAt;
        final include = monthly
            ? (dt.year == ref.year && dt.month == ref.month)
            : (dt.year == ref.year &&
                  dt.month == ref.month &&
                  dt.day == ref.day);
        if (!include) continue;
      }
      for (final item in tx.items) {
        final id = item.product.id;
        final prev = map[id];
        map[id] = TopProductStat(
          productId: id,
          name: item.product.name,
          category: item.product.category,
          quantitySold: (prev?.quantitySold ?? 0) + item.quantity,
          revenue: (prev?.revenue ?? 0.0) + item.subtotal,
        );
      }
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final byRev = b.revenue.compareTo(a.revenue);
        if (byRev != 0) return byRev;
        return b.quantitySold.compareTo(a.quantitySold);
      });
    return list;
  }

  List<TopProductStat> get topSellingProducts => topSellingProductsFor();

  /// Payment breakdown restricted to Cash & QRIS only (legacy 'Tunai' normalized into 'Cash')
  Map<String, double> paymentMethodBreakdownFor({
    bool? monthly,
    DateTime? referenceDate,
  }) {
    final ref = referenceDate ?? DateTime.now();
    final totals = <String, double>{'Cash': 0.0, 'QRIS': 0.0};
    for (final tx in activeTransactions) {
      if (monthly != null) {
        final dt = tx.createdAt;
        final include = monthly
            ? (dt.year == ref.year && dt.month == ref.month)
            : (dt.year == ref.year &&
                  dt.month == ref.month &&
                  dt.day == ref.day);
        if (!include) continue;
      }
      final key = normalizePaymentMethod(tx.paymentMethod);
      totals[key] = (totals[key] ?? 0.0) + tx.totalAmount;
    }
    return totals;
  }

  Map<String, double> get paymentMethodBreakdown => paymentMethodBreakdownFor();

  @override
  void dispose() {
    _disposed = true;
    _sessionTimer?.cancel();
    _billsSub?.cancel();
    _productsSub?.cancel();
    _transactionsSub?.cancel();
    _usersSub?.cancel();
    _categoriesSub?.cancel();
    _expensesSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }
}
