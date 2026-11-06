import '../../models/user_role.dart';
import '../../widgets/access_denied.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_profile.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';

class UserManagementScreen extends StatefulWidget {
  final bool isEmbedded;

  const UserManagementScreen({
    super.key,
    this.isEmbedded = false,
  });

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  void _openUserFormDialog(BuildContext context, {UserProfile? userToEdit}) {
    final isEditing = userToEdit != null;
    final pos = context.read<PosProvider>();
    final isSelf = isEditing && pos.currentUser?.id == userToEdit.id;
    final isPrimaryOwner =
        isEditing &&
        (userToEdit.username.toLowerCase() == 'warloc.owner' ||
            userToEdit.username.toLowerCase() == 'iggoys');

    final usernameController =
        TextEditingController(text: userToEdit?.username ?? '');
    final nameController =
        TextEditingController(text: userToEdit?.displayName ?? '');
    final passwordController = TextEditingController();

    UserRole selectedRole = userToEdit?.role ?? UserRole.barista;
    bool isActive = userToEdit?.isActive ?? true;
    bool obscurePassword = true;
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
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
                              child: Icon(
                                isEditing
                                    ? Icons.manage_accounts_rounded
                                    : Icons.person_add_alt_1_rounded,
                                color: AppTheme.accentAmber,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isEditing ? 'Ubah Profil Staff' : 'Tambah Staff Baru',
                              style: const TextStyle(
                                fontSize: 17,
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

                    if (dialogError != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.dangerLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.dangerRed.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: AppTheme.dangerRed,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dialogError!,
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
                      'Username Login',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: usernameController,
                      enabled: !isPrimaryOwner,
                      autocorrect: false,
                      onChanged: (_) {
                        if (dialogError != null) {
                          setDialogState(() => dialogError = null);
                        }
                      },
                      decoration: const InputDecoration(
                        hintText: 'Contoh: warloc.kasir2',
                        prefixIcon: Icon(
                          Icons.alternate_email_rounded,
                          size: 18,
                          color: AppTheme.accentAmber,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'Nama Lengkap / Tampilan Kasir',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      onChanged: (_) {
                        if (dialogError != null) {
                          setDialogState(() => dialogError = null);
                        }
                      },
                      decoration: const InputDecoration(
                        hintText: 'Contoh: Rian Barista',
                        prefixIcon: Icon(
                          Icons.badge_outlined,
                          size: 18,
                          color: AppTheme.accentAmber,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'Level Hak Akses',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildRoleChip(
                          role: UserRole.barista,
                          label: 'Barista',
                          selected: selectedRole,
                          enabled: !isPrimaryOwner,
                          onSelect: (r) => setDialogState(() => selectedRole = r),
                        ),
                        const SizedBox(width: 8),
                        _buildRoleChip(
                          role: UserRole.admin,
                          label: 'Admin',
                          selected: selectedRole,
                          enabled: !isPrimaryOwner,
                          onSelect: (r) => setDialogState(() => selectedRole = r),
                        ),
                        const SizedBox(width: 8),
                        _buildRoleChip(
                          role: UserRole.owner,
                          label: 'Owner',
                          selected: selectedRole,
                          enabled: true,
                          onSelect: (r) => setDialogState(() => selectedRole = r),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing
                              ? 'Ubah Password (Opsional)'
                              : 'Password Akun (Alfanumerik)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const Text(
                          'SHA-256 + Salt',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.successGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        hintText: isEditing
                            ? 'Kosongkan bila tidak diganti'
                            : 'Huruf, angka, atau simbol',
                        prefixIcon: const Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: AppTheme.accentAmber,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18,
                          ),
                          onPressed: () =>
                              setDialogState(() => obscurePassword = !obscurePassword),
                        ),
                      ),
                    ),

                    if (isEditing && !isPrimaryOwner && !isSelf) ...[
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Status Akun Aktif',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: const Text(
                          'Nonaktifkan untuk mencabut akses login staf',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        value: isActive,
                        activeTrackColor: AppTheme.successGreen,
                        onChanged: (val) => setDialogState(() => isActive = val),
                      ),
                    ],

                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Batal'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final username =
                                  usernameController.text.trim().toLowerCase();
                              final displayName = nameController.text.trim();
                              final plainPass = passwordController.text;

                              if (username.isEmpty || displayName.isEmpty) {
                                setDialogState(() {
                                  dialogError =
                                      'Username dan nama lengkap wajib diisi.';
                                });
                                return;
                              }
                              if (username.contains(' ')) {
                                setDialogState(() {
                                  dialogError =
                                      'Username tidak boleh mengandung spasi.';
                                });
                                return;
                              }
                              if ((!isEditing || plainPass.isNotEmpty) && (plainPass.length < 12 || plainPass.length > 128)) {
                                setDialogState(() {
                                  dialogError =
                                      'Password harus 12?128 karakter.';
                                });
                                return;
                              }

                              String? saveError;
                              if (isEditing) {
                                UserProfile updated = userToEdit.copyWith(
                                  username: username,
                                  displayName: displayName,
                                  role: selectedRole,
                                  isActive: isActive,
                                );
                                if (plainPass.isNotEmpty) {
                                  updated = await updated.withSecurePassword(plainPass);
                                }
                                saveError = await pos.saveUserProfile(updated);
                              } else {
                                final newUser = await UserProfile.create(
                                  username: username,
                                  displayName: displayName,
                                  role: selectedRole,
                                  plainPassword: plainPass,
                                ).withSecurePassword(plainPass);
                                saveError = await pos.saveUserProfile(newUser);
                              }

                              if (saveError != null) {
                                if (!ctx.mounted) return;
                                setDialogState(() => dialogError = saveError);
                                return;
                              }

                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                              }
                              if (context.mounted) {
                                AppTheme.showToast(
                                  context,
                                  message:
                                      'Profil staf "$displayName" berhasil disimpan.',
                                );
                              }
                            },
                            child: Text(isEditing ? 'Simpan' : 'Tambah Staff'),
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

  Widget _buildRoleChip({
    required UserRole role,
    required String label,
    required UserRole selected,
    required bool enabled,
    required ValueChanged<UserRole> onSelect,
  }) {
    final isChosen = role == selected;
    final chipColor = AppTheme.roleColor(role);

    return Expanded(
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Material(
          color: isChosen ? chipColor : AppTheme.surfaceSubtle,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: enabled ? () => onSelect(role) : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isChosen ? chipColor : AppTheme.borderSubtle,
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isChosen ? Colors.white : AppTheme.textMain,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<PosProvider>();
    if (!access.isAuthenticated || !access.currentRole.canManageUsers) return const AccessDenied();
    final pos = context.watch<PosProvider>();
    final users = pos.users;

    return Scaffold(
      backgroundColor: AppTheme.surfaceLight,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('Kelola Profil Pengguna'),
              actions: [
                IconButton(
                  onPressed: () => _openUserFormDialog(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  tooltip: 'Tambah Staff Baru',
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openUserFormDialog(context),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Tambah Staff',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          if (widget.isEmbedded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manajemen Akun & Hak Akses Staff',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${users.length} akun terdaftar · Proteksi SHA-256 + Salt aktif',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Cryptographic Notice Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: AppTheme.accentCopperSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.accentAmber.withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.enhanced_encryption_rounded,
                  color: AppTheme.accentAmber,
                  size: 21,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enkripsi Sandi Kriptografis (Salted SHA-256)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Password tidak pernah disimpan sebagai teks biasa di perangkat maupun di Firestore.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: users.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final u = users[index];
                      final roleColor = AppTheme.roleColor(u.role);
                      final roleBg = AppTheme.roleBg(u.role);
                      final isPrimaryOwner =
                          u.username.toLowerCase() == 'warloc.owner' ||
                          u.username.toLowerCase() == 'iggoys';
                      final isCurrentSession = pos.currentUser?.id == u.id;

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.borderSubtle),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: roleBg,
                              ),
                              child: Center(
                                child: Text(
                                  u.displayName.isNotEmpty
                                      ? u.displayName[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: roleColor,
                                  ),
                                ),
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
                                          u.displayName,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textMain,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: roleBg,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          u.role.shortName,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: roleColor,
                                          ),
                                        ),
                                      ),
                                      if (isCurrentSession) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.successGreenLight,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'Anda',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.successGreen,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '@${u.username} · ${u.isActive ? "Aktif" : "Nonaktif"}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: u.isActive
                                          ? AppTheme.textMuted
                                          : AppTheme.dangerRed,
                                      fontWeight: u.isActive
                                          ? FontWeight.w500
                                          : FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _openUserFormDialog(context, userToEdit: u),
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 20,
                                color: AppTheme.textMain,
                              ),
                              tooltip: 'Ubah Profil / Reset Password',
                            ),
                            if (!isPrimaryOwner && !isCurrentSession)
                              IconButton(
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text(
                                        'Hapus Akun Staff',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      content: Text(
                                        'Hapus akun "${u.displayName}" (@${u.username}) secara permanen?',
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(c).pop(false),
                                          child: const Text('Batal'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.dangerRed,
                                          ),
                                          onPressed: () =>
                                              Navigator.of(c).pop(true),
                                          child: const Text('Hapus'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true && context.mounted) {
                                    await pos.deleteUserProfile(u.id);
                                    if (context.mounted) {
                                      AppTheme.showToast(
                                        context,
                                        message:
                                            'Akun "${u.displayName}" berhasil dihapus.',
                                        isWarning: true,
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                  color: AppTheme.dangerRed,
                                ),
                                tooltip: 'Hapus Akun',
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
