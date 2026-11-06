import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_provider.dart';
import '../../services/thermal_printer_service.dart';
import '../../theme/app_theme.dart';
import '../../services/app_release_service.dart';

class PrinterSettingsDialog extends StatefulWidget {
  const PrinterSettingsDialog({super.key});

  @override
  State<PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends State<PrinterSettingsDialog> {
  final ThermalPrinterService _printerService = ThermalPrinterService.instance;

  List<BluetoothInfo> _pairedDevices = [];
  bool _isLoadingDevices = false;
  bool _isConnecting = false;
  bool _isPrintingTest = false;
  bool _bluetoothEnabled = true;
  String? _selectedMac;
  String? _selectedName;

  @override
  void initState() {
    super.initState();
    _initPrinterState();
  }

  Future<void> _initPrinterState() async {
    final pos = context.read<PosProvider>();
    _selectedMac = pos.selectedPrinterMac.isNotEmpty ? pos.selectedPrinterMac : null;
    _selectedName = pos.selectedPrinterName.isNotEmpty ? pos.selectedPrinterName : null;

    await _checkBluetoothAndFetchDevices();
  }

  Future<void> _checkBluetoothAndFetchDevices() async {
    if (!(context.read<AppReleaseService?>()?.enabled('thermal_printer') ?? true)) return;
    setState(() => _isLoadingDevices = true);
    final pos = context.read<PosProvider>();

    // Android 12+ requires runtime CONNECT permission before adapter access.
    final permitted = await _printerService.isPermissionGranted();
    if (!mounted) return;
    final btOn = permitted && await _printerService.isBluetoothEnabled();
    final connected = await _printerService.isConnected();
    pos.setPrinterConnected(connected);

    List<BluetoothInfo> devices = [];
    if (btOn) {
      devices = await _printerService.getPairedPrinters();
    }

    if (mounted) {
      setState(() {
        _bluetoothEnabled = btOn;
        _pairedDevices = devices;
        _isLoadingDevices = false;

        // Auto-select first device if none selected
        if ((_selectedMac == null || _selectedMac!.isEmpty) && devices.isNotEmpty) {
          _selectedMac = devices.first.macAdress;
          _selectedName = devices.first.name;
          pos.setSelectedPrinter(_selectedName!, _selectedMac!);
        } else if (_selectedMac != null && devices.any((d) => d.macAdress == _selectedMac)) {
          final matched = devices.firstWhere((d) => d.macAdress == _selectedMac);
          _selectedName = matched.name;
        }
      });
    }
  }

  Future<void> _handleConnectToggle(PosProvider pos) async {
    if (!(context.read<AppReleaseService?>()?.enabled('thermal_printer') ?? true)) return;
    if (pos.isPrinterConnected) {
      // Disconnect
      setState(() => _isConnecting = true);
      final res = await _printerService.disconnect();
      if (!mounted) return;
      setState(() => _isConnecting = false);
      await pos.setPrinterConnected(false);

      if (!mounted) return;
      AppTheme.showToast(
        context,
        message: res.message,
        icon: Icons.bluetooth_disabled_rounded,
      );
    } else {
      // Connect
      final mac = _selectedMac ?? pos.selectedPrinterMac;
      if (mac.isEmpty) {
        AppTheme.showToast(
          context,
          message: 'Pilih printer Bluetooth terlebih dahulu dari daftar.',
          isWarning: true,
        );
        return;
      }

      setState(() => _isConnecting = true);
      final res = await _printerService.connect(mac);
      if (!mounted) return;
      setState(() => _isConnecting = false);

      if (res.success) {
        await pos.setSelectedPrinter(_selectedName ?? 'Printer Thermal', mac);
        await pos.setPrinterConnected(true);
        if (!mounted) return;
        AppTheme.showToast(
          context,
          message: 'Terhubung ke ${_selectedName ?? "Printer Thermal"}.',
          icon: Icons.bluetooth_connected_rounded,
        );
      } else {
        await pos.setPrinterConnected(false);
        if (!mounted) return;
        AppTheme.showToast(context, message: res.message, isError: true);
      }
    }
  }

  Future<void> _handlePrintTest(PosProvider pos) async {
    if (!(context.read<AppReleaseService?>()?.enabled('thermal_printer') ?? true)) return;
    setState(() => _isPrintingTest = true);
    final res = await _printerService.printTestReceipt(paperWidth: pos.printerPaperWidth);
    if (!mounted) return;
    setState(() => _isPrintingTest = false);

    if (res.success) {
      AppTheme.showToast(
        context,
        message: res.message,
        icon: Icons.receipt_long_rounded,
      );
    } else {
      AppTheme.showToast(context, message: res.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.accentCopperSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.print_rounded,
                          color: AppTheme.accentAmber,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Flexible(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pengaturan Printer Kasir',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain,
                            ),
                          ),
                          Text(
                            'Driver Thermal ESC/POS Bluetooth',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      )),
                    ],
                  )),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Bluetooth Status Banner
              if (!_bluetoothEnabled) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warningLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.warningOrange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bluetooth_disabled_rounded, color: AppTheme.warningOrange, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Bluetooth perangkat Anda belum aktif. Aktifkan Bluetooth di HP untuk menghubungkan printer.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMain, fontWeight: FontWeight.w500),
                        ),
                      ),
                      IconButton(
                        onPressed: _checkBluetoothAndFetchDevices,
                        icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.primary),
                        tooltip: 'Muat Ulang',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Paper Width Selection
              const Text(
                'Ukuran Kertas Thermal Struk',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildPaperSizeOption(
                      title: '58 mm',
                      subtitle: 'Mini Portable / Bluetooth Kasir',
                      isSelected: pos.printerPaperWidth == 58,
                      onTap: () => pos.setPrinterPaperWidth(58),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPaperSizeOption(
                      title: '80 mm',
                      subtitle: 'Desktop POS / Lebar Standar',
                      isSelected: pos.printerPaperWidth == 80,
                      onTap: () => pos.setPrinterPaperWidth(80),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Bluetooth Device Selection Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pilih Printer Bluetooth (Paired)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                  InkWell(
                    onTap: _isLoadingDevices ? null : _checkBluetoothAndFetchDevices,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        children: [
                          if (_isLoadingDevices)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.8),
                            )
                          else
                            const Icon(Icons.refresh_rounded, size: 14, color: AppTheme.accentAmber),
                          const SizedBox(width: 4),
                          const Text(
                            'Pindai Ulang',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentAmber),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Device Selector Dropdown or Empty Warning
              if (_pairedDevices.isEmpty && !_isLoadingDevices)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.textMuted),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tidak ada printer Bluetooth yang terpasang (paired). Pasangkan printer thermal terlebih dahulu di menu Pengaturan Bluetooth HP.',
                          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _pairedDevices.any((d) => d.macAdress == _selectedMac)
                          ? _selectedMac
                          : (_pairedDevices.isNotEmpty ? _pairedDevices.first.macAdress : null),
                      hint: const Text('Pilih perangkat printer...', style: TextStyle(fontSize: 13)),
                      items: _pairedDevices.map((device) {
                        return DropdownMenuItem<String>(
                          value: device.macAdress,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.bluetooth_rounded,
                                size: 18,
                                color: AppTheme.accentAmber,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      device.name.isNotEmpty ? device.name : 'Printer Thermal',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textMain,
                                      ),
                                    ),
                                    Text(
                                      device.macAdress,
                                      style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (mac) {
                        if (mac != null) {
                          final dev = _pairedDevices.firstWhere((d) => d.macAdress == mac);
                          setState(() {
                            _selectedMac = dev.macAdress;
                            _selectedName = dev.name;
                          });
                          pos.setSelectedPrinter(dev.name, dev.macAdress);
                        }
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 14),

              // Live Status Badge
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: pos.isPrinterConnected
                      ? AppTheme.successGreenLight
                      : AppTheme.surfaceSubtle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: pos.isPrinterConnected
                        ? AppTheme.successGreen.withValues(alpha: 0.3)
                        : AppTheme.borderSubtle,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      pos.isPrinterConnected
                          ? Icons.check_circle_rounded
                          : Icons.link_off_rounded,
                      size: 18,
                      color: pos.isPrinterConnected
                          ? AppTheme.successGreen
                          : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pos.isPrinterConnected
                            ? 'Terhubung · ${pos.selectedPrinterName} (${pos.printerPaperWidth}mm ESC/POS)'
                            : 'Printer belum terhubung · Tekan "Hubungkan" untuk menyambungkan.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: pos.isPrinterConnected
                              ? AppTheme.successGreen
                              : AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Connect and Print Test Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isConnecting
                          ? null
                          : () => _handleConnectToggle(pos),
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              pos.isPrinterConnected
                                  ? Icons.link_off_rounded
                                  : Icons.link_rounded,
                              size: 17,
                            ),
                      label: Text(pos.isPrinterConnected ? 'Putuskan' : 'Hubungkan'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (!pos.isPrinterConnected || _isPrintingTest)
                          ? null
                          : () => _handlePrintTest(pos),
                      icon: _isPrintingTest
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.receipt_long_rounded, size: 17),
                      label: const Text('Cetak Uji Coba'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
  }

  Widget _buildPaperSizeOption({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? AppTheme.accentCopperSoft : AppTheme.cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.accentAmber : AppTheme.borderSubtle,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? AppTheme.accentAmber : AppTheme.textMain,
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
