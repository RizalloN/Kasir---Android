import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/user_role.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../owner/user_management_screen.dart';
import '../auth/change_password_screen.dart';

class UserProfileModal extends StatelessWidget {
  final PosProvider pos;

  const UserProfileModal({super.key, required this.pos});

  @override
  Widget build(BuildContext context) {
    final user = pos.currentUser;
    final role = pos.currentRole;
    final roleColor = AppTheme.roleColor(role);
    final roleBg = AppTheme.roleBg(role);
    final roleIcon = AppTheme.roleIcon(role);

    final loginTime = user?.lastLoginAt != null
        ? DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(user!.lastLoginAt!)
        : 'Sesi Aktif';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: AppTheme.cardBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modal Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Profil Akun Aktif',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
                    tooltip: 'Tutup',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Avatar with Role Badge
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: roleBg,
                      border: Border.all(color: roleColor.withValues(alpha: 0.45), width: 2),
                    ),
                    child: Center(
                      child: Text(
                        (user?.displayName.isNotEmpty ?? false)
                            ? user!.displayName[0].toUpperCase()
                            : 'W',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: roleColor,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: roleColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(roleIcon, size: 13, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Display Name & Username
              Text(
                user?.displayName ?? 'Pengguna Warloc',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                '@${user?.username ?? "staff"}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 12),

              // Level / Role Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: roleBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(roleIcon, size: 15, color: roleColor),
                    const SizedBox(width: 6),
                    Text(
                      'Level: ${role.displayName}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: roleColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Account Details Table
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      icon: Icons.check_circle_rounded,
                      iconColor: AppTheme.successGreen,
                      label: 'Status Akun',
                      value: 'Aktif Terverifikasi',
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1),
                    ),
                    _buildDetailRow(
                      icon: Icons.enhanced_encryption_rounded,
                      iconColor: AppTheme.accentAmber,
                      label: 'Proteksi Sandi',
                      value: 'SHA-256 + Salt',
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1),
                    ),
                    _buildDetailRow(
                      icon: Icons.schedule_rounded,
                      iconColor: AppTheme.textSecondary,
                      label: 'Login Terakhir',
                      value: loginTime,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1),
                    ),
                    _buildDetailRow(
                      icon: Icons.verified_user_outlined,
                      iconColor: roleColor,
                      label: 'Wewenang',
                      value: role.permissionSummary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              if (role.canChangeOwnPassword) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
                  },
                  icon: const Icon(Icons.password, size: 18),
                  label: const Text('Ganti Password Saya'),
                ),
              ),
              const SizedBox(height: 10),
              ],
              if (role.canManageUsers) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const UserManagementScreen(isEmbedded: false),
                        ),
                      );
                    },
                    icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                    label: const Text('Kelola Profil Pengguna / Staff'),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Logout Action
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text(
                          'Konfirmasi Logout',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        content: Text(
                          'Keluar dari sesi akun "${user?.displayName}" (@${user?.username})?',
                          style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Batal'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.dangerRed,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Ya, Logout'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && context.mounted) {
                      Navigator.of(context).pop();
                      await pos.logout();
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Logout / Keluar Akun'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.dangerRed,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMain,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        ),
      ],
    );
  }
}
