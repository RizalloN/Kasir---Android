import '../../models/user_role.dart';
import '../../widgets/access_denied.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/analytics_charts.dart';
import 'stock_management_screen.dart';
import 'operational_expenses_screen.dart';
import 'reports_screen.dart';
import 'user_management_screen.dart';
import '../barista/receipt_dialog.dart';
import '../dialogs/low_stock_alert_dialog.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isMonthlyView = false; // false = Harian, true = Bulanan
  bool _showExpenseDonut = false; // false = Kategori Menu, true = Operasional
  bool _showTopMenuBars = false; // false = Arus Kas/Benchmark, true = Top Menu

  static const List<Color> _palette = [
    AppTheme.accentAmber,
    AppTheme.roleAdmin,
    AppTheme.primaryLight,
    AppTheme.successGreen,
    Color(0xFF9333EA),
    Color(0xFFDC2626),
    Color(0xFF2563EB),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: context.read<PosProvider>().currentRole.canManageUsers ? 5 : 3,
        vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<PosProvider>();
    if (!access.isAuthenticated || !access.currentRole.canViewFinancialReports) return const AccessDenied();
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final compactTabs = outerConstraints.maxWidth < 540;
        return Scaffold(
          backgroundColor: AppTheme.surfaceLight,
          body: Column(
            children: [
              Container(
                width: double.infinity,
                color: AppTheme.cardBg,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: compactTabs,
                  tabAlignment: compactTabs ? TabAlignment.start : null,
                  indicatorWeight: 2.5,
                  tabs: [
                    const Tab(
                      icon: Icon(Icons.space_dashboard_rounded, size: 19),
                      text: 'Ringkasan',
                    ),
                    const Tab(
                      icon: Icon(Icons.inventory_2_outlined, size: 19),
                      text: 'Stok',
                    ),
                    if (access.currentRole.canManageOperationalExpenses) const Tab(
                      icon: Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 19,
                      ),
                      text: 'Operasional',
                    ),
                    const Tab(
                      icon: Icon(Icons.receipt_long_rounded, size: 19),
                      text: 'Histori',
                    ),
                    if (access.currentRole.canManageUsers) const Tab(
                      icon: Icon(Icons.badge_outlined, size: 19),
                      text: 'Staff',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(context),
                    const StockManagementScreen(),
                    if (access.currentRole.canManageOperationalExpenses) const OperationalExpensesScreen(),
                    const ReportsScreen(),
                    if (access.currentRole.canManageUsers) const UserManagementScreen(isEmbedded: true),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewTab(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final now = DateTime.now();
    final summary = pos.computeRevenueComparison(referenceDate: now);
    final lowStock = pos.lowStockProducts;
    final outStockCount = pos.outOfStockAlertProducts.length;
    final recentTransactions = pos.transactions.take(6).toList();

    final timeSeriesPoints = _isMonthlyView
        ? pos.buildMonthlyDailySeries(monthDate: now)
        : pos.buildDailyHourlySeries(date: now);

    // Donut slices (Category Revenue or Operational Expenses)
    final List<DonutSliceItem> donutSlices = [];
    if (_showExpenseDonut) {
      final expMap = pos.operationalExpenseBreakdown(monthly: _isMonthlyView);
      int idx = 0;
      expMap.forEach((cat, val) {
        if (val > 0) {
          donutSlices.add(
            DonutSliceItem(
              label: cat,
              value: val,
              subtitle: cat,
              color: _palette[idx % _palette.length],
            ),
          );
          idx++;
        }
      });
    } else {
      final catSlices = pos.buildCategoryRevenueBreakdown(
        monthly: _isMonthlyView,
        referenceDate: now,
      );
      for (int i = 0; i < catSlices.length; i++) {
        final c = catSlices[i];
        donutSlices.add(
          DonutSliceItem(
            label: c.category,
            value: c.revenue,
            subtitle: '${c.quantity} item',
            color: _palette[i % _palette.length],
          ),
        );
      }
    }

    // Bar chart items
    final topPeriodProducts = pos
        .topSellingProductsFor(monthly: _isMonthlyView, referenceDate: now)
        .take(5)
        .toList();

    final List<BarChartItem> barItems;
    if (_showTopMenuBars) {
      barItems = [
        for (int i = 0; i < topPeriodProducts.length; i++)
          BarChartItem(
            label: _shortenLabel(topPeriodProducts[i].name),
            fullTitle:
                '${topPeriodProducts[i].name} (${topPeriodProducts[i].quantitySold}x)',
            value: topPeriodProducts[i].revenue,
            color: _palette[i % _palette.length],
          ),
      ];
    } else {
      final activeOmset = _isMonthlyView
          ? summary.currentMonthRevenue
          : summary.todayRevenue;
      final activeGross = _isMonthlyView
          ? summary.currentMonthGrossProfit
          : summary.todayGrossProfit;
      final activeHpp = (activeOmset - activeGross).clamp(0.0, double.infinity);
      final activeOps = _isMonthlyView
          ? summary.currentMonthOperationalExpense
          : summary.todayOperationalExpense;
      final activeNet = _isMonthlyView
          ? summary.currentMonthNetProfit
          : summary.todayNetProfit;

      barItems = [
        BarChartItem(
          label: 'Omset',
          fullTitle: _isMonthlyView ? 'Omset Bulan Ini' : 'Omset Hari Ini',
          value: activeOmset,
          color: AppTheme.accentAmber,
        ),
        BarChartItem(
          label: 'Modal HPP',
          fullTitle: 'Total Modal Pokok (HPP)',
          value: activeHpp,
          color: AppTheme.primaryLight,
        ),
        BarChartItem(
          label: 'Operasional',
          fullTitle: 'Biaya Operasional (Listrik, Air, Plastik, dll)',
          value: activeOps,
          color: AppTheme.dangerRed,
        ),
        BarChartItem(
          label: 'Laba Bersih',
          fullTitle: 'Laba Bersih Operasional',
          value: activeNet,
          color: activeNet >= 0 ? AppTheme.successGreen : AppTheme.dangerRed,
        ),
      ];
    }

    final paymentBreakdown = pos.paymentMethodBreakdownFor(
      monthly: _isMonthlyView,
      referenceDate: now,
    );

    final activeRevenue = _isMonthlyView
        ? summary.currentMonthRevenue
        : summary.todayRevenue;
    final activeTxCount = _isMonthlyView
        ? summary.currentMonthTransactionCount
        : summary.todayTransactionCount;
    final activeGrossProfit = _isMonthlyView
        ? summary.currentMonthGrossProfit
        : summary.todayGrossProfit;
    final activeOpsExpense = _isMonthlyView
        ? summary.currentMonthOperationalExpense
        : summary.todayOperationalExpense;
    final activeNetProfit = _isMonthlyView
        ? summary.currentMonthNetProfit
        : summary.todayNetProfit;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 880;

        final metricCards = [
          _MetricData(
            title: _isMonthlyView
                ? 'Pendapatan Bulan Ini'
                : 'Pendapatan Hari Ini',
            value: CurrencyFormatter.formatShort(activeRevenue),
            subtitle: '$activeTxCount transaksi selesai',
            icon: Icons.payments_outlined,
            accentColor: AppTheme.successGreen,
            accentBg: AppTheme.successGreenLight,
          ),
          _MetricData(
            title: _isMonthlyView
                ? 'Laba Bersih Bulanan'
                : 'Laba Bersih Hari Ini',
            value: CurrencyFormatter.formatShort(activeNetProfit),
            subtitle:
                'Kotor ${CurrencyFormatter.formatShort(activeGrossProfit)} − Ops ${CurrencyFormatter.formatShort(activeOpsExpense)}',
            icon: Icons.trending_up_rounded,
            accentColor: activeNetProfit >= 0
                ? AppTheme.accentAmber
                : AppTheme.dangerRed,
            accentBg: activeNetProfit >= 0
                ? AppTheme.accentCopperSoft
                : AppTheme.dangerLight,
          ),
          _MetricData(
            title: _isMonthlyView
                ? 'Operasional Bulan Ini'
                : 'Operasional Hari Ini',
            value: CurrencyFormatter.formatShort(activeOpsExpense),
            subtitle: 'Listrik, Air, Plastik, Sedotan & ATK',
            icon: Icons.account_balance_wallet_outlined,
            accentColor: AppTheme.roleAdmin,
            accentBg: AppTheme.roleAdminBg,
            onTap: pos.currentRole.canManageOperationalExpenses ? () => _tabController.animateTo(2) : null,
          ),
          _MetricData(
            title: 'Peringatan Stok',
            value: '${lowStock.length} Menu',
            subtitle: lowStock.isEmpty
                ? 'Seluruh inventori aman'
                : '$outStockCount habis · ketuk restock',
            icon: lowStock.isEmpty
                ? Icons.verified_outlined
                : Icons.notifications_active_rounded,
            accentColor: lowStock.isEmpty
                ? AppTheme.successGreen
                : (outStockCount > 0
                      ? AppTheme.dangerRed
                      : AppTheme.warningOrange),
            accentBg: lowStock.isEmpty
                ? AppTheme.successGreenLight
                : (outStockCount > 0
                      ? AppTheme.dangerLight
                      : AppTheme.warningLight),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const LowStockAlertDialog(),
              );
            },
          ),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Control Strip: Harian / Bulanan Mode Switcher + Date Label
              _buildPeriodHeaderBar(now, pos),
              const SizedBox(height: 14),

              // 2. KPI Metric Grid
              if (isWide)
                Row(
                  children: [
                    for (int i = 0; i < metricCards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: _buildMetricCard(metricCards[i])),
                    ],
                  ],
                )
              else ...[
                Row(
                  children: [
                    Expanded(child: _buildMetricCard(metricCards[0])),
                    const SizedBox(width: 12),
                    Expanded(child: _buildMetricCard(metricCards[1])),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildMetricCard(metricCards[2])),
                    const SizedBox(width: 12),
                    Expanded(child: _buildMetricCard(metricCards[3])),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // 3. Today vs MTD & MTM Benchmark Comparison Section
              _buildMtdMtmComparisonPanel(summary, isWide),
              const SizedBox(height: 16),

              // 4. Finalized Low Stock Actionable Banner
              if (lowStock.isNotEmpty) ...[
                _buildLowStockBanner(context, lowStock, outStockCount),
                const SizedBox(height: 16),
              ],

              // 5. Interactive Time-Series Chart (Full Width)
              InteractiveTimeSeriesChart(
                title: _isMonthlyView
                    ? 'Grafik Time-Series Omset Bulanan'
                    : 'Grafik Time-Series Omset Harian (Per 2 Jam)',
                subtitle: _isMonthlyView
                    ? 'Tren pendapatan harian sepanjang ${DateFormat('MMMM yyyy', 'id_ID').format(now)} · Ketuk titik untuk detail'
                    : 'Pergerakan transaksi ${DateFormat('dd MMMM yyyy', 'id_ID').format(now)} · Ketuk grafik untuk inspeksi',
                points: timeSeriesPoints,
              ),
              const SizedBox(height: 14),

              // 6. Donut Chart & Bar Chart Diagram
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: InteractiveDonutChart(
                        title: _showExpenseDonut
                            ? 'Donut Biaya Operasional'
                            : 'Donut Kontribusi Kategori',
                        subtitle: _isMonthlyView
                            ? 'Komposisi bulan berjalan'
                            : 'Komposisi hari ini',
                        slices: donutSlices,
                        trailingHeader: _buildMiniToggle(
                          leftLabel: 'Menu',
                          rightLabel: 'Biaya',
                          isRightActive: _showExpenseDonut,
                          onToggle: (val) =>
                              setState(() => _showExpenseDonut = val),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: InteractiveBarChart(
                        title: _showTopMenuBars
                            ? 'Diagram Batang Top Produk & PS'
                            : 'Diagram Batang Arus Kas',
                        subtitle: _showTopMenuBars
                            ? '5 kontributor omset tertinggi'
                            : 'Omset vs HPP vs Operasional vs Laba Bersih',
                        bars: barItems,
                        trailingHeader: _buildMiniToggle(
                          leftLabel: 'Kas',
                          rightLabel: 'Menu',
                          isRightActive: _showTopMenuBars,
                          onToggle: (val) =>
                              setState(() => _showTopMenuBars = val),
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                InteractiveDonutChart(
                  title: _showExpenseDonut
                      ? 'Donut Biaya Operasional'
                      : 'Donut Kontribusi Kategori',
                  subtitle: _isMonthlyView
                      ? 'Komposisi bulan berjalan'
                      : 'Komposisi hari ini',
                  slices: donutSlices,
                  trailingHeader: _buildMiniToggle(
                    leftLabel: 'Menu',
                    rightLabel: 'Biaya',
                    isRightActive: _showExpenseDonut,
                    onToggle: (val) => setState(() => _showExpenseDonut = val),
                  ),
                ),
                const SizedBox(height: 14),
                InteractiveBarChart(
                  title: _showTopMenuBars
                      ? 'Diagram Batang Top Produk & PS'
                      : 'Diagram Batang Arus Kas',
                  subtitle: _showTopMenuBars
                      ? '5 kontributor omset tertinggi'
                      : 'Omset vs HPP vs Operasional vs Laba Bersih',
                  bars: barItems,
                  trailingHeader: _buildMiniToggle(
                    leftLabel: 'Kas',
                    rightLabel: 'Menu',
                    isRightActive: _showTopMenuBars,
                    onToggle: (val) => setState(() => _showTopMenuBars = val),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // 7. Top Selling Menu & Cash/QRIS Payment Breakdown
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildTopProductsPanel(
                        topPeriodProducts.take(4).toList(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: _buildPaymentBreakdownPanel(paymentBreakdown),
                    ),
                  ],
                )
              else ...[
                _buildTopProductsPanel(topPeriodProducts.take(4).toList()),
                const SizedBox(height: 12),
                _buildPaymentBreakdownPanel(paymentBreakdown),
              ],
              const SizedBox(height: 20),

              // 8. Live Transaction Feed
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Aktivitas Transaksi Terbaru',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _tabController.animateTo(pos.currentRole.canManageOperationalExpenses ? 3 : 2),
                    child: const Text('Lihat Semua'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (recentTransactions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 32,
                        color: AppTheme.textMuted,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Belum ada transaksi tercatat',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Transaksi kasir & rental PS akan tampil otomatis di sini.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: recentTransactions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final tx = recentTransactions[index];
                    return _buildRecentTxTile(context, tx);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPeriodHeaderBar(DateTime now, PosProvider pos) {
    final periodTitle = _isMonthlyView
        ? DateFormat('MMMM yyyy', 'id_ID').format(now)
        : DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(now);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.analytics_outlined,
                size: 20,
                color: AppTheme.accentAmber,
              ),
              const SizedBox(width: 8),
              Flexible(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isMonthlyView
                        ? 'Ringkasan Eksekutif Bulanan'
                        : 'Ringkasan Eksekutif Harian',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                    ),
                  ),
                  Text(
                    periodTitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              )),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppTheme.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _buildSegmentButton(
                  label: 'Harian',
                  icon: Icons.today_rounded,
                  selected: !_isMonthlyView,
                  onTap: () => setState(() => _isMonthlyView = false),
                ),
                const SizedBox(width: 4),
                _buildSegmentButton(
                  label: 'Bulanan',
                  icon: Icons.calendar_month_rounded,
                  selected: _isMonthlyView,
                  onTap: () => setState(() => _isMonthlyView = true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppTheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : AppTheme.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders Pendapatan Hari Ini & Bulanan vs MTD (Last day of previous month)
  /// and MTM (Same day of previous month), collapsing MTM into MTD when at month-end.
  Widget _buildMtdMtmComparisonPanel(
    RevenueComparisonSummary summary,
    bool isWide,
  ) {
    final prevEndStr = DateFormat(
      'dd MMM yyyy',
      'id_ID',
    ).format(summary.prevMonthLastDate);
    final prevSameStr = DateFormat(
      'dd MMM yyyy',
      'id_ID',
    ).format(summary.prevMonthSameDate);
    final prevMonthName = DateFormat(
      'MMM yyyy',
      'id_ID',
    ).format(summary.prevMonthLastDate);
    final todayStr = DateFormat(
      'dd MMM yyyy',
      'id_ID',
    ).format(summary.referenceDate);

    // Anchor & Benchmark values depending on Harian vs Bulanan view
    final anchorLabel = _isMonthlyView
        ? 'Pendapatan Bulan Ini (1–${summary.referenceDate.day} ${DateFormat('MMM', 'id_ID').format(summary.referenceDate)})'
        : 'Pendapatan Hari Ini ($todayStr)';
    final anchorValue = _isMonthlyView
        ? summary.currentMonthRevenue
        : summary.todayRevenue;
    final secondaryAnchorNote = _isMonthlyView
        ? 'Pendapatan Hari Ini: ${CurrencyFormatter.format(summary.todayRevenue)}'
        : 'Akumulasi Bulan Ini: ${CurrencyFormatter.format(summary.currentMonthRevenue)}';

    final mtdBaseline = _isMonthlyView
        ? summary.prevMonthFullRevenue
        : summary.mtdPrevMonthLastDayRevenue;
    final mtdDelta = _isMonthlyView
        ? summary.monthVsMtdDelta
        : summary.todayVsMtdDelta;
    final mtdPct = _isMonthlyView
        ? summary.monthVsMtdPct
        : summary.todayVsMtdPct;
    final mtdSubtitle = _isMonthlyView
        ? 'Total Akhir Bulan Kemarin (1–${summary.prevMonthLastDate.day} $prevMonthName)'
        : 'Akhir Bulan Kemarin (Tgl $prevEndStr)';

    final mtmBaseline = _isMonthlyView
        ? summary.prevMonthMtmCumulativeRevenue
        : summary.mtmPrevMonthSameDayRevenue;
    final mtmDelta = _isMonthlyView
        ? summary.monthVsMtmDelta
        : summary.todayVsMtmDelta;
    final mtmPct = _isMonthlyView
        ? summary.monthVsMtmPct
        : summary.todayVsMtmPct;
    final mtmSubtitle = _isMonthlyView
        ? 'Periode Sama Bulan Lalu (1–${summary.prevMonthSameDate.day} $prevMonthName)'
        : 'Tanggal Sama Bulan Lalu (Tgl $prevSameStr)';

    final mtdCard = _buildBenchmarkSubCard(
      badge: 'MTD',
      title: mtdSubtitle,
      baselineAmount: mtdBaseline,
      deltaAmount: mtdDelta,
      pctChange: mtdPct,
      accent: AppTheme.accentAmber,
    );

    final mtmCard = summary.collapseMtmIntoMtd
        ? null
        : _buildBenchmarkSubCard(
            badge: 'MTM',
            title: mtmSubtitle,
            baselineAmount: mtmBaseline,
            deltaAmount: mtmDelta,
            pctChange: mtmPct,
            accent: AppTheme.roleAdmin,
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.compare_arrows_rounded,
                    size: 19,
                    color: AppTheme.primary,
                  ),
                  SizedBox(width: 7),
                  Flexible(child: Text(
                    'Komparasi Pendapatan (MTD & MTM)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                    ),
                  )),
                ],
              ),
              if (summary.collapseMtmIntoMtd)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCopperSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Akhir Bulan: MTM = MTD (Ditampilkan MTD)',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentAmber,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Primary Anchor Strip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anchorLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(anchorValue),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFFFBEB),
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    secondaryAnchorNote,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentGold,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (mtmCard == null)
            mtdCard
          else if (isWide)
            Row(
              children: [
                Expanded(child: mtdCard),
                const SizedBox(width: 12),
                Expanded(child: mtmCard),
              ],
            )
          else ...[
            mtdCard,
            const SizedBox(height: 10),
            mtmCard,
          ],
        ],
      ),
    );
  }

  Widget _buildBenchmarkSubCard({
    required String badge,
    required String title,
    required double baselineAmount,
    required double deltaAmount,
    required double? pctChange,
    required Color accent,
  }) {
    final isPositive = deltaAmount >= 0;
    final trendColor = deltaAmount == 0
        ? AppTheme.textMuted
        : (isPositive ? AppTheme.successGreen : AppTheme.dangerRed);
    final trendBg = deltaAmount == 0
        ? AppTheme.surfaceSubtle
        : (isPositive ? AppTheme.successGreenLight : AppTheme.dangerLight);
    final sign = deltaAmount > 0 ? '+' : '';
    final pctText = pctChange != null
        ? '$sign${pctChange.toStringAsFixed(1)}%'
        : (deltaAmount > 0 ? 'Baru' : '0%');

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: accent,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: trendBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPositive
                          ? Icons.north_east_rounded
                          : Icons.south_east_rounded,
                      size: 12,
                      color: trendColor,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      pctText,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: trendColor,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pembanding',
                    style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                  ),
                  Text(
                    CurrencyFormatter.format(baselineAmount),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Selisih',
                    style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                  ),
                  Text(
                    '$sign${CurrencyFormatter.format(deltaAmount)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: trendColor,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockBanner(
    BuildContext context,
    List lowStock,
    int outStockCount,
  ) {
    final isCritical = outStockCount > 0;
    final color = isCritical ? AppTheme.dangerRed : AppTheme.warningOrange;
    final bg = isCritical ? AppTheme.dangerLight : AppTheme.warningLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_rounded, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCritical
                      ? 'Peringatan Inventori Kritis ($outStockCount Habis)'
                      : 'Peringatan Inventori Menipis (${lowStock.length} Menu)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lowStock
                      .map((p) => '${p.name} (sisa ${p.stock})')
                      .join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMain,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const LowStockAlertDialog(),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: color,
              backgroundColor: Colors.white.withValues(alpha: 0.8),
            ),
            child: const Text('Restock'),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniToggle({
    required String leftLabel,
    required String rightLabel,
    required bool isRightActive,
    required ValueChanged<bool> onToggle,
  }) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => onToggle(false),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: !isRightActive ? AppTheme.cardBg : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                leftLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: !isRightActive
                      ? FontWeight.w800
                      : FontWeight.w600,
                  color: !isRightActive
                      ? AppTheme.textMain
                      : AppTheme.textMuted,
                ),
              ),
            ),
          ),
          InkWell(
            onTap: () => onToggle(true),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isRightActive ? AppTheme.cardBg : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                rightLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isRightActive ? FontWeight.w800 : FontWeight.w600,
                  color: isRightActive ? AppTheme.textMain : AppTheme.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortenLabel(String name) {
    final clean = name.replaceAll('Warloc', '').trim();
    if (clean.length <= 11) return clean;
    return '${clean.substring(0, 10)}…';
  }

  Widget _buildRecentTxTile(BuildContext context, dynamic tx) {
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
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => ReceiptDialog(transaction: tx, allowVoid: true),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tx.isVoided
                        ? AppTheme.dangerLight
                        : AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    tx.isVoided ? Icons.block_rounded : Icons.receipt_outlined,
                    size: 19,
                    color: tx.isVoided ? AppTheme.dangerRed : AppTheme.textMain,
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
                              tx.invoiceNumber,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
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
                          if (tx.isVoided) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.dangerLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'VOID',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.dangerRed,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${tx.cashierName} · ${CurrencyFormatter.formatTimeOnly(tx.createdAt)} · ${PosProvider.normalizePaymentMethod(tx.paymentMethod)} (${tx.orderType})',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.format(tx.totalAmount),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: tx.isVoided
                            ? AppTheme.textMuted
                            : AppTheme.textMain,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                    if (!tx.isVoided)
                      Text(
                        '+${CurrencyFormatter.format(tx.totalProfit)} kotor',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.successGreen,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(_MetricData data) {
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
          onTap: data.onTap,
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
                      child: Text(
                        data.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: data.accentBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(data.icon, size: 16, color: data.accentColor),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: data.accentColor == AppTheme.dangerRed
                        ? AppTheme.dangerRed
                        : AppTheme.textMain,
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopProductsPanel(List<TopProductStat> topProducts) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_fire_department_outlined,
                size: 18,
                color: AppTheme.accentAmber,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(
                _isMonthlyView
                    ? 'Menu & Hiburan Terlaris (Bulan Ini)'
                    : 'Menu & Hiburan Terlaris (Hari Ini)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                ),
              )),
            ],
          ),
          const SizedBox(height: 12),
          if (topProducts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Data penjualan periode ini akan tampil setelah ada transaksi.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            )
          else
            ...topProducts.asMap().entries.map((entry) {
              final idx = entry.key;
              final stat = entry.value;
              final isHiburan =
                  stat.category.trim().toLowerCase() == 'hiburan';
              return Padding(
                padding: EdgeInsets.only(
                  bottom: idx == topProducts.length - 1 ? 0 : 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: idx == 0
                            ? AppTheme.accentCopperSoft
                            : AppTheme.surfaceSubtle,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: idx == 0
                              ? AppTheme.accentAmber
                              : AppTheme.textSecondary,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        stat.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${stat.quantitySold} ${isHiburan ? "jam" : "terjual"}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      CurrencyFormatter.formatShort(stat.revenue),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Payment Breakdown restricted strictly to Cash & QRIS only
  Widget _buildPaymentBreakdownPanel(Map<String, double> breakdown) {
    final total = breakdown.values.fold(0.0, (sum, v) => sum + v);
    final entries = [
      ('Cash', breakdown['Cash'] ?? 0.0, AppTheme.successGreen),
      ('QRIS', breakdown['QRIS'] ?? 0.0, AppTheme.accentAmber),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: AppTheme.textMain,
              ),
              SizedBox(width: 6),
              Expanded(child: Text(
                'Metode Pembayaran (Cash & QRIS)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                ),
              )),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Builder(
              builder: (_) {
                final (label, amount, color) = entries[i];
                final ratio = total > 0
                    ? (amount / total).clamp(0.0, 1.0)
                    : 0.0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          '${CurrencyFormatter.format(amount)} (${(ratio * 100).round()}%)',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                            fontFeatures: AppTheme.tabularFigures,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 7,
                        backgroundColor: AppTheme.surfaceSubtle,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricData {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Color accentBg;
  final VoidCallback? onTap;

  const _MetricData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.accentBg,
    this.onTap,
  });
}
