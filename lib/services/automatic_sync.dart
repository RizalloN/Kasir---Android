import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'secure_preferences.dart';

/// The timer checks local state only. Network traffic requires pending work,
/// a usable connection, an expired retry deadline, and a single active worker.
class AutomaticSync {
  final bool Function() hasWork;
  final Future<bool> Function() send;
  final DateTime Function() now;
  final void Function(bool) onConnection;
  bool connected = false;
  bool _disposed = false;
  Future<void>? _running;
  Timer? _timer;
  Timer? _debounce;

  AutomaticSync({required this.hasWork, required this.send,
    required this.onConnection, DateTime Function()? now}) : now = now ?? DateTime.now;

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 15), (_) => unawaited(tick()));
  }

  void networkChanged(bool available) {
    if (_disposed || connected == available) return;
    connected = available;
    debugPrint('Automatic sync: connection ${available ? 'available' : 'unavailable'}');
    onConnection(available);
    _debounce?.cancel();
    _debounce = null;
    if (available) request();
  }

  void request() {
    if (_disposed || !connected) return;
    _debounce ??= Timer(const Duration(seconds: 2), () {
      _debounce = null;
      unawaited(tick());
    });
  }

  Future<void> tick() => _running ??= _attempt().whenComplete(() => _running = null);

  Future<void> _attempt() async {
    if (_disposed || !connected || !hasWork()) return;
    try {
      final prefs = await SecurePreferences.getInstance();
      final state = jsonDecode(prefs.getString('firestore_auto_retry_v1') ?? '{}') as Map;
      final next = state['next'] as int? ?? 0;
      if (now().millisecondsSinceEpoch < next) return;
      final failures = state['failures'] as int? ?? 0;
      // Reserve BEFORE network access. Restarting or flapping Wi-Fi cannot
      // bypass the retry deadline, including failed reads and transactions.
      final delay = Duration(seconds: (30 * (1 << failures.clamp(0, 6))).clamp(30, 1800));
      if (!await prefs.setString('firestore_auto_retry_v1', jsonEncode({
        'next': now().add(delay).millisecondsSinceEpoch,
        'failures': (failures + 1).clamp(0, 6),
      }))) {
        return;
      }
      if (_disposed || !connected) return;
      if (await send()) {
        await prefs.setString('firestore_auto_retry_v1', jsonEncode({
          'next': now().add(const Duration(seconds: 15)).millisecondsSinceEpoch,
          'failures': 0,
        }));
      }
    } catch (error) {
      debugPrint('Automatic sync retained locally: $error');
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _debounce?.cancel();
  }
}
