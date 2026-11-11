import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'secure_preferences.dart';
import 'firestore_sync_safety.dart';
import 'automatic_sync.dart';
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
  Completer<void>? _transactionDeletion;
  int get pendingDeletedTransactionCount => _transactions.where((tx) => tx.isDeleted && !tx.isSynced).length;
  final Set<String> _pendingDeletes = {};
  Future<void> _deleteQueue = Future.value();
  Future<void>? _deletingPending;
  int get pendingDeletionCount => _pendingDeletes.length;
  final _openBillsController = StreamController<List<OpenBill>>.broadcast();
  Stream<List<OpenBill>> get openBillsStream => _openBillsController.stream;
  List<OpenBill> getOpenBills() => _actor == null ? const [] : List.unmodifiable(_openBills.where((bill) =>
    (_actor!.role != UserRole.barista || bill.createdBy == _actor!.id) &&
    !_transactions.any((tx) => tx.openBillId == bill.id)));

  Future<void> saveOpenBill(OpenBill bill, {int? expectedRevision}) async {
    if (_transactionDeletion != null) throw StateError('Penghapusan transaksi sedang disimpan.');
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
    final staged = List<OpenBill>.of(_openBills);
    if (index < 0) { staged.add(bill); } else { staged[index] = bill; }
    await _persistOpenBills(staged);
    _openBills..clear()..addAll(staged);
    _openBillsController.add(getOpenBills());
  }

  Future<void> deleteOpenBill(String id) async {
    if (_transactionDeletion != null) throw StateError('Penghapusan transaksi sedang disimpan.');
    _requireAccess((r) => true);
    final bill = _openBills.where((b) => b.id == id).firstOrNull;
    if (bill == null || (_actor!.role == UserRole.barista && bill.createdBy != _actor!.id)) throw StateError('Akses ditolak.');
    final staged = _openBills.where((b) => b.id != id).toList();
    await _persistOpenBills(staged);
    _openBills..clear()..addAll(staged);
    _openBillsController.add(getOpenBills());
  }

  Future<void> _persistOpenBills(List<OpenBill> bills) => _persistLedger(openBills: bills);

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

  bool _isOnline = false;
  bool get isOnline => _isOnline;
  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;
  AutomaticSync? _automaticSync;
  StreamSubscription<dynamic>? _networkSub;
  final Map<String, Map<String, dynamic>> _pendingMetadata = {};
  Future<void> _metadataQueue = Future.value();
  bool _referenceCheckNeeded = false;
  int get pendingMetadataCount => _pendingMetadata.length;

  void _requestAutoSync() => _automaticSync?.request();

  void _connectionChanged(bool connected) {
    _isOnline = connected && _firestore != null && !FirestoreSyncSafety.instance.connectionBlocked;
    _connectionController.add(_isOnline);
  }

  void _startAutomaticSync() {
    if (_automaticSync != null || _testMode) return;
    _automaticSync = AutomaticSync(
      hasWork: () => _hasPendingOfflineData || _referenceCheckNeeded || FirestoreSyncSafety.instance.connectionBlocked,
      onConnection: _connectionChanged,
      send: _automaticSyncAttempt,
    )..start();
    _networkSub = const EventChannel('com.kafekita.pos/network').receiveBroadcastStream().listen(
      (event) => _automaticSync?.networkChanged(event == true),
      onError: (Object error) => debugPrint('Network monitor unavailable: $error'),
    );
  }

  Future<bool> _automaticSyncAttempt() async {
    final safety = FirestoreSyncSafety.instance;
    if (safety.connectionBlocked) {
      final prefs = await SecurePreferences.getInstance();
      // A failed queue inspection requires review, not repeated automatic clearing.
      final until = prefs.getInt('firestore_blocked_until');
      if (until == null || !await safety.resumeIfAllowed(_firestore)) return false;
      if (_firestore == null) _setupFirestoreLiveSync();
    }
    _connectionChanged(_automaticSync?.connected ?? _isOnline);
    if (_firestore == null || !_isOnline) return false;
    if (_referenceCheckNeeded) await _bootstrapReferenceData();
    if (_referenceCheckNeeded) return false;
    if (safety.pendingDocuments.isNotEmpty) {
      try {
        await _firestore!.waitForPendingWrites().timeout(const Duration(seconds: 15));
        safety.pendingDocuments.clear();
      } catch (error) {
        _onCloudError(error);
        await safety.suspendUnconfirmed(_firestore!);
        _connectionChanged(false);
        return false;
      }
    }
    final before = _pendingItemCount;
    await _syncPendingOfflineData();
    return !safety.connectionBlocked && (!_hasPendingOfflineData || _pendingItemCount < before);
  }

  @visibleForTesting
  Future<void> connectForTesting(FirebaseFirestore firestore, {bool online = true}) async {
    if (!_testMode) throw StateError('Test only.');
    _firestore = firestore;
    _isOnline = online;
    _referenceCheckNeeded = false;
  }

  @visibleForTesting
  Future<void> flushForTesting() {
    if (!_testMode) throw StateError('Test only.');
    return _syncPendingOfflineData();
  }

  @visibleForTesting
  Future<bool> automaticAttemptForTesting() {
    if (!_testMode) throw StateError('Test only.');
    return _automaticSyncAttempt();
  }

  bool _initialized = false;
  Future<void>? _initializationFuture;
  bool _loading = false;

  FirebaseFirestore? _firestore;
  StreamSubscription? _firestoreProductsSub;
  StreamSubscription? _firestoreTransactionsSub;
  StreamSubscription? _firestoreDailyTransactionsSub;
  Timer? _salesDayTimer;
  DateTime? _salesDay;
  List<TransactionRecord> _recentTransactionsSnapshot = [];
  List<TransactionRecord> _dailyTransactionsSnapshot = [];
  StreamSubscription? _firestoreUsersSub;
  StreamSubscription? _firestoreCategoriesSub;
  StreamSubscription? _firestoreExpensesSub;
  bool _seedingProducts = false;
  final _writeGuard = FirestoreWriteGuard();
  Future<void>? _bootstrapFuture;
  final Map<String, Future<void>> _loginSyncs = {};

  Future<void> initialize() {
    if (_initialized) return _initializeDatabase();
    return _initializationFuture ??= _initializeDatabase().whenComplete(() => _initializationFuture = null);
  }

  Future<void> _initializeDatabase() async {
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
    _referenceCheckNeeded = prefs.getBool('firestore_reference_bootstrap_attempted_v1') != true;
    _pendingDeletes..clear()..addAll(
        (jsonDecode(prefs.getString('firestore_pending_deletes_v1') ?? '[]') as List).cast<String>());
    final metadata = jsonDecode(prefs.getString('firestore_pending_metadata_v1') ?? '{}') as Map;
    _pendingMetadata..clear()..addAll(metadata.map((key, value) => MapEntry(key as String, Map<String, dynamic>.from(value as Map))));
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
    _overlayPendingMetadata();
    await _persistCategories();

    _products.removeWhere((p) => _pendingDeletes.contains('products/${p.id}'));
    _users.removeWhere((u) => _pendingDeletes.contains('users/${u.id}'));
    _operationalExpenses.removeWhere((e) => _pendingDeletes.contains('operational_expenses/${e.id}'));
    _loading = false;
    if (_pendingDeletes.isNotEmpty) { await _persistUsers(); await _persistOperationalExpenses(); }
    await _persistLedger();
    _initialized = true;
    _notifyProducts();
    _notifyTransactions();
    _notifyUsers();
    _notifyCategories();
    _notifyOperationalExpenses();

    _setupFirestoreLiveSync();
    _startAutomaticSync();
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
      if (_pendingDeletes.contains('users/${def.id}')) continue;
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
    if (_testMode || _firestore != null) return;
    if (FirestoreSyncSafety.instance.connectionBlocked) { _isOnline = false; return; }
    try {
      _firestore = FirebaseFirestore.instance;

      // Products Sync (Cross-device product details + Base64/URL photos + Hiburan items)
      _firestoreProductsSub?.cancel();
      _firestoreProductsSub = _firestore!
          .collection('products')
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snapshot) async {
              await _transactionDeletion?.future;
              if (snapshot.docs.isNotEmpty) {
                final remoteMap = <String, Product>{};
                for (final doc in snapshot.docs) {
                  if (_pendingDeletes.contains('products/${doc.id}')) continue;
                  _acknowledgeRemote('products/${doc.id}', doc.metadata);
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

                _products
                  ..clear()
                  ..addAll(remoteMap.values);
                await _persistProducts();
                _notifyProducts();


              }
            },
            onError: (error) {
              _onCloudError(error);
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
              _recentTransactionsSnapshot = snapshot.docs.map(_readRemoteTransaction).toList();
              await _applySalesSnapshots();
            },
            onError: (error) {
              _onCloudError(error);
            },
          );

      _watchDailySales();
      _salesDayTimer?.cancel();
      _salesDayTimer = Timer.periodic(const Duration(minutes: 1), (_) => _watchDailySales());

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
                  if (_pendingDeletes.contains('operational_expenses/${doc.id}')) continue;
                  _acknowledgeRemote('operational_expenses/${doc.id}', doc.metadata);
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
              _onCloudError(error);
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
                    .map((doc) {
                      _acknowledgeRemote('users/${doc.id}', doc.metadata);
                      return UserProfile.fromMap(doc.data());
                    })
                    .where(
                      (u) =>
                          !legacyUsernames.contains(u.username.toLowerCase()) && !_pendingDeletes.contains('users/${u.id}'),
                    )
                    .toList();

                _users
                  ..clear()
                  ..addAll(remoteUsers);
                _overlayPendingMetadata();
                _ensureDefaultUsers();
                await _persistUsers();
                _notifyUsers();


              }
            },
            onError: (error) {
              _onCloudError(error);
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
              _acknowledgeRemote('meta/categories', snapshot.metadata);
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

                  }
                  _categories
                    ..clear()
                    ..addAll(merged.toList()..sort());
                  _overlayPendingMetadata();
                  await _persistCategories();
                  _notifyCategories();
                }

              }
            },
            onError: (error) {
              _onCloudError(error);
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

  Future<T> _cloudWrite<T>(Iterable<String> paths, Future<T> Function() send) async {
    try {
      // Timeout does not cancel/release the original guard reservation. A retry
      // cannot create another SDK write while the first is still pending.
      return await _writeGuard.run(paths, send).timeout(const Duration(seconds: 15), onTimeout: () {
        if (_firestore != null) {
          unawaited(FirestoreSyncSafety.instance.suspendUnconfirmed(_firestore!).catchError((Object _) {}));
        }
        _isOnline = false;
        _connectionController.add(false);
        throw StateError('Konfirmasi server tertunda. Data lokal tetap tersimpan.');
      });
    } on FirebaseException catch (error) {
      if (error.code == 'resource-exhausted' && _firestore != null) {
        await FirestoreSyncSafety.instance.suspendForQuota(_firestore!);
        _isOnline = false;
        _connectionController.add(false);
      }
      rethrow;
    } on StateError catch (error) {
      FirestoreSyncSafety.instance.report(error.message.toString());
      rethrow;
    }
  }

  void _onCloudError(Object error) {
    debugPrint('Firestore stream notice: $error');
    if (error is FirebaseException && error.code == 'resource-exhausted' && _firestore != null) {
      _isOnline = false;
      _connectionController.add(false);
      unawaited(FirestoreSyncSafety.instance.suspendForQuota(_firestore!).catchError((Object _) {}));
    }
  }

  Future<T> _cloudRead<T>(Future<T> Function() read) async {
    try {
      return await read().timeout(const Duration(seconds: 10));
    } catch (error) {
      _onCloudError(error);
      rethrow;
    }
  }

  void _overlayPendingMetadata() {
    for (final entry in _pendingMetadata.entries) {
      if (_pendingDeletes.contains(entry.key)) continue;
      if (entry.key.startsWith('users/')) {
        final user = UserProfile.fromMap(entry.value);
        final index = _users.indexWhere((u) => u.id == user.id);
        if (index < 0) { _users.add(user); } else { _users[index] = user; }
      } else if (entry.key == 'meta/categories') {
        _categories..clear()..addAll((entry.value['list'] as List).cast<String>());
      }
    }
  }

  Future<void> _queueMetadata(String path, Map<String, dynamic>? payload) {
    final operation = _metadataQueue.catchError((Object _) {}).then((_) async {
      final next = {..._pendingMetadata};
      if (payload == null) { next.remove(path); } else { next[path] = payload; }
      final prefs = await SecurePreferences.getInstance();
      if (!await prefs.setString('firestore_pending_metadata_v1', jsonEncode(next))) {
        throw StateError('Perubahan belum tersimpan di perangkat.');
      }
      _pendingMetadata..clear()..addAll(next);
    });
    _metadataQueue = operation;
    return operation;
  }

  Future<void> _syncPendingMetadata() async {
    if (_firestore == null || !_isOnline) return;
    for (final entry in _pendingMetadata.entries.take(20).toList()) {
      if (_pendingDeletes.contains(entry.key)) { await _queueMetadata(entry.key, null); continue; }
      try {
        await _cloudWrite([entry.key], () => _firestore!.runTransaction((tx) async {
          final ref = _firestore!.doc(entry.key);
          final remote = (await tx.get(ref)).data();
          if (remote != null && (entry.key.startsWith('users/')
              ? _sameUser(UserProfile.fromMap(remote), UserProfile.fromMap(entry.value))
              : jsonEncode(_canonicalJson(remote)) == jsonEncode(_canonicalJson(entry.value)))) {
            return;
          }
          tx.set(ref, entry.value, SetOptions(merge: true));
        }, maxAttempts: 2));
        // Serialize the comparison with local edits; a newer payload must survive.
        final operation = _metadataQueue.catchError((Object _) {}).then((_) async {
          if (jsonEncode(_pendingMetadata[entry.key]) != jsonEncode(entry.value)) return;
          final next = {..._pendingMetadata}..remove(entry.key);
          final prefs = await SecurePreferences.getInstance();
          if (!await prefs.setString('firestore_pending_metadata_v1', jsonEncode(next))) {
            throw StateError('Konfirmasi belum tersimpan.');
          }
          _pendingMetadata..clear()..addAll(next);
        });
        _metadataQueue = operation;
        await operation;
      } catch (error) { _onCloudError(error); break; }
    }
  }

  void _acknowledgeRemote(String path, SnapshotMetadata metadata) {
    if (!metadata.isFromCache && !metadata.hasPendingWrites) {
      FirestoreSyncSafety.instance.pendingDocuments.remove(path);
    }
  }

  TransactionRecord _readRemoteTransaction(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    _acknowledgeRemote('transactions/${doc.id}', doc.metadata);
    return TransactionRecord.fromMap(doc.data()).copyWith(isSynced: !doc.metadata.hasPendingWrites);
  }

  Future<void> _deleteCloudDocument(String path) =>
      _cloudWrite([path], () => _firestore!.doc(path).delete());

  Future<void> _updateDeleteQueue(String path, {required bool add}) {
    final operation = _deleteQueue.catchError((Object _) {}).then((_) async {
      final next = Set<String>.from(_pendingDeletes);
      if (add) { next.add(path); } else { next.remove(path); }
      final prefs = await SecurePreferences.getInstance();
      if (!await prefs.setString('firestore_pending_deletes_v1', jsonEncode(next.toList()))) {
        throw StateError('Antrean penghapusan belum tersimpan.');
      }
      _pendingDeletes..clear()..addAll(next);
    });
    _deleteQueue = operation;
    return operation;
  }

  Future<void> _flushPendingDeletes() => _deletingPending ??= _sendPendingDeletes()
      .whenComplete(() => _deletingPending = null);

  Future<void> _sendPendingDeletes() async {
    if (_firestore == null || !_isOnline) return;
    for (final path in _pendingDeletes.take(20).toList()) {
      try {
        final remote = await _cloudRead(() => _firestore!.doc(path).get(const GetOptions(source: Source.server)));
        if (remote.exists) {
          if (FirestoreSyncSafety.instance.pendingDocuments.contains(path)) continue;
          await _deleteCloudDocument(path);
        }
        await _updateDeleteQueue(path, add: false);
      } catch (error) {
        _onCloudError(error);
        break;
      }
    }
  }

  Future<void> _bootstrapReferenceData() {
    return _bootstrapFuture ??= _bootstrapOnce()
        .whenComplete(() => _bootstrapFuture = null);
  }

  Future<void> _bootstrapOnce() async {
    if (_firestore == null || !_isOnline) return;
    final prefs = await SecurePreferences.getInstance();
    const key = 'firestore_reference_bootstrap_attempted_v1';
    if (prefs.getBool(key) == true) { _referenceCheckNeeded = false; return; }
    // AutomaticSync reserves its persisted retry deadline before reaching here.
    final firestore = _firestore!;
    _seedingProducts = true;
    try {
      final products = await _cloudRead(() => firestore.collection('products').limit(1)
          .get(const GetOptions(source: Source.server)));
      final users = await _cloudRead(() => firestore.collection('users').limit(1)
          .get(const GetOptions(source: Source.server)));
      final categories = await _cloudRead(() => firestore.doc('meta/categories')
          .get(const GetOptions(source: Source.server)));
      final seeds = <String, Map<String, dynamic>>{};
      if (products.docs.isEmpty) {
        for (final p in _products) { seeds['products/${p.id}'] = p.copyWith(isSynced: true).toMap(); }
      }
      if (users.docs.isEmpty) {
        for (final u in _users) { seeds['users/${u.id}'] = u.toMap(); }
      }
      if (!categories.exists) seeds['meta/categories'] = {'list': _categories};
      for (var offset = 0; offset < seeds.length; offset += 100) {
        final chunk = seeds.entries.skip(offset).take(100).toList();
        await _cloudWrite(chunk.map((e) => e.key), () => firestore.runTransaction((tx) async {
          final absent = <String, Map<String, dynamic>>{};
          for (final entry in chunk) {
            if (!(await tx.get(firestore.doc(entry.key))).exists) absent[entry.key] = entry.value;
          }
          for (final entry in absent.entries) { tx.set(firestore.doc(entry.key), entry.value); }
        }, maxAttempts: 2));
      }
      if (!await prefs.setBool(key, true)) throw StateError('Inisialisasi belum tersimpan.');
      _referenceCheckNeeded = false;
    } catch (error) {
      debugPrint('Firestore reference initialization deferred: $error');
    } finally {
      _seedingProducts = false;
    }
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
    await _transactionDeletion?.future;
    await _flushPendingDeletes();
    await _syncPendingOfflineTransactions();
    await _syncPendingOfflineProducts();
    await _syncPendingOfflineExpenses();
    await _syncPendingMetadata();
    _connectionController.add(_isOnline);
  }

  bool get _hasPendingOfflineData => _pendingMetadata.isNotEmpty || _pendingDeletes.isNotEmpty || _products.any((p) => !p.isSynced) ||
      _transactions.any((t) => !t.isSynced) ||
      _operationalExpenses.any((e) => !e.isSynced);

  int get _pendingItemCount => _pendingMetadata.length + _pendingDeletes.length +
      _products.where((p) => !p.isSynced).length + _transactions.where((t) => !t.isSynced).length +
      _operationalExpenses.where((e) => !e.isSynced).length;

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
    if (_firestore == null || !_isOnline) return;
    if (_seedingProducts) return;
    final saleProducts = _transactions.where((tx) => !tx.isSynced).expand((tx) => tx.items.map((i) => i.product.id)).toSet();
    final unsynced = _products.where((p) => !p.isSynced && !saleProducts.contains(p.id) && !_activeProductWrites.containsKey(p.id)).take(20).toList();
    if (unsynced.isEmpty) return;

    try {
      for (var offset = 0; offset < unsynced.length && _isOnline; offset += 10) {
        final chunk = unsynced.skip(offset).take(10).toList();
        await _cloudWrite(chunk.map((p) => 'products/${p.id}'), () => _firestore!.runTransaction((tx) async {
          final changed = <Product>[];
          for (final product in chunk) {
            final data = (await tx.get(_firestore!.doc('products/${product.id}'))).data();
            if (data == null || !_sameProduct(product, Product.fromMap(data))) changed.add(product);
          }
          for (final product in changed) {
            tx.set(_firestore!.doc('products/${product.id}'), product.copyWith(isSynced: true).toMap(), SetOptions(merge: true));
          }
        }, maxAttempts: 2));
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
    if (_firestore == null || !_isOnline) return;
    final pending = _transactions.where((t) => !t.isSynced && !_activeTransactionWrites.containsKey(t.id)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final pendingTx in pending.take(20)) {
      if (!_isOnline) break;
      final ids = pendingTx.items.map((i) => i.product.id).toSet();
      if (!await _syncCheckout(pendingTx, _products.where((p) => ids.contains(p.id)).toList())) break;
    }
  }

  Future<void> _syncPendingOfflineExpenses() async {
    if (_firestore == null || !_isOnline) return;
    final unsynced = _operationalExpenses.where((e) => !e.isSynced && !_activeExpenseWrites.containsKey(e.id)).take(20).toList();
    if (unsynced.isEmpty) return;

    try {
      for (var offset = 0; offset < unsynced.length && _isOnline; offset += 100) {
        final chunk = unsynced.skip(offset).take(100).toList();
        await _cloudWrite(chunk.map((e) => 'operational_expenses/${e.id}'), () => _firestore!.runTransaction((tx) async {
          final changed = <OperationalExpense>[];
          for (final expense in chunk) {
            final data = (await tx.get(_firestore!.doc('operational_expenses/${expense.id}'))).data();
            if (data == null || !_sameExpense(expense, OperationalExpense.fromMap(data))) changed.add(expense);
          }
          for (final expense in changed) {
            tx.set(_firestore!.doc('operational_expenses/${expense.id}'), expense.copyWith(isSynced: true).toMap(), SetOptions(merge: true));
          }
        }, maxAttempts: 2));
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

  // Keep all sales for today and the barista's 24-hour correction window,
  // independently of the existing 100-record history subscription.
  void _watchDailySales() {
    final firestore = _firestore;
    if (firestore == null) return;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    if (_salesDay == day) return;
    _salesDay = day;
    _firestoreDailyTransactionsSub?.cancel();
    _dailyTransactionsSnapshot = [];
    _firestoreDailyTransactionsSub = firestore.collection('transactions')
        .where('createdAt', isGreaterThanOrEqualTo: DateTime(now.year, now.month, now.day - 1).toIso8601String())
        .where('createdAt', isLessThan: DateTime(now.year, now.month, now.day + 1).toIso8601String())
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) async {
          if (_salesDay != day) return;
          _dailyTransactionsSnapshot = snapshot.docs.map(_readRemoteTransaction).toList();
          await _applySalesSnapshots();
        }, onError: (Object error) {
          _onCloudError(error);
        });
    _notifyTransactions();
  }

  @visibleForTesting
  static List<TransactionRecord> mergeSalesSnapshots({
    required List<TransactionRecord> recent,
    required List<TransactionRecord> daily,
    required List<TransactionRecord> local,
    required DateTime retainSince,
  }) {
    final merged = <String, TransactionRecord>{};
    void merge(TransactionRecord tx) {
      final previous = merged[tx.id];
      if (previous == null || (tx.isDeleted && (!previous.isDeleted || tx.revision > previous.revision ||
          (tx.revision == previous.revision && tx.isSynced && !previous.isSynced))) ||
          (!previous.isDeleted && (tx.revision > previous.revision ||
          (tx.revision == previous.revision && (!previous.isVoided || tx.isVoided))))) {
        merged[tx.id] = tx;
      }
    }
    for (final tx in [...recent, ...daily]) {
      merge(tx);
    }
    for (final tx in local) {
      final remote = merged[tx.id];
      if (remote == null) {
        if (tx.isDeleted || !tx.isSynced || !tx.createdAt.isBefore(retainSince)) merge(tx);
      } else if (tx.isDeleted || tx.revision > remote.revision || (tx.isVoided && !remote.isVoided)) {
        merge(tx);
      }
    }
    return merged.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _applySalesSnapshots() async {
    await _transactionDeletion?.future;
    if (_recentTransactionsSnapshot.isEmpty && _dailyTransactionsSnapshot.isEmpty) {
      _notifyTransactions();
      return;
    }
    final now = DateTime.now();
    final merged = mergeSalesSnapshots(
      recent: _recentTransactionsSnapshot,
      daily: _dailyTransactionsSnapshot,
      local: _transactions,
      retainSince: DateTime(now.year, now.month, now.day - 1),
    );
    _transactions..clear()..addAll(merged);
    await _persistTransactions();
    _notifyTransactions();
  }

  List<Product> getProducts() => List.unmodifiable(_products);
  List<TransactionRecord> getTransactions() => _actor == null ? const [] : List.unmodifiable(
    _transactions.where((t) => !t.isDeleted && (_actor!.role.canViewFinancialReports || t.cashierId == _actor!.id))
      .map((t) => t.copyWith(items: t.items.map((i) => i.copyWith()).toList())));
  List<TransactionRecord> getDeletedTransactions() {
    _requireAccess((role) => role.canDeleteTransactions);
    return List.unmodifiable(_transactions.where((tx) => tx.isDeleted)
      .map((tx) => tx.copyWith(items: tx.items.map((item) => item.copyWith()).toList())));
  }
  bool isTransactionDeleted(String id) {
    final actor = _actor;
    final tx = _transactions.where((tx) => tx.id == id).firstOrNull;
    return actor != null && tx != null && tx.isDeleted && (actor.role.canViewFinancialReports || tx.cashierId == actor.id);
  }
  ({double totalAmount, int transactionCount}) getTodaySalesSummary() {
    _requireAccess((r) => true);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day + 1);
    var total = 0.0;
    var count = 0;
    for (final tx in _transactions) {
      if (!tx.isVoided && !tx.isDeleted && !tx.createdAt.isBefore(start) && tx.createdAt.isBefore(end)) {
        total += tx.totalAmount;
        count++;
      }
    }
    return (totalAmount: total, transactionCount: count);
  }
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
    await _queueMetadata('meta/categories', {'list': List<String>.of(_categories)});
    await _persistCategories();
    _notifyCategories();

    _requestAutoSync();
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
        final updatedProd = _products[i].copyWith(
          category: cleanNew,
          updatedAt: now,
          isSynced: false,
        );
        _products[i] = updatedProd;
        productsChanged = true;
      }
    }

    await _queueMetadata('meta/categories', {'list': List<String>.of(_categories)});
    await _persistCategories();
    if (productsChanged) {
      await _persistProducts();
      _notifyProducts();
    }
    _notifyCategories();

    _requestAutoSync();
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
        final updatedProd = _products[i].copyWith(
          category: fallbackCategory,
          updatedAt: now,
          isSynced: false,
        );
        _products[i] = updatedProd;
        productsChanged = true;
      }
    }

    await _queueMetadata('meta/categories', {'list': List<String>.of(_categories)});
    await _persistCategories();
    if (productsChanged) {
      await _persistProducts();
      _notifyProducts();
    }
    _notifyCategories();

    _requestAutoSync();
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
    if (_firestore != null && _isOnline) unawaited(_syncLoginTime(_users[index]));
  }

  Future<UserProfile> changeOwnPassword(String oldPassword, String newPassword) async {
    _requireAccess((role) => role.canChangeOwnPassword);
    final actor = _actor!;
    if (!await actor.verifyPasswordAsync(oldPassword)) { throw StateError('Password saat ini tidak valid.'); }
    if (oldPassword == newPassword) throw ArgumentError('Gunakan password baru yang berbeda.');
    final changed = await actor.withSecurePassword(newPassword);
    if (_actor?.id != actor.id || _actor?.passwordHash != actor.passwordHash || _actor?.role.canChangeOwnPassword != true) throw StateError('Sesi sudah berubah.');
    await _queueMetadata('users/${changed.id}', changed.toMap());
    _users[_users.indexWhere((u) => u.id == actor.id)] = changed;
    await _persistUsers();
    _notifyUsers();
    _requestAutoSync();
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
    if (existing != null && _sameUser(existing, user)) return null;
    await _queueMetadata('users/${user.id}', user.toMap());

    final index = _users.indexWhere((u) => u.id == user.id);
    if (index != -1) {
      _users[index] = user;
    } else {
      _users.add(user);
    }
    await _persistUsers();
    _notifyUsers();

    // A queued offline cloud write must not prevent local login/session saving.
    _requestAutoSync();
    return null;
  }

  Future<void> _syncLoginTime(UserProfile user) => _loginSyncs.putIfAbsent(user.id,
      () => _sendLoginTime(user).whenComplete(() => _loginSyncs.remove(user.id)));

  Future<void> _sendLoginTime(UserProfile user) async {
    try {
      final prefs = await SecurePreferences.getInstance();
      final key = 'firestore_last_login_attempt_${user.id}';
      final last = prefs.getInt(key) ?? 0;
      final now = DateTime.now();
      if (now.millisecondsSinceEpoch - last < const Duration(minutes: 15).inMilliseconds) return;
      await prefs.setInt(key, now.millisecondsSinceEpoch);
      await _cloudWrite(['users/${user.id}'], () => _firestore!.doc('users/${user.id}')
          .update({'lastLoginAt': user.lastLoginAt?.toIso8601String()}));
    } catch (error) {
      debugPrint('Firestore login timestamp deferred: $error');
    }
  }

  static bool _sameUser(UserProfile a, UserProfile b) {
    final left = a.toMap()..remove('lastLoginAt');
    final right = b.toMap()..remove('lastLoginAt');
    return jsonEncode(_canonicalJson(left)) == jsonEncode(_canonicalJson(right));
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

    await _updateDeleteQueue('users/$userId', add: true);
    await _queueMetadata('users/$userId', null);
    _users.removeWhere((u) => u.id == userId);
    await _persistUsers();
    _notifyUsers();

    _requestAutoSync();
    return true;
  }

  bool _savingCheckout = false;
  Future<TransactionRecord> processTransaction(TransactionRecord transaction) async {
    if (_transactionDeletion != null) throw StateError('Penghapusan transaksi sedang disimpan.');
    if (_savingCheckout) throw StateError('Pembayaran sedang disimpan.');
    _savingCheckout = true;
    try { return await _saveCheckout(transaction); }
    finally { _savingCheckout = false; }
  }

  Future<TransactionRecord> _saveCheckout(TransactionRecord transaction) async {
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
    final nextProducts = List<Product>.of(_products);
    for (final item in transaction.items) {
      final productIndex = _products.indexWhere((p) => p.id == item.product.id);
      if (productIndex != -1) {
        final current = nextProducts[productIndex];
        // Entertainment rental items (minStockThreshold == 0 && isEntertainment) keep service capacity high
        final newStock = current.isEntertainment && current.minStockThreshold == 0
            ? current.stock
            : (current.stock - item.quantity).clamp(0, 99999);

        final updatedProd = current.copyWith(
          stock: newStock,
          updatedAt: now,
          isSynced: false,
        );

        nextProducts[productIndex] = updatedProd;
        updatedProducts[updatedProd.id] = updatedProd;
      }
    }

    final finalTransaction = transaction.copyWith(isSynced: false);
    final nextBills = _openBills.where((b) => b.id != transaction.openBillId).toList();
    final prefs = await SecurePreferences.getInstance();
    if (!await prefs.setString('cached_ledger_v1', jsonEncode({
      'products': nextProducts.map((p) => p.toMap()).toList(),
      'transactions': [finalTransaction, ..._transactions].map((t) => t.toMap()).toList(),
      'openBills': nextBills.map((b) => b.toMap()).toList(),
    }))) {
      throw StateError('Pembayaran belum tersimpan di perangkat.');
    }
    // No cloud worker can observe this sale before the durable commit succeeds.
    _transactions.insert(0, finalTransaction);
    for (final entry in updatedProducts.entries) {
      final index = _products.indexWhere((p) => p.id == entry.key);
      if (index >= 0) _products[index] = entry.value;
    }
    if (transaction.openBillId != null) {
      _openBills.removeWhere((b) => b.id == transaction.openBillId);
      _openBillsController.add(getOpenBills());
    }

    _notifyProducts();
    _notifyTransactions();

    // Persist the sale locally before waiting for a server acknowledgement.
    if (_firestore != null && _isOnline) {
      _requestAutoSync();
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
        !['Cash', 'QRIS'].contains(transaction.paymentMethod) || transaction.isVoided || transaction.isDeleted ||
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

  @visibleForTesting
  static ({TransactionRecord sale, Map<String, Product> products, bool writeSale}) planCheckoutSync({
    required TransactionRecord local,
    required TransactionRecord? remote,
    required Map<String, Product> localProducts,
    required Map<String, Product> remoteProducts,
  }) {
    if (remote?.isDeleted == true) {
      return (sale: remote!.copyWith(isSynced: true), products: <String, Product>{}, writeSale: false);
    }
    if (local.isDeleted && remote != null) {
      final original = local.toMap()
        ..remove('isDeleted')..remove('deletedAt')..remove('deletedById')..remove('deletedByName')..remove('deletionReason')
        ..remove('isSynced');
      if (local.revision <= 1) { original.remove('revision'); } else { original['revision'] = local.revision - 1; }
      original['isVoided'] = remote.isVoided ? 1 : 0;
      final server = remote.toMap()..remove('isSynced');
      if (jsonEncode(_canonicalJson(original)) != jsonEncode(_canonicalJson(server))) {
        throw StateError('Transaksi berubah di perangkat lain. Penghapusan menunggu pemeriksaan; data server tidak diubah.');
      }
    }
    if (remote != null) {
      if (remote.revision > local.revision || (remote.isVoided && !local.isVoided)) {
        return (sale: remote.copyWith(isSynced: true), products: <String, Product>{}, writeSale: false);
      }
      if (!local.isDeleted && !_sameTransaction(remote, local.copyWith(isVoided: remote.isVoided))) {
        throw StateError('Transaksi berbeda dengan data server. Data lokal dipertahankan.');
      }
      if (!local.isDeleted && remote.isVoided == local.isVoided) {
        return (sale: remote.copyWith(isSynced: true), products: <String, Product>{}, writeSale: false);
      }
    }
    final quantities = <String, int>{};
    for (final item in local.items) {
      quantities[item.product.id] = (quantities[item.product.id] ?? 0) + item.quantity;
    }
    final updates = <String, Product>{};
    final factor = local.isDeleted ? (remote != null && !remote.isVoided ? 1 : 0)
        : remote == null ? (local.isVoided ? 0 : -1) : 1;
    if (factor != 0) {
      for (final entry in quantities.entries) {
        final cached = localProducts[entry.key];
        if (cached == null) throw StateError('Menu transaksi belum tersedia. Data lokal dipertahankan.');
        if (local.isDeleted && remoteProducts[entry.key] == null && !(cached.isEntertainment && cached.minStockThreshold == 0)) {
          throw StateError('Stok menu server tidak tersedia. Penghapusan menunggu pemeriksaan.');
        }
        final product = remoteProducts[entry.key] ?? cached.copyWith(
          stock: local.items.firstWhere((i) => i.product.id == entry.key).product.stock);
        if (product.isEntertainment && product.minStockThreshold == 0) continue;
        final stock = product.stock + factor * entry.value;
        if (stock < 0 || stock > 99999) throw StateError('Stok server tidak mencukupi. Transaksi lokal menunggu pemeriksaan.');
        updates[entry.key] = product.copyWith(stock: stock, updatedAt: local.deletedAt ?? local.createdAt, isSynced: true);
      }
    }
    return (sale: local.copyWith(isSynced: true), products: updates, writeSale: true);
  }

  Future<bool> _syncCheckout(TransactionRecord sale, List<Product> products) async {
    await _transactionDeletion?.future;
    _trackWrites(_activeTransactionWrites, [sale.id], 1);
    _trackWrites(_activeProductWrites, products.map((p) => p.id), 1);
    try {
      final firestore = _firestore!;
      final result = await _cloudWrite(['transactions/${sale.id}', ...products.map((p) => 'products/${p.id}')],
          () => firestore.runTransaction((operation) async {
        final ref = firestore.doc('transactions/${sale.id}');
        final data = (await operation.get(ref)).data();
        final remoteProducts = <String, Product>{};
        // Read every stock value before writing. The sale ID and inventory
        // changes commit together, so a retry cannot deduct inventory twice.
        for (final product in products) {
          final data = (await operation.get(firestore.doc('products/${product.id}'))).data();
          if (data != null) remoteProducts[product.id] = Product.fromMap(data);
        }
        final plan = planCheckoutSync(local: sale,
          remote: data == null ? null : TransactionRecord.fromMap(data),
          localProducts: {for (final p in products) p.id: p}, remoteProducts: remoteProducts);
        for (final product in plan.products.values) {
          operation.set(firestore.doc('products/${product.id}'), product.toMap());
        }
        if (plan.writeSale) operation.set(ref, plan.sale.toMap());
        return (sale: plan.sale, products: {...remoteProducts, ...plan.products});
      }, maxAttempts: 2));
      final index = _transactions.indexWhere((t) => t.id == sale.id);
      if (index >= 0 && _transactions[index].revision == sale.revision && _transactions[index].isVoided == sale.isVoided &&
          _transactions[index].isDeleted == sale.isDeleted) {
        _transactions[index] = result.sale;
      }
      for (final entry in result.products.entries) {
        final index = _products.indexWhere((p) => p.id == entry.key);
        if (index < 0) continue;
        final current = _products[index];
        final before = products.where((p) => p.id == entry.key).first;
        // Keep edits made while the cloud operation was awaiting confirmation.
        if (!_sameProduct(current, before)) continue;
        final outstanding = _transactions.where((tx) => !tx.isSynced && tx.id != sale.id).toList();
        // A pending deletion can refer to a sale never committed on the server.
        // Preserve local stock until its atomic sale/stock reconciliation finishes.
        if (outstanding.any((tx) => tx.isDeleted && tx.items.any((item) => item.product.id == entry.key))) continue;
        var stock = entry.value.stock;
        for (final tx in outstanding) {
          for (final item in tx.items.where((i) => i.product.id == entry.key)) {
            if (!(current.isEntertainment && current.minStockThreshold == 0)) {
              stock += (tx.isVoided ? 1 : -1) * item.quantity;
            }
          }
        }
        final left = current.toMap()..remove('stock')..remove('updatedAt')..remove('isSynced');
        final right = entry.value.toMap()..remove('stock')..remove('updatedAt')..remove('isSynced');
        final metadataMatches = jsonEncode(_canonicalJson(left)) == jsonEncode(_canonicalJson(right));
        final stillPending = outstanding.any((tx) => tx.items.any((i) => i.product.id == entry.key));
        _products[index] = current.copyWith(stock: stock.clamp(0, 99999), isSynced: metadataMatches && !stillPending);
      }
      await _persistLedger();
      _notifyProducts();
      _notifyTransactions();
      return true;
    } catch (error) {
      _onCloudError(error);
      if (!FirestoreSyncSafety.instance.connectionBlocked) {
        FirestoreSyncSafety.instance.report('Sinkronisasi transaksi tertunda. Data lokal tetap tersimpan.');
      }
      return false;
    } finally {
      _trackWrites(_activeTransactionWrites, [sale.id], -1);
      _trackWrites(_activeProductWrites, products.map((p) => p.id), -1);
    }
  }

  /// Voids a transaction and restores deducted inventory stock
  bool _correctingTransaction = false;
  bool _voidingTransaction = false;

  Future<TransactionRecord> correctTransaction({
    required String transactionId,
    required int expectedRevision,
    required List<CartItem> items,
    required double amountPaid,
    required String reason,
  }) async {
    _requireAccess((r) => r.canCorrectTransactions);
    if (_transactionDeletion != null) throw StateError('Penghapusan transaksi sedang disimpan.');
    if (_correctingTransaction) throw StateError('Koreksi transaksi sedang diproses.');
    _correctingTransaction = true;
    try {
      final actor = _actor!;
      final old = _transactions.where((t) => t.id == transactionId).firstOrNull;
      if (old == null) {
        throw StateError('Transaksi tidak ditemukan atau akses ditolak.');
      }
      if (!old.isVoided && !old.canBeCorrectedBy(role: actor.role, userId: actor.id)) {
        throw StateError('Transaksi tidak dapat dikoreksi.');
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
          throw StateError('Tunggu sinkronisasi otomatis transaksi dan stok selesai sebelum koreksi.');
        }
        final firestore = _firestore!;
        await _cloudWrite(['transactions/${old.id}', ...updates.keys.map((id) => 'products/$id')],
            () => firestore.runTransaction((transaction) async {
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
          if (!remote.canBeCorrectedBy(role: actor.role, userId: actor.id)) {
            throw StateError('Transaksi tidak dapat dikoreksi.');
          }
          for (final entry in updates.entries) {
            transaction.update(refs[entry.key]!, {'stock': entry.value.stock, 'updatedAt': now.toIso8601String(), 'isSynced': 1});
          }
          transaction.set(txRef, corrected.toMap());
        }, maxAttempts: 2));
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

  Future<TransactionRecord> deleteTransaction({
    required String transactionId, required int expectedRevision, required String reason,
  }) async {
    _requireAccess((role) => role.canDeleteTransactions);
    if (_transactionDeletion != null || _savingCheckout || _correctingTransaction || _voidingTransaction || _pendingSyncFuture != null) {
      throw StateError('Transaksi sedang diproses atau disinkronkan. Tunggu sebentar lalu coba lagi.');
    }
    final actor = _actor!;
    final index = _transactions.indexWhere((tx) => tx.id == transactionId);
    if (index < 0) throw StateError('Transaksi tidak ditemukan.');
    final old = _transactions[index];
    if (old.isDeleted) throw StateError('Transaksi sudah dihapus.');
    if (old.revision != expectedRevision) throw StateError('Transaksi sudah berubah. Buka kembali detail sebelum menghapus.');
    final cleanReason = reason.trim();
    if (cleanReason.length < 3 || cleanReason.length > 200) throw ArgumentError('Isi alasan penghapusan, 3 sampai 200 karakter.');
    final barrier = Completer<void>();
    _transactionDeletion = barrier;
    try {
      final now = DateTime.now();
      final products = List<Product>.of(_products);
      final quantities = <String, int>{};
      if (!old.isVoided) {
        for (final item in old.items) {
          if (item.quantity < 1) throw StateError('Jumlah item transaksi tidak valid.');
          quantities[item.product.id] = (quantities[item.product.id] ?? 0) + item.quantity;
        }
      }
      for (final entry in quantities.entries) {
        final productIndex = products.indexWhere((product) => product.id == entry.key);
        if (productIndex < 0) throw StateError('Menu transaksi tidak tersedia. Stok belum dapat dikembalikan.');
        final product = products[productIndex];
        if (product.isEntertainment && product.minStockThreshold == 0) continue;
        final stock = product.stock + entry.value;
        if (stock > 99999) throw StateError('Pengembalian melebihi batas stok. Periksa inventori terlebih dahulu.');
        products[productIndex] = product.copyWith(stock: stock, updatedAt: now, isSynced: false);
      }
      final deleted = old.copyWith(isDeleted: true, isVoided: true, isSynced: false, revision: old.revision + 1,
        deletedAt: now, deletedById: actor.id, deletedByName: actor.displayName, deletionReason: cleanReason);
      final sales = List<TransactionRecord>.of(_transactions);
      sales[index] = deleted;
      final prefs = await SecurePreferences.getInstance();
      _requireAccess((role) => role.canDeleteTransactions);
      if (_actor!.id != actor.id) throw StateError('Sesi pengguna sudah berubah.');
      if (!await prefs.setString('cached_ledger_v1', jsonEncode({
        'products': products.map((product) => product.toMap()).toList(),
        'transactions': sales.map((tx) => tx.toMap()).toList(),
        'openBills': _openBills.map((bill) => bill.toMap()).toList(),
      }))) {
        throw StateError('Penghapusan belum tersimpan di perangkat.');
      }
      _products..clear()..addAll(products);
      _transactions..clear()..addAll(sales);
      _notifyProducts();
      _notifyTransactions();
      _requestAutoSync();
      return deleted.copyWith(items: deleted.items.map((item) => item.copyWith()).toList());
    } finally {
      _transactionDeletion = null;
      barrier.complete();
    }
  }

  Future<bool> voidTransaction(String transactionId) async {
    if (_transactionDeletion != null) throw StateError('Penghapusan transaksi sedang disimpan.');
    _requireAccess((r) => r.canVoidTransactions);
    if (_correctingTransaction) throw StateError('Koreksi transaksi sedang diproses.');
    if (_voidingTransaction) throw StateError('Pembatalan transaksi sedang disimpan.');
    _voidingTransaction = true;
    try {
    final index = _transactions.indexWhere((t) => t.id == transactionId);
    if (index < 0 || _transactions[index].isVoided) return false;
    final transaction = _transactions[index];
    final updates = <String, Product>{};
    final nextProducts = List<Product>.of(_products);
    final now = DateTime.now();
    for (final item in transaction.items) {
      final productIndex = _products.indexWhere((p) => p.id == item.product.id);
      if (productIndex < 0) continue;
      final product = nextProducts[productIndex];
      final stock = product.isEntertainment && product.minStockThreshold == 0
          ? product.stock : (product.stock + item.quantity).clamp(0, 99999);
      final updated = product.copyWith(stock: stock, updatedAt: now, isSynced: false);
      nextProducts[productIndex] = updated;
      updates[updated.id] = updated;
    }
    final voided = transaction.copyWith(isVoided: true, isSynced: false);
    final nextTransactions = List<TransactionRecord>.of(_transactions);
    nextTransactions[index] = voided;
    final prefs = await SecurePreferences.getInstance();
    if (!await prefs.setString('cached_ledger_v1', jsonEncode({
      'products': nextProducts.map((p) => p.toMap()).toList(),
      'transactions': nextTransactions.map((t) => t.toMap()).toList(),
      'openBills': _openBills.map((b) => b.toMap()).toList(),
    }))) {
      throw StateError('Pembatalan belum tersimpan di perangkat.');
    }
    _transactions[index] = voided;
    for (final entry in updates.entries) {
      final current = _products.indexWhere((p) => p.id == entry.key);
      if (current >= 0) _products[current] = entry.value;
    }
    _notifyProducts();
    _notifyTransactions();
    if (_firestore != null && _isOnline) _requestAutoSync();
    return true;
    } finally { _voidingTransaction = false; }
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
        _requestAutoSync();
      }
    });
  }

  Future<void> addOperationalExpenses(List<OperationalExpense> expenses) {
    final input = List<OperationalExpense>.of(expenses);
    return _enqueueBatchInsert(() async {
      _requireAccess((r) => r.canManageOperationalExpenses);
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
      _requireAccess((r) => r.canManageOperationalExpenses);
      final next = [..._operationalExpenses, ...saved]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final persisted = await prefs.setString('cached_operational_expenses',
          jsonEncode(next.map((e) => e.toMap()).toList()));
      if (!persisted) throw StateError('Biaya belum berhasil disimpan di perangkat.');
      _operationalExpenses.addAll(saved);
      _sortOperationalExpenses();
      _notifyOperationalExpenses();
      if (_firestore != null && _isOnline) {
        _requestAutoSync();
      }
    });
  }

  Future<void> _saveProductLocally(Product product, {bool insert = false}) async {
    final next = List<Product>.of(_products);
    final index = next.indexWhere((p) => p.id == product.id);
    if (insert) { next.add(product); } else if (index >= 0) { next[index] = product; }
    final prefs = await SecurePreferences.getInstance();
    if (!await prefs.setString('cached_ledger_v1', jsonEncode({
      'products': next.map((p) => p.toMap()).toList(),
      'transactions': _transactions.map((t) => t.toMap()).toList(),
      'openBills': _openBills.map((b) => b.toMap()).toList(),
    }))) {
      throw StateError('Menu belum tersimpan di perangkat.');
    }
    final current = _products.indexWhere((p) => p.id == product.id);
    if (current < 0) { _products.add(product); } else { _products[current] = product; }
    _notifyProducts();
    _requestAutoSync();
  }

  Future<void> _saveExpenseLocally(OperationalExpense expense, {bool insert = false}) async {
    final next = List<OperationalExpense>.of(_operationalExpenses);
    final index = next.indexWhere((e) => e.id == expense.id);
    if (insert) { next.insert(0, expense); } else if (index >= 0) { next[index] = expense; }
    final prefs = await SecurePreferences.getInstance();
    if (!await prefs.setString('cached_operational_expenses', jsonEncode(next.map((e) => e.toMap()).toList()))) {
      throw StateError('Biaya belum tersimpan di perangkat.');
    }
    final current = _operationalExpenses.indexWhere((e) => e.id == expense.id);
    if (current < 0) { _operationalExpenses.add(expense); } else { _operationalExpenses[current] = expense; }
    _sortOperationalExpenses();
    _notifyOperationalExpenses();
    _requestAutoSync();
  }

  Future<void> addProduct(Product product) async {
    _requireAccess((r) => r.canEditProducts);
    _validateProduct(product);
    if (_products.any((p) => p.id == product.id)) throw StateError('ID produk sudah digunakan.');
    final stamped = product.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );


    await _saveProductLocally(stamped, insert: true);
  }

  Future<void> updateProduct(Product product) async {
    _requireAccess((r) => r.canEditProducts);
    _validateProduct(product);
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index == -1) return;
    final currentValues = _products[index].toMap()..remove('isSynced')..remove('updatedAt');
    final nextValues = product.toMap()..remove('isSynced')..remove('updatedAt');
    if (jsonEncode(_canonicalJson(currentValues)) == jsonEncode(_canonicalJson(nextValues))) return;

    final stamped = product.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );


    await _saveProductLocally(stamped);
  }

  Future<bool> deleteProduct(String productId) async {
    _requireAccess((r) => r.canEditProducts);
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return false;

    await _updateDeleteQueue('products/$productId', add: true);
    _products.removeWhere((p) => p.id == productId);
    await _persistProducts();
    _notifyProducts();

    _requestAutoSync();
    return true;
  }

  Future<void> adjustStock(String productId, int newStock) async {
    _requireAccess((r) => r.canAdjustStock);
    if (newStock < 0 || newStock > 99999) throw ArgumentError('Stok tidak valid.');
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return;
    if (_products[index].stock == newStock) return;

    final updated = _products[index].copyWith(
      stock: newStock.clamp(0, 99999),
      updatedAt: DateTime.now(),
      isSynced: false,
    );


    await _saveProductLocally(updated);
  }

  // Operational Expenses CRUD (Listrik, Air, Kantong Plastik, Sedotan, ATK, dll)
  Future<OperationalExpense> addOperationalExpense(
    OperationalExpense expense,
  ) async {
    _requireAccess((r) => r.canManageOperationalExpenses);
    if (!expense.amount.isFinite || expense.amount <= 0) throw ArgumentError('Nominal biaya tidak valid.');

    final saved = expense.copyWith(isSynced: false);
    if (_operationalExpenses.any((e) => e.id == saved.id)) throw StateError('ID biaya sudah digunakan.');
    await _saveExpenseLocally(saved, insert: true);
    return saved;
  }

  Future<OperationalExpense?> updateOperationalExpense(
    OperationalExpense expense,
  ) async {
    _requireAccess((r) => r.canManageOperationalExpenses);
    if (!expense.amount.isFinite || expense.amount <= 0) throw ArgumentError('Nominal biaya tidak valid.');
    final index = _operationalExpenses.indexWhere((e) => e.id == expense.id);
    if (index == -1) return null;
    if (_sameExpense(_operationalExpenses[index], expense)) return _operationalExpenses[index];


    final saved = expense.copyWith(isSynced: false);
    await _saveExpenseLocally(saved);
    return saved;
  }

  Future<bool> deleteOperationalExpense(String expenseId) async {
    _requireAccess((r) => r.canManageOperationalExpenses);
    final index = _operationalExpenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) return false;

    await _updateDeleteQueue('operational_expenses/$expenseId', add: true);
    _operationalExpenses.removeWhere((e) => e.id == expenseId);
    await _persistOperationalExpenses();
    _notifyOperationalExpenses();

    _requestAutoSync();
    return true;
  }

  void _validateProduct(Product product) {
    if (product.id.isEmpty || product.id.contains('/') || product.name.trim().isEmpty ||
        !product.sellPrice.isFinite || product.sellPrice < 0 || !product.baseCost.isFinite ||
        product.baseCost < 0 || product.stock < 0 || product.stock > 99999 || product.minStockThreshold < 0) {
      throw ArgumentError('Data produk tidak valid.');
    }
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
      if (remote == null || !_sameUser(remote, user)) {
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

  Future<void> _persistLedger({List<OpenBill>? openBills}) async {
    if (_loading) return;
    final payload = jsonEncode({
      'products': _products.map((p) => p.toMap()).toList(),
      'transactions': _transactions.map((t) => t.toMap()).toList(),
      'openBills': (openBills ?? _openBills).map((b) => b.toMap()).toList(),
    });
    final prefs = await SecurePreferences.getInstance();
    if (!await prefs.setString('cached_ledger_v1', payload)) throw StateError('Data belum tersimpan di perangkat.');
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
    dispose();
    _firestore = null;
    _isOnline = false;
    _automaticSync = null;
    _salesDay = null;
    _pendingSyncFuture = null;
    _metadataQueue = Future.value();
    _batchInsertQueue = Future.value();
    _deleteQueue = Future.value();
    _deletingPending = null;
    _recentTransactionsSnapshot = [];
    _dailyTransactionsSnapshot = [];
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
    _automaticSync?.dispose();
    _networkSub?.cancel();
    _firestoreProductsSub?.cancel();
    _firestoreTransactionsSub?.cancel();
    _firestoreDailyTransactionsSub?.cancel();
    _salesDayTimer?.cancel();
    _firestoreUsersSub?.cancel();
    _firestoreCategoriesSub?.cancel();
    _firestoreExpensesSub?.cancel();
  }
}
