import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_release_service.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key});

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _opening = false;
  String? _downloadError;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AppReleaseService>();
    return AlertDialog(
      scrollable: true,
      title: const Text('Pembaruan Aplikasi'),
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(service.installedCode == null
                ? 'Versi perangkat belum terbaca.'
                : 'Terpasang: ${service.installedName} (${service.installedCode})'),
            const SizedBox(height: 12),
            if (service.isChecking) const LinearProgressIndicator(),
            if (service.error != null) Text(service.error!),
            if (service.updateAvailable) ...[
              Text(
                  'Versi baru: ${service.release.versionName} (${service.release.versionCode})'),
              const SizedBox(height: 8),
              Text(service.release.notes),
              const SizedBox(height: 12),
              const Text('Selesaikan transaksi lalu unduh APK melalui browser. '
                  'Buka file unduhan dan setujui pemasangan pembaruan di Android. '
                  'Jangan hapus aplikasi lama agar data lokal tetap tersimpan.'),
              const SizedBox(height: 8),
              Text('Sumber: ${service.release.downloadUrl!.host}'),
            ] else if (!service.isChecking && service.error == null)
              const Text(
                  'Belum ada pembaruan yang diterbitkan untuk perangkat ini.'),
            if (_downloadError != null) ...[
              const SizedBox(height: 8),
              Text(_downloadError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup')),
        TextButton(
          onPressed: service.isChecking ? null : service.refresh,
          child: const Text('Periksa Lagi'),
        ),
        if (service.updateAvailable)
          FilledButton.icon(
            onPressed: _opening
                ? null
                : () async {
                    setState(() {
                      _opening = true;
                      _downloadError = null;
                    });
                    try {
                      await service.downloadUpdate();
                    } catch (_) {
                      if (mounted) {
                        setState(() => _downloadError =
                            'Unduhan tidak dapat dibuka. Coba lagi atau periksa browser perangkat.');
                      }
                    } finally {
                      if (mounted) setState(() => _opening = false);
                    }
                  },
            icon: const Icon(Icons.download_rounded),
            label: const Text('Unduh APK'),
          ),
      ],
    );
  }
}
