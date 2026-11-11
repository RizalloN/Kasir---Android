import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/user_role.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/screens/auth/change_password_screen.dart';
import 'package:kasir_super/screens/dialogs/user_profile_modal.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';
import 'package:kasir_super/widgets/access_denied.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PosDatabaseService.enableTestMode();
  SecurePreferences.enableTestStorage();
  final db = PosDatabaseService.instance;

  setUpAll(() => initializeDateFormatting('id_ID', null));

  Future<PosProvider> fresh(String account) async {
    SharedPreferences.setMockInitialValues({});
    SecurePreferences.resetForTesting();
    await db.resetForTesting();
    final pos = PosProvider();
    addTearDown(pos.dispose);
    while (!pos.isInitialized && pos.initializationError == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pos.initializationError, isNull);
    final password = switch (account) {
      'kasir' => 'sukses000',
      'admin' => 'sukses123',
      _ => 'sukses888',
    };
    expect(await pos.login('warloc.$account', password), isNull);
    return pos;
  }

  Widget wrap(PosProvider pos, Widget child) =>
      ChangeNotifierProvider.value(value: pos, child: MaterialApp(home: child));

  test(
      'Barista cannot change password through provider, storage or user management',
      () async {
    final pos = await fresh('kasir');
    final before = pos.currentUser!;
    expect(pos.currentRole.canChangeOwnPassword, isFalse);
    await expectLater(pos.changeOwnPassword('sukses000', 'KasirChanged2026'),
        throwsStateError);
    await expectLater(db.changeOwnPassword('sukses000', 'KasirChanged2026'),
        throwsStateError);
    final tampered = before.copyWith(passwordHash: 'blocked', salt: 'blocked');
    expect(await pos.saveUserProfile(tampered), contains('Akses ditolak'));
    await expectLater(db.saveUser(tampered), throwsStateError);
    expect(pos.currentUser!.passwordHash, before.passwordHash);
    expect(db.getUsers().single.passwordHash, before.passwordHash);
    await pos.logout();
    await db.resetForTesting();
    expect(await db.authenticate('warloc.kasir', 'sukses000'), isNotNull);
    expect(await db.authenticate('warloc.kasir', 'KasirChanged2026'), isNull);
  });

  for (final account in ['admin', 'owner']) {
    test('$account can change own password and log in after restart', () async {
      final pos = await fresh(account);
      final oldPassword = account == 'admin' ? 'sukses123' : 'sukses888';
      final nextPassword = '${account}Changed2026';
      expect(pos.currentRole.canChangeOwnPassword, isTrue);
      await pos.changeOwnPassword(oldPassword, nextPassword);
      expect(await pos.currentUser!.verifyPasswordAsync(nextPassword), isTrue);
      await pos.logout();
      await db.resetForTesting();
      expect(await db.authenticate('warloc.$account', oldPassword), isNull);
      expect(await db.authenticate('warloc.$account', nextPassword), isNotNull);
      if (account == 'admin') {
        final user = db.getUsers().single;
        await expectLater(db.saveUser(user.copyWith(displayName: 'Denied')),
            throwsStateError);
      }
    });
  }

  test(
      'Owner can reset barista and admin passwords without changing their roles',
      () async {
    final pos = await fresh('owner');
    final accounts = [('kasir', UserRole.barista), ('admin', UserRole.admin)];
    for (final (account, role) in accounts) {
      final user = pos.users.firstWhere((u) => u.username == 'warloc.$account');
      final updated =
          await user.withSecurePassword('${account}ResetByOwner2026');
      expect(await pos.saveUserProfile(updated), isNull);
      expect(pos.users.firstWhere((u) => u.id == user.id).role, role);
    }
    await pos.logout();
    await db.resetForTesting();
    for (final (account, role) in accounts) {
      final authenticated = await db.authenticate(
          'warloc.$account', '${account}ResetByOwner2026');
      expect(authenticated?.role, role);
    }
  });

  for (final account in ['kasir', 'admin', 'owner']) {
    testWidgets(
        '$account profile and direct password route follow role permissions',
        (tester) async {
      final pos = (await tester.runAsync(() => fresh(account)))!;
      await tester.pumpWidget(wrap(pos, UserProfileModal(pos: pos)));
      await tester.pumpAndSettle();
      expect(find.text('Ganti Password Saya'),
          account == 'kasir' ? findsNothing : findsOneWidget);
      expect(find.text('Kelola Profil Pengguna / Staff'),
          account == 'owner' ? findsOneWidget : findsNothing);
      expect(find.text('Logout / Keluar Akun'), findsOneWidget);
      await tester.pumpWidget(wrap(pos, const ChangePasswordScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(AccessDenied),
          account == 'kasir' ? findsOneWidget : findsNothing);
      expect(find.byType(TextField),
          account == 'kasir' ? findsNothing : findsNWidgets(3));
      expect(find.text('Simpan Password'),
          account == 'kasir' ? findsNothing : findsOneWidget);
      if (account != 'kasir') {
        await tester.runAsync(pos.logout);
        await tester.pumpAndSettle();
        expect(find.byType(AccessDenied), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      }
    });
  }
}
