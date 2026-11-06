import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/warloc_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final pos = context.read<PosProvider>();
    final error = await pos.login(
      _usernameController.text,
      _passwordController.text,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = error;
    });

    if (error == null) {
      AppTheme.showToast(
        context,
        message: 'Selamat bertugas, ${pos.currentUser?.displayName}!',
        icon: Icons.verified_user_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.espressoDark,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide =
                constraints.maxWidth >= 880 && constraints.maxHeight >= 500;

            if (isWide) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 940),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _buildWideBrandColumn(),
                        ),
                        const SizedBox(width: 48),
                        Expanded(
                          flex: 5,
                          child: _buildLoginCard(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final isCompact = constraints.maxHeight < 680;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Hero(
                        tag: 'warloc_brand_emblem',
                        child: WarlocLogo(size: 76),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'WARLOC',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.2,
                          color: Color(0xFFFFFBEB),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Coffee, Eatery & Entertainment POS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.accentGold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      SizedBox(height: isCompact ? 20 : 28),
                      _buildLoginCard(),
                      const SizedBox(height: 20),
                      _buildSecurityPill(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWideBrandColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Hero(
          tag: 'warloc_brand_emblem',
          child: WarlocLogo(size: 84),
        ),
        const SizedBox(height: 24),
        const Text(
          'WARLOC',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.2,
            color: Color(0xFFFFFBEB),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sistem Kasir, Hiburan, Inventori & Laporan Keuangan Terpadu',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppTheme.accentGold,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        _buildFeatureItem(
          Icons.bolt_rounded,
          'Transaksi Kasir & Rental Cepat',
          'Mendukung F&B serta layanan hiburan dengan pembayaran Cash & QRIS.',
        ),
        const SizedBox(height: 14),
        _buildFeatureItem(
          Icons.sync_lock_rounded,
          'Otorisasi Ketat Tanpa Login Instan',
          'Hanya staf berwenang dengan kredensial terverifikasi yang dapat masuk.',
        ),
        const SizedBox(height: 14),
        _buildFeatureItem(
          Icons.cloud_sync_rounded,
          'Sinkronisasi Lintas Perangkat Real-Time',
          'Katalog foto produk, stok, biaya operasional & laporan tersinkron ke Firebase.',
        ),
        const SizedBox(height: 28),
        _buildSecurityPill(),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.accentGold.withValues(alpha: 0.25),
            ),
          ),
          child: Icon(icon, size: 18, color: AppTheme.accentGold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFFBEB),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  color: const Color(0xFFFFFBEB).withValues(alpha: 0.65),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
                  Icons.lock_person_rounded,
                  size: 20,
                  color: AppTheme.accentAmber,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Masuk ke Akun',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Gunakan kredensial resmi staf Warloc',
                      style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    color: AppTheme.dangerRed,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: AppTheme.dangerRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          const Text(
            'Username',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _usernameController,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            onSubmitted: (_) => _passwordFocusNode.requestFocus(),
            decoration: const InputDecoration(
              hintText: 'Masukkan username terdaftar',
              prefixIcon: Icon(
                Icons.person_outline_rounded,
                color: AppTheme.accentAmber,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Password',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleLogin(),
            decoration: InputDecoration(
              hintText: 'Masukkan password akun',
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                color: AppTheme.accentAmber,
                size: 20,
              ),
              suffixIcon: IconButton(
                tooltip: _obscurePassword
                    ? 'Tampilkan password'
                    : 'Sembunyikan password',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppTheme.textMuted,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 22),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: const Color(0xFFFFFBEB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.3,
                      ),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Masuk ke Sistem Warloc',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 15,
                  color: AppTheme.textMuted,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Akses terbatas untuk personel resmi. Hubungi Owner jika lupa kredensial akun.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_user_outlined,
              color: Color(0xFF34D399),
              size: 15,
            ),
            SizedBox(width: 6),
            Text(
              'SHA-256 Salted Hashing & Firestore Sync Protected',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE7E0D8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
