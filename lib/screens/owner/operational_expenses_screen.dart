import '../../models/user_role.dart';
import '../../widgets/access_denied.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/operational_expense.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../dialogs/batch_insert_dialog.dart';

class OperationalExpensesScreen extends StatefulWidget {
  const OperationalExpensesScreen({super.key});

  static IconData iconForCategory(String category) {
    final c = category.toLowerCase();
    if (c.contains('listrik')) return Icons.bolt_rounded;
    if (c.contains('air')) return Icons.water_drop_rounded;
    if (c.contains('lpg') || c.contains('gas')) return Icons.local_fire_department_rounded;
    if (c.contains('plastik') || c.contains('kemasan')) return Icons.shopping_bag_outlined;
    if (c.contains('sedotan') || c.contains('cup')) return Icons.local_drink_outlined;
    if (c.contains('es')) return Icons.ac_unit_rounded;
    if (c.contains('atk') || c.contains('kertas')) return Icons.edit_note_rounded;
    if (c.contains('bersih') || c.contains('sanitasi')) return Icons.cleaning_services_rounded;
    if (c.contains('rawat') || c.contains('servis')) return Icons.build_rounded;
    return Icons.receipt_long_outlined;
  }

  static Color colorForCategory(String category) {
    final c = category.toLowerCase();
    if (c.contains('listrik')) return AppTheme.accentAmber;
    if (c.contains('air')) return AppTheme.roleAdmin;
    if (c.contains('lpg') || c.contains('gas')) return const Color(0xFFEA580C);
    if (c.contains('plastik') || c.contains('kemasan')) return const Color(0xFF9A3412);
    if (c.contains('sedotan') || c.contains('cup')) return AppTheme.successGreen;
    if (c.contains('es')) return const Color(0xFF0284C7);
    if (c.contains('atk') || c.contains('kertas')) return AppTheme.roleOwner;
    if (c.contains('bersih') || c.contains('sanitasi')) return const Color(0xFF0D9488);
    if (c.contains('rawat') || c.contains('servis')) return const Color(0xFF4F46E5);
    return AppTheme.textSecondary;
  }

  @override
  State<OperationalExpensesScreen> createState() =>
      _OperationalExpensesScreenState();
}

class _OperationalExpensesScreenState extends State<OperationalExpensesScreen> {
  String _periodFilter = 'Bulan Ini'; // Hari Ini, Bulan Ini, Semua
  String _categoryFilter = 'Semua';

  static IconData iconForCategory(String category) =>
      OperationalExpensesScreen.iconForCategory(category);
  static Color colorForCategory(String category) =>
      OperationalExpensesScreen.colorForCategory(category);

  void _openExpenseFormDialog(
    BuildContext context,
    PosProvider pos, {
    OperationalExpense? existing,
  }) {
    String selectedCat =
        existing?.category ?? OperationalExpense.defaultCategories.first;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final amountCtrl = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(0) : '',
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    DateTime pickedDate = existing?.createdAt ?? DateTime.now();
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.accentCopperSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 20,
                                color: AppTheme.accentAmber,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              existing != null
                                  ? 'Edit Biaya Operasional'
                                  : 'Catat Biaya Operasional',
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textMain,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: AppTheme.textMuted,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (errorMsg != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.dangerLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 17,
                              color: AppTheme.dangerRed,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMsg!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.dangerRed,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    const Text(
                      'Kategori Operasional',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: OperationalExpense.defaultCategories.map((cat) {
                        final isSel = selectedCat == cat;
                        final catColor = colorForCategory(cat);
                        return ChoiceChip(
                          showCheckmark: false,
                          avatar: Icon(
                            iconForCategory(cat),
                            size: 15,
                            color: isSel ? Colors.white : catColor,
                          ),
                          label: Text(cat),
                          selected: isSel,
                          selectedColor: AppTheme.primary,
                          backgroundColor: AppTheme.cardBg,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: isSel
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSel ? Colors.white : AppTheme.textMain,
                          ),
                          onSelected: (_) {
                            setModalState(() {
                              selectedCat = cat;
                              errorMsg = null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Nama / Keterangan Pengeluaran',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        hintText: selectedCat == 'Biaya Listrik'
                            ? 'Contoh: Token Listrik PLN Kasir/Bar'
                            : (selectedCat == 'Biaya Air'
                                ? 'Contoh: Air Galon / Tagihan PDAM'
                                : (selectedCat == 'Gas LPG'
                                    ? 'Contoh: Tabung Gas LPG 3kg / 12kg'
                                    : (selectedCat == 'Kantong Plastik'
                                        ? 'Contoh: Plastik Kresek Takeaway & Cup'
                                        : (selectedCat == 'Es Batu'
                                            ? 'Contoh: Es Batu Kristal 10kg'
                                            : (selectedCat == 'ATK'
                                                ? 'Contoh: Kertas Thermal 58mm / Pulpen'
                                                : (selectedCat == 'Kebersihan & Sanitasi'
                                                    ? 'Contoh: Sabun Cuci Piring & Cairan Pel'
                                                    : 'Contoh: Pengeluaran $selectedCat')))))),
                        prefixIcon: const Icon(
                          Icons.description_outlined,
                          size: 19,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Nominal Biaya (Rp)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textMain,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: amountCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (_) {
                                  if (errorMsg != null) {
                                    setModalState(() => errorMsg = null);
                                  }
                                },
                                decoration: const InputDecoration(
                                  prefixText: 'Rp ',
                                  hintText: '0',
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                children: [10000, 20000, 50000, 100000].map((preset) {
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () {
                                      final current = CurrencyFormatter.parseDigits(amountCtrl.text);
                                      final next = current + preset;
                                      amountCtrl.text = next.toStringAsFixed(0);
                                      setModalState(() => errorMsg = null);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceSubtle,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppTheme.borderSubtle),
                                      ),
                                      child: Text(
                                        '+${CurrencyFormatter.formatShort(preset)}',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tanggal',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textMain,
                                ),
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  final chosen = await showDatePicker(
                                    context: context,
                                    initialDate: pickedDate,
                                    firstDate: DateTime(2023),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                  );
                                  if (chosen != null) {
                                    final now = DateTime.now();
                                    setModalState(() {
                                      pickedDate = DateTime(
                                        chosen.year,
                                        chosen.month,
                                        chosen.day,
                                        now.hour,
                                        now.minute,
                                      );
                                    });
                                  }
                                },
                                child: Container(
                                  height: 48,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceSubtle,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.borderSubtle,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today_rounded,
                                        size: 15,
                                        color: AppTheme.accentAmber,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          '${pickedDate.day.toString().padLeft(2, '0')}/${pickedDate.month.toString().padLeft(2, '0')}/${pickedDate.year}',
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textMain,
                                            fontFeatures:
                                                AppTheme.tabularFigures,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'Catatan Tambahan (Opsional)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Contoh: 5 pack plastik cup / tagihan PLN...',
                        prefixIcon: Icon(Icons.notes_rounded, size: 19),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        if (existing != null) ...[
                          IconButton(
                            tooltip: 'Hapus Pencatatan',
                            onPressed: () async {
                              await pos.deleteOperationalExpense(existing.id);
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                                AppTheme.showToast(
                                  context,
                                  message:
                                      'Biaya operasional berhasil dihapus.',
                                  isWarning: true,
                                );
                              }
                            },
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppTheme.dangerRed,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Batal'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final amount = CurrencyFormatter.parseDigits(
                                amountCtrl.text,
                              );
                              if (amount <= 0) {
                                setModalState(
                                  () => errorMsg =
                                      'Nominal biaya harus lebih dari Rp 0.',
                                );
                                return;
                              }
                              final resolvedTitle =
                                  titleCtrl.text.trim().isEmpty
                                  ? selectedCat
                                  : titleCtrl.text.trim();

                              if (existing != null) {
                                await pos.updateOperationalExpense(
                                  existing.copyWith(
                                    title: resolvedTitle,
                                    category: selectedCat,
                                    amount: amount,
                                    createdAt: pickedDate,
                                    notes: notesCtrl.text.trim().isEmpty
                                        ? null
                                        : notesCtrl.text.trim(),
                                  ),
                                );
                              } else {
                                await pos.addOperationalExpense(
                                  title: resolvedTitle,
                                  category: selectedCat,
                                  amount: amount,
                                  createdAt: pickedDate,
                                  notes: notesCtrl.text,
                                );
                              }

                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                                AppTheme.showToast(
                                  context,
                                  message:
                                      'Biaya "$resolvedTitle" berhasil disimpan.',
                                );
                              }
                            },
                            child: Text(
                              existing != null ? 'Perbarui' : 'Simpan Biaya',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<PosProvider>();
    if (!access.isAuthenticated || !access.currentRole.canManageOperationalExpenses) return const AccessDenied();
    final pos = context.watch<PosProvider>();
    final now = DateTime.now();

    final periodItems = pos.operationalExpenses.where((exp) {
      if (_periodFilter == 'Hari Ini') {
        return exp.createdAt.year == now.year &&
            exp.createdAt.month == now.month &&
            exp.createdAt.day == now.day;
      } else if (_periodFilter == 'Bulan Ini') {
        return exp.createdAt.year == now.year &&
            exp.createdAt.month == now.month;
      }
      return true;
    }).toList();

    final categoryTotals = <String, double>{
      for (final c in OperationalExpense.defaultCategories) c: 0.0,
    };
    for (final exp in periodItems) {
      categoryTotals[exp.category] =
          (categoryTotals[exp.category] ?? 0.0) + exp.amount;
    }

    final filteredList = _categoryFilter == 'Semua'
        ? periodItems
        : periodItems.where((e) => e.category == _categoryFilter).toList();

    final totalFiltered = filteredList.fold(0.0, (sum, e) => sum + e.amount);
    final totalPeriod = periodItems.fold(0.0, (sum, e) => sum + e.amount);

    String topCat = '-';
    double topCatAmount = 0.0;
    categoryTotals.forEach((cat, val) {
      if (val > topCatAmount) {
        topCatAmount = val;
        topCat = cat;
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.surfaceLight,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: Column(children: [
          // Header & Action
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Biaya Operasional Warloc',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Listrik, Air, Gas LPG, Kantong Plastik, Es Batu, ATK & kebutuhan toko',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _openExpenseFormDialog(context, pos),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Catat Biaya'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final count = await showDialog<int>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const BatchInsertDialog.expenses(),
                    );
                    if (context.mounted && count != null) {
                      AppTheme.showToast(context, message: '$count biaya tersimpan di perangkat. Sinkronisasi mengikuti status koneksi.');
                    }
                  },
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: const Text('Tambah Sekaligus'),
                ),
              ],
            ),
          ),

          // Summary Strip
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCol(
                    'Total ($_periodFilter)',
                    CurrencyFormatter.format(totalFiltered),
                    AppTheme.dangerRed,
                  ),
                ),
                Container(width: 1, height: 32, color: AppTheme.borderSubtle),
                Expanded(
                  child: _buildStatCol(
                    'Pos Terbesar',
                    topCatAmount > 0 ? topCat : 'Belum Ada',
                    AppTheme.accentAmber,
                  ),
                ),
                Container(width: 1, height: 32, color: AppTheme.borderSubtle),
                Expanded(
                  child: _buildStatCol(
                    'Pencatatan',
                    '${filteredList.length} item',
                    AppTheme.textMain,
                  ),
                ),
              ],
            ),
          ),

          // Category Quick Cards Strip
          SizedBox(
            height: 66 + (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 2) * 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: OperationalExpense.defaultCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final cat = OperationalExpense.defaultCategories[idx];
                final val = categoryTotals[cat] ?? 0.0;
                final pct = totalPeriod > 0
                    ? ((val / totalPeriod) * 100).round()
                    : 0;
                final isSelected = _categoryFilter == cat;
                final color = colorForCategory(cat);

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _categoryFilter = isSelected ? 'Semua' : cat;
                    });
                  },
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.borderSubtle,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.16)
                                : color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            iconForCategory(cat),
                            size: 16,
                            color: isSelected ? Colors.white : color,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                cat,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.85)
                                      : AppTheme.textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${CurrencyFormatter.formatShort(val)} ($pct%)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? Colors.white
                                      : AppTheme.textMain,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Period & Reset Category Chips
          SizedBox(
            height: 36,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in ['Hari Ini', 'Bulan Ini', 'Semua'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Text(p),
                      selected: _periodFilter == p,
                      selectedColor: AppTheme.primary,
                      backgroundColor: AppTheme.cardBg,
                      labelStyle: TextStyle(
                        fontSize: 11.5,
                        fontWeight: _periodFilter == p
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _periodFilter == p
                            ? Colors.white
                            : AppTheme.textSecondary,
                      ),
                      onSelected: (_) => setState(() => _periodFilter = p),
                    ),
                  ),
                if (_categoryFilter != 'Semua') ...[
                  const SizedBox(width: 4),
                  ActionChip(
                    avatar: const Icon(
                      Icons.filter_alt_off_rounded,
                      size: 14,
                      color: AppTheme.accentAmber,
                    ),
                    label: Text('Filter: $_categoryFilter ×'),
                    labelStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentAmber,
                    ),
                    backgroundColor: AppTheme.accentCopperSoft,
                    onPressed: () => setState(() => _categoryFilter = 'Semua'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Expenses List
          ])),
          if (filteredList.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: const BoxDecoration(
                              color: AppTheme.surfaceSubtle,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 30,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Belum ada biaya operasional tercatat',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textMain,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Catat pengeluaran Listrik, Air, Kantong Plastik, Sedotan, atau ATK untuk menghitung laba bersih akurat.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ))
          else
            SliverPadding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), sliver: SliverList.separated(
                    itemCount: filteredList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final exp = filteredList[index];
                      final catColor = colorForCategory(exp.category);
                      return Container(
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.borderSubtle),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _openExpenseFormDialog(
                              context,
                              pos,
                              existing: exp,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(13),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: catColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      iconForCategory(exp.category),
                                      size: 20,
                                      color: catColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                exp.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.textMain,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1.5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.surfaceLight,
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                                border: Border.all(
                                                  color: AppTheme.borderSubtle,
                                                ),
                                              ),
                                              child: Text(
                                                exp.category,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: catColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${CurrencyFormatter.formatDateTime(exp.createdAt)} · ${exp.recordedBy}${exp.notes != null ? " · ${exp.notes}" : ""}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '-${CurrencyFormatter.format(exp.amount)}',
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.dangerRed,
                                          fontFeatures: AppTheme.tabularFigures,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            exp.isSynced
                                                ? Icons.cloud_done_rounded
                                                : Icons.schedule_rounded,
                                            size: 11,
                                            color: exp.isSynced
                                                ? AppTheme.successGreen
                                                : AppTheme.warningOrange,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            exp.isSynced
                                                ? 'Cloud'
                                                : 'Lokal',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: exp.isSynced
                                                  ? AppTheme.successGreen
                                                  : AppTheme.warningOrange,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )),
        ],
      ),
    );
  }

  Widget _buildStatCol(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: valueColor,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
