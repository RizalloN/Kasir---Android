import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static String format(num amount) {
    if (amount < 0) {
      return '-${_formatter.format(amount.abs())}';
    }
    return _formatter.format(amount);
  }

  static String formatShort(num amount) {
    final absVal = amount.abs();
    final sign = amount < 0 ? '-' : '';
    if (absVal >= 1000000000) {
      final m = absVal / 1000000000;
      return '${sign}Rp ${m.toStringAsFixed(m.truncateToDouble() == m ? 0 : 1)} M';
    } else if (absVal >= 1000000) {
      final jt = absVal / 1000000;
      return '${sign}Rp ${jt.toStringAsFixed(jt.truncateToDouble() == jt ? 0 : 1)} jt';
    } else if (absVal >= 1000) {
      final rb = absVal / 1000;
      return '${sign}Rp ${rb.toStringAsFixed(rb.truncateToDouble() == rb ? 0 : 1)} rb';
    }
    return format(amount);
  }

  static double parseDigits(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return 0.0;
    return double.tryParse(digitsOnly) ?? 0.0;
  }

  static String formatDateTime(DateTime dateTime) {
    return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(dateTime);
  }

  static String formatTimeOnly(DateTime dateTime) {
    return DateFormat('HH:mm', 'id_ID').format(dateTime);
  }

  static String formatDateOnly(DateTime dateTime) {
    return DateFormat('dd MMMM yyyy', 'id_ID').format(dateTime);
  }
}
