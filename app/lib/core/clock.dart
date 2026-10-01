import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/data_source.dart';
import '../features/account/application/account_providers.dart';
import 'config.dart';

/// Default household zone (the backend's default too).
const kDefaultTimezone = 'Asia/Kolkata';

bool _tzReady = false;

tz.Location? _location(String name) {
  if (!_tzReady) {
    tzdata.initializeTimeZones();
    _tzReady = true;
  }
  try {
    return tz.getLocation(name);
  } catch (_) {
    return null;
  }
}

/// The household's zone (`Household.timezone`, default Asia/Kolkata) in API
/// mode; null in the sandbox (device time: the demo family has no zone).
final householdTimezoneProvider = Provider<String?>((ref) {
  if (ref.watch(dataSourceProvider) != DataSource.api) return null;
  return ref.watch(householdSettingsProvider).value?.timezone ?? kDefaultTimezone;
});

/// [instant] as a wall-clock [DateTime] in [zone] (device local when null or
/// unknown). The result's fields are the household's date and time.
DateTime wallClockIn(DateTime instant, String? zone) {
  final loc = zone == null ? null : _location(zone);
  if (loc == null) return instant.toLocal();
  final z = tz.TZDateTime.from(instant, loc);
  return DateTime(z.year, z.month, z.day, z.hour, z.minute, z.second, z.millisecond);
}

/// A household wall-clock time ([wall]'s fields) → the real instant, for
/// writes such as `due_at` (sent with an offset, so the server gets the
/// right moment whatever zone the phone is in).
DateTime instantFromWallClock(DateTime wall, String? zone) {
  final loc = zone == null ? null : _location(zone);
  if (loc == null) return wall;
  return tz.TZDateTime(loc, wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second).toLocal();
}

/// "Now" on the household's wall clock.
final householdNowProvider = Provider<DateTime Function()>((ref) {
  final clock = ref.watch(clockProvider);
  final zone = ref.watch(householdTimezoneProvider);
  return () => wallClockIn(clock(), zone);
});

/// Bumped at the household's midnight and 04:00 (the planning day rolls
/// over at 04:00) and whenever the app resumes, so "today" and the default
/// slot never go stale. Driven by [DayTicker].
final dayTickProvider = NotifierProvider<DayTick, int>(DayTick.new);

class DayTick extends Notifier<int> {
  @override
  int build() => 0;

  void tick() => state++;
}

/// Keeps [dayTickProvider] moving: a timer to the next 00:00 / 04:00 on the
/// household clock, and a tick on every resume. Owned by the app widget so
/// the timer dies with the tree.
class DayTicker extends ConsumerStatefulWidget {
  const DayTicker({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DayTicker> createState() => _DayTickerState();
}

class _DayTickerState extends ConsumerState<DayTicker> {
  Timer? _timer;
  AppLifecycleListener? _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: _tick);
    _schedule();
  }

  void _tick() {
    if (!mounted) return;
    ref.read(dayTickProvider.notifier).tick();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final now = ref.read(householdNowProvider)();
    final today = DateTime(now.year, now.month, now.day);
    final four = today.add(const Duration(hours: 4));
    final next = now.isBefore(four) ? four : today.add(const Duration(days: 1));
    _timer = Timer(next.difference(now) + const Duration(seconds: 1), _tick);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _life?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
