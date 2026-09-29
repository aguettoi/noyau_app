import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/dashboard_metrics.dart';

const chartPalette = [
  AppColors.primary,
  AppColors.secondary,
  AppColors.accent,
  Color(0xFF8295A5),
  Color(0xFFA5B9A6),
  Color(0xFFB8BFC4),
];
String chartMoney(int cents) =>
    '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} MAD';

/// Presentation-only canvas. Empty charts retain axes without fake values.
class IncomeExpenseChart extends StatelessWidget {
  const IncomeExpenseChart({super.key, required this.points});
  final List<DashboardFlowPoint> points;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const ChartLegend(
        labels: ['Revenus', 'Dépenses'],
        colors: [AppColors.primary, AppColors.secondary],
      ),
      const SizedBox(height: 8),
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _IncomePainter(
                    points,
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (points.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Les données apparaîtront après les premières opérations.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              if (points.isNotEmpty)
                Positioned.fill(
                  left: 44,
                  bottom: 26,
                  top: 18,
                  child: Row(
                    children: [
                      for (final p in points)
                        Expanded(
                          child: Tooltip(
                            message:
                                '${p.month.month}/${p.month.year}\nRevenus : ${chartMoney(p.flow.income.minorUnits)}\nDépenses : ${chartMoney(p.flow.expense.minorUnits)}',
                            child: const SizedBox.expand(),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.labels, required this.colors});
  final List<String> labels;
  final List<Color> colors;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 4,
    children: [
      for (var i = 0; i < labels.length; i++)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors[i % colors.length],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Tooltip(
                message: labels[i],
                child: Text(
                  labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
    ],
  );
}

class EmptyPlot extends StatelessWidget {
  const EmptyPlot({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: CustomPaint(
          painter: _IncomePainter(
            const [],
            Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 38),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    ],
  );
}

class _IncomePainter extends CustomPainter {
  _IncomePainter(this.points, this.textColor);
  final List<DashboardFlowPoint> points;
  final Color textColor;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 60 || size.height < 40) return;
    final area = Rect.fromLTRB(44, 18, size.width - 8, size.height - 26);
    final grid = Paint()
      ..color = AppColors.border.withValues(alpha: .65)
      ..strokeWidth = 1;
    var maxValue = 1;
    for (final p in points) {
      maxValue = math.max(
        maxValue,
        math.max(p.flow.income.minorUnits, p.flow.expense.minorUnits),
      );
    }
    for (var i = 0; i <= 4; i++) {
      final y = area.bottom - area.height * i / 4;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), grid);
      if (points.isNotEmpty) {
        _text(
          canvas,
          (maxValue * i / 4 / 100).toStringAsFixed(0),
          Offset(0, y - 6),
          40,
        );
      }
    }
    canvas.drawLine(area.topLeft, area.bottomLeft, grid);
    _text(canvas, 'MAD', const Offset(0, 0), 42);
    if (points.isEmpty) {
      _text(canvas, 'Mois', Offset(area.center.dx - 15, area.bottom + 8), 50);
      return;
    }
    final slot = area.width / points.length;
    final width = math.min(slot * .27, 28.0);
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final center = area.left + slot * (i + .5);
      for (var j = 0; j < 2; j++) {
        final amount = j == 0
            ? p.flow.income.minorUnits
            : p.flow.expense.minorUnits;
        final height = area.height * (amount / maxValue).clamp(0, 1);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              center + (j == 0 ? -width - 2 : 2),
              area.bottom - height,
              width,
              height,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = j == 0 ? AppColors.primary : AppColors.secondary,
        );
      }
      _text(
        canvas,
        '${p.month.month.toString().padLeft(2, '0')}/${p.month.year % 100}',
        Offset(center - slot / 2, area.bottom + 8),
        slot,
      );
    }
  }

  void _text(Canvas canvas, String text, Offset offset, double width) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: width);
    p.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _IncomePainter old) =>
      old.points != points || old.textColor != textColor;
}

class ExpenseDonut extends StatelessWidget {
  const ExpenseDonut({super.key, required this.segments});
  final List<({String name, int cents})> segments;
  @override
  Widget build(BuildContext context) {
    final positive = segments.where((s) => s.cents > 0).toList();
    final total = positive.fold<int>(0, (s, e) => s + e.cents);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _DonutPainter(
                      positive.map((e) => e.cents).toList(),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            total == 0 ? 'Non disponible' : chartMoney(total),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            total == 0 ? 'Aucune dépense' : 'Total dépenses',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (total == 0)
          const Text(
            'La répartition apparaîtra ici.',
            style: TextStyle(fontSize: 12),
          )
        else
          ChartLegend(
            labels: positive
                .map(
                  (e) =>
                      '${e.name} ${(e.cents / total * 100).toStringAsFixed(0)} %',
                )
                .toList(),
            colors: chartPalette,
          ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.amounts);
  final List<int> amounts;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.shortestSide - 22,
      height: size.shortestSide - 22,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..color = AppColors.border;
    canvas.drawOval(rect, paint);
    final total = amounts.fold<int>(0, (s, e) => s + e);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < amounts.length; i++) {
      final sweep = 2 * math.pi * amounts[i] / total;
      paint.color = chartPalette[i % chartPalette.length];
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.amounts != amounts;
}

class ValueBar extends StatelessWidget {
  const ValueBar({
    super.key,
    required this.label,
    required this.cents,
    required this.maximum,
    this.color = AppColors.primary,
    this.suffix,
  });
  final String label;
  final int cents, maximum;
  final Color color;
  final String? suffix;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Tooltip(
      message: '$label : ${chartMoney(cents)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${chartMoney(cents)}${suffix == null ? '' : ' • $suffix'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: maximum <= 0 ? 0 : (cents.abs() / maximum).clamp(0, 1),
              minHeight: 7,
              color: color,
              backgroundColor: AppColors.surface,
            ),
          ),
        ],
      ),
    ),
  );
}
