import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'secure_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../models/transaction.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../models/operational_expense.dart';
import '../models/open_bill.dart';

class PosDatabaseService {
  static bool _testMode = false;
  static void enableTestMode({bool enabled = true}) { assert(() { _testMode = enabled; return true; }()); }
  String? _sessionUserId;
  UserProfile? get _actor => _users.where((u) => u.id == _sessionUserId && u.isActive).firstOrNull;
  void _requireAccess(bool Function(UserRole) check) {
    final actor = _actor;
    if (actor == null || !check(actor.role)) throw StateError('Akses ditolak.');
  }
  Future<UserProfile?> restoreSession() async {
    final prefs = await SecurePreferences.getInstance();
    final expires = prefs.getInt('saved_session_expires_at') ?? 0;
    _sessionUserId = expires > DateTime.now().millisecondsSinceEpoch ? prefs.getString('saved_active_user_id') : null;
    return _actor;
  }
  void endSession() { _sessionUserId = null; }
  static final PosDatabaseService instance = PosDatabaseService._internal();
  PosDatabaseService._internal();

  final List<Product> _products = [];
  final List<TransactionRecord> _transactions = [];
  final List<UserProfile> _users = [];
  final List<String> _categories = [];
  final List<OperationalExpense> _operationalExpenses = [];
  final List<OpenBill> _openBills = [];
  final _openBillsController = StreamController<List<OpenBill>>.broadcast();
  Stream<List<OpenBill>> get openBillsStream => _openBillsController.stream;
  List<OpenBill> getOpenBills() => _actor == null ? const [] : List.unmodifiable(_openBills.where((bill) =>
    (_actor!.role != UserRole.barista || bill.createdBy == _actor!.id) &&
    !_transactions.any((tx) => tx.openBillId == bill.id)));

  Future<void> saveOpenBill(OpenBill bill, {int? expectedRevision}) async {
    _requireAccess((r) => true);
    final old = _openBills.where((b) => b.id == bill.id).firstOrNull;
    if ((old != null && old.createdBy != _actor!.id && _actor!.role == UserRole.barista) ||
        (old == null && bill.createdBy != _actor!.id) ||
        bill.items.isEmpty || bill.customerName.trim().isEmpty || !bill.discountAmount.isFinite || bill.discountAmount < 0) {
      throw StateError('Tagihan tidak valid atau akses ditolak.');
    }
    final index = _openBills.indexWhere((b) => b.id == bill.id);
    if (index >= 0 && _openBills[index].revision != expectedRevision) {
      throw StateError('Tagihan sudah berubah. Buka kembali tagihan.');
    }
    if (index < 0 && expectedRevision != null) throw StateError('Tagihan tidak ditemukan.');
    if (old != null && bill.createdBy != old.createdBy) throw StateError('Pemilik tagihan tidak boleh berubah.');
    final ids = <String>{};
    final quantities = <String, int>{};
    var subtotal = 0.0;
    for (final item in bill.items) {
      final product = _products.where((p) => p.id == item.product.id).firstOrNull;
      final total = (quantities[item.product.id] ?? 0) + item.quantity;
      if (product == null || !product.isAvailable || item.quantity < 1 || total > product.stock ||
          (item.drinkVariant != null && !product.isDrink) ||
          !ids.add('${item.product.id}\u0000${item.drinkVariant ?? ''}') ||
          product.sellPrice + (CartItem.variantPrices[item.drinkVariant] ?? 0) != item.product.sellPrice || product.baseCost != item.product.baseCost) {
        throw StateError('Menu/harga/stok tagihan tidak valid.');
      }
      quantities[product.id] = total;
      subtotal += item.subtotal;
    }
    if (bill.discountAmount > subtotal || bill.revision != (expectedRevision ?? 0) + 1) throw StateError('Diskon/revisi tagihan tidak valid.');
    if (_transactions.any((tx) => tx.openBillId == bill.id)) throw StateError('Tagihan sudah dibayar.');
    if (index < 0) { _openBills.add(bill); } else { _openBills[index] = bill; }
    await _persistOpenBills();
    _openBillsController.add(getOpenBills());
  }

  Future<void> deleteOpenBill(String id) async {
    _requireAccess((r) => true);
    final bill = _openBills.where((b) => b.id == id).firstOrNull;
    if (bill == null || (_actor!.role == UserRole.barista && bill.createdBy != _actor!.id)) throw StateError('Akses ditolak.');
    _openBills.removeWhere((b) => b.id == id);
    await _persistOpenBills();
    _openBillsController.add(getOpenBills());
  }

  Future<void> _persistOpenBills() => _persistLedger();

  final _productsStreamController = StreamController<List<Product>>.broadcast();
  final _transactionsStreamController =
      StreamController<List<TransactionRecord>>.broadcast();
  final _usersStreamController =
      StreamController<List<UserProfile>>.broadcast();
  final _categoriesStreamController =
      StreamController<List<String>>.broadcast();
  final _operationalExpensesStreamController =
      StreamController<List<OperationalExpense>>.broadcast();

  Stream<List<Product>> get productsStream => _productsStreamController.stream;
  Stream<List<TransactionRecord>> get transactionsStream =>
      _transactionsStreamController.stream;
  Stream<List<UserProfile>> get usersStream => _usersStreamController.stream;
  Stream<List<String>> get categoriesStream =>
      _categoriesStreamController.stream;
  Stream<List<OperationalExpense>> get operationalExpensesStream =>
      _operationalExpensesStreamController.stream;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  bool _initialized = false;
  bool _loading = false;

  FirebaseFirestore? _firestore;
  StreamSubscription? _firestoreProductsSub;
  StreamSubscription? _firestoreTransactionsSub;
  StreamSubscription? _firestoreUsersSub;
  StreamSubscription? _firestoreCategoriesSub;
  StreamSubscription? _firestoreExpensesSub;
  bool _seedingProducts = false;
  bool _seedingCategories = false;

  Future<void> initialize() async {
    if (_initialized) {
      _notifyProducts();
      _notifyTransactions();
      _notifyUsers();
      _notifyCategories();
      _notifyOperationalExpenses();
      return;
    }

    final prefs = await SecurePreferences.getInstance();
    _loading = true;
    final rawLedger = prefs.getString('cached_ledger_v1');
    final ledger = rawLedger == null ? null : Map<String, dynamic>.from(jsonDecode(rawLedger) as Map);
    final savedBills = ledger == null ? prefs.getString('cached_open_bills') : jsonEncode(ledger['openBills']);
    if (savedBills != null) {
      _openBills..clear()..addAll((jsonDecode(savedBills) as List).map((b) => OpenBill.fromMap(Map<String, dynamic>.from(b as Map))));
    }
    final productsJson = ledger == null ? prefs.getString('cached_products') : jsonEncode(ledger['products']);
    final transactionsJson = ledger == null ? prefs.getString('cached_transactions') : jsonEncode(ledger['transactions']);
    final usersJson = prefs.getString('cached_users');
    final categoriesJson = prefs.getString('cached_categories');
    final expensesJson = prefs.getString('cached_operational_expenses');
    final catalogSeeded = prefs.getBool('warloc_catalog_seeded_v2') ?? false;
    final hiburanSeeded = prefs.getBool('warloc_hiburan_ps_seeded_v1') ?? false;

    // 1. Load Products
    if (productsJson != null && productsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(productsJson);
        _products
          ..clear()
          ..addAll(
            decoded.map(
              (m) => Product.fromMap(Map<String, dynamic>.from(m as Map)),
            ),
          );
      } catch (e) {
        debugPrint('Error decoding cached products: $e');
      }
      if (!catalogSeeded && _products.length <= 2) {
        final initial = _getInitialWarlocMenu();
        for (final item in initial) {
          if (!_products.any(
            (p) =>
                p.id == item.id ||
                p.name.toLowerCase() == item.name.toLowerCase(),
          )) {
            _products.add(item);
          }
        }
        await prefs.setBool('warloc_catalog_seeded_v2', true);
        await _persistProducts();
      }
    } else {
      _products
        ..clear()
        ..addAll(_getInitialWarlocMenu());
      await prefs.setBool('warloc_catalog_seeded_v2', true);
      await prefs.setBool('warloc_hiburan_ps_seeded_v1', true);
      await _persistProducts();
    }

    // Ensure Hiburan category & Rental PS3 / Rental PS4 exist on upgraded installs
    if (!hiburanSeeded) {
      bool addedHiburan = false;
      for (final psItem in _getDefaultHiburanProducts()) {
        final exists = _products.any(
          (p) =>
              p.id == psItem.id ||
              p.name.trim().toLowerCase() == psItem.name.trim().toLowerCase(),
        );
        if (!exists) {
          _products.add(psItem.copyWith(isSynced: false));
          addedHiburan = true;
        }
      }
      await prefs.setBool('warloc_hiburan_ps_seeded_v1', true);
      if (addedHiburan) {
        await _persistProducts();
      }
    }

    // 2. Load Transactions
    if (transactionsJson != null && transactionsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(transactionsJson);
        _transactions
          ..clear()
          ..addAll(
            decoded.map(
              (m) => TransactionRecord.fromMap(
                Map<String, dynamic>.from(m as Map),
              ),
            ),
          );
        _sortTransactions();
      } catch (e) {
        debugPrint('Error decoding cached transactions: $e');
      }
    }

    // 3. Load Operational Expenses
    if (expensesJson != null && expensesJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(expensesJson);
        _operationalExpenses
          ..clear()
          ..addAll(
            decoded.map(
              (m) => OperationalExpense.fromMap(
                Map<String, dynamic>.from(m as Map),
              ),
            ),
          );
        _sortOperationalExpenses();
      } catch (e) {
        debugPrint('Error decoding cached operational expenses: $e');
      }
    }

    // 4. Load Users with SHA-256 Salted Hashed Passwords
    if (usersJson != null && usersJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(usersJson);
        _users
          ..clear()
          ..addAll(
            decoded.map(
              (m) => UserProfile.fromMap(Map<String, dynamic>.from(m as Map)),
            ),
          );
      } catch (e) {
        debugPrint('Error decoding cached users: $e');
      }
      _ensureDefaultUsers();
      await _persistUsers();
    } else {
      _users
        ..clear()
        ..addAll(_getDefaultUsers());
      _ensureDefaultUsers();
      await _persistUsers();
    }


    // 5. Load Categories (including Hiburan)
    final Set<String> loadedCategories = {
      'Coffee',
      'Non-Coffee',
      'Pastry',
      'Snack',
      'Makanan',
      'Hiburan',
    };
    if (categoriesJson != null && categoriesJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(categoriesJson);
        loadedCategories.clear();
        loadedCategories.addAll(
          decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
        );
      } catch (e) {
        debugPrint('Error decoding cached categories: $e');
      }
    }
    for (final p in _products) {
      if (p.category.trim().isNotEmpty) {
        loadedCategories.add(p.category.trim());
      }
    }
    _categories
      ..clear()
      ..addAll(loadedCategories.toList()..sort());
    await _persistCategories();

    _loading = false;
    await _persistLedger();
    _initialized = true;
    _notifyProducts();
    _notifyTransactions();
    _notifyUsers();
    _notifyCategories();
    _notifyOperationalExpenses();

    _setupFirestoreLiveSync();
  }

  void _sortTransactions() {
    _transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _sortOperationalExpenses() {
    _operationalExpenses.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<UserProfile> _getDefaultUsers() {
    return [
      UserProfile.create(
        id: 'u_barista_default',
        username: 'warloc.kasir',
        displayName: 'Kasir Warloc',
        role: UserRole.barista,
        plainPassword: 'sukses000',
      ),
      UserProfile.create(
        id: 'u_admin_default',
        username: 'warloc.admin',
        displayName: 'Admin Warloc',
        role: UserRole.admin,
        plainPassword: 'sukses123',
      ),
      UserProfile.create(
        id: 'u_owner_default',
        username: 'warloc.owner',
        displayName: 'Owner Warloc',
        role: UserRole.owner,
        plainPassword: 'sukses888',
      ),
    ];
  }

  void _ensureDefaultUsers() {
    final legacyUsernames = {'user', 'admin', 'iggoys'};
    _users.removeWhere(
      (u) => legacyUsernames.contains(u.username.toLowerCase()),
    );

    final defaults = _getDefaultUsers();
    for (final def in defaults) {
      final existingIndex = _users.indexWhere(
        (u) =>
            u.id == def.id ||
            u.username.toLowerCase() == def.username.toLowerCase(),
      );
      if (existingIndex < 0) {
        _users.add(def);
      } else {
        final existing = _users[existingIndex];
        if (!existing.isActive) {
          _users[existingIndex] = existing.copyWith(isActive: true);
        }
      }
    }
  }

  void _setupFirestoreLiveSync() {
    try {
      _firestore = FirebaseFirestore.instance;

      // Products Sync (Cross-device product details + Base64/URL photos + Hiburan items)
      _firestoreProductsSub?.cancel();
      _firestoreProductsSub = _firestore!
          .collection('products')
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snapshot) async {
              if (snapshot.docs.isNotEmpty) {
                final remoteMap = <String, Product>{};
                for (final doc in snapshot.docs) {
                  final prod = Product.fromMap(
                    doc.data(),
                  ).copyWith(isSynced: !doc.metadata.hasPendingWrites);
                  remoteMap[prod.id] = prod;
                }

                // Preserve unsynced local product edits/photos & push them to Firestore
                final unsyncedLocals = _products
                    .where((p) => !p.isSynced || _seedingProducts)
                    .toList();
                for (final localProd in unsyncedLocals) {
                  final remoteProd = remoteMap[localProd.id];
                  final localNewer =
                      remoteProd == null ||
                      (localProd.updatedAt != null &&
                          (remoteProd.updatedAt == null ||
                              localProd.updatedAt!.isAfter(
                                remoteProd.updatedAt!,
                              )));
                  if (localNewer) {
                    remoteMap[localProd.id] = localProd;
                  }
                }

                // Ensure Rental PS3 & Rental PS4 exist in remote Firestore catalog
                for (final psItem in _getDefaultHiburanProducts()) {
                  final hasInRemote = remoteMap.values.any(
                    (p) =>
                        p.id == psItem.id ||
                        p.name.trim().toLowerCase() ==
                            psItem.name.trim().toLowerCase(),
                  );
                  if (!hasInRemote) {
                    remoteMap[psItem.id] = psItem.copyWith(isSynced: false);
                  }
                }

                _products
                  ..clear()
                  ..addAll(remoteMap.values);
                await _persistProducts();
                _notifyProducts();

              } else if (!snapshot.metadata.isFromCache &&
                  !snapshot.metadata.hasPendingWrites && _isOnline &&
                  _products.isNotEmpty && !_seedingProducts) {
                _seedingProducts = true;
                try {
                  final initial = List<Product>.of(_products);
                  for (var offset = 0; offset < initial.length; offset += 10) {
                    final chunk = initial.skip(offset).take(10).toList();
                    final batch = _firestore!.batch();
                    for (final product in chunk) {
                      batch.set(_firestore!.collection('products').doc(product.id),
                          product.copyWith(isSynced: true).toMap());
                    }
                    await batch.commit();
                    _acknowledgeProducts(chunk);
                  }
                  await _persistProducts();
                  _notifyProducts();
                } catch (e) {
                  debugPrint('Initial products seeding notice: $e');
                } finally {
                  _seedingProducts = false;
                }
              }
            },
            onError: (error) {
              debugPrint('Firestore products stream notice: $error');
            },
          );

      // Transactions Sync (Preserves unsynced offline records)
      _firestoreTransactionsSub?.cancel();
      _firestoreTransactionsSub = _firestore!
          .collection('transactions')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snapshot) async {
              if (snapshot.docs.isNotEmpty) {
                final remoteMap = <String, TransactionRecord>{};
                for (final doc in snapshot.docs) {
                  final tx = TransactionRecord.fromMap(
                    doc.data(),
                  ).copyWith(isSynced: !doc.metadata.hasPendingWrites);
                  remoteMap[tx.id] = tx;
                }
                for (final localTx in _transactions) {
                  final remoteTx = remoteMap[localTx.id];
                  if ((!localTx.isSynced && remoteTx == null) ||
                      (remoteTx != null && localTx.revision > remoteTx.revision)) {
                    remoteMap[localTx.id] = localTx;
                  }
                }
                _transactions
                  ..clear()
                  ..addAll(remoteMap.values);
                _sortTransactions();
                await _persistTransactions();
                _notifyTransactions();
              }
            },
            onError: (error) {
              debugPrint('Firestore transactions stream notice: $error');
            },
          );

      // Operational Expenses Sync (Limited to 100 to conserve Firestore read quota)
      _firestoreExpensesSub?.cancel();
      _firestoreExpensesSub = _firestore!
          .collection('operational_expenses')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snapshot) async {
              if (snapshot.docs.isNotEmpty) {
                final remoteMap = <String, OperationalExpense>{};
                for (final doc in snapshot.docs) {
                  final exp = OperationalExpense.fromMap(
                    doc.data(),
                  ).copyWith(isSynced: !doc.metadata.hasPendingWrites);
                  remoteMap[exp.id] = exp;
                }
                for (final localExp in _operationalExpenses) {
                  final remoteExp = remoteMap[localExp.id];
                  if (!localExp.isSynced && (remoteExp == null ||
                      !_sameExpense(localExp, remoteExp))) {
                    remoteMap[localExp.id] = localExp;
                  }
                }
                _operationalExpenses
                  ..clear()
                  ..addAll(remoteMap.values);
                _sortOperationalExpenses();
                await _persistOperationalExpenses();
                _notifyOperationalExpenses();
              }
            },
            onError: (error) {
              debugPrint('Firestore operational_expenses stream notice: $error');
            },
          );

      // Users Sync (Salted SHA-256 Hashed Records Only)
      _firestoreUsersSub?.cancel();
      _firestoreUsersSub = _firestore!
          .collection('users')
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snapshot) async {
              if (snapshot.docs.isNotEmpty) {
                final legacyUsernames = {'user', 'admin', 'iggoys'};
                final remoteUsers = snapshot.docs
                    .map((doc) => UserProfile.fromMap(doc.data()))
                    .where(
                      (u) =>
                          !legacyUsernames.contains(u.username.toLowerCase()),
                    )
                    .toList();

                _users
                  ..clear()
                  ..addAll(remoteUsers);
                _ensureDefaultUsers();
                await _persistUsers();
                _notifyUsers();

                // Cache events (including local pending writes) are not evidence
                // that a server account needs to be created or replaced.
                if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) return;

                // Clean up any legacy docs in Firestore and ensure current defaults exist
                for (final doc in snapshot.docs) {
                  final data = doc.data();
                  final uname =
                      (data['username'] ?? '').toString().toLowerCase();
                  if (legacyUsernames.contains(uname) ||
                      legacyUsernames.contains(doc.id.toLowerCase())) {
                    try {
                      await _firestore!.collection('users').doc(doc.id).delete();
                    } catch (_) {}
                  }
                }
                for (final def in usersMissingFromSnapshot(_users, remoteUsers)) {
                  try {
                    await _firestore!
                        .collection('users')
                        .doc(def.id)
                        .set(def.toMap(), SetOptions(merge: true));
                  } catch (_) {}
                }
              } else if (!snapshot.metadata.isFromCache &&
                  !snapshot.metadata.hasPendingWrites && _users.isNotEmpty) {
                try {
                  for (final u in _users) {
                    await _firestore!
                        .collection('users')
                        .doc(u.id)
                        .set(u.toMap(), SetOptions(merge: true));
                  }
                } catch (e) {
                  debugPrint('Initial users seeding notice: $e');
                }
              }
            },
            onError: (error) {
              debugPrint('Firestore users stream notice: $error');
            },
          );

      // Categories Sync
      _firestoreCategoriesSub?.cancel();
      _firestoreCategoriesSub = _firestore!
          .collection('meta')
          .doc('categories')
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snapshot) async {
              if (snapshot.exists && snapshot.data() != null) {
                final data = snapshot.data()!;
                final list = (data['list'] as List<dynamic>?)
                    ?.map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                if (list != null && list.isNotEmpty) {
                  final merged = {...list};
                  if (_products.any(
                        (p) => p.category.trim().toLowerCase() == 'hiburan',
                      ) &&
                      !merged.any((c) => c.toLowerCase() == 'hiburan')) {
                    merged.add('Hiburan');
                    if (_isOnline && !snapshot.metadata.isFromCache &&
                        !snapshot.metadata.hasPendingWrites && !_seedingCategories) {
                      _seedingCategories = true;
                      try {
                        await _firestore!
                            .collection('meta')
                            .doc('categories')
                            .set({
                              'list': merged.toList()..sort(),
                            }, SetOptions(merge: true));
                      } catch (_) {
                      } finally {
                        _seedingCategories = false;
                      }
                    }
                  }
                  _categories
                    ..clear()
                    ..addAll(merged.toList()..sort());
                  await _persistCategories();
                  _notifyCategories();
                }
              } else if (_categories.isNotEmpty && _isOnline &&
                  !snapshot.metadata.isFromCache &&
                  !snapshot.metadata.hasPendingWrites && !_seedingCategories) {
                _seedingCategories = true;
                try {
                  await _firestore!
                      .collection('meta')
                      .doc('categories')
                      .set({'list': _categories}, SetOptions(merge: true));
                } catch (e) {
                  debugPrint('Initial categories seeding notice: $e');
                } finally {
                  _seedingCategories = false;
                }
              }
            },
            onError: (error) {
              debugPrint('Firestore categories stream notice: $error');
            },
          );
    } catch (e) {
      debugPrint('Firestore setup notice (operating in offline fallback): $e');
    }
  }

  @visibleForTesting
  static List<UserProfile> usersMissingFromSnapshot(
    Iterable<UserProfile> localUsers,
    Iterable<UserProfile> remoteUsers,
  ) {
    final ids = remoteUsers.map((u) => u.id).toSet();
    final usernames = remoteUsers.map((u) => u.username.toLowerCase()).toSet();
    return localUsers.where((u) =>
      !ids.contains(u.id) && !usernames.contains(u.username.toLowerCase()),
    ).toList();
  }

  Future<void>? _pendingSyncFuture;
  final Map<String, int> _activeProductWrites = {};
  final Map<String, int> _activeTransactionWrites = {};
  final Map<String, int> _activeExpenseWrites = {};

  void _trackWrites(Map<String, int> counts, Iterable<String> ids, int delta) {
    for (final id in ids) {
      final count = (counts[id] ?? 0) + delta;
      if (count <= 0) { counts.remove(id); } else { counts[id] = count; }
    }
  }

  void setOnlineStatus(bool online) {
    _isOnline = online;
    if (_isOnline) {
      _syncPendingOfflineData();
    }
  }

  Future<void> _syncPendingOfflineData() {
    final existing = _pendingSyncFuture;
    if (existing != null) return existing;
    if (_firestore == null || !_isOnline) return Future.value();
    late final Future<void> attempt;
    attempt = _runPendingOfflineData().whenComplete(() {
      if (identical(_pendingSyncFuture, attempt)) _pendingSyncFuture = null;
    });
    _pendingSyncFuture = attempt;
    return attempt;
  }

  Future<void> _runPendingOfflineData() async {
    await _syncPendingOfflineProducts();
    await _syncPendingOfflineTransactions();
    await _syncPendingOfflineExpenses();
  }

  bool get _hasPendingOfflineData => _products.any((p) => !p.isSynced) ||
      _transactions.any((t) => !t.isSynced) ||
      _operationalExpenses.any((e) => !e.isSynced);

  static bool _sameProduct(Product a, Product b) =>
      jsonEncode(_canonicalJson(a.copyWith(isSynced: false).toMap())) ==
      jsonEncode(_canonicalJson(b.copyWith(isSynced: false).toMap()));

  static bool _sameExpense(OperationalExpense a, OperationalExpense b) =>
      jsonEncode(_canonicalJson(a.copyWith(isSynced: false).toMap())) ==
      jsonEncode(_canonicalJson(b.copyWith(isSynced: false).toMap()));

  @visibleForTesting
  static List<Product> acknowledgeProducts(List<Product> current, List<Product> committed) {
    final sent = {for (final product in committed) product.id: product};
    return current.map((product) {
      final original = sent[product.id];
      return original != null && !product.isSynced && _sameProduct(product, original)
          ? product.copyWith(isSynced: true) : product;
    }).toList();
  }

  @visibleForTesting
  static List<OperationalExpense> acknowledgeExpenses(
      List<OperationalExpense> current, List<OperationalExpense> committed) {
    final sent = {for (final expense in committed) expense.id: expense};
    return current.map((expense) {
      final original = sent[expense.id];
      return original != null && !expense.isSynced && _sameExpense(expense, original)
          ? expense.copyWith(isSynced: true) : expense;
    }).toList();
  }

  void _acknowledgeProducts(List<Product> committed) {
    final updated = acknowledgeProducts(_products, committed);
    _products..clear()..addAll(updated);
  }

  Future<void> _syncPendingOfflineProducts() async {
    if (_firestore == null) return;
    if (_seedingProducts) return;
    final unsynced = _products.where((p) => !p.isSynced && !_activeProductWrites.containsKey(p.id)).toList();
    if (unsynced.isEmpty) return;

    try {
      for (var offset = 0; offset < unsynced.length; offset += 10) {
        final chunk = unsynced.skip(offset).take(10).toList();
        final batch = _firestore!.batch();
        for (final product in chunk) {
          batch.set(_firestore!.collection('products').doc(product.id),
              product.copyWith(isSynced: true).toMap(), SetOptions(merge: true));
        }
        await batch.commit();
        final before = List<Product>.of(_products);
        _acknowledgeProducts(chunk);
        try {
          await _persistProducts();
        } catch (_) {
          for (final previous in before.where((p) => !p.isSynced)) {
            final index = _products.indexWhere((p) => p.id == previous.id);
            if (index >= 0 && _products[index].isSynced && _sameProduct(_products[index], previous)) {
              _products[index] = previous;
            }
          }
          rethrow;
        }
      }
      _notifyProducts();
    } catch (e) {
      debugPrint('Batch sync products notice: $e');
    }
  }

  Future<void> _syncPendingOfflineTransactions() async {
    if (_firestore == null) return;
    bool hasChanges = false;
    final pending = _transactions.where((t) => !t.isSynced && !_activeTransactionWrites.containsKey(t.id)).toList();
    for (final pendingTx in pending) {
        try {
          final syncedTx = pendingTx.copyWith(isSynced: true);
          final ref = _firestore!.collection('transactions').doc(syncedTx.id);
          final newer = await _firestore!.runTransaction<TransactionRecord?>((transaction) async {
            final snapshot = await transaction.get(ref);
            final data = snapshot.data();
            if (data != null) {
              final remote = TransactionRecord.fromMap(data);
              if (remote.revision > syncedTx.revision || (remote.isVoided && !syncedTx.isVoided)) {
                return remote.copyWith(isSynced: true);
              }
            }
            transaction.set(ref, syncedTx.toMap(), SetOptions(merge: true));
            return null;
          });
          final index = _transactions.indexWhere((t) => t.id == syncedTx.id);
          if (index >= 0) {
            final current = _transactions[index];
            if (newer != null && (newer.revision > current.revision ||
                (newer.revision == current.revision && newer.isVoided && !current.isVoided))) {
              _transactions[index] = newer;
            } else if (newer == null && _sameTransaction(current, syncedTx)) {
              _transactions[index] = current.copyWith(isSynced: true);
            }
          }
          hasChanges = true;
        } catch (e) {
          debugPrint('Failed to sync transaction ${pendingTx.id}: $e');
        }
    }
    if (hasChanges) {
      await _persistTransactions();
      _notifyTransactions();
    }
  }

  Future<void> _syncPendingOfflineExpenses() async {
    if (_firestore == null) return;
    final unsynced = _operationalExpenses.where((e) => !e.isSynced && !_activeExpenseWrites.containsKey(e.id)).toList();
    if (unsynced.isEmpty) return;

    try {
      for (var offset = 0; offset < unsynced.length; offset += 100) {
        final chunk = unsynced.skip(offset).take(100).toList();
        final batch = _firestore!.batch();
        for (final expense in chunk) {
          batch.set(_firestore!.collection('operational_expenses').doc(expense.id),
              expense.copyWith(isSynced: true).toMap(), SetOptions(merge: true));
        }
        await batch.commit();
        final before = List<OperationalExpense>.of(_operationalExpenses);
        final updated = acknowledgeExpenses(_operationalExpenses, chunk);
        _operationalExpenses..clear()..addAll(updated);
        try {
          await _persistOperationalExpenses();
        } catch (_) {
          for (final previous in before.where((e) => !e.isSynced)) {
            final index = _operationalExpenses.indexWhere((e) => e.id == previous.id);
            if (index >= 0 && _operationalExpenses[index].isSynced && _sameExpense(_operationalExpenses[index], previous)) {
              _operationalExpenses[index] = previous;
            }
          }
          rethrow;
        }
      }
      _notifyOperationalExpenses();
    } catch (e) {
      debugPrint('Batch sync operational expenses notice: $e');
    }
  }

  List<Product> getProducts() => List.unmodifiable(_products);
  List<TransactionRecord> getTransactions() => _actor == null ? const [] : List.unmodifiable(
    _transactions.where((t) => _actor!.role.canViewFinancialReports || t.cashierId == _actor!.id)
      .map((t) => t.copyWith(items: t.items.map((i) => i.copyWith()).toList())));
  List<UserProfile> getUsers() => _actor == null ? const [] : List.unmodifiable(
    _users.where((u) => _actor!.role.canManageUsers || u.id == _actor!.id));
  List<String> getCategories() => List.unmodifiable(_categories);
  List<OperationalExpense> getOperationalExpenses() =>
      _actor?.role.canViewFinancialReports == true ? List.unmodifiable(_operationalExpenses) : const [];

  Future<String?> addCategory(String category) async {
    _requireAccess((r) => r.canManageCategories);
    final clean = category.trim();
    if (clean.isEmpty) {
      return 'Nama kategori tidak boleh kosong.';
    }
    if (_categories.any((c) => c.toLowerCase() == clean.toLowerCase())) {
      return 'Kategori "$clean" sudah ada.';
    }
    _categories.add(clean);
    _categories.sort();
    await _persistCategories();
    _notifyCategories();

    if (_firestore != null && _isOnline) {
      try {
        await _firestore!
            .collection('meta')
            .doc('categories')
            .set({'list': _categories}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore add category error: $e');
      }
    }
    return null;
  }

  Future<String?> updateCategory(String oldCategory, String newCategory) async {
    _requireAccess((r) => r.canManageCategories);
    final cleanOld = oldCategory.trim();
    final cleanNew = newCategory.trim();
    if (cleanNew.isEmpty) {
      return 'Nama kategori baru tidak boleh kosong.';
    }
    if (cleanOld.toLowerCase() == cleanNew.toLowerCase()) {
      return null;
    }
    if (_categories.any((c) => c.toLowerCase() == cleanNew.toLowerCase())) {
      return 'Kategori "$cleanNew" sudah ada.';
    }

    final index = _categories.indexWhere(
      (c) => c.toLowerCase() == cleanOld.toLowerCase(),
    );
    if (index == -1) {
      return 'Kategori "$cleanOld" tidak ditemukan.';
    }

    _categories[index] = cleanNew;
    _categories.sort();

    bool productsChanged = false;
    final now = DateTime.now();
    for (int i = 0; i < _products.length; i++) {
      if (_products[i].category.toLowerCase() == cleanOld.toLowerCase()) {
        bool synced = false;
        final updatedProd = _products[i].copyWith(
          category: cleanNew,
          updatedAt: now,
          isSynced: false,
        );
        if (_firestore != null && _isOnline) {
          try {
            await _firestore!
                .collection('products')
                .doc(updatedProd.id)
                .set(updatedProd.copyWith(isSynced: true).toMap());
            synced = true;
          } catch (_) {}
        }
        _products[i] = updatedProd.copyWith(isSynced: synced);
        productsChanged = true;
      }
    }

    await _persistCategories();
    if (productsChanged) {
      await _persistProducts();
      _notifyProducts();
    }
    _notifyCategories();

    if (_firestore != null && _isOnline) {
      try {
        await _firestore!
            .collection('meta')
            .doc('categories')
            .set({'list': _categories}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore update category error: $e');
      }
    }
    return null;
  }

  Future<String?> deleteCategory(
    String category, {
    String fallbackCategory = 'Umum',
  }) async {
    _requireAccess((r) => r.canManageCategories);
    final clean = category.trim();
    if (_categories.length <= 1) {
      return 'Minimal harus tersisa satu kategori di sistem.';
    }

    final index = _categories.indexWhere(
      (c) => c.toLowerCase() == clean.toLowerCase(),
    );
    if (index == -1) {
      return 'Kategori "$clean" tidak ditemukan.';
    }

    _categories.removeAt(index);
    if (!_categories.any(
      (c) => c.toLowerCase() == fallbackCategory.toLowerCase(),
    )) {
      _categories.add(fallbackCategory);
    }
    _categories.sort();

    bool productsChanged = false;
    final now = DateTime.now();
    for (int i = 0; i < _products.length; i++) {
      if (_products[i].category.toLowerCase() == clean.toLowerCase()) {
        bool synced = false;
        final updatedProd = _products[i].copyWith(
          category: fallbackCategory,
          updatedAt: now,
          isSynced: false,
        );
        if (_firestore != null && _isOnline) {
          try {
            await _firestore!
                .collection('products')
                .doc(updatedProd.id)
                .set(updatedProd.copyWith(isSynced: true).toMap());
            synced = true;
          } catch (_) {}
        }
        _products[i] = updatedProd.copyWith(isSynced: synced);
        productsChanged = true;
      }
    }

    await _persistCategories();
    if (productsChanged) {
      await _persistProducts();
      _notifyProducts();
    }
    _notifyCategories();

    if (_firestore != null && _isOnline) {
      try {
        await _firestore!
            .collection('meta')
            .doc('categories')
            .set({'list': _categories}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore delete category error: $e');
      }
    }
    return null;
  }

  // Authentication
  UserProfile? _findUserByUsername(String username) {
    final cleanUsername = username.trim().toLowerCase();
    for (final user in _users) {
      if (user.username.toLowerCase() == cleanUsername) {
        return user;
      }
    }
    return null;
  }

  Future<UserProfile?> authenticate(String username, String password) => authenticateAsync(username, password);

  bool _authInFlight = false;
  Future<UserProfile?> authenticateAsync(String username, String password) async {
    if (_authInFlight) throw StateError('Login sedang diproses.');
    _authInFlight = true;
    try {
      final prefs = await SecurePreferences.getInstance();
      final until = prefs.getInt('login_locked_until') ?? 0;
      if (until > DateTime.now().millisecondsSinceEpoch) throw StateError('Terlalu banyak percobaan. Coba lagi dalam 30 detik.');
      
      final cleanUsername = username.trim().toLowerCase();
      final user = _findUserByUsername(cleanUsername);

      if (user == null || !await user.verifyPasswordAsync(password)) {
        final failures = (prefs.getInt('login_failures') ?? 0) + 1;
        await prefs.setInt('login_failures', failures >= 5 ? 0 : failures);
        if (failures >= 5) await prefs.setInt('login_locked_until', DateTime.now().add(const Duration(seconds: 30)).millisecondsSinceEpoch);
        return null;
      }
      await prefs.remove('login_failures');
      await prefs.remove('login_locked_until');
      _sessionUserId = user.id;
      return user;
    } finally { _authInFlight = false; }
  }

  Future<void> recordLogin(UserProfile user) async {
    if (_actor?.id != user.id) throw StateError('Akses ditolak.');
    final index = _users.indexWhere((u) => u.id == user.id);
    _users[index] = _users[index].copyWith(lastLoginAt: DateTime.now());
    await _persistUsers();
    _notifyUsers();
    if (_firestore != null && _isOnline) unawaited(_syncSavedUser(_users[index]));
  }

  Future<UserProfile> changeOwnPassword(String oldPassword, String newPassword) async {
    final actor = _actor;
    if (actor == null || !await actor.verifyPasswordAsync(oldPassword)) { throw StateError('Password saat ini tidak valid.'); }
    if (oldPassword == newPassword) throw ArgumentError('Gunakan password baru yang berbeda.');
    final changed = await actor.withSecurePassword(newPassword);
    if (_actor?.id != actor.id || _actor?.passwordHash != actor.passwordHash) throw StateError('Sesi sudah berubah.');
    _users[_users.indexWhere((u) => u.id == actor.id)] = changed;
    await _persistUsers();
    _notifyUsers();
    if (_firestore != null && _isOnline) unawaited(_syncSavedUser(changed));
    return changed;
  }

  bool isUsernameTaken(String username, {String? excludeUserId}) {
    final clean = username.trim().toLowerCase();
    return _users.any(
      (u) => u.username.toLowerCase() == clean && u.id != excludeUserId,
    );
  }

  // User Profile CRUD
  Future<String?> saveUser(UserProfile user) async {
    _requireAccess((r) => r.canManageUsers);
    final existing = _users.where((u) => u.id == user.id).firstOrNull;
    if (existing != null && (existing.id == _actor!.id || existing.username == 'warloc.owner') &&
        (!user.isActive || user.role != UserRole.owner || user.username != existing.username)) { return 'Akun owner utama dilindungi.'; }
    if (user.username.trim().isEmpty || user.displayName.trim().isEmpty ||
        !RegExp(r'^[a-z0-9._-]{3,64}$').hasMatch(user.username) || user.displayName.length > 120) {
      return 'Username/nama pengguna tidak valid.';
    }
    if (existing == null && !user.passwordHash.startsWith('pbkdf2-sha256:600000:')) return 'Gunakan password kuat untuk akun baru.';
    if (isUsernameTaken(user.username, excludeUserId: user.id)) {
      return 'Username "@${user.username}" sudah digunakan oleh akun lain.';
    }

    final index = _users.indexWhere((u) => u.id == user.id);
    if (index != -1) {
      _users[index] = user;
    } else {
      _users.add(user);
    }
    await _persistUsers();
    _notifyUsers();

    // A queued offline cloud write must not prevent local login/session saving.
    if (_firestore != null && _isOnline) unawaited(_syncSavedUser(user));
    return null;
  }

  Future<void> _syncSavedUser(UserProfile user) async {
    try {
      await _firestore!.collection('users').doc(user.id)
          .set(user.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore save user error: $e');
    }
  }

  Future<bool> deleteUser(String userId) async {
    _requireAccess((r) => r.canManageUsers);
    if (userId == _actor!.id) return false;
    final index = _users.indexWhere((u) => u.id == userId);
    if (index == -1) return false;

    final target = _users[index];
    if (target.username.toLowerCase() == 'warloc.owner' ||
        target.username.toLowerCase() == 'iggoys') {
      return false; // Primary owner protected
    }

    _users.removeAt(index);
    await _persistUsers();
    _notifyUsers();

    if (_firestore != null && _isOnline) {
      try {
        await _firestore!.collection('users').doc(userId).delete();
      } catch (e) {
        debugPrint('Firestore delete user error: $e');
      }
    }
    return true;
  }

  Future<TransactionRecord> processTransaction(
    TransactionRecord transaction,
  ) async {
    _requireAccess((r) => true);
    if (_correctingTransaction) throw StateError('Koreksi transaksi sedang diproses.');
    transaction = transaction.copyWith(items: transaction.items.map((i) => i.copyWith()).toList());
    _validateTransaction(transaction);
    if (_transactions.any((tx) => tx.id == transaction.id ||
        (transaction.openBillId != null && tx.openBillId == transaction.openBillId))) {
      throw StateError('Transaksi atau tagihan sudah diproses.');
    }
    final now = DateTime.now();
    final updatedProducts = <String, Product>{};
    for (final item in transaction.items) {
      final productIndex = _products.indexWhere((p) => p.id == item.product.id);
      if (productIndex != -1) {
        final current = _products[productIndex];
        // Entertainment rental items (minStockThreshold == 0 && isEntertainment) keep service capacity high
        final newStock = current.isEntertainment && current.minStockThreshold == 0
            ? current.stock
            : (current.stock - item.quantity).clamp(0, 99999);

        final updatedProd = current.copyWith(
          stock: newStock,
          updatedAt: now,
          isSynced: false,
        );

        _products[productIndex] = updatedProd;
        updatedProducts[updatedProd.id] = updatedProd;
      }
    }

    final finalTransaction = transaction.copyWith(isSynced: false);
    _transactions.insert(0, finalTransaction);

    await _persistProducts();
    await _persistTransactions();

    if (transaction.openBillId != null) {
      _openBills.removeWhere((b) => b.id == transaction.openBillId);
      await _persistOpenBills();
      _openBillsController.add(getOpenBills());
    }

    _notifyProducts();
    _notifyTransactions();

    // Persist the sale locally before waiting for a server acknowledgement.
    if (_firestore != null && _isOnline) {
      unawaited(_syncCheckout(finalTransaction, updatedProducts.values.toList()));
    }

    return finalTransaction.copyWith(items: finalTransaction.items.map((i) => i.copyWith()).toList());
  }

  void _validateTransaction(TransactionRecord transaction) {
    final values = [transaction.subtotalAmount, transaction.discountAmount, transaction.totalAmount,
      transaction.totalCost, transaction.totalProfit, transaction.amountPaid, transaction.changeAmount];
    if (transaction.items.isEmpty || values.any((v) => !v.isFinite) ||
        transaction.items.length > 200 || !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(transaction.id) ||
        transaction.id != transaction.invoiceNumber ||
        transaction.discountAmount < 0 || transaction.totalAmount < 0 ||
        !['Cash', 'QRIS'].contains(transaction.paymentMethod) || transaction.isVoided ||
        transaction.cashierId != _actor!.id || transaction.cashierName != _actor!.displayName) {
      throw ArgumentError('Transaksi tidak valid.');
    }
    var subtotal = 0.0;
    var cost = 0.0;
    final ids = <String>{};
    final quantities = <String, int>{};
    for (final item in transaction.items) {
      final product = _products.where((p) => p.id == item.product.id).firstOrNull;
      final total = (quantities[item.product.id] ?? 0) + item.quantity;
      if (product == null || !product.isAvailable || item.quantity < 1 || total > product.stock ||
          (item.drinkVariant != null && !product.isDrink) ||
          !ids.add('${item.product.id}\u0000${item.drinkVariant ?? ''}') ||
          item.product.sellPrice != product.sellPrice + (CartItem.variantPrices[item.drinkVariant] ?? 0) || item.product.baseCost != product.baseCost) {
        throw StateError('Stok/harga tidak sesuai katalog.');
      }
      quantities[product.id] = total;
      subtotal += item.product.sellPrice * item.quantity;
      cost += product.baseCost * item.quantity;
    }
    bool equal(double a, double b) => (a - b).abs() < 0.001;
    final total = subtotal - transaction.discountAmount;
    if (total < 0 || !equal(subtotal, transaction.subtotalAmount) || !equal(cost, transaction.totalCost) ||
        !equal(total, transaction.totalAmount) || !equal(total - cost, transaction.totalProfit) ||
        transaction.amountPaid < total || !equal(transaction.amountPaid - total, transaction.changeAmount)) {
      throw ArgumentError('Perhitungan transaksi tidak valid.');
    }
    if (transaction.openBillId != null) {
      final bill = _openBills.where((b) => b.id == transaction.openBillId).firstOrNull;
      if (bill == null || bill.revision != transaction.openBillRevision ||
          (_actor!.role == UserRole.barista && bill.createdBy != _actor!.id)) { throw StateError('Akses/revisi tagihan ditolak.'); }
    }
  }

  @visibleForTesting
  Future<void> insertHistoricalTransactionForTesting(TransactionRecord transaction) async {
    var allowed = false;
    assert(() { allowed = true; return true; }());
    if (!allowed) { throw StateError('Test fixture only.'); }
    _transactions.insert(0, transaction);
    await _persistTransactions();
    _notifyTransactions();
  }

  static Object? _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonicalJson(value[key])};
    }
    if (value is List) return value.map(_canonicalJson).toList();
    return value;
  }

  static bool _sameTransaction(TransactionRecord a, TransactionRecord b) =>
      jsonEncode(_canonicalJson(a.copyWith(isSynced: false).toMap())) ==
      jsonEncode(_canonicalJson(b.copyWith(isSynced: false).toMap()));

  Future<void> _syncCheckout(TransactionRecord transaction, List<Product> products) async {
    _trackWrites(_activeTransactionWrites, [transaction.id], 1);
    _trackWrites(_activeProductWrites, products.map((p) => p.id), 1);
    try {
      final firestore = _firestore!;
      await firestore.runTransaction((operation) async {
        final txRef = firestore.collection('transactions').doc(transaction.id);
        final existing = (await operation.get(txRef)).data();
        if (existing != null) {
          final remote = TransactionRecord.fromMap(existing);
          if (remote.revision > transaction.revision || (remote.isVoided && !transaction.isVoided)) {
            throw StateError('Transaksi sudah dikoreksi atau dibatalkan di perangkat lain.');
          }
          final comparable = transaction.copyWith(isVoided: remote.isVoided, isSynced: false);
          if (!_sameTransaction(remote, comparable)) {
            throw StateError('Transaksi berbeda dengan data server.');
          }
          if (remote.isVoided == transaction.isVoided) return;
        }
        for (final product in products) {
          operation.set(firestore.collection('products').doc(product.id),
              product.copyWith(isSynced: true).toMap());
        }
        operation.set(txRef, transaction.copyWith(isSynced: true).toMap());
      });
      for (final product in products) {
        final index = _products.indexWhere((p) => p.id == product.id);
        if (index != -1 && _products[index].updatedAt == product.updatedAt &&
            _products[index].stock == product.stock) {
          _products[index] = _products[index].copyWith(isSynced: true);
        }
      }
      final index = _transactions.indexWhere((t) => t.id == transaction.id);
      if (index != -1 && _transactions[index].isVoided == transaction.isVoided &&
          _transactions[index].revision == transaction.revision) {
        _transactions[index] = _transactions[index].copyWith(isSynced: true);
      }
      await _persistProducts();
      await _persistTransactions();
      _notifyProducts();
      _notifyTransactions();
    } catch (e) {
      debugPrint('Firestore checkout sync pending: $e');
    } finally {
      _trackWrites(_activeTransactionWrites, [transaction.id], -1);
      _trackWrites(_activeProductWrites, products.map((p) => p.id), -1);
    }
  }

  /// Voids a transaction and restores deducted inventory stock
  bool _correctingTransaction = false;

  Future<TransactionRecord> correctTransaction({
    required String transactionId,
    required int expectedRevision,
    required List<CartItem> items,
    required double amountPaid,
    required String reason,
  }) async {
    _requireAccess((r) => true);
    if (_correctingTransaction) throw StateError('Koreksi transaksi sedang diproses.');
    _correctingTransaction = true;
    try {
      final actor = _actor!;
      final old = _transactions.where((t) => t.id == transactionId).firstOrNull;
      if (old == null || (actor.role != UserRole.owner && old.cashierId != actor.id)) {
        throw StateError('Transaksi tidak ditemukan atau akses ditolak.');
      }
      if (old.isVoided || old.revision != expectedRevision) {
        throw StateError('Transaksi sudah berubah atau telah dibatalkan. Buka kembali riwayat.');
      }
      if (!old.totalAmount.isFinite || old.totalAmount < 0 ||
          !old.discountAmount.isFinite || old.discountAmount < 0) {
        throw StateError('Data transaksi awal tidak valid.');
      }
      if (reason.trim().isEmpty || reason.trim().length > 200) throw ArgumentError('Alasan koreksi wajib diisi, maksimal 200 karakter.');
      if (items.isEmpty || items.length > 200) throw ArgumentError('Sisakan minimal satu item pada transaksi.');
      if (!amountPaid.isFinite || amountPaid < 0) throw ArgumentError('Pembayaran tidak valid.');

      String itemKey(CartItem item) => '${item.product.id}\u0000${item.drinkVariant ?? ''}';
      final oldItems = {for (final item in old.items) itemKey(item): item};
      final previousQty = <String, int>{};
      final newQty = <String, int>{};
      final unique = <String>{};
      for (final item in old.items) {
        if (item.quantity < 1 || item.quantity > 99999) throw StateError('Jumlah item transaksi awal tidak valid.');
        previousQty[item.product.id] = (previousQty[item.product.id] ?? 0) + item.quantity;
      }
      var subtotal = 0.0;
      var cost = 0.0;
      final cleaned = <CartItem>[];
      for (final entry in items) {
        var item = entry.copyWith();
        final product = _products.where((p) => p.id == item.product.id).firstOrNull;
        final previous = oldItems[itemKey(item)];
        if (product == null || item.quantity < 1 || item.quantity > 99999 || !unique.add(itemKey(item)) ||
            (item.drinkVariant != null && previous == null && !product.isDrink) ||
            !item.product.sellPrice.isFinite || item.product.sellPrice < 0 ||
            !item.product.baseCost.isFinite || item.product.baseCost < 0 ||
            (previous != null && (item.product.sellPrice != previous.product.sellPrice || item.product.baseCost != previous.product.baseCost)) ||
            (previous == null && (!product.isAvailable || item.product.sellPrice != product.sellPrice + (CartItem.variantPrices[item.drinkVariant] ?? 0) || item.product.baseCost != product.baseCost))) {
          throw StateError('Item atau harga koreksi tidak valid. Buka kembali transaksi.');
        }
        item = previous != null
            ? previous.copyWith(quantity: item.quantity)
            : CartItem(product: product.copyWith(sellPrice: product.sellPrice + (CartItem.variantPrices[item.drinkVariant] ?? 0)),
                quantity: item.quantity, note: CartItem.composeNote(item.drinkVariant, null));
        newQty[product.id] = (newQty[product.id] ?? 0) + item.quantity;
        subtotal += item.subtotal;
        cost += item.subtotalCost;
        cleaned.add(item);
      }
      if (!subtotal.isFinite || !cost.isFinite || old.discountAmount > subtotal) {
        throw StateError('Subtotal lebih kecil dari diskon transaksi atau tidak valid.');
      }
      final total = subtotal - old.discountAmount;
      if (amountPaid < total || (old.paymentMethod == 'QRIS' && amountPaid != total)) {
        throw ArgumentError('Pembayaran akhir harus mencukupi; untuk QRIS harus sama dengan total.');
      }
      final now = DateTime.now();
      final affectedIds = {...previousQty.keys, ...newQty.keys};
      final before = <String, Product>{};
      final updates = <String, Product>{};
      for (final id in affectedIds) {
        final product = _products.where((p) => p.id == id).firstOrNull;
        if (product == null) throw StateError('Produk transaksi tidak lagi tersedia di inventori.');
        final restored = previousQty[id] ?? 0;
        final consumed = newQty[id] ?? 0;
        final newStock = product.isEntertainment && product.minStockThreshold == 0
            ? product.stock : product.stock + restored - consumed;
        if (newStock < 0 || newStock > 99999) throw StateError('Stok tidak mencukupi untuk koreksi.');
        before[id] = product;
        if (newStock != product.stock) {
          updates[id] = product.copyWith(stock: newStock, updatedAt: now, isSynced: _firestore != null);
        }
      }
      final audit = <String, dynamic>{
        'revision': old.revision + 1,
        'correctedAt': now.toIso8601String(),
        'correctedById': actor.id,
        'correctedBy': actor.displayName,
        'reason': reason.trim(),
        'previousItems': old.items.map((item) => item.toMap()).toList(),
        'previousSubtotal': old.subtotalAmount,
        'previousTotal': old.totalAmount,
        'previousDiscount': old.discountAmount,
        'previousCost': old.totalCost,
        'previousProfit': old.totalProfit,
        'paymentMethod': old.paymentMethod,
        'previousAmountPaid': old.amountPaid,
        'previousChangeAmount': old.changeAmount,
        'newTotal': total,
        'newAmountPaid': amountPaid,
        'difference': total - old.totalAmount,
      };
      final corrected = old.copyWith(
        items: cleaned, subtotalAmount: subtotal, totalAmount: total,
        totalCost: cost, totalProfit: total - cost,
        amountPaid: amountPaid, changeAmount: amountPaid - total,
        revision: old.revision + 1, corrections: [...old.corrections, audit],
        isSynced: _firestore != null,
      );

      if (_firestore == null && !_testMode) {
        throw StateError('Koreksi transaksi memerlukan koneksi Firebase agar stok dan pembayaran tetap konsisten.');
      }
      if (_firestore != null) {
        if (!_isOnline || !old.isSynced || before.values.any((p) => !p.isSynced)) {
          throw StateError('Sinkronkan transaksi dan stok, lalu hubungkan internet sebelum koreksi.');
        }
        final firestore = _firestore!;
        await firestore.runTransaction((transaction) async {
          final txRef = firestore.collection('transactions').doc(old.id);
          final txSnapshot = await transaction.get(txRef);
          final txData = txSnapshot.data();
          if (txData == null) throw StateError('Transaksi belum tersedia di server.');
          final remote = TransactionRecord.fromMap(txData);
          if (!_sameTransaction(remote, old)) {
            throw StateError('Transaksi sudah berubah di perangkat lain. Buka kembali riwayat.');
          }
          final refs = <String, DocumentReference<Map<String, dynamic>>>{};
          for (final entry in before.entries) {
            final ref = firestore.collection('products').doc(entry.key);
            final snapshot = await transaction.get(ref);
            final data = snapshot.data();
            final remoteProduct = data == null ? null : Product.fromMap(data);
            final localProduct = entry.value;
            if (remoteProduct == null || remoteProduct.stock != localProduct.stock ||
                remoteProduct.sellPrice != localProduct.sellPrice || remoteProduct.baseCost != localProduct.baseCost ||
                remoteProduct.isAvailable != localProduct.isAvailable || remoteProduct.isDrink != localProduct.isDrink ||
                remoteProduct.isEntertainment != localProduct.isEntertainment ||
                remoteProduct.minStockThreshold != localProduct.minStockThreshold) {
              throw StateError('Stok atau menu berubah di perangkat lain. Sinkronkan dan coba lagi.');
            }
            refs[entry.key] = ref;
          }
          if (_actor?.id != actor.id) throw StateError('Sesi pengguna telah berubah.');
          for (final entry in updates.entries) {
            transaction.update(refs[entry.key]!, {'stock': entry.value.stock, 'updatedAt': now.toIso8601String(), 'isSynced': 1});
          }
          transaction.set(txRef, corrected.toMap());
        });
      }
      final current = _transactions.indexWhere((t) => t.id == old.id);
      if (current >= 0 && _transactions[current].revision == old.revision && !_transactions[current].isVoided) {
        _transactions[current] = corrected;
      }
      for (final entry in updates.entries) {
        final index = _products.indexWhere((p) => p.id == entry.key);
        if (index >= 0 && _products[index].stock == before[entry.key]!.stock) {
          _products[index] = entry.value;
        }
      }
      try {
        await _persistLedger();
      } catch (_) {
        if (_firestore == null) {
          final index = _transactions.indexWhere((t) => identical(t, corrected));
          if (index >= 0) _transactions[index] = old;
          for (final entry in updates.entries) {
            final index = _products.indexWhere((p) => identical(p, entry.value));
            if (index >= 0) _products[index] = before[entry.key]!;
          }
          throw StateError('Koreksi gagal disimpan pada perangkat.');
        }
        throw StateError('Koreksi tersimpan di server, tetapi penyimpanan perangkat gagal. Buka kembali riwayat setelah sinkronisasi.');
      }
      _notifyProducts();
      _notifyTransactions();
      return corrected;
    } finally {
      _correctingTransaction = false;
    }
  }

  Future<bool> voidTransaction(String transactionId) async {
    _requireAccess((r) => r.canVoidTransactions);
    if (_correctingTransaction) throw StateError('Koreksi transaksi sedang diproses.');
    final index = _transactions.indexWhere((t) => t.id == transactionId);
    if (index < 0 || _transactions[index].isVoided) return false;
    final transaction = _transactions[index];
    final updates = <String, Product>{};
    final now = DateTime.now();
    for (final item in transaction.items) {
      final productIndex = _products.indexWhere((p) => p.id == item.product.id);
      if (productIndex < 0) continue;
      final product = _products[productIndex];
      final stock = product.isEntertainment && product.minStockThreshold == 0
          ? product.stock : (product.stock + item.quantity).clamp(0, 99999);
      final updated = product.copyWith(stock: stock, updatedAt: now, isSynced: false);
      _products[productIndex] = updated;
      updates[updated.id] = updated;
    }
    final voided = transaction.copyWith(isVoided: true, isSynced: false);
    _transactions[index] = voided;
    await _persistProducts();
    await _persistTransactions();
    _notifyProducts();
    _notifyTransactions();
    if (_firestore != null && _isOnline) unawaited(_syncCheckout(voided, updates.values.toList()));
    return true;
  }

  static const maxBatchInsertItems = 100;
  Future<void> _batchInsertQueue = Future.value();

  Future<void> _enqueueBatchInsert(Future<void> Function() operation) {
    final result = _batchInsertQueue.then((_) => operation());
    _batchInsertQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _validateBatchSize(int count) {
    if (count < 1 || count > maxBatchInsertItems) {
      throw ArgumentError('Isi 1 sampai $maxBatchInsertItems item per penyimpanan.');
    }
  }

  Future<void> addProducts(List<Product> products) {
    final input = List<Product>.of(products);
    return _enqueueBatchInsert(() async {
      _requireAccess((r) => r.canEditProducts);
      _validateBatchSize(input.length);
      final ids = _products.map((p) => p.id).toSet();
      for (final product in input) {
        _validateProduct(product);
        if (product.category.trim().isEmpty || product.sellPrice <= 0) {
          throw ArgumentError('Kategori dan harga jual menu wajib diisi.');
        }
        if (!ids.add(product.id)) throw StateError('ID produk sudah digunakan.');
      }
      final now = DateTime.now();
      final saved = input.map((p) => p.copyWith(updatedAt: now, isSynced: false)).toList();
      final prefs = await SecurePreferences.getInstance();
      _requireAccess((r) => r.canEditProducts);
      final persisted = await prefs.setString('cached_ledger_v1', jsonEncode({
        'products': [..._products, ...saved].map((p) => p.toMap()).toList(),
        'transactions': _transactions.map((t) => t.toMap()).toList(),
        'openBills': _openBills.map((b) => b.toMap()).toList(),
      }));
      if (!persisted) throw StateError('Menu belum berhasil disimpan di perangkat.');
      _products.addAll(saved);
      _notifyProducts();
      if (_firestore != null && _isOnline) {
        unawaited(_syncInsertedBatch(products: saved));
      }
    });
  }

  Future<void> addOperationalExpenses(List<OperationalExpense> expenses) {
    final input = List<OperationalExpense>.of(expenses);
    return _enqueueBatchInsert(() async {
      _requireAccess((r) => r.canViewFinancialReports);
      _validateBatchSize(input.length);
      final ids = _operationalExpenses.map((e) => e.id).toSet();
      for (final expense in input) {
        if (expense.id.isEmpty || expense.id.contains('/') ||
            expense.title.trim().isEmpty || expense.category.trim().isEmpty ||
            !expense.amount.isFinite || expense.amount <= 0 ||
            expense.recordedBy != _actor!.displayName) {
          throw ArgumentError('Data biaya operasional tidak valid.');
        }
        if (!ids.add(expense.id)) throw StateError('ID biaya sudah digunakan.');
      }
      final saved = input.map((e) => e.copyWith(isSynced: false)).toList();
      final prefs = await SecurePreferences.getInstance();
      _requireAccess((r) => r.canViewFinancialReports);
      final next = [..._operationalExpenses, ...saved]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final persisted = await prefs.setString('cached_operational_expenses',
          jsonEncode(next.map((e) => e.toMap()).toList()));
      if (!persisted) throw StateError('Biaya belum berhasil disimpan di perangkat.');
      _operationalExpenses.addAll(saved);
      _sortOperationalExpenses();
      _notifyOperationalExpenses();
      if (_firestore != null && _isOnline) {
        unawaited(_syncInsertedBatch(expenses: saved));
      }
    });
  }

  Future<void> _syncInsertedBatch({
    List<Product> products = const [],
    List<OperationalExpense> expenses = const [],
  }) async {
    _trackWrites(_activeProductWrites, products.map((p) => p.id), 1);
    _trackWrites(_activeExpenseWrites, expenses.map((e) => e.id), 1);
    try {
      final batch = _firestore!.batch();
      for (final product in products) {
        batch.set(_firestore!.collection('products').doc(product.id),
            product.copyWith(isSynced: true).toMap());
      }
      for (final expense in expenses) {
        batch.set(_firestore!.collection('operational_expenses').doc(expense.id),
            expense.copyWith(isSynced: true).toMap());
      }
      await batch.commit();
      for (final product in products) {
        final index = _products.indexWhere((p) => identical(p, product));
        if (index >= 0) _products[index] = product.copyWith(isSynced: true);
      }
      for (final expense in expenses) {
        final index = _operationalExpenses.indexWhere((e) => identical(e, expense));
        if (index >= 0) _operationalExpenses[index] = expense.copyWith(isSynced: true);
      }
      if (products.isNotEmpty) {
        await _persistProducts();
        _notifyProducts();
      }
      if (expenses.isNotEmpty) {
        await _persistOperationalExpenses();
        _notifyOperationalExpenses();
      }
    } catch (e) {
      debugPrint('Firestore batch insert sync pending: $e');
    } finally {
      _trackWrites(_activeProductWrites, products.map((p) => p.id), -1);
      _trackWrites(_activeExpenseWrites, expenses.map((e) => e.id), -1);
    }
  }

  Future<void> addProduct(Product product) async {
    _requireAccess((r) => r.canEditProducts);
    _validateProduct(product);
    if (_products.any((p) => p.id == product.id)) throw StateError('ID produk sudah digunakan.');
    final stamped = product.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    bool synced = false;
    if (_firestore != null && _isOnline) {
      try {
        await _firestore!
            .collection('products')
            .doc(stamped.id)
            .set(stamped.copyWith(isSynced: true).toMap());
        synced = true;
      } catch (e) {
        debugPrint('Firestore add product error: $e');
      }
    }

    _products.add(stamped.copyWith(isSynced: synced));
    await _persistProducts();
    _notifyProducts();
  }

  Future<void> updateProduct(Product product) async {
    _requireAccess((r) => r.canEditProducts);
    _validateProduct(product);
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index == -1) return;

    final stamped = product.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    bool synced = false;
    if (_firestore != null && _isOnline) {
      try {
        // Full document .set() ensures updated or cleared imageUrl syncs across all devices
        await _firestore!
            .collection('products')
            .doc(stamped.id)
            .set(stamped.copyWith(isSynced: true).toMap());
        synced = true;
      } catch (e) {
        debugPrint('Firestore update product error: $e');
      }
    }

    _products[index] = stamped.copyWith(isSynced: synced);
    await _persistProducts();
    _notifyProducts();
  }

  Future<bool> deleteProduct(String productId) async {
    _requireAccess((r) => r.canEditProducts);
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return false;

    _products.removeAt(index);
    await _persistProducts();
    _notifyProducts();

    if (_firestore != null && _isOnline) {
      try {
        await _firestore!.collection('products').doc(productId).delete();
      } catch (e) {
        debugPrint('Firestore delete product error: $e');
      }
    }
    return true;
  }

  Future<void> adjustStock(String productId, int newStock) async {
    _requireAccess((r) => r.canAdjustStock);
    if (newStock < 0 || newStock > 99999) throw ArgumentError('Stok tidak valid.');
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return;

    final updated = _products[index].copyWith(
      stock: newStock.clamp(0, 99999),
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    bool synced = false;
    if (_firestore != null && _isOnline) {
      try {
        await _firestore!
            .collection('products')
            .doc(productId)
            .set(updated.copyWith(isSynced: true).toMap());
        synced = true;
      } catch (e) {
        debugPrint('Firestore adjust stock error: $e');
      }
    }

    _products[index] = updated.copyWith(isSynced: synced);
    await _persistProducts();
    _notifyProducts();
  }

  // Operational Expenses CRUD (Listrik, Air, Kantong Plastik, Sedotan, ATK, dll)
  Future<OperationalExpense> addOperationalExpense(
    OperationalExpense expense,
  ) async {
    _requireAccess((r) => r.canViewFinancialReports);
    if (!expense.amount.isFinite || expense.amount <= 0) throw ArgumentError('Nominal biaya tidak valid.');
    bool synced = false;
    if (_firestore != null && _isOnline) {
      try {
        final payload = expense.copyWith(isSynced: true);
        await _firestore!
            .collection('operational_expenses')
            .doc(expense.id)
            .set(payload.toMap());
        synced = true;
      } catch (e) {
        debugPrint('Firestore add operational expense error: $e');
      }
    }

    final saved = expense.copyWith(isSynced: synced);
    _operationalExpenses.insert(0, saved);
    _sortOperationalExpenses();
    await _persistOperationalExpenses();
    _notifyOperationalExpenses();
    return saved;
  }

  Future<OperationalExpense?> updateOperationalExpense(
    OperationalExpense expense,
  ) async {
    _requireAccess((r) => r.canViewFinancialReports);
    if (!expense.amount.isFinite || expense.amount <= 0) throw ArgumentError('Nominal biaya tidak valid.');
    final index = _operationalExpenses.indexWhere((e) => e.id == expense.id);
    if (index == -1) return null;

    bool synced = false;
    if (_firestore != null && _isOnline) {
      try {
        final payload = expense.copyWith(isSynced: true);
        await _firestore!
            .collection('operational_expenses')
            .doc(expense.id)
            .set(payload.toMap());
        synced = true;
      } catch (e) {
        debugPrint('Firestore update operational expense error: $e');
      }
    }

    final saved = expense.copyWith(isSynced: synced);
    _operationalExpenses[index] = saved;
    _sortOperationalExpenses();
    await _persistOperationalExpenses();
    _notifyOperationalExpenses();
    return saved;
  }

  Future<bool> deleteOperationalExpense(String expenseId) async {
    _requireAccess((r) => r.canViewFinancialReports);
    final index = _operationalExpenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) return false;

    _operationalExpenses.removeAt(index);
    await _persistOperationalExpenses();
    _notifyOperationalExpenses();

    if (_firestore != null && _isOnline) {
      try {
        await _firestore!
            .collection('operational_expenses')
            .doc(expenseId)
            .delete();
      } catch (e) {
        debugPrint('Firestore delete operational expense error: $e');
      }
    }
    return true;
  }

  void _validateProduct(Product product) {
    if (product.id.isEmpty || product.id.contains('/') || product.name.trim().isEmpty ||
        !product.sellPrice.isFinite || product.sellPrice < 0 || !product.baseCost.isFinite ||
        product.baseCost < 0 || product.stock < 0 || product.stock > 99999 || product.minStockThreshold < 0) {
      throw ArgumentError('Data produk tidak valid.');
    }
  }

  Future<String?> syncForCurrentUser() async {
    _requireAccess((r) => true);
    if (_firestore == null) return 'Firebase belum terhubung.';
    if (!_isOnline) return 'Perangkat offline. Data lokal tetap tersimpan.';
    try {
      await _syncPendingOfflineData().timeout(const Duration(seconds: 10));
      if (_hasPendingOfflineData || _activeProductWrites.isNotEmpty ||
          _activeTransactionWrites.isNotEmpty || _activeExpenseWrites.isNotEmpty) {
        return 'Masih ada data menunggu sinkronisasi. Periksa koneksi atau kuota Firebase.';
      }
      return null;
    }
    catch (_) { return 'Sinkronisasi belum selesai. Data lokal tetap tersimpan.'; }
  }

  @visibleForTesting
  static Future<int> syncChangedMetadata({
    required List<UserProfile> localUsers,
    required Map<String, UserProfile> remoteUsers,
    required List<String> localCategories,
    required List<String>? remoteCategories,
    required Future<void> Function(UserProfile) writeUser,
    required Future<void> Function(List<String>) writeCategories,
  }) async {
    var writes = 0;
    for (final user in localUsers) {
      final remote = remoteUsers[user.id];
      if (remote == null ||
          jsonEncode(_canonicalJson(remote.toMap())) !=
              jsonEncode(_canonicalJson(user.toMap()))) {
        await writeUser(user);
        writes++;
      }
    }
    final localSorted = List<String>.of(localCategories)..sort();
    final remoteSorted = remoteCategories == null
        ? null : (List<String>.of(remoteCategories)..sort());
    if (remoteSorted == null || jsonEncode(localSorted) != jsonEncode(remoteSorted)) {
      await writeCategories(localCategories);
      writes++;
    }
    return writes;
  }

  Future<String?> syncAllToFirestore() async {
    _requireAccess((r) => r.canManageUsers);
    if (_firestore == null) return 'Firebase belum terhubung pada perangkat ini.';
    final pendingError = await syncForCurrentUser();
    if (pendingError != null) return pendingError;
    try {
      final usersSnapshot = await _firestore!.collection('users')
          .get(const GetOptions(source: Source.server));
      final categoriesSnapshot = await _firestore!.collection('meta')
          .doc('categories').get(const GetOptions(source: Source.server));
      final categoryData = categoriesSnapshot.data()?['list'];
      await syncChangedMetadata(
        localUsers: List<UserProfile>.of(_users),
        remoteUsers: {for (final doc in usersSnapshot.docs)
          doc.id: UserProfile.fromMap(doc.data())},
        localCategories: List<String>.of(_categories),
        remoteCategories: categoryData is List
            ? categoryData.map((value) => value.toString()).toList() : null,
        writeUser: (user) => _firestore!.collection('users').doc(user.id)
            .set(user.toMap(), SetOptions(merge: true)),
        writeCategories: (categories) => _firestore!.collection('meta')
            .doc('categories').set({'list': categories}, SetOptions(merge: true)),
      );
      return null;
    } catch (e) {
      debugPrint('Sync error: $e');
      return 'Sinkronisasi belum selesai. Data lokal tetap tersimpan.';
    }
  }

  Future<void> _persistLedger() async {
    if (_loading) return;
    final payload = jsonEncode({
      'products': _products.map((p) => p.toMap()).toList(),
      'transactions': _transactions.map((t) => t.toMap()).toList(),
      'openBills': _openBills.map((b) => b.toMap()).toList(),
    });
    final prefs = await SecurePreferences.getInstance();
    await prefs.setString('cached_ledger_v1', payload);
  }

  Future<void> _persistProducts() => _persistLedger();
  Future<void> _persistTransactions() => _persistLedger();

  Future<void> _persistOperationalExpenses() async {
    final prefs = await SecurePreferences.getInstance();
    final list = _operationalExpenses.map((e) => e.toMap()).toList();
    await prefs.setString('cached_operational_expenses', jsonEncode(list));
  }

  Future<void> _persistUsers() async {
    final prefs = await SecurePreferences.getInstance();
    final list = _users.map((u) => u.toMap()).toList();
    await prefs.setString('cached_users', jsonEncode(list));
  }

  Future<void> _persistCategories() async {
    final prefs = await SecurePreferences.getInstance();
    await prefs.setString('cached_categories', jsonEncode(_categories));
  }

  void _notifyProducts() {
    if (!_productsStreamController.isClosed) {
      _productsStreamController.add(List.unmodifiable(_products));
    }
  }

  void _notifyTransactions() {
    if (!_transactionsStreamController.isClosed) {
      _transactionsStreamController.add(getTransactions());
    }
  }

  void _notifyUsers() {
    if (!_usersStreamController.isClosed) {
      _usersStreamController.add(getUsers());
    }
  }

  void _notifyCategories() {
    if (!_categoriesStreamController.isClosed) {
      _categoriesStreamController.add(List.unmodifiable(_categories));
    }
  }

  void _notifyOperationalExpenses() {
    if (!_operationalExpensesStreamController.isClosed) {
      _operationalExpensesStreamController.add(getOperationalExpenses());
    }
  }

  List<Product> _getDefaultHiburanProducts() {
    return const [
      Product(
        id: 'w_ps3',
        name: 'Rental PS3',
        category: 'Hiburan',
        sellPrice: 4000,
        baseCost: 0,
        stock: 999,
        minStockThreshold: 0,
        barcode: '8992009',
      ),
      Product(
        id: 'w_ps4',
        name: 'Rental PS4',
        category: 'Hiburan',
        sellPrice: 5000,
        baseCost: 0,
        stock: 999,
        minStockThreshold: 0,
        barcode: '8992010',
      ),
    ];
  }

  List<Product> _getInitialWarlocMenu() {
    return [
      const Product(
        id: 'w_1',
        name: 'Kopi Susu Warloc Gula Aren',
        category: 'Coffee',
        sellPrice: 22000,
        baseCost: 9000,
        stock: 50,
        minStockThreshold: 5,
        barcode: '8992001',
        imageUrl:
            'https://images.unsplash.com/photo-1541167760496-1628856ab772?w=400&q=80',
      ),
      const Product(
        id: 'w_2',
        name: 'Espresso Double Warloc',
        category: 'Coffee',
        sellPrice: 18000,
        baseCost: 6500,
        stock: 65,
        minStockThreshold: 5,
        barcode: '8992002',
        imageUrl:
            'https://images.unsplash.com/photo-1510591509098-f4fdc6d0ff04?w=400&q=80',
      ),
      const Product(
        id: 'w_3',
        name: 'Caramel Macchiato Warloc',
        category: 'Coffee',
        sellPrice: 28000,
        baseCost: 12000,
        stock: 35,
        minStockThreshold: 5,
        barcode: '8992003',
        imageUrl:
            'https://images.unsplash.com/photo-1485808191679-5f86510681a2?w=400&q=80',
      ),
      const Product(
        id: 'w_4',
        name: 'Iced Matcha Latte Warloc',
        category: 'Non-Coffee',
        sellPrice: 26000,
        baseCost: 11000,
        stock: 28,
        minStockThreshold: 5,
        barcode: '8992004',
        imageUrl:
            'https://images.unsplash.com/photo-1536256263959-770b48d82b0a?w=400&q=80',
      ),
      const Product(
        id: 'w_5',
        name: 'Red Velvet Fusion Warloc',
        category: 'Non-Coffee',
        sellPrice: 25000,
        baseCost: 10500,
        stock: 20,
        minStockThreshold: 5,
        barcode: '8992005',
        imageUrl:
            'https://images.unsplash.com/photo-1544787219-7f47ccb76574?w=400&q=80',
      ),
      const Product(
        id: 'w_6',
        name: 'Butter Croissant Warloc',
        category: 'Pastry',
        sellPrice: 24000,
        baseCost: 13000,
        stock: 4,
        minStockThreshold: 5,
        barcode: '8992006',
        imageUrl:
            'https://images.unsplash.com/photo-1555507036-ab1f4038808a?w=400&q=80',
      ),
      const Product(
        id: 'w_7',
        name: 'Roti Bakar Coklat Keju Warloc',
        category: 'Snack',
        sellPrice: 22000,
        baseCost: 9500,
        stock: 30,
        minStockThreshold: 5,
        barcode: '8992007',
        imageUrl:
            'https://images.unsplash.com/photo-1528735602780-2552fd46c7af?w=400&q=80',
      ),
      const Product(
        id: 'w_8',
        name: 'French Fries Crispy Warloc',
        category: 'Snack',
        sellPrice: 20000,
        baseCost: 8000,
        stock: 40,
        minStockThreshold: 5,
        barcode: '8992008',
        imageUrl:
            'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?w=400&q=80',
      ),
      ..._getDefaultHiburanProducts(),
    ];
  }

  /// Helper exclusively for clean unit test resets
  @visibleForTesting
  Future<void> resetForTesting() async {
    _batchInsertQueue = Future.value();
    _initialized = false;
    _products.clear();
    _transactions.clear();
    _users.clear();
    _categories.clear();
    _operationalExpenses.clear();
    _openBills.clear();
    _sessionUserId = null;
    await initialize();
  }

  void dispose() {
    _firestoreProductsSub?.cancel();
    _firestoreTransactionsSub?.cancel();
    _firestoreUsersSub?.cancel();
    _firestoreCategoriesSub?.cancel();
    _firestoreExpensesSub?.cancel();
  }
}
