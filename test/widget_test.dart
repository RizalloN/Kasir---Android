import 'package:kasir_super/services/secure_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_super/main.dart';
import 'package:kasir_super/models/cart_item.dart';
import 'package:kasir_super/models/operational_expense.dart';
import 'package:kasir_super/models/product.dart';
import 'package:kasir_super/models/transaction.dart';
import 'package:kasir_super/models/user_profile.dart';
import 'package:kasir_super/models/user_role.dart';
import 'package:kasir_super/providers/pos_provider.dart';
import 'package:kasir_super/services/pos_database_service.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurePreferences.enableTestStorage();
  PosDatabaseService.enableTestMode();

  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  group('Cryptographic Password & User Security', () {
    test('Salted SHA-256 generates unique salts and verifies accurately', () {
      final user1 = UserProfile.create(
        username: 'barista_test',
        displayName: 'Barista Test',
        role: UserRole.barista,
        plainPassword: 'Alpha#2026!',
      );
      final user2 = UserProfile.create(
        username: 'barista_test2',
        displayName: 'Barista Test 2',
        role: UserRole.barista,
        plainPassword: 'Alpha#2026!',
      );

      expect(user1.salt, isNot(equals(user2.salt)));
      expect(user1.passwordHash, isNot(equals(user2.passwordHash)));
      expect(user1.passwordHash, isNot(contains('Alpha#2026!')));
      expect(user1.verifyPassword('Alpha#2026!'), isTrue);
      expect(user1.verifyPassword('wrong_pass'), isFalse);

      final rotated = user1.withUpdatedPassword('NewSecret99!');
      expect(rotated.verifyPassword('Alpha#2026!'), isFalse);
      expect(rotated.verifyPassword('NewSecret99!'), isTrue);
    });

    test(
      'Warloc Credentials Verification: warloc.kasir/sukses000, warloc.admin/sukses123, warloc.owner/sukses888; rejects legacy accounts',
      () async {
        SharedPreferences.setMockInitialValues({});
        await PosDatabaseService.instance.resetForTesting();

        final pos = PosProvider();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // 1. Barista: warloc.kasir / sukses000
        final baristaErr = await pos.login('warloc.kasir', 'sukses000');
        expect(baristaErr, isNull);
        expect(pos.isAuthenticated, isTrue);
        expect(pos.currentRole, UserRole.barista);
        expect(pos.currentUser?.username, 'warloc.kasir');

        await pos.logout();
        expect(pos.isAuthenticated, isFalse);

        // 2. Admin: warloc.admin / sukses123
        final adminErr = await pos.login('warloc.admin', 'sukses123');
        expect(adminErr, isNull);
        expect(pos.isAuthenticated, isTrue);
        expect(pos.currentRole, UserRole.admin);
        expect(pos.currentUser?.username, 'warloc.admin');

        await pos.logout();
        expect(pos.isAuthenticated, isFalse);

        // 3. Owner: warloc.owner / sukses888
        final ownerErr = await pos.login('warloc.owner', 'sukses888');
        expect(ownerErr, isNull);
        expect(pos.isAuthenticated, isTrue);
        expect(pos.currentRole, UserRole.owner);
        expect(pos.currentUser?.username, 'warloc.owner');

        await pos.logout();
        expect(pos.isAuthenticated, isFalse);

        // 4. Reject obsolete legacy accounts
        final legacyUserErr = await pos.login('user', '0000');
        expect(legacyUserErr, contains('tidak valid'));

        final legacyAdminErr = await pos.login('admin', 'admin123');
        expect(legacyAdminErr, contains('tidak valid'));

        final legacyOwnerErr = await pos.login('iggoys', '9999');
        expect(legacyOwnerErr, contains('tidak valid'));

        pos.dispose();
      },
    );
  });

  group('Category Management & Role Permissions', () {
    test(
      'Barista cannot modify categories; Admin & Owner have full category CRUD with cascade updates',
      () async {
        SharedPreferences.setMockInitialValues({});
        await PosDatabaseService.instance.resetForTesting();

        final pos = PosProvider();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // 1. Barista role cannot manage categories
        await pos.login('warloc.kasir', 'sukses000');
        expect(pos.currentRole, UserRole.barista);
        expect(pos.currentRole.canManageCategories, isFalse);

        final baristaAddErr = await pos.addCategory('Mocktail Eksklusif');
        expect(baristaAddErr, contains('Akses ditolak'));

        final baristaEditErr = await pos.updateCategory('Coffee', 'Kopi Enak');
        expect(baristaEditErr, contains('Akses ditolak'));

        final baristaDelErr = await pos.deleteCategory('Snack');
        expect(baristaDelErr, contains('Akses ditolak'));

        // 2. Admin role can manage categories
        await pos.login('warloc.admin', 'sukses123');
        expect(pos.currentRole, UserRole.admin);
        expect(pos.currentRole.canManageCategories, isTrue);

        // Add category
        final adminAddErr = await pos.addCategory('Artisan Mocktail');
        expect(adminAddErr, isNull);
        expect(pos.categories.contains('Artisan Mocktail'), isTrue);

        // Duplicate category rejected
        final dupErr = await pos.addCategory('Artisan Mocktail');
        expect(dupErr, isNotNull);

        // 3. Rename category cascades to all products with that category
        final adminEditErr = await pos.updateCategory('Coffee', 'Kopi Warloc');
        expect(adminEditErr, isNull);
        expect(pos.categories.contains('Kopi Warloc'), isTrue);
        expect(pos.categories.contains('Coffee'), isFalse);

        final coffeeProducts = pos.products
            .where((p) => p.category == 'Kopi Warloc')
            .toList();
        expect(coffeeProducts.isNotEmpty, isTrue);
        expect(pos.products.any((p) => p.category == 'Coffee'), isFalse);

        // 4. Delete category safely reassigns existing products to 'Umum'
        expect(
          pos.products.where((p) => p.category == 'Snack').isNotEmpty,
          isTrue,
        );
        final delErr = await pos.deleteCategory('Snack');
        expect(delErr, isNull);
        expect(pos.categories.contains('Snack'), isFalse);
        expect(
          pos.products.where((p) => p.category == 'Umum').isNotEmpty,
          isTrue,
        );

        pos.dispose();
      },
    );
  });

  group('Hiburan PS3/PS4, Base64 Image Sync & Stock Thresholds', () {
    test(
      'Hiburan category seeds Rental PS3 (4rb/jam) & Rental PS4 (5rb/jam) without false low-stock alerts, and preserves Base64 product images',
      () async {
        SharedPreferences.setMockInitialValues({});
        await PosDatabaseService.instance.resetForTesting();

        final pos = PosProvider();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await pos.login('warloc.admin', 'sukses123');

        expect(pos.categories.contains('Hiburan'), isTrue);

        final ps3 = pos.products.firstWhere((p) => p.name == 'Rental PS3');
        final ps4 = pos.products.firstWhere((p) => p.name == 'Rental PS4');

        expect(ps3.sellPrice, 4000);
        expect(ps4.sellPrice, 5000);
        expect(ps3.unitLabel, 'jam');
        expect(ps4.unitLabel, 'jam');
        expect(ps3.needsRestock, isFalse);
        expect(ps4.needsRestock, isFalse);

        // Test Base64 photo serialization & custom minStockThreshold
        const sampleBase64 =
            'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA==';
        final autoBarcode =
            'WLC${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
        final newProd = Product(
          id: 'p_auto_1',
          name: 'Avocado Coffee Special',
          category: 'Coffee',
          sellPrice: 28000,
          baseCost: 12000,
          stock: 6,
          minStockThreshold: 8,
          barcode: autoBarcode,
          imageUrl: sampleBase64,
        );

        await pos.addNewProduct(newProd);
        final found = pos.findProductByBarcode(autoBarcode);
        expect(found, isNotNull);
        expect(found?.imageUrl, sampleBase64);
        expect(found?.isLowStock, isTrue);
        expect(pos.lowStockProducts.any((p) => p.id == 'p_auto_1'), isTrue);

        pos.dispose();
      },
    );
  });

  group('Analytics MTD vs MTM End-of-Month Collapse & Operational Expenses', () {
    test(
      'Mid-month shows both MTD & MTM; End-of-month (31 Oct) collapses MTM into MTD; Operational expenses deduct from net profit',
      () async {
        SharedPreferences.setMockInitialValues({});
        await PosDatabaseService.instance.resetForTesting();

        final pos = PosProvider();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await pos.login('warloc.owner', 'sukses888');

        final ps4 = pos.products.firstWhere((p) => p.name == 'Rental PS4');

        // Seed historical transactions on 2 Oct 2026 (MTM for 2 Nov) and 31 Oct 2026 (MTD for 2 Nov)
        await PosDatabaseService.instance.insertHistoricalTransactionForTesting(
          TransactionRecord(
            id: 'tx_oct2',
            invoiceNumber: 'INV-20261002-00001',
            items: [CartItem(product: ps4, quantity: 4)], // 20.000
            totalAmount: 20000,
            totalCost: 0,
            totalProfit: 20000,
            paymentMethod: 'Cash',
            amountPaid: 20000,
            changeAmount: 0,
            cashierName: 'Barista Warloc',
            createdAt: DateTime(2026, 10, 2, 14, 0),
          ),
        );
        await PosDatabaseService.instance.insertHistoricalTransactionForTesting(
          TransactionRecord(
            id: 'tx_oct31',
            invoiceNumber: 'INV-20261031-00002',
            items: [CartItem(product: ps4, quantity: 10)], // 50.000
            totalAmount: 50000,
            totalCost: 0,
            totalProfit: 50000,
            paymentMethod: 'QRIS',
            amountPaid: 50000,
            changeAmount: 0,
            cashierName: 'Barista Warloc',
            createdAt: DateTime(2026, 10, 31, 19, 0),
          ),
        );
        await PosDatabaseService.instance.insertHistoricalTransactionForTesting(
          TransactionRecord(
            id: 'tx_nov2',
            invoiceNumber: 'INV-20261102-00003',
            items: [CartItem(product: ps4, quantity: 6)], // 30.000
            totalAmount: 30000,
            totalCost: 0,
            totalProfit: 30000,
            paymentMethod: 'Cash',
            amountPaid: 30000,
            changeAmount: 0,
            cashierName: 'Barista Warloc',
            createdAt: DateTime(2026, 11, 2, 11, 0),
          ),
        );

        // Record operational expenses on 2 Nov 2026
        await pos.addOperationalExpense(
          title: 'Token PLN',
          category: 'Biaya Listrik',
          amount: 8000,
          createdAt: DateTime(2026, 11, 2, 12, 0),
        );
        await pos.addOperationalExpense(
          title: 'Sedotan Steril',
          category: 'Sedotan',
          amount: 2000,
          createdAt: DateTime(2026, 11, 2, 12, 30),
        );
        expect(
          OperationalExpense.defaultCategories,
          containsAll([
            'Biaya Listrik',
            'Biaya Air',
            'Kantong Plastik',
            'Sedotan',
            'ATK',
          ]),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));

        // 1. Mid-month check (2 Nov 2026): MTM (2 Oct) != MTD (31 Oct) -> both active
        final midMonth = pos.computeRevenueComparison(
          referenceDate: DateTime(2026, 11, 2),
        );
        expect(midMonth.collapseMtmIntoMtd, isFalse);
        expect(midMonth.todayRevenue, 30000);
        expect(midMonth.mtdPrevMonthLastDayRevenue, 50000);
        expect(midMonth.mtmPrevMonthSameDayRevenue, 20000);
        expect(midMonth.prevMonthFullRevenue, 70000);
        expect(midMonth.todayOperationalExpense, 10000);
        expect(midMonth.todayNetProfit, 20000);

        // 2. End-of-month check (31 Oct 2026): MTM and MTD coincide -> collapseMtmIntoMtd == true!
        final endOfMonth = pos.computeRevenueComparison(
          referenceDate: DateTime(2026, 10, 31),
        );
        expect(endOfMonth.collapseMtmIntoMtd, isTrue);

        // Payment breakdown contains strictly Cash & QRIS (no Transfer)
        final breakdown = pos.paymentMethodBreakdown;
        expect(breakdown.keys.toSet(), equals({'Cash', 'QRIS'}));

        pos.dispose();
      },
    );

    test(
      'Operational Profit Summary accurately calculates Gross Profit, Operational Costs (Listrik, Air, Gas LPG, Plastik, Es Batu), and Net Profit',
      () async {
        SharedPreferences.setMockInitialValues({});
        await PosDatabaseService.instance.resetForTesting();

        final pos = PosProvider();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await pos.login('warloc.owner', 'sukses888');

        // Check categories include Gas LPG and Es Batu
        expect(
          OperationalExpense.defaultCategories,
          containsAll([
            'Biaya Listrik',
            'Biaya Air',
            'Gas LPG',
            'Kantong Plastik',
            'Sedotan',
            'Es Batu',
            'ATK',
          ]),
        );

        // 1. Add operational expenses on 5 Nov 2026
        final targetDate = DateTime(2026, 11, 5, 10, 0);
        await pos.addOperationalExpense(
          title: 'Token Listrik Bar & AC',
          category: 'Biaya Listrik',
          amount: 100000,
          createdAt: targetDate,
        );
        await pos.addOperationalExpense(
          title: 'Tabung Gas LPG 3kg',
          category: 'Gas LPG',
          amount: 22000,
          createdAt: targetDate,
        );
        await pos.addOperationalExpense(
          title: 'Air Galon PDAM',
          category: 'Biaya Air',
          amount: 25000,
          createdAt: targetDate,
        );
        await pos.addOperationalExpense(
          title: 'Kresek Takeaway & Cup',
          category: 'Kantong Plastik',
          amount: 15000,
          createdAt: targetDate,
        );
        await pos.addOperationalExpense(
          title: 'Es Batu Kristal 10kg',
          category: 'Es Batu',
          amount: 18000,
          createdAt: targetDate,
        );

        // Total Ops = 100k + 22k + 25k + 15k + 18k = 180.000
        expect(pos.operationalExpenses.length, 5);

        // 2. Add sample transactions on 5 Nov 2026
        final prodKopi = pos.products.first; // e.g. Kopi Warloc / beverage
        await PosDatabaseService.instance.insertHistoricalTransactionForTesting(
          TransactionRecord(
            id: 'tx_profit_1',
            invoiceNumber: 'INV-20261105-00001',
            items: [CartItem(product: prodKopi, quantity: 5)],
            subtotalAmount: 75000,
            discountAmount: 0,
            totalAmount: 75000,
            totalCost: 30000, // HPP 30.000
            totalProfit: 45000, // Gross 45.000
            paymentMethod: 'Cash',
            amountPaid: 100000,
            changeAmount: 25000,
            cashierName: 'Barista Warloc',
            createdAt: DateTime(2026, 11, 5, 11, 0),
          ),
        );

        await PosDatabaseService.instance.insertHistoricalTransactionForTesting(
          TransactionRecord(
            id: 'tx_profit_2',
            invoiceNumber: 'INV-20261105-00002',
            items: [CartItem(product: prodKopi, quantity: 10)],
            subtotalAmount: 120000,
            discountAmount: 20000,
            totalAmount: 100000,
            totalCost: 40000, // HPP 40.000
            totalProfit: 60000, // Gross 60.000
            paymentMethod: 'QRIS',
            amountPaid: 100000,
            changeAmount: 0,
            cashierName: 'Barista Warloc',
            createdAt: DateTime(2026, 11, 5, 14, 0),
          ),
        );

        // Voided transaction should NOT count towards revenue or profit
        await PosDatabaseService.instance.insertHistoricalTransactionForTesting(
          TransactionRecord(
            id: 'tx_profit_voided',
            invoiceNumber: 'INV-20261105-VOID',
            items: [CartItem(product: prodKopi, quantity: 8)],
            subtotalAmount: 100000,
            discountAmount: 0,
            totalAmount: 100000,
            totalCost: 40000,
            totalProfit: 60000,
            paymentMethod: 'Cash',
            amountPaid: 100000,
            changeAmount: 0,
            cashierName: 'Barista Warloc',
            createdAt: DateTime(2026, 11, 5, 15, 0),
            isVoided: true,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Compute Operational Profit Summary for 5 Nov 2026
        final summary = pos.computeOperationalProfitSummary(
          start: DateTime(2026, 11, 5),
          end: DateTime(2026, 11, 5),
        );

        expect(summary.totalRevenue, 175000); // 75.000 + 100.000
        expect(summary.totalCogs, 70000); // 30.000 + 40.000
        expect(summary.grossProfit, 105000); // 175.000 - 70.000
        expect(summary.operationalExpenses, 180000);
        expect(summary.netProfit, -75000); // 105.000 - 180.000 (Rugi Operasional)
        expect(summary.isProfitable, isFalse);

        // Verify Category Breakdown in Summary
        expect(summary.expenseCategoryBreakdown['Gas LPG'], 22000);
        expect(summary.expenseCategoryBreakdown['Biaya Listrik'], 100000);
        expect(summary.expenseCategoryBreakdown['Biaya Air'], 25000);
        expect(summary.expenseCategoryBreakdown['Kantong Plastik'], 15000);
        expect(summary.expenseCategoryBreakdown['Es Batu'], 18000);

        // Now add a high revenue sale bringing business to net profit
        await PosDatabaseService.instance.insertHistoricalTransactionForTesting(
          TransactionRecord(
            id: 'tx_profit_3',
            invoiceNumber: 'INV-20261105-00003',
            items: [CartItem(product: prodKopi, quantity: 20)],
            subtotalAmount: 300000,
            discountAmount: 0,
            totalAmount: 300000,
            totalCost: 120000, // HPP 120.000
            totalProfit: 180000, // Gross 180.000
            paymentMethod: 'Cash',
            amountPaid: 300000,
            changeAmount: 0,
            cashierName: 'Barista Warloc',
            createdAt: DateTime(2026, 11, 5, 18, 0),
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));

        final profitableSummary = pos.computeOperationalProfitSummary(
          start: DateTime(2026, 11, 5),
          end: DateTime(2026, 11, 5),
        );

        expect(profitableSummary.totalRevenue, 475000); // 175.000 + 300.000
        expect(profitableSummary.totalCogs, 190000); // 70.000 + 120.000
        expect(profitableSummary.grossProfit, 285000); // 105.000 + 180.000
        expect(profitableSummary.operationalExpenses, 180000);
        expect(profitableSummary.netProfit, 105000); // 285.000 - 180.000
        expect(profitableSummary.isProfitable, isTrue);

        // Check monthly daily series factors in operational expenses
        final dailySeries = pos.buildMonthlyDailySeries(
          monthDate: DateTime(2026, 11, 5),
        );
        // Day 5 is index 4
        expect(dailySeries[4].value, 475000); // Revenue
        expect(dailySeries[4].secondaryValue, 105000); // Net Profit after ops

        pos.dispose();
      },
    );
  });

  group('Thermal Printer & ESC/POS Ticket Generation', () {
    test(
      'ESC/POS generator builds valid receipt byte arrays for 58mm and 80mm',
      () async {
        final profile = await CapabilityProfile.load();

        // 58mm test
        final gen58 = Generator(PaperSize.mm58, profile);
        List<int> bytes58 = [];
        bytes58 += gen58.text(
          'WARLOC',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        bytes58 += gen58.hr();
        bytes58 += gen58.row([
          PosColumn(text: 'Kopi Susu Warloc', width: 7),
          PosColumn(
            text: 'Rp 22.000',
            width: 5,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
        bytes58 += gen58.feed(1);
        bytes58 += gen58.cut();

        expect(bytes58.isNotEmpty, isTrue);

        // 80mm test
        final gen80 = Generator(PaperSize.mm80, profile);
        List<int> bytes80 = [];
        bytes80 += gen80.text(
          'WARLOC',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        bytes80 += gen80.hr();
        bytes80 += gen80.row([
          PosColumn(text: 'Rental PS4 (2 jam)', width: 6),
          PosColumn(
            text: 'Rp 10.000',
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
        bytes80 += gen80.feed(2);
        bytes80 += gen80.cut();

        expect(bytes80.isNotEmpty, isTrue);
      },
    );
  });

  group('POS Business Logic & Inventory Integrity', () {
    test(
      'Duplicate username protection, stock ceiling, discount & void stock restoration',
      () async {
        SharedPreferences.setMockInitialValues({});
        await PosDatabaseService.instance.resetForTesting();

        final pos = PosProvider();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(pos.isInitialized, isTrue);

        // Login as Owner
        final err = await pos.login('warloc.owner', 'sukses888');
        expect(err, isNull);
        expect(pos.isAuthenticated, isTrue);
        expect(pos.currentRole, UserRole.owner);

        // Reject duplicate username
        final dupUser = UserProfile.create(
          username: 'warloc.admin',
          displayName: 'Duplicate Admin',
          role: UserRole.admin,
          plainPassword: 'secret',
        );
        final dupError = await pos.saveUserProfile(dupUser);
        expect(dupError, isNotNull);

        // Stock ceiling check (Butter Croissant has stock 4)
        final croissant = pos.products.firstWhere((p) => p.id == 'w_6');
        expect(croissant.stock, 4);

        expect(pos.addToCart(croissant), isTrue);
        expect(pos.updateQuantity(croissant.id, 3), isTrue); // Total 4 in cart
        expect(
          pos.updateQuantity(croissant.id, 1),
          isFalse,
        ); // Exceeds 4 -> blocked!

        // Apply Rp 6.000 promo discount (Subtotal 4 * 24.000 = 96.000 -> Total 90.000)
        pos.setDiscountAmount(6000);
        expect(pos.subtotalCartAmount, 96000);
        expect(pos.totalCartAmount, 90000);

        final tx = await pos.processCheckout(
          paymentMethod: 'Cash',
          amountPaid: 100000,
          cashierName: 'Owner Warloc',
          customerName: 'Meja 4',
        );

        expect(tx.paymentMethod, 'Cash');
        expect(tx.changeAmount, 10000);
        expect(pos.products.firstWhere((p) => p.id == 'w_6').stock, 0);
        expect(pos.todayRevenue, 90000);

        // Void transaction -> stock restored to 4 & excluded from revenue
        final voidOk = await pos.voidTransaction(tx.id);
        expect(voidOk, isTrue);
        expect(pos.products.firstWhere((p) => p.id == 'w_6').stock, 4);
        expect(pos.todayRevenue, 0);

        pos.dispose();
      },
    );
  });

  testWidgets(
    'Warloc startup & secure login screen hides quick-login credentials',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await PosDatabaseService.instance.resetForTesting();

      await tester.pumpWidget(const KasirSuperApp());
      await tester.pumpAndSettle();

      expect(find.text('WARLOC'), findsOneWidget);
      expect(find.text('Masuk ke Akun'), findsOneWidget);
      expect(find.text('Akses Cepat Akun Default:'), findsNothing);
      expect(find.text('CAFE WARLOC'), findsNothing);
    },
  );
}
