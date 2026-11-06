import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../providers/pos_provider.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';

class DonutSliceItem {
  final String label;
  final double value;
  final String subtitle;
  final Color color;

  const DonutSliceItem({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
  });
}

class BarChartItem {
  final String label;
  final String fullTitle;
  final double value;
  final Color color;

  const BarChartItem({
    required this.label,
    required this.fullTitle,
    required this.value,
    required this.color,
  });
}

/// 1. Interactive Smooth Time-Series Line & Area Chart
class InteractiveTimeSeriesChart extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<AnalyticsPoint> points;
  final Color lineColor;

  const InteractiveTimeSeriesChart({
    super.key,
    required this.title,
    required this.subtitle,
    required this.points,
    this.lineColor = AppTheme.accentAmber,
  });

  @override
  State<InteractiveTimeSeriesChart> createState() =>
      _InteractiveTimeSeriesChartState();
}

class _InteractiveTimeSeriesChartState
    extends State<InteractiveTimeSeriesChart> {
  int? _selectedIndex;

  void _handleTouch(Offset localPos, double width) {
    if (widget.points.isEmpty || width <= 0) return;
    const leftPad = 52.0;
    const rightPad = 14.0;
    final chartW = (width - leftPad - rightPad).clamp(1.0, double.infinity);
    final relX = (localPos.dx - leftPad).clamp(0.0, chartW);
    final count = widget.points.length;
    final idx = count <= 1
        ? 0
        : ((relX / chartW) * (count - 1)).round().clamp(0, count - 1);
    if (_selectedIndex != idx) {
      setState(() => _selectedIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    int defaultPeakIdx = 0;
    for (int i = 0; i < pts.length; i++) {
      if (pts[i].value >= pts[defaultPeakIdx].value) {
        defaultPeakIdx = i;
      }
    }
    final activeIdx =
        (_selectedIndex != null && _selectedIndex! < pts.length)
        ? _selectedIndex!
        : (pts.isNotEmpty ? defaultPeakIdx : null);
    final activePoint = activeIdx != null ? pts[activeIdx] : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCopperSoft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.ssid_chart_rounded,
                      size: 17,
                      color: widget.lineColor,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                        ),
                      ),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  )),
                ],
              ),
              if (activePoint != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: widget.lineColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${activePoint.subtitle}: ',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(activePoint.value),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 205,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) =>
                      _handleTouch(d.localPosition, constraints.maxWidth),
                  onHorizontalDragUpdate: (d) =>
                      _handleTouch(d.localPosition, constraints.maxWidth),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 205),
                    painter: _TimeSeriesChartPainter(
                      points: pts,
                      selectedIndex: activeIdx,
                      lineColor: widget.lineColor,
                    ),
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

class _TimeSeriesChartPainter extends CustomPainter {
  final List<AnalyticsPoint> points;
  final int? selectedIndex;
  final Color lineColor;

  const _TimeSeriesChartPainter({
    required this.points,
    required this.selectedIndex,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 52.0;
    const rightPad = 14.0;
    const topPad = 12.0;
    const bottomPad = 26.0;

    final chartW = (size.width - leftPad - rightPad).clamp(1.0, double.infinity);
    final chartH = (size.height - topPad - bottomPad).clamp(
      1.0,
      double.infinity,
    );

    double maxVal = 0.0;
    for (final p in points) {
      if (p.value > maxVal) maxVal = p.value;
    }
    final yMax = maxVal <= 0 ? 100000.0 : (maxVal * 1.18);

    final gridPaint = Paint()
      ..color = AppTheme.borderSubtle
      ..strokeWidth = 1.0;

    // 4 horizontal grid levels
    for (int i = 0; i <= 3; i++) {
      final ratio = i / 3.0;
      final y = topPad + chartH - (ratio * chartH);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartW, y),
        gridPaint,
      );

      final val = yMax * ratio;
      final label = val == 0
          ? '0'
          : CurrencyFormatter.formatShort(val).replaceFirst('Rp ', '');
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMuted,
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: leftPad - 6);
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    if (points.isEmpty) return;

    final coords = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? leftPad + chartW / 2
          : leftPad + (i / (points.length - 1)) * chartW;
      final norm = (points[i].value / yMax).clamp(0.0, 1.0);
      final y = topPad + chartH - (norm * chartH);
      coords.add(Offset(x, y));
    }

    // Smooth cubic path
    final linePath = Path()..moveTo(coords.first.dx, coords.first.dy);
    for (int i = 0; i < coords.length - 1; i++) {
      final p0 = coords[i];
      final p1 = coords[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(coords.last.dx, topPad + chartH)
      ..lineTo(coords.first.dx, topPad + chartH)
      ..close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.28),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, areaPaint);

    final strokePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, strokePaint);

    // X-Axis Labels (smart stride so labels never overlap)
    final maxLabels = (chartW / 44).floor().clamp(3, 12);
    final stride = (points.length / maxLabels).ceil().clamp(1, points.length);
    for (int i = 0; i < points.length; i++) {
      if (i % stride != 0 && i != points.length - 1) continue;
      if (i == points.length - 1 &&
          points.length > 4 &&
          (i % stride != 0) &&
          (coords.last.dx - coords[i - (i % stride)].dx) < 30) {
        continue;
      }
      final tp = TextPainter(
        text: TextSpan(
          text: points[i].label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selectedIndex == i ? FontWeight.w800 : FontWeight.w500,
            color: selectedIndex == i ? AppTheme.textMain : AppTheme.textMuted,
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (coords[i].dx - tp.width / 2).clamp(
        leftPad - 6,
        size.width - tp.width,
      );
      tp.paint(canvas, Offset(dx, topPad + chartH + 7));
    }

    // Active Point Highlight & Guide
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < coords.length) {
      final pt = coords[selectedIndex!];
      final guidePaint = Paint()
        ..color = lineColor.withValues(alpha: 0.35)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        Offset(pt.dx, topPad),
        Offset(pt.dx, topPad + chartH),
        guidePaint,
      );

      canvas.drawCircle(
        pt,
        7,
        Paint()..color = lineColor.withValues(alpha: 0.2),
      );
      canvas.drawCircle(pt, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(pt, 3.3, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _TimeSeriesChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.lineColor != lineColor;
  }
}

/// 2. Interactive Donut Chart with Tappable Slices & Legend
class InteractiveDonutChart extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<DonutSliceItem> slices;
  final Widget? trailingHeader;

  const InteractiveDonutChart({
    super.key,
    required this.title,
    required this.subtitle,
    required this.slices,
    this.trailingHeader,
  });

  @override
  State<InteractiveDonutChart> createState() => _InteractiveDonutChartState();
}

class _InteractiveDonutChartState extends State<InteractiveDonutChart> {
  int? _activeSlice;

  @override
  Widget build(BuildContext context) {
    final total = widget.slices.fold(0.0, (sum, s) => sum + s.value);
    final validIdx =
        (_activeSlice != null && _activeSlice! < widget.slices.length)
        ? _activeSlice
        : null;
    final selected = validIdx != null ? widget.slices[validIdx] : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.accentCopperSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.donut_large_rounded,
                  size: 17,
                  color: AppTheme.accentAmber,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.trailingHeader != null) widget.trailingHeader!,
            ],
          ),
          const SizedBox(height: 16),
          if (total <= 0 || widget.slices.isEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 185),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      size: Size(110, 110),
                      painter: _DonutChartPainter(
                        slices: [],
                        total: 0,
                        activeIndex: null,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Belum ada data tercatat pada periode ini',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth >= 340;
                final donutBox = SizedBox(
                  width: 158,
                  height: 158,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      GestureDetector(
                        onTapUp: (details) {
                          const center = Offset(79, 79);
                          final delta = details.localPosition - center;
                          final dist = delta.distance;
                          if (dist < 38 || dist > 79) {
                            setState(() => _activeSlice = null);
                            return;
                          }
                          double angle =
                              math.atan2(delta.dy, delta.dx) + math.pi / 2;
                          if (angle < 0) angle += 2 * math.pi;
                          double acc = 0.0;
                          for (int i = 0; i < widget.slices.length; i++) {
                            final sweep =
                                (widget.slices[i].value / total) * 2 * math.pi;
                            if (angle >= acc && angle <= acc + sweep) {
                              setState(
                                () => _activeSlice = _activeSlice == i
                                    ? null
                                    : i,
                              );
                              return;
                            }
                            acc += sweep;
                          }
                        },
                        child: CustomPaint(
                          size: const Size(158, 158),
                          painter: _DonutChartPainter(
                            slices: widget.slices,
                            total: total,
                            activeIndex: validIdx,
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 26),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                selected != null ? selected.label : 'Total',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  selected != null
                                      ? '${((selected.value / total) * 100).toStringAsFixed(0)}%'
                                      : CurrencyFormatter.formatShort(total),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textMain,
                                    fontFeatures: AppTheme.tabularFigures,
                                  ),
                                ),
                              ),
                              if (selected != null)
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    CurrencyFormatter.formatShort(
                                      selected.value,
                                    ),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: selected.color,
                                      fontFeatures: AppTheme.tabularFigures,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                final legendList = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.slices.asMap().entries.map((entry) {
                    final i = entry.key;
                    final s = entry.value;
                    final pct = ((s.value / total) * 100).round();
                    final isSel = validIdx == i;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(
                        () => _activeSlice = _activeSlice == i ? null : i,
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? s.color.withValues(alpha: 0.10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: s.color,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSel
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: AppTheme.textMain,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${CurrencyFormatter.formatShort(s.value)} ($pct%)',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textSecondary,
                                fontFeatures: AppTheme.tabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );

                if (sideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      donutBox,
                      const SizedBox(width: 16),
                      Expanded(child: legendList),
                    ],
                  );
                }

                return Column(
                  children: [
                    donutBox,
                    const SizedBox(height: 14),
                    legendList,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<DonutSliceItem> slices;
  final double total;
  final int? activeIndex;

  const _DonutChartPainter({
    required this.slices,
    required this.total,
    required this.activeIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = math.min(size.width, size.height) / 2 - 14;

    if (total <= 0 || slices.isEmpty) {
      final emptyPaint = Paint()
        ..color = AppTheme.surfaceSubtle
        ..strokeWidth = 18
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, baseRadius, emptyPaint);
      return;
    }

    double startAngle = -math.pi / 2;
    final gap = slices.length > 1 ? 0.035 : 0.0;

    for (int i = 0; i < slices.length; i++) {
      final s = slices[i];
      final fullSweep = (s.value / total) * 2 * math.pi;
      final drawSweep = math.max(0.01, fullSweep - gap);
      final isSelected = activeIndex == i;

      final paint = Paint()
        ..color = s.color
        ..strokeWidth = isSelected ? 24.0 : 19.0
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;

      final radius = isSelected ? baseRadius + 2.5 : baseRadius;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + gap / 2,
        drawSweep,
        false,
        paint,
      );

      startAngle += fullSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.slices != slices ||
        oldDelegate.total != total ||
        oldDelegate.activeIndex != activeIndex;
  }
}

/// 3. Interactive Vertical Bar Chart Diagram
class InteractiveBarChart extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<BarChartItem> bars;
  final Widget? trailingHeader;

  const InteractiveBarChart({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bars,
    this.trailingHeader,
  });

  @override
  State<InteractiveBarChart> createState() => _InteractiveBarChartState();
}

class _InteractiveBarChartState extends State<InteractiveBarChart> {
  int? _selectedBar;

  @override
  Widget build(BuildContext context) {
    final items = widget.bars;
    double maxAbs = 0.0;
    for (final b in items) {
      if (b.value.abs() > maxAbs) maxAbs = b.value.abs();
    }
    final safeMax = maxAbs <= 0 ? 1.0 : maxAbs;
    final activeBar = (_selectedBar != null && _selectedBar! < items.length)
        ? items[_selectedBar!]
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCopperSoft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.bar_chart_rounded,
                      size: 17,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                        ),
                      ),
                      Text(
                        activeBar != null
                            ? '${activeBar.fullTitle}: ${CurrencyFormatter.format(activeBar.value)}'
                            : widget.subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: activeBar != null
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: activeBar != null
                              ? AppTheme.accentAmber
                              : AppTheme.textMuted,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    ],
                  )),
                ],
              ),
              if (widget.trailingHeader != null) widget.trailingHeader!,
            ],
          ),
          const SizedBox(height: 18),
          if (items.isEmpty)
            const SizedBox(
              height: 165,
              child: Center(
                child: Text(
                  'Belum ada data diagram batang pada periode ini',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
            )
          else
            SizedBox(
              height: 182,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(items.length, (i) {
                  final item = items[i];
                  final ratio = maxAbs <= 0
                      ? 0.04
                      : (item.value.abs() / safeMax).clamp(0.05, 1.0);
                  final isSel = _selectedBar == i;
                  final barHeight = 118.0 * ratio;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(
                          () => _selectedBar = _selectedBar == i ? null : i,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                CurrencyFormatter.formatShort(item.value),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: isSel
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                  color: item.value < 0
                                      ? AppTheme.dangerRed
                                      : AppTheme.textMain,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              height: 122,
                              alignment: Alignment.bottomCenter,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOutCubic,
                                height: barHeight,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      item.color,
                                      item.color.withValues(alpha: 0.78),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: isSel
                                      ? Border.all(
                                          color: AppTheme.primary,
                                          width: 1.8,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSel
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isSel
                                    ? AppTheme.textMain
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
