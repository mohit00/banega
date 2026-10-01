import 'package:banega/core/clock.dart';
import 'package:banega/core/config.dart';
import 'package:banega/features/home/home_providers.dart';
import 'package:banega/features/recipe/domain/recipe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('00:00–03:59 is still the previous day\'s Dinner', () {
    expect(slotForTime(DateTime(2026, 9, 27, 2, 30)), Slot.dinner);
    expect(planDateFor(DateTime(2026, 9, 27, 2, 30)), DateTime(2026, 9, 26));
    expect(slotForTime(DateTime(2026, 9, 27, 4)), Slot.breakfast);
    expect(planDateFor(DateTime(2026, 9, 27, 4)), DateTime(2026, 9, 27));
    expect(planDateFor(DateTime(2026, 10, 1, 1)), DateTime(2026, 9, 30), reason: 'month boundary');
    expect(slotForTime(DateTime(2026, 9, 27, 11)), Slot.lunch);
    expect(slotForTime(DateTime(2026, 9, 27, 16)), Slot.dinner);
  });

  test('household zone: wall clock and due-time instants', () {
    final instant = DateTime.utc(2026, 9, 26, 20, 0); // 01:30 IST next day
    final wall = wallClockIn(instant, 'Asia/Kolkata');
    expect((wall.day, wall.hour, wall.minute), (27, 1, 30));
    final due = instantFromWallClock(DateTime(2026, 9, 27, 13, 30), 'Asia/Kolkata');
    expect(due.toUtc(), DateTime.utc(2026, 9, 27, 8, 0));
    // Unknown zone → device time, never a crash.
    expect(wallClockIn(instant, 'Mars/Olympus'), instant.toLocal());
  });

  test('API mode defaults the household zone to Asia/Kolkata; the sandbox uses device time', () {
    final api = containerAt(
      testNoon,
      overrides: [appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test'))],
    );
    expect(api.read(householdTimezoneProvider), kDefaultTimezone);
    expect(containerAt(testNoon).read(householdTimezoneProvider), isNull);
  });

  test('"today" and the default slot move on the day tick (midnight / resume), not before', () {
    var now = DateTime(2026, 9, 26, 22);
    final c = ProviderContainer(overrides: [clockProvider.overrideWithValue(() => now)]);
    addTearDown(c.dispose);
    c.listen(planDateProvider, (_, _) {});
    c.listen(slotProvider, (_, _) {});
    expect(c.read(planDateProvider), DateTime(2026, 9, 26));
    expect(c.read(slotProvider), Slot.dinner);
    now = DateTime(2026, 9, 27, 8);
    expect(c.read(planDateProvider), DateTime(2026, 9, 26), reason: 'cached until the tick');
    c.read(dayTickProvider.notifier).tick();
    expect(c.read(planDateProvider), DateTime(2026, 9, 27));
    expect(c.read(slotProvider), Slot.breakfast);
  });
}
