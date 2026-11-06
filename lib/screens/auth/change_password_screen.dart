import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_provider.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ganti Password'), actions: [
          TextButton(
            onPressed: _busy ? null : context.read<PosProvider>().logout,
            child: const Text('Keluar'),
          )
        ]),
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                                'Gunakan password pribadi yang berbeda dari password bawaan. Minimal 12 karakter.'),
                            const SizedBox(height: 20),
                            TextField(
                                controller: _old,
                                obscureText: true,
                                decoration: const InputDecoration(
                                    labelText: 'Password saat ini')),
                            const SizedBox(height: 12),
                            TextField(
                                controller: _new,
                                obscureText: true,
                                decoration: const InputDecoration(
                                    labelText: 'Password baru')),
                            const SizedBox(height: 12),
                            TextField(
                                controller: _confirm,
                                obscureText: true,
                                decoration: const InputDecoration(
                                    labelText: 'Ulangi password baru')),
                            if (_error != null)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(_error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                            const SizedBox(height: 16),
                            FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (_new.text != _confirm.text) {
                                          setState(() => _error =
                                              'Konfirmasi password tidak sama.');
                                          return;
                                        }
                                        if (_new.text.length < 12 ||
                                            _new.text.length > 128) {
                                          setState(() => _error =
                                              'Password harus 12–128 karakter.');
                                          return;
                                        }
                                        setState(() {
                                          _busy = true;
                                          _error = null;
                                        });
                                        try {
                                          await context
                                              .read<PosProvider>()
                                              .changeOwnPassword(
                                                  _old.text, _new.text);
                                          if (context.mounted &&
                                              !context
                                                  .read<PosProvider>()
                                                  .requiresPasswordChange &&
                                              Navigator.canPop(context)) {
                                            Navigator.pop(context);
                                          }
                                        } catch (_) {
                                          if (mounted) {
                                            setState(() => _error =
                                                'Password saat ini salah, password baru tidak valid, atau sesi telah berubah.');
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _busy = false);
                                          }
                                        }
                                      },
                                child: Text(_busy
                                    ? 'Menyimpan...'
                                    : 'Simpan Password')),
                          ]),
                    )))),
      );
}
