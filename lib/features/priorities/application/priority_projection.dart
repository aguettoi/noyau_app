import '../../../core/money/money.dart';
import '../domain/priority_plan.dart';

/// Pure planning projection. It never mutates a source object or a ledger.
List<PriorityProjectionEntry> projectPriorityPlan({
  required List<PriorityPlanItemView> items,
  required Money? monthlyCapacity,
  required DateTime from,
}) {
  if (monthlyCapacity == null || monthlyCapacity.minorUnits <= 0) {
    return List.unmodifiable([
      for (final item in items)
        PriorityProjectionEntry(
          item: item,
          estimatedNeed: item.source.estimatedNeed,
          estimatedMonths: null,
          estimatedCompletionDate: null,
        ),
    ]);
  }

  var cursor = from;
  return List.unmodifiable([
    for (final item in items)
      () {
        final need = item.source.estimatedNeed;
        final months = need == null
            ? null
            : (need.minorUnits / monthlyCapacity.minorUnits).ceil();
        if (months != null) {
          cursor = DateTime(cursor.year, cursor.month + months, cursor.day);
        }
        return PriorityProjectionEntry(
          item: item,
          estimatedNeed: need,
          estimatedMonths: months,
          estimatedCompletionDate: months == null ? null : cursor,
        );
      }(),
  ]);
}
