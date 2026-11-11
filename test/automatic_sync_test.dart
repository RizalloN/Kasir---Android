import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/services/automatic_sync.dart';
import 'package:kasir_super/services/secure_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  late DateTime time;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    time = DateTime(2026, 11, 10);
  });

  test('Offline work never sends; reconnect automatically drains without user action', () async {
    var work = true;
    var sends = 0;
    final sync = AutomaticSync(hasWork: () => work, now: () => time,
      onConnection: (_) {}, send: () async { sends++; work = false; return true; });
    addTearDown(sync.dispose);
    await sync.tick();
    expect(sends, 0);
    sync.networkChanged(true);
    await sync.tick();
    expect(sends, 1);
    for (var i = 0; i < 1000; i++) { await sync.tick(); }
    expect(sends, 1);
  });

  test('Network flapping, parallel ticks and restart cannot bypass persisted backoff', () async {
    var sends = 0;
    AutomaticSync create() => AutomaticSync(hasWork: () => true, now: () => time,
      onConnection: (_) {}, send: () async { sends++; return false; });
    var sync = create();
    sync.networkChanged(true);
    await Future.wait(List.generate(100, (_) => sync.tick()));
    expect(sends, 1);
    for (var i = 0; i < 100; i++) {
      sync.networkChanged(false); sync.networkChanged(true);
      await sync.tick();
    }
    expect(sends, 1);
    sync.dispose();
    sync = create();
    addTearDown(sync.dispose);
    sync.networkChanged(true);
    await sync.tick();
    expect(sends, 1);
    time = time.add(const Duration(seconds: 30));
    await sync.tick();
    expect(sends, 2);
    time = time.add(const Duration(seconds: 59));
    await sync.tick();
    expect(sends, 2);
    time = time.add(const Duration(seconds: 1));
    await sync.tick();
    expect(sends, 3);
  });

  test('A pending acknowledgement holds the worker and the deadline survives exceptions', () async {
    var sends = 0;
    final gate = Completer<bool>();
    final sync = AutomaticSync(hasWork: () => true, now: () => time,
      onConnection: (_) {}, send: () { sends++; return gate.future; });
    addTearDown(sync.dispose);
    sync.networkChanged(true);
    final first = sync.tick();
    while (sends == 0) { await Future<void>.delayed(Duration.zero); }
    expect(identical(first, sync.tick()), isTrue);
    gate.completeError(StateError('Disconnected'));
    await first;
    await sync.tick();
    expect(sends, 1);
  });
}
