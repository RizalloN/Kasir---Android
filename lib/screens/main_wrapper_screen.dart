import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/user_role.dart';
import '../providers/pos_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/warloc_logo.dart';
import 'auth/login_screen.dart';
import 'barista/pos_screen.dart';
import 'owner/owner_dashboard_screen.dart';
import 'dialogs/user_profile_modal.dart';
import 'dialogs/printer_settings_dialog.dart';
import 'dialogs/edit_product_dialog.dart';
import 'dialogs/category_management_dialog.dart';
import 'dialogs/low_stock_alert_dialog.dart';
import '../services/app_release_service.dart';
import 'dialogs/app_update_dialog.dart';
import 'barista/open_bills_screen.dart';
import 'dialogs/transaction_history_dialog.dart';
import 'dialogs/today_sales_dialog.dart';
import '../services/firestore_sync_safety.dart';

class MainWrapperScreen extends StatefulWidget {
  const MainWrapperScreen({super.key});

  @override
  State<MainWrapperScreen> createState() => _MainWrapperScreenState();
}

class _MainWrapperScreenState extends State<MainWrapperScreen> {
  bool? _cashierMode;
  int _cashierPage = 0;
  String? _selectedBillId;
  int _billSelectionVersion = 0;

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final releases = context.watch<AppReleaseService>();
    final compact = MediaQuery.sizeOf(context).width < 680;

    if (pos.initializationError != null) {
      return Scaffold(body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(pos.initializationError!)))));
    }

    if (!pos.isInitialized) {
      return const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppTheme.espressoDark,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                WarlocLogo(size: 72),
                SizedBox(height: 20),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppTheme.accentGold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!pos.isAuthenticated) {
      return const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: LoginScreen(),
      );
    }


    final canViewReports = pos.currentRole.canViewFinancialReports;
    final showReports = canViewReports && !(_cashierMode ?? (pos.currentRole != UserRole.owner));
    final roleColor = AppTheme.roleColor(pos.currentRole);
    final pendingCount = pos.pendingSyncCount;
    final lowStockAlerts = pos.lowStockProducts;
    final hasOutStock = pos.outOfStockAlertProducts.isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 60,
          titleSpacing: 16,
          title: WarlocLogo(
            size: 36,
            showText: !compact,
            subtitle:
                '${pos.currentUser?.displayName ?? pos.currentRole.shortName} · ${pos.currentRole.shortName}',
          ),
          actions: [
            if (canViewReports)
              IconButton(tooltip: showReports ? 'Buka Kasir' : 'Dashboard Penjualan',
                icon: Icon(showReports ? Icons.point_of_sale : Icons.dashboard_outlined),
                onPressed: () => setState(() { _cashierMode = showReports; if (showReports) _cashierPage = 0; })),
            if (compact)
              PopupMenuButton<String>(
                tooltip: 'Menu Aplikasi',
                onSelected: (action) {
                  switch (action) {
                    case 'sales':
                      showDialog(context: context, builder: (_) => const TodaySalesDialog());
                    case 'bills':
                      setState(() { _cashierMode = true; _cashierPage = 1; });
                    case 'history':
                      setState(() { _cashierMode = true; _cashierPage = 2; });
                    case 'stock':
                      showDialog(context: context, builder: (_) => const LowStockAlertDialog());
                    case 'printer':
                      showDialog(context: context, builder: (_) => const PrinterSettingsDialog());
                    case 'product':
                      showDialog(context: context, builder: (_) => EditProductDialog(onSave: pos.addNewProduct));
                    case 'categories':
                      showDialog(context: context, builder: (_) => const CategoryManagementDialog());
                    case 'update':
                      showDialog(context: context, builder: (_) => const AppUpdateDialog());
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'sales', child: Text('Penjualan Hari Ini')),
                  const PopupMenuItem(value: 'history', child: Text('Riwayat Transaksi')),
                  if (pos.currentRole.canEditProducts)
                    const PopupMenuItem(value: 'stock', child: Text('Peringatan Stok')),
                  if (releases.enabled('thermal_printer'))
                    const PopupMenuItem(value: 'printer', child: Text('Pengaturan Printer')),
                  if (pos.currentRole.canEditProducts)
                    const PopupMenuItem(value: 'product', child: Text('Tambah Menu Baru')),
                  if (pos.currentRole.canManageCategories)
                    const PopupMenuItem(value: 'categories', child: Text('Kelola Kategori')),
                  PopupMenuItem(value: 'update', child: Text(releases.updateAvailable ? 'Pembaruan Tersedia' : 'Pembaruan Aplikasi')),
                ],
              ),
            if (!compact)
              IconButton(tooltip: 'Penjualan Hari Ini', icon: const Icon(Icons.payments_outlined),
                onPressed: () => showDialog(context: context, builder: (_) => const TodaySalesDialog())),
            if (!compact)
              IconButton(
                tooltip: releases.updateAvailable ? 'Pembaruan Tersedia' : 'Pembaruan Aplikasi',
                icon: Badge(isLabelVisible: releases.updateAvailable, child: const Icon(Icons.system_update_rounded)),
                onPressed: () {
                  showDialog(context: context, builder: (_) => const AppUpdateDialog());
                },
              ),
            // Connection state is informational. Only the automatic worker syncs.
            Tooltip(
              message: pos.isOnline
                  ? (pendingCount > 0
                        ? 'Sinkronisasi otomatis: $pendingCount data tertunda'
                        : 'Terhubung ? Sinkronisasi otomatis aktif')
                  : 'Data tersimpan lokal ? Otomatis disinkronkan saat koneksi pulih',
              child: Semantics(
                key: const ValueKey('automatic-sync-status'),
                label: 'Status sinkronisasi otomatis',
                child: SizedBox(
                  width: 40,
                  height: 44,
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: pos.isOnline
                                ? AppTheme.successGreenLight
                                : AppTheme.warningLight,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: pos.isOnline
                                    ? AppTheme.successGreen
                                    : AppTheme.warningOrange,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                        if (pendingCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accentAmber,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$pendingCount',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Low-Stock Inventory Alert Badge (Admin & Owner)
            if (!compact && pos.currentRole.canEditProducts)
              Tooltip(
                message: lowStockAlerts.isEmpty
                    ? 'Inventori Aman'
                    : '${lowStockAlerts.length} Menu Perlu Restock',
                child: InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => const LowStockAlertDialog(),
                    );
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    width: 42,
                    height: 44,
                    child: Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            lowStockAlerts.isEmpty
                                ? Icons.notifications_none_rounded
                                : Icons.notifications_active_rounded,
                            size: 21,
                            color: lowStockAlerts.isEmpty
                                ? AppTheme.textMuted
                                : (hasOutStock
                                      ? AppTheme.dangerRed
                                      : AppTheme.warningOrange),
                          ),
                          if (lowStockAlerts.isNotEmpty)
                            Positioned(
                              right: -5,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: hasOutStock
                                      ? AppTheme.dangerRed
                                      : AppTheme.warningOrange,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${lowStockAlerts.length}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    fontFeatures: AppTheme.tabularFigures,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Printer Settings Button
            if (!compact && releases.enabled('thermal_printer')) IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const PrinterSettingsDialog(),
                );
              },
              icon: Icon(
                pos.isPrinterConnected
                    ? Icons.print_rounded
                    : Icons.print_disabled_rounded,
                color: pos.isPrinterConnected
                    ? AppTheme.textMain
                    : AppTheme.textMuted,
                size: 21,
              ),
              tooltip:
                  'Pengaturan Printer Thermal (${pos.printerPaperWidth}mm)',
            ),

            // Add Product Quick Button (Visible only to Admin or Owner)
            if (!compact && pos.currentRole.canEditProducts)
              IconButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => EditProductDialog(
                      onSave: (newProduct) {
                        pos.addNewProduct(newProduct);
                        AppTheme.showToast(
                          context,
                          message:
                              'Menu "${newProduct.name}" berhasil ditambahkan.',
                        );
                      },
                    ),
                  );
                },
                icon: const Icon(
                  Icons.add_box_outlined,
                  color: AppTheme.textMain,
                  size: 22,
                ),
                tooltip: 'Tambah Menu Baru',
              ),

            // Category Management Button (Visible only to Admin or Owner)
            if (!compact && pos.currentRole.canManageCategories)
              IconButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const CategoryManagementDialog(),
                  );
                },
                icon: const Icon(
                  Icons.category_outlined,
                  color: AppTheme.textMain,
                  size: 21,
                ),
                tooltip: 'Kelola Kategori Menu',
              ),

            const SizedBox(width: 4),

            // User Profile Avatar Button (Opens Account Info, Role & Logout Modal)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Semantics(
                button: true,
                label: 'Profil Pengguna ${pos.currentUser?.displayName ?? ""}',
                child: Tooltip(
                  message: 'Profil Akun & Logout',
                  child: InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => UserProfileModal(pos: pos),
                      );
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        width: 38,
                        height: 38,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: roleColor, width: 1.8),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppTheme.roleBg(pos.currentRole),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              (pos.currentUser?.displayName.isNotEmpty ?? false)
                                  ? pos.currentUser!.displayName[0]
                                        .toUpperCase()
                                  : 'W',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: roleColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          bottom: showReports ? null : PreferredSize(
            preferredSize: const Size.fromHeight(66),
            child: Material(
              color: AppTheme.cardBg,
              child: Row(children: [
                _cashierTab(label: 'Menu', icon: Icons.restaurant_menu_rounded, selected: _cashierPage == 0,
                  onTap: () => setState(() => _cashierPage = 0)),
                _cashierTab(label: 'Open Bill', icon: Icons.receipt_long_outlined, selected: _cashierPage == 1,
                  count: pos.openBills.length, onTap: () => setState(() => _cashierPage = 1)),
                _cashierTab(label: 'Transaksi', icon: Icons.history_rounded, selected: _cashierPage == 2,
                  onTap: () => setState(() => _cashierPage = 2)),
              ]),
            ),
          ),
        ),
        body: SafeArea(top: false, child: Column(children: [
          AnimatedBuilder(
            animation: FirestoreSyncSafety.instance,
            builder: (context, _) {
              final notice = FirestoreSyncSafety.instance.notice;
              return notice == null ? const SizedBox.shrink() : Material(
                color: AppTheme.warningLight,
                child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
                  const Icon(Icons.cloud_off_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(notice)),
                ])),
              );
            },
          ),
          if (releases.updateAvailable)
            Material(
              color: AppTheme.accentCopperSoft,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.system_update_rounded),
                title: Text('Warloc ${releases.release.versionName} tersedia'),
                trailing: TextButton(onPressed: () => showDialog(context: context, builder: (_) => const AppUpdateDialog()), child: const Text('Lihat')),
              ),
            ),
          Expanded(child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: showReports
              ? OwnerDashboardScreen(key: ValueKey('reports_${pos.currentRole.name}'))
              : IndexedStack(key: const ValueKey('cashier_workspace'), index: _cashierPage,
                  children: [PosScreen(key: const ValueKey('pos_surface'), onBillSaved: _billSaved,
                    onBillCancelled: () => setState(() => _cashierPage = 1)),
                    OpenBillsScreen(initialBillId: _selectedBillId, selectionVersion: _billSelectionVersion,
                      onEdit: () => setState(() => _cashierPage = 0), onCreate: () => setState(() => _cashierPage = 0)),
                    const TransactionHistoryView()]),
        )),
        ])),
      ),
    );
  }
  void _billSaved(String id) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() { _cashierMode = true; _cashierPage = 1; _selectedBillId = id; _billSelectionVersion++; });
  }

  Widget _cashierTab({required String label, required IconData icon, required bool selected,
      required VoidCallback onTap, int? count}) {
    final small = MediaQuery.sizeOf(context).width < 600 || MediaQuery.textScalerOf(context).scale(14) > 19;
    final text = Text(!small && count != null ? '$label ($count)' : label, maxLines: 1, softWrap: false,
      style: TextStyle(fontSize: small ? 12 : 14, fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        color: selected ? AppTheme.primary : AppTheme.textSecondary));
    final glyph = Icon(icon, size: 20, color: selected ? AppTheme.accentAmber : AppTheme.textMuted);
    return Expanded(child: Semantics(selected: selected, button: true,
      child: InkWell(key: ValueKey('cashier-tab-${label.toLowerCase().replaceAll(' ', '-')}'),
        onTap: () { FocusManager.instance.primaryFocus?.unfocus(); onTap(); },
        child: AnimatedContainer(duration: const Duration(milliseconds: 180), height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(color: selected ? AppTheme.accentCopperSoft : AppTheme.cardBg,
            border: Border(bottom: BorderSide(color: selected ? AppTheme.accentAmber : AppTheme.borderSubtle, width: selected ? 3 : 1))),
          child: small ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [glyph, const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: text)])
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [glyph, const SizedBox(width: 8), Flexible(child: text)]),
        ),
      ),
    ));
  }
}
