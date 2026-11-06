import 'package:flutter/material.dart';

class AccessDenied extends StatelessWidget {
  const AccessDenied({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: SafeArea(
            child: Center(
                child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'Akses ditolak. Akun Anda tidak memiliki izin untuk halaman ini.',
              textAlign: TextAlign.center),
        ))),
      );
}
