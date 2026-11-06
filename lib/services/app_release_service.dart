import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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

class AppReleaseService extends ChangeNotifier with WidgetsBindingObserver {
  static const channel = MethodChannel('com.kafekita.pos/app_release');
  AppRelease release = const AppRelease();
  int? installedCode;
  String installedName = '';
  String? error;
  bool isChecking = false;
  bool _disposed = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  bool get updateAvailable =>
      installedCode != null &&
      release.versionCode > installedCode! &&
      release.downloadUrl != null;
  bool enabled(String key) => release.enabled(key);

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    await refresh();
    if (_disposed || Firebase.apps.isEmpty) return;
    _subscription = FirebaseFirestore.instance
        .doc('app_config/android')
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (_disposed) return;
      try {
        release = snapshot.exists
            ? AppRelease.fromMap(snapshot.data()!)
            : const AppRelease();
        // Cached snapshots must not erase a failed server-check message.
        if (!snapshot.metadata.isFromCache) error = null;
        notifyListeners();
      } catch (_) {
        error =
            'Konfigurasi rilis tidak valid. Pengaturan terakhir tetap dipakai.';
        notifyListeners();
      }
    }, onError: (Object _) {
      if (_disposed) return;
      error =
          'Kontrol fitur belum terhubung. Pengaturan terakhir tetap dipakai.';
      notifyListeners();
    });
  }

  Future<void> refresh() async {
    if (isChecking || _disposed) return;
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
      final snapshot = await FirebaseFirestore.instance
          .doc('app_config/android')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (_disposed) return;
      // A deleted document restores all feature defaults and removes old releases.
      release = snapshot.exists
          ? AppRelease.fromMap(snapshot.data()!)
          : const AppRelease();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }
}
