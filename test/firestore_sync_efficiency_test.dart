import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_super/models/product.dart';
import 'package:kasir_super/models/operational_expense.dart';
import 'package:kasir_super/models/user_profile.dart';
import 'package:kasir_super/models/user_role.dart';
import 'package:kasir_super/services/pos_database_service.dart';

void main() {
  test('Acknowledgement does not mark a newer product or expense as synced', () {
    const product = Product(id: 'p', name: 'Kopi', category: 'Coffee', sellPrice: 10000, baseCost: 4000, stock: 10, isSynced: false);
    final expense = OperationalExpense(id: 'e', title: 'Sachet', category: 'Lainnya', amount: 1000, createdAt: DateTime(2026), recordedBy: '', isSynced: false);
    final products = PosDatabaseService.acknowledgeProducts([product.copyWith(stock: 9), product.copyWith(id: 'other')], [product]);
    final expenses = PosDatabaseService.acknowledgeExpenses([expense.copyWith(amount: 2000)], [expense]);
    expect(products.every((p) => !p.isSynced), isTrue);
    expect(expenses.single.isSynced, isFalse);
    expect(PosDatabaseService.acknowledgeProducts([product], [product]).single.isSynced, isTrue);
    expect(PosDatabaseService.acknowledgeExpenses([expense], [expense]).single.isSynced, isTrue);
  });

  test('Manual metadata sync writes only changed documents', () async {
    final user = UserProfile(id: 'u', username: 'kasir', displayName: 'Kasir', role: UserRole.barista, passwordHash: 'hash', salt: 'salt', createdAt: DateTime(2026));
    final written = <String>[];
    Future<int> sync(UserProfile local, List<String> categories) => PosDatabaseService.syncChangedMetadata(
      localUsers: [local], remoteUsers: {'u': user}, localCategories: categories,
      remoteCategories: ['Coffee', 'Makanan'],
      writeUser: (u) async { written.add(u.id); },
      writeCategories: (_) async { written.add('categories'); },
    );
    expect(await sync(user, ['Makanan', 'Coffee']), 0);
    expect(written, isEmpty);
    expect(await sync(user.copyWith(displayName: 'Barista'), ['Coffee', 'Makanan']), 1);
    expect(written, ['u']);
    written.clear();
    expect(await sync(user, ['Coffee']), 1);
    expect(written, ['categories']);
  });
}


