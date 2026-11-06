import '../../models/user_role.dart';
import '../../widgets/access_denied.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/operational_expense.dart';
import '../../models/transaction.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../barista/receipt_dialog.dart';
import 'operational_expenses_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _periodFilter = 'Semua'; // Semua, Hari Ini, 7 Hari, Bulan Ini
  String _methodFilter = 'Semua'; // Semua, Cash, QRIS
  String _activeView = 'Transaksi'; // Transaksi, Operasional

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showProfitBreakdownDialog({
    required BuildContext context,
    required double revenue,
    required double cogs,
    required double grossProfit,
    required double opsExpense,
    required double netProfit,
    required List<OperationalExpense> expenses,
    required String period,
  }) {
    final catBreakdown = <String, double>{};
    for (final e in expenses) {
      catBreakdown[e.category] = (catBreakdown[e.category] ?? 0.0) + e.amount;
    }

    final netMargin = revenue > 0 ? (netProfit / revenue) * 100 : 0.0;
    final isProfitable = netProfit >= 0;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
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
                            color: isProfitable
                                ? AppTheme.successGreenLight
                                : AppTheme.dangerLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isProfitable
                                ? Icons.account_balance_rounded
                                : Icons.warning_rounded,
                            size: 20,
                            color: isProfitable
                                ? AppTheme.successGreen
                                : AppTheme.dangerRed,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Audit Laba Operasional',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textMain,
                              ),
                            ),
                            Text(
                              'Periode: $period',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
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

                // Calculation Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      _buildAuditRow(
                        '1. Omset Penjualan Kotor (A)',
                        CurrencyFormatter.format(revenue),
                        AppTheme.textMain,
                      ),
                      const SizedBox(height: 6),
                      _buildAuditRow(
                        '2. Modal Pokok HPP (B)',
                        CurrencyFormatter.format(cogs),
                        AppTheme.textMuted,
                      ),
                      const Divider(height: 16),
                      _buildAuditRow(
                        'Laba Kotor Toko (C = A − B)',
                        CurrencyFormatter.format(grossProfit),
                        AppTheme.successGreen,
                        isBold: true,
                      ),
                      const SizedBox(height: 6),
                      _buildAuditRow(
                        '3. Biaya Operasional Toko (D)',
                        '-${CurrencyFormatter.format(opsExpense)}',
                        AppTheme.dangerRed,
                      ),
                      const Divider(height: 16),
                      _buildAuditRow(
                        'Laba Bersih Operasional (E = C − D)',
                        CurrencyFormatter.format(netProfit),
                        isProfitable ? AppTheme.successGreen : AppTheme.dangerRed,
                        isBold: true,
                        fontSize: 14.5,
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Margin Bersih: ${netMargin.toStringAsFixed(1)}% dari Omset',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isProfitable
                                ? AppTheme.successGreen
                                : AppTheme.dangerRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Rincian Biaya Operasional Masuk Hitungan:',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 8),

                if (expenses.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Belum ada biaya operasional tercatat pada periode ini.',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                    ),
                  )
                else ...[
                  for (final entry in catBreakdown.entries) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            OperationalExpensesScreen.iconForCategory(entry.key),
                            size: 15,
                            color: OperationalExpensesScreen.colorForCategory(
                              entry.key,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMain,
                              ),
                            ),
                          ),
                          Text(
                            CurrencyFormatter.format(entry.value),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.dangerRed,
                              fontFeatures: AppTheme.tabularFigures,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Tutup'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuditRow(
    String label,
    String value,
    Color color, {
    bool isBold = false,
    double fontSize = 12.5,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
            color: AppTheme.textMain,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
            color: color,
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<PosProvider>();
    if (!access.isAuthenticated || !access.currentRole.canViewFinancialReports) return const AccessDenied();
    final pos = context.watch<PosProvider>();
    final now = DateTime.now();
    final query = _searchController.text.trim().toLowerCase();

    // 1. Filter Transactions
    final filteredTransactions = pos.transactions.where((tx) {
      if (_periodFilter == 'Hari Ini') {
        final sameDay = tx.createdAt.year == now.year &&
            tx.createdAt.month == now.month &&
            tx.createdAt.day == now.day;
        if (!sameDay) return false;
      } else if (_periodFilter == '7 Hari') {
        if (now.difference(tx.createdAt).inDays > 7) return false;
      } else if (_periodFilter == 'Bulan Ini') {
        final sameMonth = tx.createdAt.year == now.year &&
            tx.createdAt.month == now.month;
        if (!sameMonth) return false;
      }

      if (_methodFilter != 'Semua' &&
          PosProvider.normalizePaymentMethod(tx.paymentMethod) !=
              _methodFilter) {
        return false;
      }

      if (query.isNotEmpty) {
        final matchInv = tx.invoiceNumber.toLowerCase().contains(query);
        final matchCashier = tx.cashierName.toLowerCase().contains(query);
        final matchCust =
            tx.customerName?.toLowerCase().contains(query) ?? false;
        if (!matchInv && !matchCashier && !matchCust) return false;
      }
      return true;
    }).toList();

    // 2. Filter Operational Expenses in matching period
    final filteredExpenses = pos.operationalExpenses.where((exp) {
      if (_periodFilter == 'Hari Ini') {
        return exp.createdAt.year == now.year &&
            exp.createdAt.month == now.month &&
            exp.createdAt.day == now.day;
      } else if (_periodFilter == '7 Hari') {
        return now.difference(exp.createdAt).inDays <= 7;
      } else if (_periodFilter == 'Bulan Ini') {
        return exp.createdAt.year == now.year &&
            exp.createdAt.month == now.month;
      }
      return true;
    }).toList();

    final activeFiltered =
        filteredTransactions.where((t) => !t.isVoided).toList();
    final periodRevenue =
        activeFiltered.fold(0.0, (sum, t) => sum + t.totalAmount);
    final periodCogs = activeFiltered.fold(0.0, (sum, t) => sum + t.totalCost);
    final periodGrossProfit =
        activeFiltered.fold(0.0, (sum, t) => sum + t.totalProfit);
    final periodOpsExpense =
        filteredExpenses.fold(0.0, (sum, e) => sum + e.amount);
    final periodNetProfit = periodGrossProfit - periodOpsExpense;

    return Scaffold(
      backgroundColor: AppTheme.surfaceLight,
      body: Column(
        children: [
          // Filtered Financial Summary Strip (Complete with Operational Costs & Net Profit)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryColumn(
                        'Omset Penjualan',
                        CurrencyFormatter.formatShort(periodRevenue),
                        AppTheme.textMain,
                        subtitle: '${activeFiltered.length} struk',
                      ),
                    ),
                    Container(width: 1, height: 34, color: AppTheme.borderSubtle),
                    Expanded(
                      child: _buildSummaryColumn(
                        'Laba Kotor',
                        CurrencyFormatter.formatShort(periodGrossProfit),
                        AppTheme.successGreen,
                        subtitle: 'Omset − HPP',
                      ),
                    ),
                    Container(width: 1, height: 34, color: AppTheme.borderSubtle),
                    Expanded(
                      child: _buildSummaryColumn(
                        'Operasional',
                        CurrencyFormatter.formatShort(periodOpsExpense),
                        AppTheme.dangerRed,
                        subtitle: '${filteredExpenses.length} pos biaya',
                      ),
                    ),
                    Container(width: 1, height: 34, color: AppTheme.borderSubtle),
                    Expanded(
                      child: _buildSummaryColumn(
                        'Laba Bersih',
                        CurrencyFormatter.formatShort(periodNetProfit),
                        periodNetProfit >= 0
                            ? AppTheme.accentAmber
                            : AppTheme.dangerRed,
                        subtitle: 'Kotor − Ops',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _showProfitBreakdownDialog(
                    context: context,
                    revenue: periodRevenue,
                    cogs: periodCogs,
                    grossProfit: periodGrossProfit,
                    opsExpense: periodOpsExpense,
                    netProfit: periodNetProfit,
                    expenses: filteredExpenses,
                    period: _periodFilter,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calculate_outlined,
                          size: 15,
                          color: AppTheme.primary,
                        ),
                        SizedBox(width: 6),
                        Flexible(child: Text(
                          'Lihat Audit & Perhitungan Rincian Laba Operasional',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        )),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 11,
                          color: AppTheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search & Filter Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Cari nomor struk, kasir, atau pelanggan...',
                  fillColor: AppTheme.cardBg,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 19,
                    color: AppTheme.textMuted,
                  ),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 17),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          SizedBox(
            height: 36,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in ['Semua', 'Hari Ini', '7 Hari', 'Bulan Ini'])
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: VerticalDivider(width: 1),
                ),
                for (final m in ['Semua', 'Cash', 'QRIS'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Text(m == 'Semua' ? 'Semua Metode' : m),
                      selected: _methodFilter == m,
                      selectedColor: AppTheme.accentAmber,
                      backgroundColor: AppTheme.cardBg,
                      labelStyle: TextStyle(
                        fontSize: 11.5,
                        fontWeight: _methodFilter == m
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _methodFilter == m
                            ? Colors.white
                            : AppTheme.textSecondary,
                      ),
                      onSelected: (_) => setState(() => _methodFilter = m),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Tab Switcher between Transactions and Operational Expenses
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _activeView = 'Transaksi'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: _activeView == 'Transaksi'
                            ? AppTheme.primary
                            : AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _activeView == 'Transaksi'
                              ? AppTheme.primary
                              : AppTheme.borderSubtle,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Struk Penjualan (${filteredTransactions.length})',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _activeView == 'Transaksi'
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _activeView = 'Operasional'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: _activeView == 'Operasional'
                            ? AppTheme.roleAdmin
                            : AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _activeView == 'Operasional'
                              ? AppTheme.roleAdmin
                              : AppTheme.borderSubtle,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Biaya Operasional (${filteredExpenses.length})',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _activeView == 'Operasional'
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // List Display (Transactions or Operational Expenses)
          Expanded(
            child: _activeView == 'Transaksi'
                ? (filteredTransactions.isEmpty
                      ? const Center(
                          child: Text(
                            'Tidak ada riwayat transaksi pada filter ini.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filteredTransactions.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _buildTransactionCard(
                              context,
                              filteredTransactions[index],
                            );
                          },
                        ))
                : (filteredExpenses.isEmpty
                      ? const Center(
                          child: Text(
                            'Tidak ada biaya operasional pada filter ini.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filteredExpenses.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _buildExpenseCard(filteredExpenses[index]);
                          },
                        )),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryColumn(
    String label,
    String value,
    Color color, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 1),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpenseCard(OperationalExpense exp) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: OperationalExpensesScreen.colorForCategory(
                exp.category,
              ).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              OperationalExpensesScreen.iconForCategory(exp.category),
              size: 20,
              color: OperationalExpensesScreen.colorForCategory(exp.category),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        exp.title,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceSubtle,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        exp.category,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${CurrencyFormatter.formatDateTime(exp.createdAt)} · Oleh ${exp.recordedBy}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                if (exp.notes != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    exp.notes!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '-${CurrencyFormatter.format(exp.amount)}',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: AppTheme.dangerRed,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(BuildContext context, TransactionRecord tx) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tx.isVoided
              ? AppTheme.dangerRed.withValues(alpha: 0.3)
              : AppTheme.borderSubtle,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => ReceiptDialog(
                transaction: tx,
                allowVoid: true,
              ),
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              tx.invoiceNumber,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: tx.isVoided
                                    ? AppTheme.textMuted
                                    : AppTheme.textMain,
                                decoration: tx.isVoided
                                    ? TextDecoration.lineThrough
                                    : null,
                                fontFeatures: AppTheme.tabularFigures,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildOrderTypeBadge(tx.orderType),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      CurrencyFormatter.format(tx.totalAmount),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: tx.isVoided
                            ? AppTheme.textMuted
                            : AppTheme.textMain,
                        decoration: tx.isVoided
                            ? TextDecoration.lineThrough
                            : null,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      tx.paymentMethod == 'QRIS'
                          ? Icons.qr_code_2_rounded
                          : Icons.payments_rounded,
                      size: 14,
                      color: tx.paymentMethod == 'QRIS'
                          ? AppTheme.accentAmber
                          : AppTheme.successGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tx.paymentMethod,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: tx.paymentMethod == 'QRIS'
                            ? AppTheme.accentAmber
                            : AppTheme.successGreen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('•', style: TextStyle(color: AppTheme.borderSubtle)),
                    const SizedBox(width: 8),
                    Text(
                      CurrencyFormatter.formatDateTime(tx.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Kasir: ${tx.cashierName}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    Row(
                      children: [
                        if (tx.isVoided)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.dangerLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'BATAL / VOID',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.dangerRed,
                              ),
                            ),
                          )
                        else
                          Text(
                            'Laba +${CurrencyFormatter.format(tx.totalProfit)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.successGreen,
                              fontFeatures: AppTheme.tabularFigures,
                            ),
                          ),
                        const SizedBox(width: 8),
                        _buildSyncStatusBadge(tx.isSynced),
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
  }

  Widget _buildOrderTypeBadge(String orderType) {
    final isDineIn = orderType == 'Dine-In';
    final text = isDineIn ? 'Dine In' : 'Take Away';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildSyncStatusBadge(bool isSynced) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: isSynced ? AppTheme.successGreenLight : AppTheme.warningLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSynced ? Icons.cloud_done_rounded : Icons.schedule_rounded,
            size: 12,
            color: isSynced ? AppTheme.successGreen : AppTheme.warningOrange,
          ),
          const SizedBox(width: 4),
          Text(
            isSynced ? 'Tersinkron' : 'Tertunda',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isSynced ? AppTheme.successGreen : AppTheme.warningOrange,
            ),
          ),
        ],
      ),
    );
  }
}
