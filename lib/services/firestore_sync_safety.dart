import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'secure_preferences.dart';

/// Runs before any Firestore consumer, so an old SDK queue cannot replay first.
class FirestoreSyncSafety extends ChangeNotifier {
  static final instance = FirestoreSyncSafety();
  static const channel = MethodChannel('com.kafekita.pos/firestore_safety');
  String? notice;
  bool connectionBlocked = false;
  final Set<String> pendingDocuments = {};
  Future<void>? _initializing;
  Future<bool>? _resuming;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final prefs = await SecurePreferences.getInstance();
      final until = prefs.getInt('firestore_blocked_until') ?? 0;
      if (until > DateTime.now().millisecondsSinceEpoch) {
        connectionBlocked = true;
        notice =
            'Sinkronisasi ditahan sementara untuk melindungi kuota. Data lokal tetap tersedia.';
        return;
      }
      connectionBlocked = false;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await protectQueue(
          inspect: () async => Map<String, dynamic>.from(await channel
                  .invokeMapMethod<String, dynamic>('inspectQueue',
                      {'projectId': Firebase.app().options.projectId}) ??
              {}),
          backup: (pendingCount) => channel.invokeMethod<String>(
              'backupQueue', {
            'projectId': Firebase.app().options.projectId,
            'expectedBatches': pendingCount
          }),
          clear: () => FirebaseFirestore.instance.clearPersistence(),
        );
      }
    } catch (_) {
      connectionBlocked = true;
      notice =
          'Sinkronisasi ditahan: antrean perlu diperiksa. Data lokal tetap tersedia.';
    } finally {
      notifyListeners();
    }
  }

  @visibleForTesting
  Future<void> protectQueue({
    required Future<Map<String, dynamic>> Function() inspect,
    required Future<String?> Function(int) backup,
    required Future<void> Function() clear,
  }) async {
    try {
      final prefs = await SecurePreferences.getInstance();
      final originalLedger = prefs.getString('cached_ledger_v1');
      final report = await inspect();
      if (report['inspected'] != true) {
        throw StateError('Antrean belum dapat diperiksa.');
      }
      final count = report['pendingBatches'] as int? ?? 0;
      pendingDocuments.addAll(
          Map<String, dynamic>.from(report['documents'] as Map? ?? {}).keys);
      if (count >= 100) {
        if (report['accountsOnly'] != true) {
          throw StateError(
              'Antrean besar memerlukan pemeriksaan agar transaksi tetap aman.');
        }
        final cachedSales = (report['cachedTransactionIds'] as List? ?? [])
            .cast<String>()
            .toSet();
        final savedSales = originalLedger == null
            ? jsonDecode(prefs.getString('cached_transactions') ?? '[]') as List
            : (jsonDecode(originalLedger)
                as Map<String, dynamic>)['transactions'] as List;
        final savedIds =
            savedSales.map((entry) => (entry as Map)['id']).toSet();
        if (!savedIds.containsAll(cachedSales)) {
          throw StateError(
              'Riwayat perangkat perlu dicadangkan sebelum pemulihan.');
        }
        // The native backup includes every queued write and encrypted local data.
        // Quarantine old account writes; never replay old password values blindly.
        final location = await backup(count);
        if (location == null || location.isEmpty) {
          throw StateError('Cadangan antrean belum tersimpan.');
        }
        await prefs.setString('firestore_recovery_backup', location);
        await prefs.setInt('firestore_recovery_quarantined_batches', count);
        await clear();
        if (prefs.getString('cached_ledger_v1') != originalLedger) {
          throw StateError('Data lokal berubah selama pemulihan.');
        }
        pendingDocuments.clear();
        await prefs.setBool('firestore_recovery_completed', true);
        notice =
            'Antrean akun lama telah dikarantina dan dicadangkan. Data penjualan lokal dipertahankan.';
        debugPrint(
            'Firestore safety: quarantined $count account batches; backup=$location');
        if (originalLedger != null) {
          final ledger = jsonDecode(originalLedger) as Map<String, dynamic>;
          debugPrint(
              'Firestore safety: local ledger preserved; transactions=${(ledger['transactions'] as List? ?? []).length}; openBills=${(ledger['openBills'] as List? ?? []).length}; sha256=${sha256.convert(utf8.encode(originalLedger))}');
        }
      }
    } catch (_) {
      connectionBlocked = true;
      notice =
          'Sinkronisasi ditahan: antrean perlu diperiksa. Data lokal tetap tersedia.';
    } finally {
      notifyListeners();
    }
  }

  Future<void> _suspensions = Future.value();

  Future<void> suspendForQuota(FirebaseFirestore firestore) => _suspend(firestore,
      const Duration(hours: 1),
      'Kuota Firebase tercapai. Sinkronisasi dihentikan sementara; data lokal tetap tersimpan.');

  Future<void> suspendUnconfirmed(FirebaseFirestore firestore) => _suspend(firestore,
      const Duration(minutes: 5),
      'Server belum mengonfirmasi data. Sinkronisasi ditahan sementara; data lokal tetap tersimpan.');

  Future<void> _suspend(FirebaseFirestore firestore, Duration delay, String message) {
    connectionBlocked = true;
    final operation = _suspensions.catchError((Object _) {}).then((_) async {
      try {
        final prefs = await SecurePreferences.getInstance();
        final deadline = DateTime.now().add(delay).millisecondsSinceEpoch;
        // A timeout arriving after a quota error must never shorten its cooldown.
        if (deadline >= (prefs.getInt('firestore_blocked_until') ?? 0)) {
          notice = message;
          await prefs.setInt('firestore_blocked_until', deadline);
        }
      } finally {
        notifyListeners();
        // Stop SDK retries even when persisting the cooldown fails.
        await firestore.disableNetwork();
      }
    });
    _suspensions = operation;
    return operation;
  }

  void report(String message) {
    notice = message;
    notifyListeners();
  }

  Future<bool> resumeIfAllowed(FirebaseFirestore? firestore) =>
      _resuming ??= _resume(firestore).whenComplete(() => _resuming = null);

  Future<bool> _resume(FirebaseFirestore? firestore) async {
    final prefs = await SecurePreferences.getInstance();
    if ((prefs.getInt('firestore_blocked_until') ?? 0) >
        DateTime.now().millisecondsSinceEpoch) {
      return false;
    }
    if (firestore == null) {
      await _initialize();
      return !connectionBlocked;
    }
    try {
      await firestore.enableNetwork();
      await firestore
          .waitForPendingWrites()
          .timeout(const Duration(seconds: 15));
      await prefs.remove('firestore_blocked_until');
      connectionBlocked = false;
      notice = null;
      notifyListeners();
      return true;
    } catch (_) {
      await suspendUnconfirmed(firestore);
      return false;
    }
  }
}

/// Per-device limits are a circuit breaker, not a substitute for server quotas.
/// Reservations persist before sending; overlapping/retried calls cannot bypass them.
class FirestoreWriteLimit extends StateError {
  FirestoreWriteLimit(super.message);
}

class FirestoreWriteGuard {
  static const dailyLimit = 5000;
  static const minuteLimit = 200;
  static const documentMinuteLimit = 20;
  final DateTime Function() now;
  final Future<SecurePreferences> Function() preferences;
  static final Set<String> _inFlight = {};
  static Future<void> _reservations = Future.value();

  FirestoreWriteGuard(
      {DateTime Function()? now,
      Future<SecurePreferences> Function()? preferences})
      : now = now ?? DateTime.now,
        preferences = preferences ?? SecurePreferences.getInstance;

  Future<T> run<T>(
      Iterable<String> documents, Future<T> Function() send) async {
    final paths = documents.toSet();
    if (paths.isEmpty ||
        paths.any((p) => !RegExp(r'^[^/]+/[^/]+$').hasMatch(p))) {
      throw ArgumentError('Daftar dokumen sinkronisasi tidak valid.');
    }
    await _reserve(paths);
    try {
      return await send();
    } finally {
      _inFlight.removeAll(paths);
    }
  }

  Future<void> _reserve(Set<String> paths) {
    final attempt = _reservations.catchError((Object _) {}).then((_) async {
      final time = now();
      final prefs = await preferences();
      if ((prefs.getInt('firestore_blocked_until') ?? 0) >
              time.millisecondsSinceEpoch ||
          FirestoreSyncSafety.instance.connectionBlocked) {
        throw FirestoreWriteLimit(
            'Sinkronisasi ditahan untuk melindungi kuota. Data lokal dipertahankan.');
      }
      if (paths.any((p) =>
          _inFlight.contains(p) ||
          FirestoreSyncSafety.instance.pendingDocuments.contains(p))) {
        throw StateError('Dokumen masih menunggu konfirmasi server.');
      }
      final raw = prefs.getString('firestore_write_budget_v1');
      final budget = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final recent = (budget['recent'] as List? ?? [])
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .where((entry) =>
              time.millisecondsSinceEpoch - (entry['at'] as int) <
              const Duration(minutes: 1).inMilliseconds)
          .toList();
      if (recent.fold<int>(
                      0, (total, e) => total + (e['paths'] as List).length) +
                  paths.length >
              minuteLimit ||
          paths.any((p) =>
              recent.where((e) => (e['paths'] as List).contains(p)).length >=
              documentMinuteLimit)) {
        throw FirestoreWriteLimit(
            'Laju sinkronisasi dibatasi. Data lokal tetap tersimpan; coba lagi nanti.');
      }
      final start = budget['start'] as int?;
      var count = budget['count'] as int? ?? 0;
      var window =
          start == null ? time : DateTime.fromMillisecondsSinceEpoch(start);
      if (time.difference(window) >= const Duration(hours: 24)) {
        window = time;
        count = 0;
      }
      if (count < 0 ||
          time.isBefore(window) ||
          count + paths.length > dailyLimit) {
        throw FirestoreWriteLimit(
            'Batas aman sinkronisasi perangkat tercapai. Data lokal dipertahankan.');
      }
      final saved = await prefs.setString(
          'firestore_write_budget_v1',
          jsonEncode({
            'start': window.millisecondsSinceEpoch,
            'count': count + paths.length,
            'recent': [
              ...recent,
              {'at': time.millisecondsSinceEpoch, 'paths': paths.toList()}
            ]
          }));
      if (!saved) throw StateError('Batas sinkronisasi belum tersimpan.');
      _inFlight.addAll(paths);
    });
    _reservations = attempt;
    return attempt;
  }
}
