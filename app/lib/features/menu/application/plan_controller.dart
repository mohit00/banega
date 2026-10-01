import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../data/repositories.dart' show wireDate, SlotWire;
import '../../home/home_providers.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../../recipe/domain/recipe.dart';
import 'day_menu.dart';

@immutable
class PlanState {
  const PlanState({
    required this.date,
    required this.slot,
    this.menu,
    this.ticket,
    this.shareText,
    this.loading = false,
    this.error,
    this.checked = const {},
    this.sending = false,
    this.sharing = false,
  });

  final DateTime date;
  final Slot slot;

  /// The server's day menu for (date, slot); null → nothing planned yet.
  final Menu? menu;

  /// The menu's ticket, when it has been confirmed.
  final Ticket? ticket;

  /// WhatsApp text from the last confirm.
  final String? shareText;
  final bool loading;
  final Object? error;

  /// Saaman rows ticked off (local only).
  final Set<String> checked;
  final bool sending;

  /// The share sheet is being prepared (share-text fetch in flight).
  final bool sharing;

  bool get hasDishes => (menu?.dishes.isNotEmpty ?? false);

  /// The menu already went to the kitchen and is still open.
  bool get sent => ticket != null && ticket!.status.isOpen;

  DateTime get dueAt => menu?.dueAt ?? defaultDueAt(date, slot.wire);

  PlanState copyWith({
    DateTime? date,
    Slot? slot,
    Menu? menu,
    bool clearMenu = false,
    Ticket? ticket,
    bool clearTicket = false,
    String? shareText,
    bool? loading,
    Object? error,
    bool clearError = false,
    Set<String>? checked,
    bool? sending,
    bool? sharing,
  }) => PlanState(
    date: date ?? this.date,
    slot: slot ?? this.slot,
    menu: clearMenu ? null : (menu ?? this.menu),
    ticket: clearTicket ? null : (ticket ?? this.ticket),
    shareText: shareText ?? this.shareText,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    checked: checked ?? this.checked,
    sending: sending ?? this.sending,
    sharing: sharing ?? this.sharing,
  );
}

/// S8 Plan: syncs the day-menu draft to PUT /v1/menus/{date}/{slot}/dishes,
/// edits eaters / guests / servings / due / assignee through PATCH, and
/// confirms into a ticket.
final planControllerProvider = NotifierProvider.autoDispose<PlanController, PlanState>(PlanController.new);

class PlanController extends Notifier<PlanState> {
  int _syncSeq = 0;

  @override
  PlanState build() {
    final s = PlanState(date: ref.read(planDateProvider), slot: ref.read(slotProvider), loading: true);
    Future.microtask(sync);
    return s;
  }

  MenuKey get key => menuKey(state.date, state.slot);

  /// Loads the server's menu for the selected (date, slot) and reconciles it
  /// with that key's draft only:
  ///
  /// - a synced draft (loaded here before) is authoritative: written when it
  ///   differs from the server;
  /// - otherwise the draft holds local additions (Home / Chat / Detail ADD),
  ///   merged after the server's dishes and written when that adds any.
  ///
  /// The result seeds the key's draft while the menu is not yet sent, so Home
  /// shows it and later ADDs extend it instead of replacing it.
  Future<void> sync() async {
    if (!ref.mounted) return;
    final seq = ++_syncSeq;
    final key = this.key;
    final drafts = ref.read(dayMenuProvider.notifier);
    final repo = ref.read(menusRepositoryProvider);
    state = state.copyWith(loading: true, clearError: true);
    try {
      final date = wireDate(state.date);
      final slot = state.slot.wire;
      final server = await repo.menu(date, slot);
      final serverEntries = [for (final d in server?.dishes ?? const <MenuDish>[]) MenuEntry(d.recipeId, d.name)];
      final draft = drafts.entries(key);
      final List<MenuEntry> want;
      if (drafts.isSynced(key)) {
        want = draft;
      } else {
        final ids = {for (final e in serverEntries) e.id};
        want = [
          ...serverEntries,
          for (final e in draft)
            if (!ids.contains(e.id)) e,
        ];
      }
      final same = listEquals([for (final e in want) e.id], [for (final e in serverEntries) e.id]);
      final menu = same ? server : await repo.putDishes(date, slot, [for (final e in want) e.id]);
      await _settle(seq, key, menu);
    } catch (e) {
      if (!ref.mounted || seq != _syncSeq) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  /// Applies a loaded / written [menu] for [key] (unless a newer sync or a
  /// date / slot switch superseded it) and reads its ticket.
  Future<void> _settle(int seq, MenuKey key, Menu? menu) async {
    Ticket? ticket;
    if (menu?.ticketId != null) {
      try {
        ticket = await ref.read(ticketsRepositoryProvider).ticket(menu!.ticketId!);
      } catch (_) {}
    }
    if (!ref.mounted || seq != _syncSeq) return;
    final drafts = ref.read(dayMenuProvider.notifier);
    if (menu == null || menu.ticketId == null) {
      drafts.replaceAll(key, [for (final d in menu?.dishes ?? const <MenuDish>[]) MenuEntry(d.recipeId, d.name)]);
    } else {
      // Already sent: the dishes live on the server; keep no local copy.
      drafts.clear(key);
    }
    state = state.copyWith(
      menu: menu,
      clearMenu: menu == null,
      ticket: ticket,
      clearTicket: ticket == null,
      loading: false,
    );
  }

  /// Switches to [d]'s menu for the current slot (its own draft).
  Future<void> setDate(DateTime d) async {
    state = state.copyWith(
      date: DateTime(d.year, d.month, d.day),
      checked: const {},
      clearMenu: true,
      clearTicket: true,
    );
    await sync();
  }

  /// Switches to [s]'s menu for the current date (its own draft).
  Future<void> setSlot(Slot s) async {
    state = state.copyWith(slot: s, checked: const {}, clearMenu: true, clearTicket: true);
    await sync();
  }

  /// Removes a dish (the × on a row) and writes the rest.
  Future<void> removeDish(String recipeId) async {
    final key = this.key;
    final seq = ++_syncSeq;
    final rest = [
      for (final d in state.menu?.dishes ?? const <MenuDish>[])
        if (d.recipeId != recipeId) MenuEntry(d.recipeId, d.name),
    ];
    ref.read(dayMenuProvider.notifier).replaceAll(key, rest);
    state = state.copyWith(loading: true, clearError: true);
    try {
      final menu = await ref.read(menusRepositoryProvider).putDishes(wireDate(state.date), state.slot.wire, [
        for (final e in rest) e.id,
      ]);
      await _settle(seq, key, menu);
    } catch (e) {
      if (!ref.mounted || seq != _syncSeq) return;
      state = state.copyWith(loading: false, error: e);
      rethrow;
    }
  }

  Future<void> _patch(MenuPatch p) async {
    final menu = state.menu;
    if (menu == null) return;
    final next = await ref.read(menusRepositoryProvider).patchMenu(menu.id, p);
    if (!ref.mounted) return;
    state = state.copyWith(menu: next);
  }

  Future<void> toggleEater(String memberId) {
    final ids = [for (final e in state.menu?.eaters ?? const <EaterRef>[]) e.memberId];
    final next = ids.contains(memberId)
        ? [
            for (final id in ids)
              if (id != memberId) id,
          ]
        : [...ids, memberId];
    return _patch(MenuPatch(eaters: next));
  }

  Future<void> setGuests(Guests g) => _patch(MenuPatch(guests: g));

  Future<void> setServings(double v) => _patch(MenuPatch(servings: v < .5 ? .5 : v));

  /// [hour]:[minute] on the household's clock (not the phone's zone).
  Future<void> setDue(int hour, int minute) {
    final d = state.date;
    final wall = DateTime(d.year, d.month, d.day, hour, minute);
    return _patch(MenuPatch(dueAt: instantFromWallClock(wall, ref.read(householdTimezoneProvider))));
  }

  Future<void> setAssignee(String? cookId) => _patch(MenuPatch(assigneeCookId: cookId, assigneeSet: true));

  /// The WhatsApp text for the current menu (last confirm's, else fetched);
  /// ignored while a previous share is still being prepared.
  Future<String?> shareText() async {
    final menu = state.menu;
    if (state.sharing || menu == null) return null;
    state = state.copyWith(sharing: true);
    try {
      return state.shareText ?? await ref.read(menusRepositoryProvider).shareText(menu.id);
    } finally {
      if (ref.mounted) state = state.copyWith(sharing: false);
    }
  }

  void toggleChecked(String ingredientId) {
    final c = {...state.checked};
    if (!c.remove(ingredientId)) c.add(ingredientId);
    state = state.copyWith(checked: c);
  }

  /// POST confirm (Idempotency-Key per intent: menu id + version; If-Match =
  /// menu version). A second call while one is in flight is ignored.
  /// Clears the Home draft and refreshes the ticket views.
  Future<ConfirmResult> confirm() async {
    final menu = state.menu;
    if (menu == null) throw StateError('no menu');
    if (state.sending) throw const AlreadyInFlight('confirm');
    state = state.copyWith(sending: true);
    try {
      final r = await ref
          .read(menusRepositoryProvider)
          .confirm(
            menu.id,
            version: menu.version,
            idempotencyKey: ref.read(intentKeyProvider)(['confirm', menu.id, menu.version]),
          );
      ref.read(dayMenuProvider.notifier).clear(menuKey(state.date, state.slot));
      ref.read(kitchenRevisionProvider.notifier).bump();
      if (ref.mounted) {
        state = state.copyWith(
          ticket: r.ticket,
          shareText: r.shareText,
          menu: await ref.read(menusRepositoryProvider).menu(menu.date, menu.slot) ?? menu,
          sending: false,
        );
      }
      return r;
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(sending: false);
        if (e is KitchenError && e.isConflict) await sync();
      }
      rethrow;
    }
  }
}
