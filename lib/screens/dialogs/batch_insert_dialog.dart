import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/operational_expense.dart';
import '../../models/product.dart';
import '../../models/user_role.dart';
import '../../providers/pos_provider.dart';
import '../../services/pos_database_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/access_denied.dart';

class BatchInsertDialog extends StatefulWidget {
  final bool isExpense;

  const BatchInsertDialog.menu({super.key}) : isExpense = false;
  const BatchInsertDialog.expenses({super.key}) : isExpense = true;

  @override
  State<BatchInsertDialog> createState() => _BatchInsertDialogState();
}

class _BatchInsertDialogState extends State<BatchInsertDialog> {
  final _formKey = GlobalKey<FormState>();
  final _rows = <_BatchRow>[];
  // Keep IDs stable on retry and distinct even when rows are added rapidly.
  final _batchId = DateTime.now().microsecondsSinceEpoch;
  int _nextRow = 0;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _addRow();
    _addRow();
  }

  void _addRow() {
    final categories = context.read<PosProvider>().categories;
    _rows.add(_BatchRow(
      id: '${widget.isExpense ? 'exp' : 'w'}_${_batchId}_${_nextRow++}',
      category: widget.isExpense
          ? OperationalExpense.defaultCategories.first
          : (categories.contains('Coffee')
              ? 'Coffee'
              : categories.firstOrNull ?? 'Umum'),
    ));
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final invalidFields = _formKey.currentState!.validateGranularly();
    if (invalidFields.isNotEmpty) {
      setState(() => _error =
          'Periksa isian yang ditandai. Belum ada item yang disimpan.');
      await Scrollable.ensureVisible(invalidFields.first.context,
          duration: const Duration(milliseconds: 200));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final pos = context.read<PosProvider>();
      if (widget.isExpense) {
        await pos.addOperationalExpenses(_rows
            .map((row) => OperationalExpense(
                  id: row.id,
                  title: row.name.text,
                  category: row.category,
                  amount: double.parse(row.price.text),
                  createdAt: row.date,
                  recordedBy: '',
                  notes: row.notes.text,
                ))
            .toList());
      } else {
        await pos.addNewProducts(_rows
            .map((row) => Product(
                  id: row.id,
                  name: row.name.text.trim(),
                  category: row.category,
                  drinkOverride: row.drinkOverride,
                  sellPrice: double.parse(row.price.text),
                  baseCost: double.parse(row.cost.text),
                  stock: int.parse(row.stock.text),
                  minStockThreshold: int.parse(row.minimum.text),
                  barcode: 'WLC${row.id.substring(2)}',
                  isAvailable: row.available,
                ))
            .toList());
      }
      if (mounted) Navigator.of(context).pop(_rows.length);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Gagal menyimpan item. Isian tetap tersedia. Periksa akses dan penyimpanan, lalu coba lagi.';
        });
      }
    }
  }

  Future<void> _pickDate(_BatchRow row) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: row.date,
      firstDate: DateTime(2023),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date != null && mounted) {
      setState(() => row.date =
          DateTime(date.year, date.month, date.day, now.hour, now.minute));
    }
  }

  Widget _numberField(_BatchRow row, String field, String label,
      TextEditingController controller,
      {bool positive = false, int? max, bool money = false}) {
    return TextFormField(
      key: ValueKey('${row.id}_$field'),
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration:
          InputDecoration(labelText: label, prefixText: money ? 'Rp ' : null),
      validator: (text) {
        final value =
            money ? double.tryParse(text ?? '') : int.tryParse(text ?? '');
        if (value == null ||
            !value.isFinite ||
            value < 0 ||
            (positive && value <= 0)) {
          return positive ? 'Wajib lebih dari 0.' : 'Isi angka 0 atau lebih.';
        }
        if (max != null && value > max) return 'Maksimal $max.';
        return null;
      },
    );
  }

  Widget _buildRow(_BatchRow row, int index, List<String> categories) {
    return Container(
      key: ValueKey(row.id),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        border: Border.all(color: AppTheme.borderSubtle),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text('Item ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton(
              tooltip: 'Hapus baris ${index + 1}',
              onPressed: _saving || _rows.length == 1
                  ? null
                  : () {
                      setState(() => _rows.remove(row));
                      row.dispose();
                    },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ]),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 520
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            final fields = <Widget>[
              TextFormField(
                key: ValueKey('${row.id}_name'),
                controller: row.name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText:
                      widget.isExpense ? 'Nama biaya (opsional)' : 'Nama menu',
                  hintText: widget.isExpense
                      ? 'Contoh: Pembelian sachet'
                      : 'Contoh: Kopi susu gula aren',
                ),
                validator: (value) =>
                    !widget.isExpense && (value?.trim().isEmpty ?? true)
                        ? 'Nama menu wajib diisi.'
                        : null,
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('${row.id}_category'),
                initialValue: row.category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: {...categories, row.category}
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    final wasEntertainment =
                        row.category.toLowerCase() == 'hiburan';
                    row.category = value;
                    if (!widget.isExpense && value.toLowerCase() == 'hiburan') {
                      row.stock.text = '999';
                      row.minimum.text = '0';
                    } else if (!widget.isExpense && wasEntertainment) {
                      row.stock.text = '20';
                      row.minimum.text = '5';
                    }
                  });
                },
              ),
              _numberField(row, 'price',
                  widget.isExpense ? 'Nominal biaya' : 'Harga jual', row.price,
                  positive: true, money: true),
              if (!widget.isExpense) ...[
                _numberField(row, 'cost', 'Modal / HPP', row.cost, money: true),
                _numberField(row, 'stock', 'Stok awal', row.stock, max: 99999),
                _numberField(row, 'minimum', 'Batas stok minimum', row.minimum,
                    max: 9999),
              ],
              if (widget.isExpense)
                OutlinedButton.icon(
                  onPressed: () => _pickDate(row),
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(CurrencyFormatter.formatDateOnly(row.date)),
                ),
            ];
            return Wrap(
                spacing: 12,
                runSpacing: 16,
                children: fields
                    .map((field) => SizedBox(width: width, child: field))
                    .toList());
          }),
          const SizedBox(height: 12),
          if (widget.isExpense)
            TextFormField(
              key: ValueKey('${row.id}_notes'),
              controller: row.notes,
              minLines: 1,
              maxLines: 3,
              decoration:
                  const InputDecoration(labelText: 'Catatan (opsional)'),
            )
          else ...[
            Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Menu minuman'),
                subtitle: const Text('Pilihan Panas, ES, dan Jumbo'),
                value: row.category.toLowerCase() != 'hiburan' && (row.drinkOverride ?? Product.categoryIsDrink(row.category)),
                onChanged: row.category.toLowerCase() == 'hiburan' ? null : (value) => setState(() => row.drinkOverride = value),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tersedia di kasir'),
                value: row.available,
                onChanged: (value) => setState(() => row.available = value),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    if (!pos.isAuthenticated ||
        pos.requiresPasswordChange ||
        !(widget.isExpense
            ? pos.currentRole.canViewFinancialReports
            : pos.currentRole.canEditProducts)) {
      return const AccessDenied();
    }
    final categories = widget.isExpense
        ? OperationalExpense.defaultCategories
        : pos.categories;
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: AbsorbPointer(
                        absorbing: _saving,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  widget.isExpense
                                      ? 'Catat Biaya Sekaligus'
                                      : 'Tambah Menu Sekaligus',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              const Text(
                                  'Isi beberapa item, lalu simpan bersama. Maksimal 100 item per penyimpanan.'),
                              const SizedBox(height: 12),
                              if (_error != null) ...[
                                Text(_error!,
                                    style: const TextStyle(
                                        color: AppTheme.dangerRed)),
                                const SizedBox(height: 12),
                              ],
                              for (var i = 0; i < _rows.length; i++)
                                _buildRow(_rows[i], i, categories),
                            ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Batal')),
                  OutlinedButton.icon(
                    onPressed: _saving ||
                            _rows.length >=
                                PosDatabaseService.maxBatchInsertItems
                        ? null
                        : () => setState(_addRow),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Tambah Baris'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving
                        ? 'Menyimpan...'
                        : 'Simpan ${_rows.length} Item'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchRow {
  final String id;
  String category;
  final name = TextEditingController();
  final price = TextEditingController();
  final cost = TextEditingController(text: '0');
  final stock = TextEditingController(text: '20');
  final minimum = TextEditingController(text: '5');
  final notes = TextEditingController();
  DateTime date = DateTime.now();
  bool available = true;
  bool? drinkOverride;

  _BatchRow({required this.id, required this.category}) {
    if (category.toLowerCase() == 'hiburan') {
      stock.text = '999';
      minimum.text = '0';
    }
  }

  void dispose() {
    for (final controller in [name, price, cost, stock, minimum, notes]) {
      controller.dispose();
    }
  }
}
