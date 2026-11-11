import 'package:flutter/material.dart';
import '../barista/open_bills_screen.dart';

// Compatibility entry for callers outside the cashier workspace.
class OpenBillsDialog extends StatelessWidget {
  final VoidCallback? onResumed;
  const OpenBillsDialog({super.key, this.onResumed});
  @override
  Widget build(BuildContext context) => Dialog(insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 800),
      child: Column(children: [
        Align(alignment: Alignment.centerRight, child: IconButton(tooltip: 'Tutup tagihan',
          onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))),
        Expanded(child: OpenBillsScreen(onEdit: () { Navigator.pop(context); onResumed?.call(); })),
      ])));
}
