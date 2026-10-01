import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/home_providers.dart';
import '../../recipe/domain/recipe.dart';

/// One dish on a day menu. The name is kept so the sticky bar can list it
/// without re-fetching the recipe.
@immutable
class MenuEntry {
  const MenuEntry(this.id, this.name);
  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is MenuEntry && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'MenuEntry($id)';
}

/// Which day menu a draft belongs to: (local date at midnight, slot).
typedef MenuKey = ({DateTime date, Slot slot});

MenuKey menuKey(DateTime date, Slot slot) => (date: DateTime(date.year, date.month, date.day), slot: slot);

/// The key Home, Chat and Detail write to: the date Home plans for and the
/// slot it shows.
final homeMenuKeyProvider = Provider<MenuKey>((ref) => menuKey(ref.watch(planDateProvider), ref.watch(slotProvider)));

/// Day-menu drafts (prototype `state.plan`), one per (date, slot). ADD /
/// "Menu mein daalo" toggle dishes in and out of a key's draft; Plan syncs a
/// key's draft with the server's menu for that (date, slot) only, so
/// switching the Plan's date or slot never moves dishes between menus.
final dayMenuProvider = NotifierProvider<DayMenuController, Map<MenuKey, List<MenuEntry>>>(DayMenuController.new);

/// The draft for Home's key (the sticky bar, "Menu · n", ADD states).
final activeMenuProvider = Provider<List<MenuEntry>>((ref) {
  final key = ref.watch(homeMenuKeyProvider);
  return ref.watch(dayMenuProvider)[key] ?? const <MenuEntry>[];
});

class DayMenuController extends Notifier<Map<MenuKey, List<MenuEntry>>> {
  /// Keys whose draft mirrors the server menu (loaded by Plan): the draft is
  /// authoritative and is written as-is. Other keys only hold local
  /// additions, which Plan merges into the server's dishes.
  final Set<MenuKey> _synced = {};

  @override
  Map<MenuKey, List<MenuEntry>> build() => const {};

  MenuKey _key(MenuKey? key) => key ?? ref.read(homeMenuKeyProvider);

  List<MenuEntry> entries([MenuKey? key]) => state[_key(key)] ?? const [];

  bool contains(String id, {MenuKey? key}) => entries(key).any((e) => e.id == id);

  bool isSynced(MenuKey key) => _synced.contains(key);

  void _set(MenuKey key, List<MenuEntry> list) {
    final next = {...state};
    if (list.isEmpty) {
      next.remove(key);
    } else {
      next[key] = List.unmodifiable(list);
    }
    state = Map.unmodifiable(next);
  }

  /// Adds or removes a dish; [key] defaults to Home's (date, slot).
  void toggle(String id, String name, {MenuKey? key}) {
    final k = _key(key);
    final cur = entries(k);
    _set(
      k,
      cur.any((e) => e.id == id)
          ? [
              for (final e in cur)
                if (e.id != id) e,
            ]
          : [...cur, MenuEntry(id, name)],
    );
  }

  /// Replaces [key]'s draft with the server's dishes (after Plan loads or
  /// writes that menu); the draft is then authoritative for [key].
  void replaceAll(MenuKey key, List<MenuEntry> entries, {bool synced = true}) {
    _set(key, entries);
    if (synced) {
      _synced.add(key);
    } else {
      _synced.remove(key);
    }
  }

  /// Empties [key]'s draft once it has been sent as a ticket; the next local
  /// addition is merged with the server's dishes again.
  void clear(MenuKey key) {
    _synced.remove(key);
    _set(key, const []);
  }

  /// Drops every draft (logout / household deletion).
  void reset() {
    _synced.clear();
    state = const {};
  }
}
