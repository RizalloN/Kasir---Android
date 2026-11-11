import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'firestore_sync_safety.dart';
import 'secure_preferences.dart';

/// Public release metadata only. Never use feature switches as authorization.
class AppRelease {
  final int versionCode;
  final String versionName;
  final String notes;
  final Uri? downloadUrl;
  final Map<String, bool> features;

  const AppRelease({
    this.versionCode = 0,
    this.versionName = '',
    this.notes = '',
    this.downloadUrl,
    this.features = const {},
  });

  factory AppRelease.fromMap(Map<String, dynamic> data) {
    final rawCode = data['versionCode'];
    if (rawCode != null && (rawCode is! int || rawCode < 1)) {
      throw const FormatException('versionCode harus bilangan bulat positif.');
    }
    final rawFeatures = data['features'];
    if (rawFeatures != null && rawFeatures is! Map) {
      throw const FormatException('features harus berupa map boolean.');
    }
    final features = <String, bool>{};
    if (rawFeatures is Map) {
      for (final entry in rawFeatures.entries) {
        if (entry.key is! String || entry.value is! bool) {
          throw const FormatException('Nilai fitur harus true atau false.');
        }
        features[entry.key as String] = entry.value as bool;
      }
    }
    final rawUrl = data['downloadUrl'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl.trim()) : null;
    final safeUrl = url != null &&
            url.scheme == 'https' &&
            url.host.isNotEmpty &&
            url.userInfo.isEmpty &&
            !url.hasFragment
        ? url
        : null;
    if (rawUrl != null && safeUrl == null) {
      throw const FormatException('downloadUrl harus URL HTTPS yang valid.');
    }
    return AppRelease(
      versionCode: rawCode as int? ?? 0,
      versionName:
          data['versionName'] is String ? data['versionName'] as String : '',
      notes: data['notes'] is String ? data['notes'] as String : '',
      downloadUrl: safeUrl,
      features: Map.unmodifiable(features),
    );
  }

  bool enabled(String key) => features[key] ?? true;
}

class AppReleaseService extends ChangeNotifier {
  static const channel = MethodChannel('com.kafekita.pos/app_release');
  AppRelease release = const AppRelease();
  int? installedCode;
  String installedName = '';
  String? error;
  bool isChecking = false;
  bool hasChecked = false;
  bool _disposed = false;
  DateTime? _lastCheckAttempt;

  bool get updateAvailable =>
      installedCode != null &&
      release.versionCode > installedCode! &&
      release.downloadUrl != null;
  bool enabled(String key) => release.enabled(key);

  Future<void> initialize() async {
    // Startup is entirely local. Repository/release changes never trigger reads.
    try {
      final info = await channel.invokeMapMethod<String, dynamic>('installedVersion');
      if (_disposed) return;
      installedCode = (info?['versionCode'] as num?)?.toInt();
      installedName = info?['versionName'] as String? ?? '';
      final prefs = await SecurePreferences.getInstance();
      final cached = prefs.getString('cached_release_metadata_v1');
      if (cached != null) release = AppRelease.fromMap(Map<String, dynamic>.from(jsonDecode(cached) as Map));
    } catch (_) {
      error = 'Versi aplikasi belum dapat dibaca. Pemeriksaan pembaruan tersedia secara manual.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (isChecking || _disposed) return;
    if (_lastCheckAttempt != null && DateTime.now().difference(_lastCheckAttempt!) < const Duration(seconds: 30)) return;
    _lastCheckAttempt = DateTime.now();
    isChecking = true;
    error = null;
    notifyListeners();
    try {
      if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
        throw UnsupportedError('Pembaruan APK hanya tersedia di Android.');
      }
      final info =
          await channel.invokeMapMethod<String, dynamic>('installedVersion');
      if (_disposed) return;
      installedCode = (info?['versionCode'] as num?)?.toInt();
      installedName = info?['versionName'] as String? ?? '';
      if (Firebase.apps.isEmpty) {
        throw StateError('Firebase belum terhubung.');
      }
      if (FirestoreSyncSafety.instance.connectionBlocked) throw StateError('Sinkronisasi ditahan.');
      final snapshot = await FirebaseFirestore.instance
          .doc('app_config/android')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (_disposed) return;
      // A deleted document restores all feature defaults and removes old releases.
      release = snapshot.exists
          ? AppRelease.fromMap(snapshot.data()!)
          : const AppRelease();
      hasChecked = true;
      final prefs = await SecurePreferences.getInstance();
      await prefs.setString('cached_release_metadata_v1', jsonEncode(snapshot.data() ?? {}));
    } catch (_) {
      if (!_disposed) {
        error =
            'Pemeriksaan pembaruan gagal. Periksa koneksi dan konfigurasi Firebase.';
      }
    } finally {
      isChecking = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> downloadUpdate() async {
    if (!updateAvailable) {
      throw StateError('Tidak ada pembaruan yang tersedia.');
    }
    await channel.invokeMethod<void>('openDownload', {
      'url': release.downloadUrl.toString(),
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
