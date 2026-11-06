import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class WarlocLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final String? subtitle;
  final Color? textColor;

  const WarlocLogo({
    super.key,
    this.size = 40,
    this.showText = false,
    this.subtitle,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final emblem = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF331E14), // Roasted Espresso Highlight
            Color(0xFF140B07), // Deep Mocha Base
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(
          color: AppTheme.accentGold.withValues(alpha: 0.65),
          width: size > 60 ? 2.0 : 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.22),
            blurRadius: size * 0.22,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.62, size * 0.62),
          painter: const _WarlocEmblemPainter(),
        ),
      ),
    );

    if (!showText) return emblem;

    final resolvedTitleColor = textColor ?? AppTheme.textMain;
    final resolvedSubColor = textColor != null
        ? textColor!.withValues(alpha: 0.75)
        : AppTheme.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        emblem,
        SizedBox(width: size * 0.28),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'WARLOC',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: (size * 0.42).clamp(14.0, 22.0),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        color: resolvedTitleColor,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCopperSoft,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppTheme.accentAmber.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Text(
                      'POS',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentAmber,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: (size * 0.28).clamp(10.5, 13.0),
                    fontWeight: FontWeight.w500,
                    color: resolvedSubColor,
                    height: 1.15,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WarlocEmblemPainter extends CustomPainter {
  const _WarlocEmblemPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final goldPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.fill;

    final cupPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFBEB), Color(0xFFFDE68A)],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final steamPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Steam curves
    final pathSteam1 = Path()
      ..moveTo(w * 0.33, h * 0.27)
      ..quadraticBezierTo(w * 0.27, h * 0.17, w * 0.35, h * 0.08);
    canvas.drawPath(pathSteam1, steamPaint);

    final pathSteam2 = Path()
      ..moveTo(w * 0.49, h * 0.24)
      ..quadraticBezierTo(w * 0.55, h * 0.14, w * 0.47, h * 0.04);
    canvas.drawPath(pathSteam2, steamPaint);

    final pathSteam3 = Path()
      ..moveTo(w * 0.65, h * 0.27)
      ..quadraticBezierTo(w * 0.71, h * 0.17, w * 0.63, h * 0.08);
    canvas.drawPath(pathSteam3, steamPaint);

    // Espresso Demitasse Cup Body
    final cupPath = Path()
      ..moveTo(w * 0.16, h * 0.35)
      ..lineTo(w * 0.76, h * 0.35)
      ..lineTo(w * 0.71, h * 0.70)
      ..quadraticBezierTo(w * 0.46, h * 0.88, w * 0.21, h * 0.70)
      ..close();
    canvas.drawPath(cupPath, cupPaint);

    // Saucer Base Line
    final saucerPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(w * 0.13, h * 0.89),
      Offset(w * 0.79, h * 0.89),
      saucerPaint,
    );

    // Cup Handle
    final handlePaint = Paint()
      ..color = const Color(0xFFFDE68A)
      ..strokeWidth = w * 0.085
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final handleRect = Rect.fromLTWH(w * 0.65, h * 0.41, w * 0.25, h * 0.25);
    canvas.drawArc(handleRect, -1.25, 2.55, false, handlePaint);

    // Roaster Star Dot
    canvas.drawCircle(Offset(w * 0.49, h * 0.01), w * 0.038, goldPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
