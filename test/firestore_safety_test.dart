import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/services/firestore_sync_safety.dart';
import 'package:kasir_super/services/secure_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  late DateTime now;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FirestoreSyncSafety.instance.connectionBlocked = false;
    FirestoreSyncSafety.instance.notice = null;
    FirestoreSyncSafety.instance.pendingDocuments.clear();
    now = DateTime(2026, 11, 10, 12);
  });

  FirestoreWriteGuard guard() => FirestoreWriteGuard(now: () => now);

  test('Concurrent duplicate writes send once until the server acknowledges',
      () async {
    final gate = guard();
    final started = Completer<void>();
    final ack = Completer<void>();
    var sends = 0;
    final first = gate.run(['users/cashier'], () async {
      sends++;
      started.complete();
      await ack.future;
    });
    await started.future;
    await expectLater(
        gate.run(['users/cashier'], () async {
          sends++;
        }),
        throwsStateError);
    expect(sends, 1);
    ack.complete();
    await first;
    await gate.run(['users/cashier'], () async {
      sends++;
    });
    expect(sends, 2);
  });

  test(
      'Caller timeout cannot release an unacknowledged write for another retry',
      () async {
    final gate = guard();
    final ack = Completer<void>();
    var sends = 0;
    final pending = gate.run(['products/coffee'], () async {
      sends++;
      await ack.future;
    });
    await expectLater(pending.timeout(const Duration(milliseconds: 2)),
        throwsA(isA<TimeoutException>()));
    await expectLater(
        gate.run(['products/coffee'], () async {
          sends++;
        }),
        throwsStateError);
    expect(sends, 1);
    ack.complete();
    await pending;
  });

  test(
      'Document storm is capped across guard recreation and allows retry after the window',
      () async {
    var gate = guard();
    var sends = 0;
    for (var i = 0; i < FirestoreWriteGuard.documentMinuteLimit; i++) {
      await gate.run(['users/cashier'], () async {
        sends++;
      });
    }
    gate = guard();
    await expectLater(
        gate.run(['users/cashier'], () async {
          sends++;
        }),
        throwsStateError);
    expect(sends, 20);
    now = now.add(const Duration(minutes: 1));
    await gate.run(['users/cashier'], () async {
      sends++;
    });
    expect(sends, 21);
  });

  test(
      'Bulk sends count every document and minute reservations persist across restart',
      () async {
    final gate = guard();
    var sends = 0;
    final paths = List.generate(100, (i) => 'products/$i');
    await gate.run(paths, () async {
      sends++;
    });
    await gate.run(paths, () async {
      sends++;
    });
    await expectLater(
        guard().run(['products/extra'], () async {
          sends++;
        }),
        throwsStateError);
    expect(sends, 2);
  });

  test(
      'Independent guards share an atomic budget and cannot spend the final reservation twice',
      () async {
    final prefs = await SecurePreferences.getInstance();
    await prefs.setString(
        'firestore_write_budget_v1',
        jsonEncode({
          'start': now.millisecondsSinceEpoch,
          'count': FirestoreWriteGuard.dailyLimit - 1,
        }));
    var sent = 0;
    Future<bool> send(FirestoreWriteGuard gate, String path) async {
      try {
        await gate.run([path], () async {
          sent++;
        });
        return true;
      } on StateError {
        return false;
      }
    }

    final results = await Future.wait(
        [send(guard(), 'products/a'), send(guard(), 'products/b')]);
    expect(results.where((success) => success).length, 1);
    expect(sent, 1);
    expect(
        (jsonDecode(prefs.getString('firestore_write_budget_v1')!)
            as Map)['count'],
        FirestoreWriteGuard.dailyLimit);
  });

  test(
      'Daily budget persists, fails closed for clock rollback and resets after 24 hours',
      () async {
    final prefs = await SecurePreferences.getInstance();
    await prefs.setString(
        'firestore_write_budget_v1',
        jsonEncode({
          'start': now.millisecondsSinceEpoch,
          'count': FirestoreWriteGuard.dailyLimit - 1,
        }));
    var sends = 0;
    await guard().run(['products/a'], () async {
      sends++;
    });
    await expectLater(
        guard().run(['products/b'], () async {
          sends++;
        }),
        throwsStateError);
    now = now.subtract(const Duration(seconds: 1));
    await expectLater(
        guard().run(['products/c'], () async {
          sends++;
        }),
        throwsStateError);
    now = now.add(const Duration(hours: 24, seconds: 2));
    await guard().run(['products/d'], () async {
      sends++;
    });
    expect(sends, 2);
  });

  test(
      'Storage failure, invalid paths, corrupt budget and quota cooldown never send',
      () async {
    var sends = 0;
    await expectLater(
        guard().run([], () async {
          sends++;
        }),
        throwsArgumentError);
    await expectLater(
        guard().run(['users'], () async {
          sends++;
        }),
        throwsArgumentError);
    final failing = FirestoreWriteGuard(
        preferences: () async => throw StateError('Storage failure'));
    await expectLater(
        failing.run(['users/a'], () async {
          sends++;
        }),
        throwsStateError);
    final prefs = await SecurePreferences.getInstance();
    await prefs.setString('firestore_write_budget_v1', 'corrupt');
    await expectLater(
        guard().run(['users/a'], () async {
          sends++;
        }),
        throwsFormatException);
    await prefs.remove('firestore_write_budget_v1');
    await prefs.setInt('firestore_blocked_until',
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch);
    await expectLater(
        guard().run(['users/a'], () async {
          sends++;
        }),
        throwsStateError);
    expect(sends, 0);
  });

  test('SDK pending paths recovered at boot cannot be enqueued a second time',
      () async {
    final safety = FirestoreSyncSafety.instance;
    await safety.protectQueue(
        inspect: () async => {
              'inspected': true,
              'pendingBatches': 2,
              'accountsOnly': false,
              'documents': {'transactions/sale': 1, 'products/coffee': 1},
            },
        backup: (_) async => throw StateError('Unexpected backup'),
        clear: () async => throw StateError('Unexpected clear'));
    var sends = 0;
    await expectLater(
        guard().run(['transactions/sale'], () async {
          sends++;
        }),
        throwsStateError);
    expect(sends, 0);
    expect(safety.connectionBlocked, isFalse);
  });

  test(
      'Account storm is backed up before SDK clear; local sales ledger stays byte-identical',
      () async {
    final prefs = await SecurePreferences.getInstance();
    const ledger =
        '{"transactions":[{"id":"sale"}],"openBills":[{"id":"bill"}]}';
    await prefs.setString('cached_ledger_v1', ledger);
    final calls = <String>[];
    final safety = FirestoreSyncSafety();
    await safety.protectQueue(
        inspect: () async => {
              'inspected': true,
              'pendingBatches': 16869,
              'accountsOnly': true,
              'cachedTransactionIds': ['sale'],
              'documents': {
                'users/u_barista_default': 16867,
                'users/u_owner_default': 2
              },
            },
        backup: (count) async {
          calls.add('backup:$count');
          return '/private/verified-backup';
        },
        clear: () async {
          calls.add('clear');
        });
    expect(calls, ['backup:16869', 'clear']);
    expect(safety.connectionBlocked, isFalse);
    expect(safety.pendingDocuments, isEmpty);
    expect(prefs.getString('cached_ledger_v1'), ledger);
    expect(prefs.getInt('firestore_recovery_quarantined_batches'), 16869);
    expect(prefs.getBool('firestore_recovery_completed'), isTrue);
    safety.dispose();
  });

  test(
      'Recovery does not clear SDK history that has not reached the durable sales ledger',
      () async {
    final prefs = await SecurePreferences.getInstance();
    await prefs.setString('cached_ledger_v1', '{"transactions":[]}');
    final safety = FirestoreSyncSafety();
    var clears = 0;
    await safety.protectQueue(
        inspect: () async => {
              'inspected': true,
              'pendingBatches': 1000,
              'accountsOnly': true,
              'cachedTransactionIds': ['sale-not-in-ledger'],
            },
        backup: (_) async => '/private/backup',
        clear: () async {
          clears++;
        });
    expect(safety.connectionBlocked, isTrue);
    expect(clears, 0);
    safety.dispose();
  });

  for (final scenario in [
    'mixed sales',
    'unknown schema',
    'backup failure',
    'clear failure'
  ]) {
    test('Recovery fails closed for $scenario and retains the local ledger',
        () async {
      final prefs = await SecurePreferences.getInstance();
      const originalLedger = '{"transactions":[],"openBills":[]}';
      await prefs.setString('cached_ledger_v1', originalLedger);
      final safety = FirestoreSyncSafety();
      var clears = 0;
      await safety.protectQueue(
          inspect: () async => {
                'inspected': scenario != 'unknown schema',
                'pendingBatches': 1000,
                'accountsOnly': scenario != 'mixed sales',
                'documents': {'users/u_barista_default': 1000},
              },
          backup: (_) async {
            if (scenario == 'backup failure') throw StateError('disk full');
            return '/private/backup';
          },
          clear: () async {
            clears++;
            if (scenario == 'clear failure') {
              throw StateError('already initialized');
            }
          });
      expect(safety.connectionBlocked, isTrue);
      expect(clears, scenario == 'clear failure' ? 1 : 0);
      expect(prefs.getString('cached_ledger_v1'), originalLedger);
      expect(prefs.getBool('firestore_recovery_completed'), isNot(true));
      safety.dispose();
    });
  }
}
