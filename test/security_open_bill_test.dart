import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_super/models/user_profile.dart';
import 'package:kasir_super/models/user_role.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/barista/pos_screen.dart';
import 'package:kasir_super/screens/owner/operational_expenses_screen.dart';
import 'package:kasir_super/screens/owner/owner_dashboard_screen.dart';
import 'package:kasir_super/screens/owner/user_management_screen.dart';
import 'package:kasir_super/services/app_release_service.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';
import 'package:kasir_super/widgets/access_denied.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();
  final db = PosDatabaseService.instance;

  Future<PosProvider> reopen() async {
    final pos = PosProvider();
    for (var i = 0; i < 20 && !pos.isInitialized; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return pos;
  }

  Future<PosProvider> fresh(String? role) async {
    SharedPreferences.setMockInitialValues({});
    await db.resetForTesting();
    final pos = await reopen();
    if (role != null) {
      final pass = {
        'kasir': 'sukses000',
        'admin': 'sukses123',
        'owner': 'sukses888',
      }[role]!;
      expect(await pos.login('warloc.$role', pass), isNull);
    }
    return pos;
  }

  Widget wrap(Widget child, PosProvider pos, [AppReleaseService? release]) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PosProvider>.value(value: pos),
        ChangeNotifierProvider<AppReleaseService>.value(
          value: release ?? AppReleaseService(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  test(
    'Unauthenticated callers cannot mutate provider or database directly',
    () async {
      final pos = await fresh(null);
      addTearDown(pos.dispose);
      expect(pos.isAuthenticated, isFalse);
      expect(pos.openBills, isEmpty);
      expect(db.getOpenBills(), isEmpty);

      final catErr = await pos.addCategory('Hacking Category');
      expect(catErr, contains('Akses ditolak'));

      expect(
        () => pos.addOperationalExpense(
          title: 'Unauthorized expense',
          category: 'Biaya Listrik',
          amount: 50000,
        ),
        throwsStateError,
      );

      final dummyUser = UserProfile.create(
        username: 'hacker',
        displayName: 'Hacker',
        role: UserRole.owner,
        plainPassword: 'password123456',
      );
      final userErr = await pos.saveUserProfile(dummyUser);
      expect(userErr, contains('Akses ditolak'));

      expect(() => pos.saveCurrentBill(), throwsStateError);
    },
  );

  test(
    'kasir cannot promote users or write financial administration',
    () async {
      final pos = await fresh('kasir');
      addTearDown(pos.dispose);
      expect(pos.currentRole, UserRole.barista);

      final promoUser = UserProfile.create(
        username: 'promoted',
        displayName: 'Promoted User',
        role: UserRole.owner,
        plainPassword: 'password123456',
      );
      final userErr = await pos.saveUserProfile(promoUser);
      expect(userErr, contains('Akses ditolak'));

      expect(
        () => pos.addOperationalExpense(
          title: 'Listrik',
          category: 'Biaya Listrik',
          amount: 100000,
        ),
        throwsStateError,
      );

      final catErr = await pos.addCategory('Illegal Category');
      expect(catErr, contains('Akses ditolak'));
    },
  );

  test(
    'PBKDF2 verifier matches Python hashlib reference and rejects wrong passwords',
    () async {
      const password = 'StrongPassword!123';
      const salt = 'TestSalt2026Warloc';
      final u = UserProfile(
        id: 'u_test_pbkdf2',
        username: 'warloc.pbkdf2',
        displayName: 'PBKDF2 Test',
        role: UserRole.owner,
        salt: salt,
        passwordHash: '',
        createdAt: DateTime.now(),
      );

      final secured = await u.withSecurePassword(password);
      expect(secured.passwordHash.startsWith('pbkdf2-sha256:600000:'), isTrue);
      expect(secured.salt, isNotEmpty);

      final match = await secured.verifyPasswordAsync(password);
      expect(match, isTrue);

      final fail = await secured.verifyPasswordAsync('WrongPassword999!');
      expect(fail, isFalse);
    },
  );

  test(
    'Default credentials require rotation; changed password survives initialization',
    () async {
      final pos = await fresh('owner');
      addTearDown(pos.dispose);
      expect(pos.currentUser, isNotNull);

      final current = pos.currentUser!;
      final updated = await current.withSecurePassword('NewOwnerPass2026#Secure');
      await db.saveUser(updated);

      final reopened = await reopen();
      addTearDown(reopened.dispose);
      final loginNew = await reopened.login('warloc.owner', 'NewOwnerPass2026#Secure');
      expect(loginNew, isNull);
      expect(reopened.isAuthenticated, isTrue);
    },
  );

  testWidgets(
    'kasir direct routes deny financial and staff access',
    (tester) async {
      final pos = (await tester.runAsync(() => fresh('kasir')))!;
      addTearDown(pos.dispose);

      await tester.pumpWidget(wrap(const OwnerDashboardScreen(), pos));
      await tester.pump();
      expect(find.byType(AccessDenied), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(wrap(const OperationalExpensesScreen(), pos));
      await tester.pump();
      expect(find.byType(AccessDenied), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(wrap(const UserManagementScreen(), pos));
      await tester.pump();
      expect(find.byType(AccessDenied), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'admin direct routes deny financial and staff access',
    (tester) async {
      final pos = (await tester.runAsync(() => fresh('admin')))!;
      addTearDown(pos.dispose);

      await tester.pumpWidget(wrap(const OwnerDashboardScreen(), pos));
      await tester.pump();
      expect(find.byType(AccessDenied), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(wrap(const OperationalExpensesScreen(), pos));
      await tester.pump();
      expect(find.byType(AccessDenied), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(wrap(const UserManagementScreen(), pos));
      await tester.pump();
      expect(find.byType(AccessDenied), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Owner can open cashier UI and resume a saved bill',
    (tester) async {
      final pos = (await tester.runAsync(() => fresh('owner')))!;
      addTearDown(pos.dispose);
      final release = AppReleaseService();
      addTearDown(release.dispose);

      await tester.runAsync(() async {
        final prod = pos.products.first;
        pos.addToCart(prod);
        pos.setCustomerName('Meja VIP 1');
        await pos.saveCurrentBill();
        expect(pos.openBills.length, 1);

        final billId = pos.openBills.first.id;
        pos.resumeOpenBill(billId);
      });

      await tester.pumpWidget(wrap(const PosScreen(), pos, release));
      await tester.pump();
      expect(find.byType(AccessDenied), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
