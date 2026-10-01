import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../data/data_source.dart';
import '../../data/models.dart';
import '../members/application/members_controller.dart';
import '../recipe/domain/recipe.dart';

/// Hour at which the planning day rolls over: 00:00–03:59 still belongs to
/// the previous day's Dinner.
const kDayStartsAtHour = 4;

/// Default slot for a household wall-clock time: 00:00–03:59 dinner (of the
/// previous day), 04:00–10:59 nashta, 11:00–15:59 lunch, from 16:00 dinner.
Slot slotForTime(DateTime t) => t.hour < kDayStartsAtHour
    ? Slot.dinner
    : t.hour < 11
    ? Slot.breakfast
    : t.hour < 16
    ? Slot.lunch
    : Slot.dinner;

/// The planning date for a household wall-clock time (before 04:00 →
/// yesterday), at midnight.
DateTime planDateFor(DateTime t) {
  final d = DateTime(t.year, t.month, t.day);
  return t.hour < kDayStartsAtHour ? DateTime(d.year, d.month, d.day - 1) : d;
}

/// The meal slot Home is showing; re-derived from the household clock at
/// each day tick (midnight / 04:00 / resume).
final slotProvider = NotifierProvider<SlotController, Slot>(SlotController.new);

class SlotController extends Notifier<Slot> {
  @override
  Slot build() {
    ref.watch(dayTickProvider);
    return slotForTime(ref.watch(householdNowProvider)());
  }

  void select(Slot s) => state = s;
}

/// The date Home plans for: today on the household's clock (Household
/// timezone, default Asia/Kolkata), rolling over at 04:00; refreshed by the
/// day tick so it never goes stale past midnight.
final planDateProvider = Provider<DateTime>((ref) {
  ref.watch(dayTickProvider);
  return planDateFor(ref.watch(householdNowProvider)());
});

/// Maharaj's pick + 8 tiles for [slot] (GET /v1/recommendations).
final recommendationsProvider = FutureProvider.family<Recommendations, Slot>(
  (ref, slot) => ref
      .watch(dataRepositoryProvider)
      .recommendations(slot: slot, date: ref.watch(planDateProvider), members: ref.watch(membersProvider)),
  retry: (_, _) => null,
);
