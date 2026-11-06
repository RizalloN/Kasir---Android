import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/models/user_role.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:kasir_super/services/secure_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PosDatabaseService.enableTestMode();
  SecurePreferences.enableTestStorage();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecurePreferences.resetForTesting();
  });

  test('All 3 default accounts login with exact requested credentials and roles', () async {
    final db = PosDatabaseService.instance;
    await db.resetForTesting();

    final pos = PosProvider();
    addTearDown(pos.dispose);

    for (var i = 0; i < 20 && !pos.isInitialized; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // 1. Kasir / Barista
    final errKasir = await pos.login('warloc.kasir', 'sukses000');
    expect(errKasir, isNull);
    expect(pos.isAuthenticated, isTrue);
    expect(pos.currentRole, UserRole.barista);
    await pos.logout();

    // 2. Admin
    final errAdmin = await pos.login('warloc.admin', 'sukses123');
    expect(errAdmin, isNull);
    expect(pos.isAuthenticated, isTrue);
    expect(pos.currentRole, UserRole.admin);
    await pos.logout();

    // 3. Owner
    final errOwner = await pos.login('warloc.owner', 'sukses888');
    expect(errOwner, isNull);
    expect(pos.isAuthenticated, isTrue);
    expect(pos.currentRole, UserRole.owner);
    await pos.logout();

    // Wrong password test (rejected without any self-healing)
    final errWrong = await pos.login('warloc.owner', 'salah_password');
    expect(errWrong, isNotNull);
    expect(pos.isAuthenticated, isFalse);
  });

  test('Standard authentication rejects old password after intentional password update', () async {
    final db = PosDatabaseService.instance;
    await db.resetForTesting();

    final pos = PosProvider();
    addTearDown(pos.dispose);

    for (var i = 0; i < 20 && !pos.isInitialized; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Login owner
    expect(await pos.login('warloc.owner', 'sukses888'), isNull);
    final user = pos.currentUser!;
    final modified = await user.withSecurePassword('NewOwnerPass2026');
    await db.saveUser(modified);
    await pos.logout();

    // Old default password should fail because self-healing is removed
    final errOld = await pos.login('warloc.owner', 'sukses888');
    expect(errOld, isNotNull);
    expect(pos.isAuthenticated, isFalse);

    // New password should succeed
    final errNew = await pos.login('warloc.owner', 'NewOwnerPass2026');
    expect(errNew, isNull);
    expect(pos.isAuthenticated, isTrue);
  });
}
