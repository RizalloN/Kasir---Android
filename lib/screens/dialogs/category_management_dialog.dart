import '../../widgets/access_denied.dart';
import '../../models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';

class CategoryManagementDialog extends StatefulWidget {
  const CategoryManagementDialog({super.key});

  @override
  State<CategoryManagementDialog> createState() => _CategoryManagementDialogState();
}

class _CategoryManagementDialogState extends State<CategoryManagementDialog> {
  final TextEditingController _newCategoryController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  Future<void> _handleAddCategory(PosProvider pos) async {
    final text = _newCategoryController.text.trim();
    if (text.isEmpty) {
      AppTheme.showToast(context, message: 'Masukkan nama kategori terlebih dahulu.', isWarning: true);
      return;
    }

    setState(() => _isSubmitting = true);
    final error = await pos.addCategory(text);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (error == null) {
      _newCategoryController.clear();
      AppTheme.showToast(
        context,
        message: 'Kategori "$text" berhasil ditambahkan!',
        icon: Icons.check_circle_rounded,
      );
    } else {
      AppTheme.showToast(context, message: error, isError: true);
    }
  }

  void _showEditCategoryDialog(BuildContext context, PosProvider pos, String oldName) {
    final editController = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: AppTheme.accentAmber, size: 22),
            SizedBox(width: 8),
            Text('Ubah Nama Kategori', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mengubah nama kategori akan otomatis memperbarui seluruh produk di kategori ini.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: editController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama Kategori',
                hintText: 'Contoh: Makanan Berat',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = editController.text.trim();
              if (newName.isEmpty) return;
              Navigator.of(ctx).pop();

              final error = await pos.updateCategory(oldName, newName);
              if (context.mounted) {
                if (error == null) {
                  AppTheme.showToast(
                    context,
                    message: 'Kategori "$oldName" berhasil diubah menjadi "$newName".',
                    icon: Icons.check_circle_rounded,
                  );
                } else {
                  AppTheme.showToast(context, message: error, isError: true);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, PosProvider pos, String category) {
    final productCount = pos.countProductsInCategory(category);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.dangerRed, size: 24),
            SizedBox(width: 8),
            Text('Hapus Kategori?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          productCount > 0
              ? 'Kategori "$category" memiliki $productCount menu. Jika dihapus, menu tersebut akan dialihkan ke kategori "Umum". Lanjutkan?'
              : 'Yakin ingin menghapus kategori "$category"?',
          style: const TextStyle(fontSize: 13, color: AppTheme.textMain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final error = await pos.deleteCategory(category);
              if (context.mounted) {
                if (error == null) {
                  AppTheme.showToast(
                    context,
                    message: 'Kategori "$category" berhasil dihapus.',
                    icon: Icons.delete_outline_rounded,
                  );
                } else {
                  AppTheme.showToast(context, message: error, isError: true);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<PosProvider>();
    if (!access.isAuthenticated || access.requiresPasswordChange || !(access.currentRole.canManageCategories)) return const AccessDenied();
    final pos = context.watch<PosProvider>();
    final categories = pos.categories;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.accentAmberLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.category_rounded, color: AppTheme.accentAmber, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Kelola Kategori Menu',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain,
                            ),
                          ),
                          Text(
                            'Akses Khusus Admin & Owner',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.roleColor(pos.currentRole),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Add Category Input Box
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newCategoryController,
                        onSubmitted: (_) => _handleAddCategory(pos),
                        decoration: const InputDecoration(
                          hintText: 'Tambah nama kategori baru...',
                          hintStyle: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : () => _handleAddCategory(pos),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Tambah'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Daftar Kategori Terdaftar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMain),
              ),
              const SizedBox(height: 8),

              // Category List
              Flexible(
                child: categories.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Belum ada kategori.', style: TextStyle(color: AppTheme.textMuted)),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: categories.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          final count = pos.countProductsInCategory(category);

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.borderSubtle),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.accentAmber,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Text(
                                        category,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textMain,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.surfaceLight,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '$count menu',
                                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _showEditCategoryDialog(context, pos, category),
                                  icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.textMuted),
                                  tooltip: 'Ubah Nama Kategori',
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  onPressed: categories.length <= 1
                                      ? null
                                      : () => _showDeleteConfirmDialog(context, pos, category),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: categories.length <= 1 ? AppTheme.borderSubtle : AppTheme.dangerRed,
                                  ),
                                  tooltip: categories.length <= 1 ? 'Minimal 1 kategori' : 'Hapus Kategori',
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Tutup'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
