import 'package:flutter/painting.dart';

import '../../../core/engine/fit_engine.dart';
import '../../../data/demo/demo_repository.dart';
import '../../../data/demo/demo_staples.dart';
import '../../../data/models.dart';
import '../../../data/repositories.dart' show wireDate;
import '../../account/data/account_repositories.dart';
import '../../account/domain/account_models.dart';
import '../../members/domain/member.dart';
import '../../pantry/data/pantry_repositories.dart';
import '../../pantry/domain/pantry_models.dart';
import '../../recipe/domain/recipe.dart';
import '../domain/kitchen_models.dart';
import 'kitchen_repositories.dart';

part 'demo_account.dart';
part 'demo_pantry.dart';

class _DemoMenu {
  _DemoMenu({required this.id, required this.date, required this.slot, required this.eaterIds, required this.dueAt});

  final String id;
  final String date;
  final String slot;
  List<String> recipeIds = [];
  List<String> eaterIds;
  Guests guests = const Guests();
  DateTime dueAt;
  String? assigneeCookId;
  bool assigneeChosen = false;
  double? servingsOverride;
  String notes = '';
  String? ticketId;
  int version = 1;
}

/// The in-memory kitchen behind demo mode: day menus, tickets with the
/// F-5.7-02 state machine (illegal moves throw the same 409 [KitchenError]
/// the API returns), cooks with the off-duty rule, the worker timers
/// (not_confirmed after due + 3 h, cancelled 24 h later, no-show alert), a
/// K6 thread per ticket and an inbox.
///
/// [asCook] is the same store seen from cook mode (its thread messages are
/// the cook's). Phase 6/7: [pantry] (stock, ration, ladder, approvals) and
/// [account] (settings, subscription, ratings, insights).
class DemoKitchen implements MenusRepository, TicketsRepository, CooksRepository, InboxRepository {
  DemoKitchen({required this.members, required this.now, this.recipes = const DemoRepository()}) {
    _seedInbox();
    _seedHistory();
  }

  /// The household's current members (eater defaults, coverage).
  final List<Member> Function() members;

  /// The demo clock (worker timers).
  final DateTime Function() now;
  final DemoRepository recipes;

  final List<Cook> _cooks = [
    const Cook(
      id: 'c1',
      name: 'Ramesh ji',
      kind: CookKind.hired,
      loginMode: 'app',
      isPrimary: true,
      onDuty: true,
      phoneMasked: '98xxxxxx21',
    ),
    const Cook(
      id: 'c2',
      name: 'Mummy',
      kind: CookKind.family,
      memberId: 'm2',
      loginMode: 'app',
      isBackup: true,
      onDuty: true,
    ),
  ];
  final Map<String, _DemoMenu> _menus = {};
  final Map<String, Ticket> _tickets = {};

  /// Current tickets (tests / debug).
  List<Ticket> get ticketsSnapshot => List.unmodifiable(_tickets.values);
  final Map<String, List<TicketMessage>> _messages = {};
  final List<InboxItem> _inbox = [];
  final Map<String, List<String>> _eaterDefaults = {};
  final Map<String, Object> _idempotent = {};
  final Set<String> _noShowSent = {};
  int _seq = 0;

  /// The demo user's cook role (Settings stub): null → family only.
  String? meCookId;

  /// The demo user always has family mode (admin).
  bool meIsFamily = true;

  late final TicketsRepository asCook = _CookView(this);

  late final DemoPantry pantry = DemoPantry(this);

  late final DemoAccount account = DemoAccount(this);

  String _id(String p) => '$p${++_seq}';

  // ---------------------------------------------------------------- menus

  _DemoMenu? _find(String date, String slot) {
    for (final m in _menus.values) {
      if (m.date == date && m.slot == slot) return m;
    }
    return null;
  }

  String _defaultsKey(String slot, String date) => '$slot|${parseWireDate(date).weekday}';

  _DemoMenu _ensure(String date, String slot) {
    final found = _find(date, slot);
    if (found != null) return found;
    final all = [for (final m in members()) m.id];
    final remembered = _eaterDefaults[_defaultsKey(slot, date)];
    final m = _DemoMenu(
      id: _id('menu'),
      date: date,
      slot: slot,
      eaterIds: remembered == null
          ? all
          : [
              for (final id in remembered)
                if (all.contains(id)) id,
            ],
      dueAt: defaultDueAt(parseWireDate(date), slot),
    );
    final primary = _primaryOnDuty(m.dueAt);
    m.assigneeCookId = primary?.id;
    _menus[m.id] = m;
    return m;
  }

  Cook? _cook(String? id) {
    for (final c in _cooks) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool _available(Cook c, DateTime at) => c.onDuty || (c.offDutyUntil != null && !at.isBefore(c.offDutyUntil!));

  Cook? _primaryOnDuty(DateTime at) {
    for (final c in _cooks) {
      if (c.isPrimary && _available(c, at)) return c;
    }
    for (final c in _cooks) {
      if (c.isBackup && _available(c, at)) return c;
    }
    return null;
  }

  Recipe? _recipe(String id) => recipes.byId(id);

  List<Member> _eatersOf(List<String> ids) => [
    for (final m in members())
      if (ids.contains(m.id)) m,
  ];

  static Member? _guestMember(Guests g) => g.count == 0 || g.diet == null
      ? null
      : Member(
          id: 'guest',
          name: 'Mehmaan',
          color: const Color(0xFF6B6A63),
          diet: switch (g.diet!) {
            GuestDiet.veg => Diet.veg,
            GuestDiet.jain => Diet.jain,
            GuestDiet.nonVeg => Diet.nonveg,
          },
        );

  static EaterRef _eaterRef(Member m) => EaterRef(memberId: m.id, name: m.name, colour: m.color, isKid: m.isKid);

  List<MenuDish> _dishes(List<String> ids, List<Member> eaters) => [
    for (final id in ids)
      if (_recipe(id) case final r?)
        MenuDish(
          recipeId: r.id,
          name: r.name,
          colour: r.color,
          mins: r.mins,
          summary: CardSummary.fromEngine(summarize(eaters, r)),
        ),
  ];

  static double servingsFor(List<Member> eaters, Guests guests) =>
      eaters.fold<double>(0, (s, m) => s + (m.isKid ? .5 : 1)) + guests.servings;

  Coverage _coverage(List<String> recipeIds, List<Member> eaters, Guests guests) {
    final rs = [for (final id in recipeIds) ?_recipe(id)];
    final people = [...eaters, ?_guestMember(guests)];
    final uncovered = [
      for (final m in people)
        if (!rs.any((r) => fitFor(m, r).kind != FitKind.no)) m.name,
    ];
    return Coverage(allCovered: rs.isNotEmpty && uncovered.isEmpty, uncovered: rs.isEmpty ? const [] : uncovered);
  }

  /// Slug id for an untracked ingredient line.
  static String ingredientId(String text) =>
      text.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

  /// Required items with live stock levels (tracked staples) from [pantry].
  List<RequiredItem> _required(List<String> recipeIds) => pantry.requiredFor(recipeIds);

  Assignee? _assigneeOf(String? cookId) {
    final c = _cook(cookId);
    return c == null ? null : Assignee(cookId: c.id, name: c.name, kind: c.kind);
  }

  Menu _view(_DemoMenu m) {
    final eaters = _eatersOf(m.eaterIds);
    return Menu(
      id: m.id,
      date: m.date,
      slot: m.slot,
      dishes: _dishes(m.recipeIds, eaters),
      eaters: [for (final e in eaters) _eaterRef(e)],
      guests: m.guests,
      servings: m.servingsOverride ?? servingsFor(eaters, m.guests),
      dueAt: m.dueAt,
      assignee: _assigneeOf(m.assigneeCookId),
      coverage: _coverage(m.recipeIds, eaters, m.guests),
      requiredItems: _required(m.recipeIds),
      ticketId: m.ticketId,
      version: m.version,
      notes: m.notes,
    );
  }

  @override
  Future<Menu?> menu(String date, String slot) async {
    final m = _find(date, slot);
    return m == null ? null : _view(m);
  }

  @override
  Future<List<Menu>> menusForDate(String date) async => [
    for (final m in _menus.values)
      if (m.date == date) _view(m),
  ];

  @override
  Future<Menu> putDishes(String date, String slot, List<String> recipeIds) async {
    final m = _ensure(date, slot);
    m.recipeIds = [for (final id in recipeIds) id];
    m.version++;
    return _view(m);
  }

  _DemoMenu _menuById(String id) =>
      _menus[id] ?? (throw const KitchenError(status: 404, code: 'menu_not_found', message: 'Menu not found'));

  @override
  Future<Menu> patchMenu(String id, MenuPatch patch) async {
    final m = _menuById(id);
    if (patch.eaters != null) {
      m.eaterIds = List.of(patch.eaters!);
      _eaterDefaults[_defaultsKey(m.slot, m.date)] = List.of(patch.eaters!);
      m.servingsOverride = null;
    }
    if (patch.guests != null) {
      m.guests = patch.guests!;
      m.servingsOverride = null;
    }
    if (patch.dueAt != null) m.dueAt = patch.dueAt!;
    if (patch.assigneeSet) {
      m.assigneeCookId = patch.assigneeCookId;
      m.assigneeChosen = true;
    }
    if (patch.notes != null) m.notes = patch.notes!;
    if (patch.servings != null) m.servingsOverride = patch.servings;
    m.version++;
    return _view(m);
  }

  @override
  Future<ConfirmResult> confirm(String id, {required int version, required String idempotencyKey}) async {
    final replay = _idempotent[idempotencyKey];
    if (replay is ConfirmResult) return replay;
    final m = _menuById(id);
    if (m.version != version) {
      throw const KitchenError(status: 409, code: KitchenError.versionMismatch);
    }
    final existing = m.ticketId == null ? null : _tickets[m.ticketId];
    if (existing != null && existing.status.isOpen) {
      throw const KitchenError(status: 409, code: KitchenError.alreadyConfirmed);
    }
    if (m.recipeIds.isEmpty) throw const KitchenError(status: 422, code: 'menu_empty');
    final view = _view(m);
    final cook = _cook(m.assigneeCookId);
    final TicketStatus status;
    Assignee? assignee;
    if (cook == null || !_available(cook, m.dueAt)) {
      status = TicketStatus.unassigned;
    } else {
      assignee = Assignee(cookId: cook.id, name: cook.name, kind: cook.kind);
      status = cook.kind == CookKind.hired ? TicketStatus.fresh : TicketStatus.accepted;
    }
    final at = now();
    final t = Ticket(
      id: _id('t'),
      menuId: m.id,
      date: m.date,
      slot: m.slot,
      dueAt: m.dueAt,
      status: status,
      assignee: assignee,
      dishes: view.dishes,
      eaters: view.eaters,
      guests: view.guests,
      servings: view.servings,
      notes: m.notes,
      acceptedAt: status == TicketStatus.accepted ? at : null,
      changeLog: [ChangeLogEntry(at: at, by: 'Aap', action: 'created', detail: status.wire)],
      version: 1,
      requiredItems: view.requiredItems,
    );
    _tickets[t.id] = t;
    m.ticketId = t.id;
    m.version++;
    _event(
      status == TicketStatus.unassigned ? 'ticket_unassigned' : 'ticket_created',
      status == TicketStatus.unassigned
          ? 'Ticket kisi ko assign nahi hua'
          : '${assignee!.name} ko ${_slotName(m.slot)} ka ticket gaya',
      t.id,
    );
    final result = ConfirmResult(ticket: t, shareText: _shareText(view));
    _idempotent[idempotencyKey] = result;
    return result;
  }

  static String _slotName(String slot) => switch (slot) {
    SlotKeys.nashta => 'Nashta',
    SlotKeys.lunch => 'Lunch',
    SlotKeys.dinner => 'Dinner',
    SlotKeys.tiffin => 'Tiffin',
    SlotKeys.shaam => 'Shaam ka nashta',
    _ => slot,
  };

  static String _hm(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')}';
  }

  static String _servingsText(double s) => s == s.roundToDouble() ? '${s.toInt()}' : s.toStringAsFixed(1);

  String _shareText(Menu m) {
    final b = StringBuffer()
      ..writeln('Banega · ${_slotName(m.slot)} menu (${m.date})')
      ..writeln('${_servingsText(m.servings)} logon ke liye · ${m.dueAt == null ? '' : 'Kab tak ${_hm(m.dueAt!)}'}')
      ..writeln()
      ..writeln('Dishes:');
    for (final d in m.dishes) {
      b.writeln('• ${d.name}');
    }
    if (m.requiredItems.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Saaman ki list:');
      for (final i in m.requiredItems) {
        b.writeln('• ${i.displayText}');
      }
    }
    if (m.notes.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Note: ${m.notes}');
    }
    return b.toString().trimRight();
  }

  @override
  Future<String> shareText(String id) async => _shareText(_view(_menuById(id)));

  // ---------------------------------------------------------------- tickets

  /// Worker timers, applied lazily on read.
  Ticket _tick(Ticket t) {
    var out = pantry.expire(t);
    final live = pantry.live(out.requiredItems);
    if (!_sameItems(live, out.requiredItems)) out = out.copyWith(requiredItems: live);
    if (!identical(out, t)) _tickets[t.id] = out;
    t = out;
    final due = t.dueAt;
    if (due == null) return t;
    final at = now();
    if ({TicketStatus.accepted, TicketStatus.cooking, TicketStatus.ready}.contains(t.status) &&
        at.isAfter(due.add(const Duration(hours: 3)))) {
      out = _log(t, TicketStatus.notConfirmed, 'System', 'not_confirmed');
      _event('not_confirmed_prompt', 'Khaana bana? ${_slotName(t.slot)} confirm nahi hua', t.id);
    }
    if (out.status == TicketStatus.notConfirmed && at.isAfter(due.add(const Duration(hours: 27)))) {
      out = _log(out, TicketStatus.cancelled, 'System', 'auto_cancelled');
    }
    if (out.status == TicketStatus.fresh &&
        at.isAfter(due.subtract(const Duration(minutes: 90))) &&
        _noShowSent.add(t.id)) {
      _event('no_show', '${t.assignee?.name ?? 'Cook'} ne ticket accept nahi kiya', t.id);
    }
    if (!identical(out, t)) _tickets[t.id] = out;
    return out;
  }

  Ticket _log(Ticket t, TicketStatus to, String by, String action, [String detail = '']) {
    final at = now();
    return Ticket(
      id: t.id,
      menuId: t.menuId,
      date: t.date,
      slot: t.slot,
      dueAt: t.dueAt,
      status: to,
      assignee: t.assignee,
      dishes: t.dishes,
      eaters: t.eaters,
      guests: t.guests,
      servings: t.servings,
      notes: t.notes,
      stockIssueOpen: t.stockIssueOpen,
      acceptedAt: to == TicketStatus.accepted ? at : t.acceptedAt,
      startedAt: to == TicketStatus.cooking ? at : t.startedAt,
      completedAt: to == TicketStatus.completed ? at : t.completedAt,
      completedBy: to == TicketStatus.completed ? by : t.completedBy,
      ratedAt: t.ratedAt,
      changeLog: [
        ...t.changeLog,
        ChangeLogEntry(at: at, by: by, action: action, detail: detail),
      ],
      version: t.version + 1,
      updated: to == TicketStatus.accepted || to == TicketStatus.cooking ? false : t.updated,
      requiredItems: t.requiredItems,
      ladder: t.ladder,
      stockIssue: t.stockIssue,
    );
  }

  static bool _sameItems(List<RequiredItem> a, List<RequiredItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].ingredientId != b[i].ingredientId || a[i].status != b[i].status) return false;
    }
    return true;
  }

  Ticket _store(Ticket t) => _tickets[t.id] = t;

  Ticket _withIssue(Ticket t, StockIssue? issue) => Ticket.fromJson({...t.toJson(), 'stock_issue': issue?.toJson()});

  Ticket _get(String id) {
    final t = _tickets[id];
    if (t == null) throw const KitchenError(status: 404, code: 'ticket_not_found');
    return _tick(t);
  }

  @override
  Future<List<Ticket>> tickets({String? date, String? status, bool mine = false}) async {
    final list = [
      for (final t in _tickets.values.toList())
        if (_tick(t) case final x)
          if ((date == null || x.date == date) &&
              (status == null || x.status.wire == status) &&
              (!mine || (x.assignee != null && x.assignee!.cookId == meCookId)))
            x,
    ]..sort((a, b) => (a.dueAt ?? DateTime(0)).compareTo(b.dueAt ?? DateTime(0)));
    return list;
  }

  @override
  Future<Ticket> ticket(String id) async => _get(id);

  @override
  Future<Ticket> transition(
    String id,
    TicketStatus to, {
    required int version,
    required String idempotencyKey,
    String? reason,
    String? note,
  }) async {
    final replay = _idempotent[idempotencyKey];
    if (replay is Ticket) return _tickets[replay.id] ?? replay;
    final t = _get(id);
    final allowed = legalTransitions[t.status]!.toList();
    if (!allowed.contains(to)) {
      throw KitchenError(status: 409, code: KitchenError.invalidTransition, allowed: allowed);
    }
    if (t.version != version) {
      throw KitchenError(status: 409, code: KitchenError.versionMismatch, allowed: allowed);
    }
    if (t.status == TicketStatus.cooking && to == TicketStatus.cancelled && (reason == null || reason.trim().isEmpty)) {
      throw KitchenError(status: 422, code: KitchenError.reasonRequired, allowed: allowed);
    }
    var base = t;
    if (t.status == TicketStatus.unassigned && to != TicketStatus.cancelled) {
      final c = _cook(meCookId) ?? _primaryOnDuty(t.dueAt ?? now());
      if (c != null) base = _reassign(t, c);
    }
    final by = switch (to) {
      TicketStatus.cancelled || TicketStatus.fresh => 'Admin',
      _ => base.assignee?.name ?? 'Admin',
    };
    final detail = [?reason, ?note].join(' · ');
    final next = _log(base, to, by, to.wire, detail);
    _tickets[id] = next;
    _idempotent[idempotencyKey] = next;
    switch (to) {
      case TicketStatus.accepted:
        _event('ticket_accepted', '${next.assignee?.name ?? 'Cook'} ne ${_slotName(t.slot)} accept kiya', id);
      case TicketStatus.completed:
        _event('ticket_completed', '${_slotName(t.slot)} ban gaya!', id);
        _onCompleted(next);
      case TicketStatus.cancelled:
        _event('ticket_cancelled', '${_slotName(t.slot)} ka ticket cancel hua', id);
      default:
    }
    return next;
  }

  /// Rate prompt (Phase 7) and the Should-level auto-decrement.
  void _onCompleted(Ticket t) {
    if (account.settings.ratingsEnabled) {
      _event(
        'rate_prompt',
        '${_slotName(t.slot)} kaisa bana? Rating do',
        t.id,
        body: t.dishes.map((d) => d.name).join(', '),
      );
    }
    if (account.settings.autoDecrement) {
      for (final i in t.requiredItems) {
        final st = DemoPantry.staple(i.ingredientId);
        if (st != null && st.perishable && pantry.levelOf(st.id) == ItemStatus.inStock) {
          pantry._set(st.id, ItemStatus.low, by: 'System');
        }
      }
    }
  }

  Ticket _reassign(Ticket t, Cook c) =>
      Ticket.fromJson({...t.toJson(), 'assignee': Assignee(cookId: c.id, name: c.name, kind: c.kind).toJson()});

  @override
  Future<Ticket> patchTicket(String id, TicketPatch patch, {required int version}) async {
    final t = _get(id);
    if (t.version != version) {
      throw KitchenError(
        status: 409,
        code: KitchenError.versionMismatch,
        allowed: legalTransitions[t.status]!.toList(),
      );
    }
    if (!t.status.isOpen) throw const KitchenError(status: 409, code: 'ticket_closed');
    final onlyNotes =
        patch.dishes == null &&
        patch.eaters == null &&
        patch.guests == null &&
        patch.servings == null &&
        patch.dueAt == null;
    if (!t.status.editable && !onlyNotes) {
      throw const KitchenError(status: 409, code: 'edit_not_allowed');
    }
    final j = t.toJson();
    final changed = <String>[];
    final eaterIds = patch.eaters ?? [for (final e in t.eaters) e.memberId];
    final eaters = _eatersOf(eaterIds);
    final guests = patch.guests ?? t.guests;
    if (patch.dishes != null) {
      j['dishes'] = [for (final d in _dishes(patch.dishes!, eaters)) d.toJson()];
      j['required_items'] = [for (final i in _required(patch.dishes!)) i.toJson()];
      changed.add('dishes');
    }
    if (patch.eaters != null) {
      j['eaters'] = [for (final e in eaters) _eaterRef(e).toJson()];
      changed.add('eaters');
    }
    if (patch.guests != null) {
      j['guests'] = guests.toJson();
      changed.add('guests');
    }
    if (patch.eaters != null || patch.guests != null) j['servings'] = servingsFor(eaters, guests);
    if (patch.servings != null) {
      j['servings'] = patch.servings;
      changed.add('servings');
    }
    if (patch.dueAt != null) {
      j['due_at'] = wireDateTime(patch.dueAt!);
      changed.add('due_at');
    }
    if (patch.notes != null) {
      j['notes'] = patch.notes;
      changed.add('notes');
    }
    var next = Ticket.fromJson(j);
    final hired = t.assignee?.kind == CookKind.hired;
    final reopen = hired && (t.status == TicketStatus.fresh || t.status == TicketStatus.accepted) && !onlyNotes;
    next = _log(next, reopen ? TicketStatus.fresh : t.status, 'Aap', 'updated', changed.join(', '));
    next = Ticket.fromJson({...next.toJson(), 'updated': true});
    _tickets[id] = next;
    if (t.assignee != null) _event('ticket_updated', '${_slotName(t.slot)} ka ticket badla: ${changed.join(', ')}', id);
    return next;
  }

  @override
  Future<Ticket> claim(String id) async {
    final t = _get(id);
    if (t.status != TicketStatus.unassigned) {
      throw KitchenError(status: 409, code: 'already_claimed', allowed: legalTransitions[t.status]!.toList());
    }
    final c = _cook(meCookId) ?? _cook('c2')!;
    final base = _reassign(t, c);
    final next = _log(base, c.kind == CookKind.hired ? TicketStatus.fresh : TicketStatus.accepted, c.name, 'claimed');
    _tickets[id] = next;
    return next;
  }

  @override
  Future<Ticket> markItemOut(String id, String ingredientId, {String? idempotencyKey}) async {
    final replay = idempotencyKey == null ? null : _idempotent[idempotencyKey];
    if (replay is Ticket) return _tickets[replay.id] ?? replay;
    final t = _get(id);
    final item = t.requiredItems.where((i) => i.ingredientId == ingredientId).firstOrNull;
    if (pantry.tracked(ingredientId) && pantry.levelOf(ingredientId) != ItemStatus.out) {
      pantry._set(ingredientId, ItemStatus.out, by: t.assignee?.name ?? 'Cook');
    }
    final name = pantry.tracked(ingredientId) ? pantry.nameOf(ingredientId) : (item?.displayText ?? ingredientId);
    final logged = _log(
      t.copyWith(
        stockIssueOpen: true,
        requiredItems: [
          for (final i in t.requiredItems) i.ingredientId == ingredientId ? i.withStatus(ItemStatus.out) : i,
        ],
      ),
      t.status,
      t.assignee?.name ?? 'Cook',
      LadderLog.itemOut,
      name,
    );
    final ladder = pantry.ladderFor(logged, ingredientId, name);
    final next = Ticket.fromJson({
      ...logged.toJson(),
      'ladder': ladder.toJson(),
      'stock_issue': StockIssue(ingredientId: ingredientId, name: name, state: StockIssueState.open).toJson(),
    });
    _tickets[id] = next;
    if (idempotencyKey != null) _idempotent[idempotencyKey] = next;
    _event('stock_issue', '$name khatam hai — ${_slotName(t.slot)}', id, body: 'Cook rasta chun raha hai');
    return next;
  }

  @override
  Future<Ticket> resolveStockIssue(
    String id,
    LadderAction action, {
    String? substituteIngredientId,
    String? recipeId,
    String? idempotencyKey,
  }) async => _resolve(id, action, substituteIngredientId, recipeId, idempotencyKey, asCook: false);

  Ticket _resolve(String id, LadderAction action, String? sub, String? recipe, String? key, {required bool asCook}) {
    final replay = key == null ? null : _idempotent[key];
    if (replay is Ticket) return _tickets[replay.id] ?? replay;
    final next = pantry.resolve(id, action, substituteIngredientId: sub, recipeId: recipe, asCook: asCook);
    if (key != null) _idempotent[key] = next;
    return next;
  }

  @override
  Future<List<TicketMessage>> messages(String id) async => List.of(_messages[id] ?? const []);

  @override
  Future<TicketMessage> sendMessage(String id, String text, {String? idempotencyKey}) =>
      _send(id, text, fromCook: false);

  Future<TicketMessage> _send(String id, String text, {required bool fromCook}) async {
    final t = _get(id);
    final m = TicketMessage(
      id: _id('msg'),
      text: text,
      author: fromCook ? (t.assignee?.name ?? 'Cook') : 'Parivaar',
      fromCook: fromCook,
      at: now(),
    );
    (_messages[id] ??= []).add(m);
    if (fromCook) _event('ticket_message', '${m.author}: $text', id);
    return m;
  }

  @override
  Future<CookRecipe> recipe(String ticketId, String recipeId, {int? servings}) async {
    final t = _get(ticketId);
    final eaters = _eatersOf([for (final e in t.eaters) e.memberId]);
    final detail = await recipes.recipe(recipeId, servings: servings ?? t.servingsInt, members: eaters);
    return CookRecipe(detail: detail);
  }

  // ---------------------------------------------------------------- cooks

  @override
  Future<List<Cook>> cooks() async => List.of(_cooks);

  @override
  Future<Cook> patchCook(String id, CookPatch patch) async {
    final i = _cooks.indexWhere((c) => c.id == id);
    if (i < 0) throw const KitchenError(status: 404, code: 'cook_not_found');
    final before = _cooks[i];
    var after = before.copyWith(
      onDuty: patch.onDuty,
      offDutyUntil: patch.offDutyUntil,
      clearOffDuty: patch.onDuty == true || (patch.offDutyUntilSet && patch.offDutyUntil == null),
    );
    if (patch.isPrimary != null || patch.isBackup != null) {
      final primary = patch.isPrimary ?? before.isPrimary;
      final backup = primary ? false : (patch.isBackup ?? before.isBackup);
      // One primary and one backup per household.
      for (var j = 0; j < _cooks.length; j++) {
        if (j == i) continue;
        final c = _cooks[j];
        _cooks[j] = _withRoles(c, primary: primary ? false : c.isPrimary, backup: backup ? false : c.isBackup);
      }
      after = _withRoles(after, primary: primary, backup: backup);
    }
    _cooks[i] = after;
    if (before.onDuty && !after.onDuty) _applyOffDuty(after);
    return after;
  }

  static Cook _withRoles(Cook c, {required bool primary, required bool backup}) => Cook(
    id: c.id,
    name: c.name,
    kind: c.kind,
    memberId: c.memberId,
    userId: c.userId,
    loginMode: c.loginMode,
    isPrimary: primary,
    isBackup: backup,
    onDuty: c.onDuty,
    offDutyUntil: c.offDutyUntil,
    phoneMasked: c.phoneMasked,
  );

  @override
  Future<Cook> addCook({
    required CookKind kind,
    required String name,
    String? phone,
    String? memberId,
    String loginMode = 'app',
  }) async {
    if (name.trim().isEmpty) throw const KitchenError(status: 422, code: 'name_required');
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (kind == CookKind.hired) {
      if (_cooks.any((c) => c.kind == CookKind.hired)) throw const KitchenError(status: 409, code: 'hired_cook_limit');
      if (digits.length < 10) throw const KitchenError(status: 422, code: 'invalid_phone');
    }
    final last = digits.length >= 10 ? digits.substring(digits.length - 10) : '';
    final c = Cook(
      id: _id('c'),
      name: name.trim(),
      kind: kind,
      memberId: memberId,
      loginMode: loginMode,
      isPrimary: !_cooks.any((c) => c.isPrimary),
      isBackup: _cooks.any((c) => c.isPrimary) && !_cooks.any((c) => c.isBackup),
      phoneMasked: last.isEmpty ? '' : '${last.substring(0, 2)}xxxxxx${last.substring(8)}',
    );
    _cooks.add(c);
    return c;
  }

  @override
  Future<void> removeCook(String id) async {
    final c = _cook(id);
    if (c == null) throw const KitchenError(status: 404, code: 'cook_not_found');
    _cooks.remove(c);
    if (meCookId == id) meCookId = null;
    for (final t in _tickets.values.toList()) {
      if (t.assignee?.cookId == id && t.status.isOpen && t.status != TicketStatus.notConfirmed) {
        _tickets[t.id] = _log(
          Ticket.fromJson({...t.toJson(), 'assignee': null}),
          TicketStatus.unassigned,
          'System',
          'unassigned',
          c.name,
        );
      }
    }
  }

  /// F-5.7-06: cooking stays; new/accepted due in the off period go to the
  /// backup if on duty, else unassigned; the admin is alerted.
  void _applyOffDuty(Cook c) {
    final until = c.offDutyUntil;
    for (final t in _tickets.values.toList()) {
      if (t.assignee?.cookId != c.id) continue;
      if (t.status != TicketStatus.fresh && t.status != TicketStatus.accepted) continue;
      final due = t.dueAt;
      if (due != null && until != null && !due.isBefore(until)) continue;
      // Available at the ticket's due time (on duty, or back from leave by then).
      final at = due ?? now();
      final backup = _cooks.where((b) => b.id != c.id && b.isBackup && _available(b, at)).firstOrNull;
      final Ticket next;
      if (backup != null) {
        next = _log(
          _reassign(t, backup),
          backup.kind == CookKind.hired ? TicketStatus.fresh : TicketStatus.accepted,
          'System',
          'reassigned',
          backup.name,
        );
      } else {
        next = _log(
          Ticket.fromJson({...t.toJson(), 'assignee': null}),
          TicketStatus.unassigned,
          'System',
          'unassigned',
          c.name,
        );
      }
      _tickets[t.id] = next;
    }
    _event('cook_off_duty', '${c.name} aaj chhutti par hain', null);
  }

  @override
  Future<Me> me() async {
    final c = _cook(meCookId);
    return Me(
      modes: ['family', if (c != null) 'cook'],
      cook: c == null ? null : MeCook(id: c.id, kind: c.kind, loginMode: c.loginMode),
      userId: 'demo-user',
      householdId: 'demo-household',
      isAdmin: true,
    );
  }

  // ---------------------------------------------------------------- inbox

  void _event(
    String event,
    String title,
    String? ticketId, {
    String body = '',
    String? approvalId,
    String? rationRequestId,
    String? link,
  }) {
    if (account._prefs[event]?.enabled == false) return;
    _inbox.insert(
      0,
      InboxItem(
        id: _id('ev'),
        event: event,
        title: title,
        body: body,
        ticketId: ticketId,
        createdAt: now(),
        approvalId: approvalId,
        rationRequestId: rationRequestId,
        link: link,
      ),
    );
  }

  /// Yesterday's dinner, cooked and not yet rated (rate prompt, weekly card).
  void _seedHistory() {
    final at = now();
    final y = DateTime(at.year, at.month, at.day - 1);
    final eaters = members();
    final due = defaultDueAt(y, SlotKeys.dinner);
    final ramesh = _cooks.first;
    final t = Ticket(
      id: _id('t'),
      date: wireDate(y),
      slot: SlotKeys.dinner,
      dueAt: due,
      status: TicketStatus.completed,
      assignee: Assignee(cookId: ramesh.id, name: ramesh.name, kind: ramesh.kind),
      dishes: _dishes(['daltadka'], eaters),
      eaters: [for (final e in eaters) _eaterRef(e)],
      servings: servingsFor(eaters, const Guests()),
      acceptedAt: due.subtract(const Duration(hours: 3)),
      startedAt: due.subtract(const Duration(hours: 1)),
      completedAt: due.subtract(const Duration(minutes: 10)),
      completedBy: ramesh.name,
      changeLog: [
        ChangeLogEntry(at: due.subtract(const Duration(hours: 4)), by: 'Aap', action: 'created', detail: 'new'),
        ChangeLogEntry(at: due.subtract(const Duration(minutes: 10)), by: ramesh.name, action: 'completed'),
      ],
      version: 4,
      requiredItems: _required(['daltadka']),
    );
    _tickets[t.id] = t;
    _inbox.insert(
      0,
      InboxItem(
        id: _id('ev'),
        event: 'rate_prompt',
        title: 'Kal ka dinner kaisa bana? Rating do',
        body: 'Ramesh ji ne Dal Tadka banaya',
        ticketId: t.id,
        createdAt: at.subtract(const Duration(hours: 14)),
      ),
    );
  }

  void _seedInbox() {
    final at = now();
    _inbox.addAll([
      InboxItem(
        id: _id('ev'),
        event: 'tomorrow_tickets',
        title: 'Kal ke liye 2 meal plan karne baaki hain',
        body: 'Nashta aur lunch ka menu abhi set karo',
        createdAt: at.subtract(const Duration(hours: 1)),
      ),
      InboxItem(
        id: _id('ev'),
        event: 'ticket_completed',
        title: 'Kal raat ka dinner ban gaya',
        body: 'Ramesh ji ne Dal Tadka + Jeera Rice banaya',
        createdAt: at.subtract(const Duration(hours: 16)),
        readAt: at.subtract(const Duration(hours: 15)),
      ),
      InboxItem(
        id: _id('ev'),
        event: 'cook_off_duty',
        title: 'Ramesh ji Sunday ko chhutti par hain',
        body: 'Sunday ke tickets Mummy ko jaayenge',
        createdAt: at.subtract(const Duration(days: 1)),
      ),
    ]);
  }

  @override
  Future<List<InboxItem>> inbox({String? cursor}) async => List.of(_inbox);

  @override
  Future<void> markRead(String id) async {
    final i = _inbox.indexWhere((e) => e.id == id);
    if (i >= 0 && _inbox[i].unread) _inbox[i] = _inbox[i].markRead(now());
  }

  /// Today in the demo clock, `YYYY-MM-DD`.
  String get today => wireDate(now());
}

/// The kitchen seen from cook mode.
class _CookView implements TicketsRepository {
  _CookView(this.k);

  final DemoKitchen k;

  @override
  Future<List<Ticket>> tickets({String? date, String? status, bool mine = false}) =>
      k.tickets(date: date, status: status, mine: mine);

  @override
  Future<Ticket> ticket(String id) => k.ticket(id);

  @override
  Future<Ticket> transition(
    String id,
    TicketStatus to, {
    required int version,
    required String idempotencyKey,
    String? reason,
    String? note,
  }) => k.transition(id, to, version: version, idempotencyKey: idempotencyKey, reason: reason, note: note);

  @override
  Future<Ticket> patchTicket(String id, TicketPatch patch, {required int version}) =>
      k.patchTicket(id, patch, version: version);

  @override
  Future<Ticket> claim(String id) => k.claim(id);

  @override
  Future<Ticket> markItemOut(String id, String ingredientId, {String? idempotencyKey}) =>
      k.markItemOut(id, ingredientId, idempotencyKey: idempotencyKey);

  @override
  Future<Ticket> resolveStockIssue(
    String id,
    LadderAction action, {
    String? substituteIngredientId,
    String? recipeId,
    String? idempotencyKey,
  }) async => k._resolve(id, action, substituteIngredientId, recipeId, idempotencyKey, asCook: true);

  @override
  Future<List<TicketMessage>> messages(String id) => k.messages(id);

  @override
  Future<TicketMessage> sendMessage(String id, String text, {String? idempotencyKey}) =>
      k._send(id, text, fromCook: true);

  @override
  Future<CookRecipe> recipe(String ticketId, String recipeId, {int? servings}) =>
      k.recipe(ticketId, recipeId, servings: servings);
}
