// Phase 5 wire models: day menus, tickets, cooks, inbox and the cook-mode
// recipe (docs/contracts/phase5-menus-tickets.md). `fromJson` parses the
// contract shapes; `toJson` round-trips them for the offline cache.
import 'package:flutter/widgets.dart';

import '../../../data/models.dart';

export '../../../core/network/app_error.dart';
import '../../recipe/domain/recipe.dart';

part 'ladder_models.dart';

// ------------------------------------------------------------------ helpers

List<Json> _maps(Object? v) => [for (final x in (v as List? ?? const [])) (x as Map).cast<String, dynamic>()];

DateTime? _time(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

String? _str(Object? v) => v == null ? null : '$v';

double _num(Object? v, [double fallback = 0]) => v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// A local [DateTime] as ISO-8601 with the device offset
/// (`2026-09-26T13:30:00+05:30`). The contract wants household time; the
/// device zone stands in for it on the client.
String wireDateTime(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final off = l.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final m = off.inMinutes.abs();
  return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}'
      'T${two(l.hour)}:${two(l.minute)}:${two(l.second)}$sign${two(m ~/ 60)}:${two(m % 60)}';
}

/// `YYYY-MM-DD` → local midnight.
DateTime parseWireDate(String d) {
  final p = DateTime.tryParse(d);
  return p == null ? DateTime.now() : DateTime(p.year, p.month, p.day);
}

// ------------------------------------------------------------------ slots

/// Contract slot keys; the app's [Slot] covers the first three.
abstract final class SlotKeys {
  static const nashta = 'nashta';
  static const lunch = 'lunch';
  static const dinner = 'dinner';
  static const tiffin = 'tiffin';
  static const shaam = 'shaam';
}

Slot? slotFromKey(String key) => switch (key) {
  SlotKeys.nashta => Slot.breakfast,
  SlotKeys.lunch => Slot.lunch,
  SlotKeys.dinner => Slot.dinner,
  _ => null,
};

/// Default due time per slot (F-5.7-01): Nashta 08:30, Lunch 13:30, Dinner
/// 20:30; tiffin 07:30 and shaam 17:30 for the optional slots.
(int, int) defaultDueFor(String slotKey) => switch (slotKey) {
  SlotKeys.nashta => (8, 30),
  SlotKeys.lunch => (13, 30),
  SlotKeys.dinner => (20, 30),
  SlotKeys.tiffin => (7, 30),
  SlotKeys.shaam => (17, 30),
  _ => (13, 30),
};

DateTime defaultDueAt(DateTime date, String slotKey) {
  final (h, m) = defaultDueFor(slotKey);
  return DateTime(date.year, date.month, date.day, h, m);
}

// ------------------------------------------------------------------ enums

enum TicketStatus {
  fresh('new'),
  unassigned('unassigned'),
  accepted('accepted'),
  cooking('cooking'),
  ready('ready'),
  completed('completed'),
  notConfirmed('not_confirmed'),
  cancelled('cancelled'),

  /// A status this build does not know (newer server): shown as-is, no
  /// actions offered.
  unknown('unknown');

  const TicketStatus(this.wire);
  final String wire;

  static TicketStatus fromWire(String? v) => values.firstWhere((s) => s.wire == v, orElse: () => unknown);

  bool get isOpen => this != completed && this != cancelled && this != unknown;

  /// Before Cooking: edits allowed (FR-K7).
  bool get editable => this == fresh || this == unassigned || this == accepted;
}

/// Transitions a user may request through POST /tickets/{id}/transitions
/// (docs/frd-review.md F-5.7-02). System-only moves (→ not_confirmed, the
/// "updated" re-open on edit) are not listed.
const Map<TicketStatus, Set<TicketStatus>> legalTransitions = {
  TicketStatus.fresh: {TicketStatus.accepted, TicketStatus.cancelled},
  TicketStatus.unassigned: {TicketStatus.fresh, TicketStatus.accepted, TicketStatus.cancelled},
  TicketStatus.accepted: {TicketStatus.cooking, TicketStatus.cancelled},
  TicketStatus.cooking: {TicketStatus.ready, TicketStatus.completed, TicketStatus.cancelled},
  TicketStatus.ready: {TicketStatus.completed},
  TicketStatus.notConfirmed: {TicketStatus.completed, TicketStatus.cancelled},
  TicketStatus.completed: {},
  TicketStatus.cancelled: {},
  TicketStatus.unknown: {},
};

enum CookKind {
  hired,
  family;

  static CookKind fromWire(String? v) => v == 'family' ? family : hired;
}

enum GuestDiet {
  veg('veg'),
  jain('jain'),
  nonVeg('non_veg');

  const GuestDiet(this.wire);
  final String wire;

  static GuestDiet? fromWire(String? v) {
    for (final d in values) {
      if (d.wire == v) return d;
    }
    return null;
  }
}

enum ItemStatus {
  inStock('in'),
  low('low'),
  out('out'),
  untracked('untracked');

  const ItemStatus(this.wire);
  final String wire;

  static ItemStatus fromWire(String? v) => values.firstWhere((s) => s.wire == v, orElse: () => untracked);
}

// ------------------------------------------------------------------ errors

// ------------------------------------------------------------------ shapes

@immutable
class EaterRef {
  const EaterRef({required this.memberId, required this.name, required this.colour, this.isKid = false});

  final String memberId;
  final String name;
  final Color colour;
  final bool isKid;

  factory EaterRef.fromJson(Json j) => EaterRef(
    memberId: '${j['member_id']}',
    name: j['name'] as String? ?? '',
    colour: parseColour(j['colour'] as String?),
    isKid: j['is_kid'] as bool? ?? false,
  );

  Json toJson() => {'member_id': memberId, 'name': name, 'colour': _hex(colour), 'is_kid': isKid};
}

@immutable
class Guests {
  const Guests({this.adults = 0, this.kids = 0, this.diet});

  final int adults;
  final int kids;
  final GuestDiet? diet;

  int get count => adults + kids;

  double get servings => adults + kids * .5;

  Guests copyWith({int? adults, int? kids, GuestDiet? diet, bool clearDiet = false}) =>
      Guests(adults: adults ?? this.adults, kids: kids ?? this.kids, diet: clearDiet ? null : (diet ?? this.diet));

  factory Guests.fromJson(Object? v) {
    final j = v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
    return Guests(
      adults: (j['adults'] as num?)?.toInt() ?? 0,
      kids: (j['kids'] as num?)?.toInt() ?? 0,
      diet: GuestDiet.fromWire(j['diet'] as String?),
    );
  }

  Json toJson() => {'adults': adults, 'kids': kids, 'diet': diet?.wire};

  @override
  bool operator ==(Object other) =>
      other is Guests && other.adults == adults && other.kids == kids && other.diet == diet;

  @override
  int get hashCode => Object.hash(adults, kids, diet);
}

/// One dish on a menu / ticket. `summary` is the RecipeCard summary object
/// when the server sends one, or a plain note string.
@immutable
class MenuDish {
  const MenuDish({
    required this.recipeId,
    required this.name,
    required this.colour,
    this.imageUrl,
    this.mins = 0,
    this.summary,
    this.note,
  });

  final String recipeId;
  final String name;
  final Color colour;
  final String? imageUrl;
  final int mins;
  final CardSummary? summary;
  final String? note;

  factory MenuDish.fromJson(Json j) {
    final s = j['summary'];
    return MenuDish(
      recipeId: '${j['recipe_id']}',
      name: j['name'] as String? ?? '',
      colour: parseColour(j['colour'] as String?),
      imageUrl: j['image_url'] is String && (j['image_url'] as String).isNotEmpty ? j['image_url'] as String : null,
      mins: (j['mins'] as num?)?.toInt() ?? 0,
      summary: s is Map ? CardSummary.fromJson(s.cast<String, dynamic>()) : null,
      note: s is String ? s : null,
    );
  }

  Json toJson() => {
    'recipe_id': recipeId,
    'name': name,
    'colour': _hex(colour),
    'image_url': imageUrl,
    'mins': mins,
    'summary': summary == null
        ? note
        : {
            'badge': summary!.badge.name,
            'label_key': summary!.labelKey,
            'label_params': summary!.labelParams,
            'note_key': summary!.noteKey,
            'note_params': summary!.noteParams,
          },
  };
}

@immutable
class Assignee {
  const Assignee({required this.cookId, required this.name, required this.kind});

  final String cookId;
  final String name;
  final CookKind kind;

  static Assignee? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    return Assignee(
      cookId: '${j['cook_id']}',
      name: j['name'] as String? ?? '',
      kind: CookKind.fromWire(j['kind'] as String?),
    );
  }

  Json toJson() => {'cook_id': cookId, 'name': name, 'kind': kind.name};
}

@immutable
class Coverage {
  const Coverage({required this.allCovered, this.uncovered = const []});

  final bool allCovered;
  final List<String> uncovered;

  factory Coverage.fromJson(Object? v) {
    final j = v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
    return Coverage(
      allCovered: j['all_covered'] as bool? ?? false,
      uncovered: [for (final n in (j['uncovered'] as List? ?? const [])) '$n'],
    );
  }

  Json toJson() => {'all_covered': allCovered, 'uncovered': uncovered};
}

@immutable
class RequiredItem {
  const RequiredItem({required this.ingredientId, required this.displayText, required this.status});

  final String ingredientId;
  final String displayText;
  final ItemStatus status;

  factory RequiredItem.fromJson(Json j) => RequiredItem(
    ingredientId: '${j['ingredient_id']}',
    displayText: j['display_text'] as String? ?? '',
    status: ItemStatus.fromWire(j['status'] as String?),
  );

  Json toJson() => {'ingredient_id': ingredientId, 'display_text': displayText, 'status': status.wire};

  RequiredItem withStatus(ItemStatus s) =>
      RequiredItem(ingredientId: ingredientId, displayText: displayText, status: s);
}

@immutable
class ChangeLogEntry {
  const ChangeLogEntry({required this.at, required this.by, required this.action, this.detail = ''});

  final DateTime? at;
  final String by;
  final String action;
  final String detail;

  factory ChangeLogEntry.fromJson(Json j) {
    final by = j['by'];
    return ChangeLogEntry(
      at: _time(j['at']),
      by: by is Map ? '${by['name'] ?? by['id'] ?? ''}' : '${by ?? ''}',
      action: '${j['action'] ?? ''}',
      detail: j['detail'] is String ? j['detail'] as String : (j['detail'] == null ? '' : '${j['detail']}'),
    );
  }

  Json toJson() => {'at': at == null ? null : wireDateTime(at!), 'by': by, 'action': action, 'detail': detail};
}

/// GET /v1/menus?date=&slot=.
@immutable
class Menu {
  const Menu({
    required this.id,
    required this.date,
    required this.slot,
    this.dishes = const [],
    this.eaters = const [],
    this.guests = const Guests(),
    this.servings = 0,
    this.dueAt,
    this.assignee,
    this.coverage = const Coverage(allCovered: false),
    this.requiredItems = const [],
    this.ticketId,
    this.version = 0,
    this.notes = '',
  });

  final String id;
  final String date;
  final String slot;
  final List<MenuDish> dishes;
  final List<EaterRef> eaters;
  final Guests guests;
  final double servings;
  final DateTime? dueAt;
  final Assignee? assignee;
  final Coverage coverage;
  final List<RequiredItem> requiredItems;
  final String? ticketId;
  final int version;
  final String notes;

  /// People at the table: eaters plus guests.
  int get headcount => eaters.length + guests.count;

  factory Menu.fromJson(Json j) => Menu(
    id: '${j['id']}',
    date: '${j['date'] ?? ''}',
    slot: '${j['slot'] ?? ''}',
    dishes: [for (final d in _maps(j['dishes'])) MenuDish.fromJson(d)],
    eaters: [for (final e in _maps(j['eaters'])) EaterRef.fromJson(e)],
    guests: Guests.fromJson(j['guests']),
    servings: _num(j['servings']),
    dueAt: _time(j['due_at']),
    assignee: Assignee.fromJson(j['assignee']),
    coverage: Coverage.fromJson(j['coverage']),
    requiredItems: [for (final i in _maps(j['required_items'])) RequiredItem.fromJson(i)],
    ticketId: _str(j['ticket_id']),
    version: (j['version'] as num?)?.toInt() ?? 0,
    notes: j['notes'] as String? ?? '',
  );
}

/// PATCH /v1/menus/{id}. Only set fields are sent; [assigneeSet] sends
/// `assignee_cook_id` even when null ("Koi nahi"). `servings` is an
/// override the contract does not list (see the Phase 5 report).
@immutable
class MenuPatch {
  const MenuPatch({
    this.eaters,
    this.guests,
    this.dueAt,
    this.assigneeCookId,
    this.assigneeSet = false,
    this.notes,
    this.servings,
  });

  final List<String>? eaters;
  final Guests? guests;
  final DateTime? dueAt;
  final String? assigneeCookId;
  final bool assigneeSet;
  final String? notes;
  final double? servings;

  Json toJson() => {
    'eaters': ?eaters,
    if (guests != null) 'guests': guests!.toJson(),
    if (dueAt != null) 'due_at': wireDateTime(dueAt!),
    if (assigneeSet) 'assignee_cook_id': assigneeCookId,
    'notes': ?notes,
    'servings': ?servings,
  };
}

@immutable
class Ticket {
  const Ticket({
    required this.id,
    this.menuId = '',
    required this.date,
    required this.slot,
    this.dueAt,
    required this.status,
    this.assignee,
    this.dishes = const [],
    this.eaters = const [],
    this.guests = const Guests(),
    this.servings = 0,
    this.notes = '',
    this.stockIssueOpen = false,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.completedBy,
    this.ratedAt,
    this.changeLog = const [],
    this.version = 0,
    this.updated = false,
    this.requiredItems = const [],
    this.ladder,
    this.stockIssue,
  });

  final String id;
  final String menuId;
  final String date;
  final String slot;
  final DateTime? dueAt;
  final TicketStatus status;
  final Assignee? assignee;
  final List<MenuDish> dishes;
  final List<EaterRef> eaters;
  final Guests guests;
  final double servings;
  final String notes;
  final bool stockIssueOpen;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? completedBy;
  final DateTime? ratedAt;
  final List<ChangeLogEntry> changeLog;
  final int version;

  /// Edited after the cook saw it (FR-K3 "Updated" tag).
  final bool updated;

  /// The menu's required items, copied onto the ticket for K2.
  final List<RequiredItem> requiredItems;

  /// Out-of-stock ladder from the last item-out (Phase 6).
  final StockLadder? ladder;

  /// The open stock issue as the server sent it (optional).
  final StockIssue? stockIssue;

  /// The open stock issue: [stockIssue], else derived from the change log.
  StockIssue? get issue => _deriveIssue(this);

  /// Servings rounded up to whole plates for recipe scaling.
  int get servingsInt => servings <= 0 ? 1 : servings.ceil();

  factory Ticket.fromJson(Json j) => Ticket(
    id: '${j['id']}',
    menuId: '${j['menu_id'] ?? ''}',
    date: '${j['date'] ?? ''}',
    slot: '${j['slot'] ?? ''}',
    dueAt: _time(j['due_at']),
    status: TicketStatus.fromWire(j['status'] as String?),
    assignee: Assignee.fromJson(j['assignee']),
    dishes: [for (final d in _maps(j['dishes'])) MenuDish.fromJson(d)],
    eaters: [for (final e in _maps(j['eaters'])) EaterRef.fromJson(e)],
    guests: Guests.fromJson(j['guests']),
    servings: _num(j['servings']),
    notes: j['notes'] as String? ?? '',
    stockIssueOpen: j['stock_issue_open'] as bool? ?? false,
    acceptedAt: _time(j['accepted_at']),
    startedAt: _time(j['started_at']),
    completedAt: _time(j['completed_at']),
    completedBy: _str(j['completed_by']),
    ratedAt: _time(j['rated_at']),
    changeLog: [for (final c in _maps(j['change_log'])) ChangeLogEntry.fromJson(c)],
    version: (j['version'] as num?)?.toInt() ?? 0,
    updated: j['updated'] as bool? ?? false,
    requiredItems: [for (final i in _maps(j['required_items'])) RequiredItem.fromJson(i)],
    ladder: StockLadder.fromJson(j['ladder']),
    stockIssue: StockIssue.fromJson(j['stock_issue']),
  );

  Json toJson() {
    String? t(DateTime? d) => d == null ? null : wireDateTime(d);
    return {
      'id': id,
      'menu_id': menuId,
      'date': date,
      'slot': slot,
      'due_at': t(dueAt),
      'status': status.wire,
      'assignee': assignee?.toJson(),
      'dishes': [for (final d in dishes) d.toJson()],
      'eaters': [for (final e in eaters) e.toJson()],
      'guests': guests.toJson(),
      'servings': servings,
      'notes': notes,
      'stock_issue_open': stockIssueOpen,
      'accepted_at': t(acceptedAt),
      'started_at': t(startedAt),
      'completed_at': t(completedAt),
      'completed_by': completedBy,
      'rated_at': t(ratedAt),
      'change_log': [for (final c in changeLog) c.toJson()],
      'version': version,
      'updated': updated,
      'required_items': [for (final i in requiredItems) i.toJson()],
      if (ladder != null) 'ladder': ladder!.toJson(),
      if (stockIssue != null) 'stock_issue': stockIssue!.toJson(),
    };
  }

  Ticket copyWith({
    TicketStatus? status,
    int? version,
    List<RequiredItem>? requiredItems,
    bool? stockIssueOpen,
    List<ChangeLogEntry>? changeLog,
    DateTime? ratedAt,
  }) => Ticket(
    id: id,
    menuId: menuId,
    date: date,
    slot: slot,
    dueAt: dueAt,
    status: status ?? this.status,
    assignee: assignee,
    dishes: dishes,
    eaters: eaters,
    guests: guests,
    servings: servings,
    notes: notes,
    stockIssueOpen: stockIssueOpen ?? this.stockIssueOpen,
    acceptedAt: acceptedAt,
    startedAt: startedAt,
    completedAt: completedAt,
    completedBy: completedBy,
    ratedAt: ratedAt ?? this.ratedAt,
    changeLog: changeLog ?? this.changeLog,
    version: version ?? this.version,
    updated: updated,
    requiredItems: requiredItems ?? this.requiredItems,
    ladder: ladder,
    stockIssue: stockIssue,
  );
}

/// PATCH /v1/tickets/{id}.
@immutable
class TicketPatch {
  const TicketPatch({this.dishes, this.eaters, this.guests, this.servings, this.dueAt, this.notes});

  /// Recipe ids.
  final List<String>? dishes;

  /// Member ids.
  final List<String>? eaters;
  final Guests? guests;
  final double? servings;
  final DateTime? dueAt;
  final String? notes;

  Json toJson() => {
    'dishes': ?dishes,
    'eaters': ?eaters,
    if (guests != null) 'guests': guests!.toJson(),
    'servings': ?servings,
    if (dueAt != null) 'due_at': wireDateTime(dueAt!),
    'notes': ?notes,
  };
}

/// POST /v1/menus/{id}/confirm.
@immutable
class ConfirmResult {
  const ConfirmResult({required this.ticket, required this.shareText});

  final Ticket ticket;
  final String shareText;

  factory ConfirmResult.fromJson(Json j) => ConfirmResult(
    ticket: Ticket.fromJson((j['ticket'] as Map).cast<String, dynamic>()),
    shareText: j['share_text'] as String? ?? '',
  );
}

/// GET /v1/cooks item.
@immutable
class Cook {
  const Cook({
    required this.id,
    required this.name,
    required this.kind,
    this.memberId,
    this.userId,
    this.loginMode = 'app',
    this.isPrimary = false,
    this.isBackup = false,
    this.onDuty = true,
    this.offDutyUntil,
    this.phoneMasked = '',
  });

  final String id;
  final String name;
  final CookKind kind;
  final String? memberId;
  final String? userId;
  final String loginMode;
  final bool isPrimary;
  final bool isBackup;
  final bool onDuty;
  final DateTime? offDutyUntil;
  final String phoneMasked;

  factory Cook.fromJson(Json j) => Cook(
    id: '${j['id']}',
    name: j['name'] as String? ?? '',
    kind: CookKind.fromWire(j['kind'] as String?),
    memberId: _str(j['member_id']),
    userId: _str(j['user_id']),
    loginMode: j['login_mode'] as String? ?? 'app',
    isPrimary: j['is_primary'] as bool? ?? false,
    isBackup: j['is_backup'] as bool? ?? false,
    onDuty: j['on_duty'] as bool? ?? true,
    offDutyUntil: _time(j['off_duty_until']),
    phoneMasked: j['phone_masked'] as String? ?? '',
  );

  Cook copyWith({bool? onDuty, DateTime? offDutyUntil, bool clearOffDuty = false}) => Cook(
    id: id,
    name: name,
    kind: kind,
    memberId: memberId,
    userId: userId,
    loginMode: loginMode,
    isPrimary: isPrimary,
    isBackup: isBackup,
    onDuty: onDuty ?? this.onDuty,
    offDutyUntil: clearOffDuty ? null : (offDutyUntil ?? this.offDutyUntil),
    phoneMasked: phoneMasked,
  );
}

/// PATCH /v1/cooks/{id}.
@immutable
class CookPatch {
  const CookPatch({this.onDuty, this.offDutyUntil, this.offDutyUntilSet = false, this.isPrimary, this.isBackup});

  final bool? onDuty;
  final DateTime? offDutyUntil;

  /// Send `off_duty_until` even when null (clears it).
  final bool offDutyUntilSet;
  final bool? isPrimary;
  final bool? isBackup;

  Json toJson() => {
    'on_duty': ?onDuty,
    if (offDutyUntilSet || offDutyUntil != null)
      'off_duty_until': offDutyUntil == null ? null : wireDateTime(offDutyUntil!),
    'is_primary': ?isPrimary,
    'is_backup': ?isBackup,
  };
}

/// The caller's cook role (`GET /v1/me` → `cook`).
@immutable
class MeCook {
  const MeCook({required this.id, required this.kind, this.loginMode = 'app'});

  final String id;
  final CookKind kind;
  final String loginMode;
}

/// `GET /v1/me`: modes, cook role, membership and consent state.
@immutable
class Me {
  const Me({
    this.modes = const ['family'],
    this.cook,
    this.userId,
    this.householdId,
    this.memberId,
    this.isAdmin = false,
    this.consentRequired = false,
    this.consentVersion,
    this.raw,
  });

  final List<String> modes;
  final MeCook? cook;
  final String? userId;

  /// Null → signed in but not in a household yet (create one).
  final String? householdId;
  final String? memberId;
  final bool isAdmin;

  /// The server wants (re-)consent to [consentVersion].
  final bool consentRequired;
  final String? consentVersion;

  /// The wire JSON, kept for the local /me cache.
  final Json? raw;

  bool get canCook => modes.contains('cook') && cook != null;
  bool get hasFamily => modes.contains('family');
  bool get hasHousehold => householdId != null && householdId!.isNotEmpty;

  /// A hired cook: cook mode only.
  bool get cookOnly => canCook && !hasFamily;

  factory Me.fromJson(Json j) {
    final c = j['cook'];
    final m = j['membership'];
    final user = j['user'];
    final consent = j['consent'];
    return Me(
      modes: [
        for (final m in (j['modes'] as List? ?? const ['family'])) '$m',
      ],
      cook: c is Map
          ? MeCook(
              id: '${c['id']}',
              kind: CookKind.fromWire(c['kind'] as String?),
              loginMode: c['login_mode'] as String? ?? 'app',
            )
          : null,
      userId: user is Map ? _str(user['id']) : null,
      householdId: m is Map ? _str(m['household_id']) : null,
      memberId: m is Map ? _str(m['member_id']) : null,
      isAdmin: m is Map && m['is_admin'] == true,
      consentRequired: consent is Map && consent['required'] == true,
      consentVersion: consent is Map ? _str(consent['current_version']) : null,
      raw: j,
    );
  }
}

/// `GET /v1/inbox` item.
@immutable
class InboxItem {
  const InboxItem({
    required this.id,
    required this.event,
    required this.title,
    this.body = '',
    this.ticketId,
    this.readAt,
    this.createdAt,
    this.approvalId,
    this.rationRequestId,
    this.link,
  });

  final String id;
  final String event;
  final String title;
  final String body;
  final String? ticketId;
  final DateTime? readAt;
  final DateTime? createdAt;

  /// Optional deep-link ids on Phase 6/7 events.
  final String? approvalId;
  final String? rationRequestId;

  /// Export download link (`export_ready`).
  final String? link;

  bool get unread => readAt == null;

  factory InboxItem.fromJson(Json j) => InboxItem(
    id: '${j['id']}',
    event: '${j['event'] ?? ''}',
    title: j['title'] as String? ?? '',
    body: j['body'] as String? ?? '',
    ticketId: _str(j['ticket_id']),
    readAt: _time(j['read_at']),
    createdAt: _time(j['created_at']),
    approvalId: _str(j['approval_id']),
    rationRequestId: _str(j['ration_request_id']),
    link: _str(j['link']),
  );

  InboxItem markRead(DateTime at) => InboxItem(
    id: id,
    event: event,
    title: title,
    body: body,
    ticketId: ticketId,
    readAt: at,
    createdAt: createdAt,
    approvalId: approvalId,
    rationRequestId: rationRequestId,
    link: link,
  );
}

/// One K6 thread message: `{id, text, author: {name, role}, created_at}`
/// (shape not fixed by the contract; see the Phase 5 report).
@immutable
class TicketMessage {
  const TicketMessage({required this.id, required this.text, required this.author, this.fromCook = false, this.at});

  final String id;
  final String text;
  final String author;
  final bool fromCook;
  final DateTime? at;

  factory TicketMessage.fromJson(Json j) {
    final a = j['author'];
    final role = a is Map ? a['role'] : j['role'];
    return TicketMessage(
      id: '${j['id']}',
      text: j['text'] as String? ?? '',
      author: a is Map ? '${a['name'] ?? ''}' : '${a ?? j['by'] ?? ''}',
      fromCook: role == 'cook',
      at: _time(j['created_at'] ?? j['at']),
    );
  }

  /// Round-trips through [TicketMessage.fromJson] (offline cache).
  Json toJson() => {
    'id': id,
    'text': text,
    'author': {'name': author, 'role': fromCook ? 'cook' : 'family'},
    'created_at': at == null ? null : wireDateTime(at!),
  };
}

/// GET /v1/tickets/{id}/recipes/{recipe_id}?servings= : the recipe plus
/// `audio.steps_hi` (URL or null per step → on-device TTS) and optional
/// Devanagari `steps_hi` text.
@immutable
class CookRecipe {
  const CookRecipe({required this.detail, this.audioStepsHi = const [], this.stepsHi = const [], this.raw});

  final RecipeDetail detail;
  final List<String?> audioStepsHi;
  final List<String> stepsHi;

  /// The wire JSON, kept for the offline cache.
  final Json? raw;

  /// Text read out for step [i]: Hindi when present, else the recipe step.
  String spokenStep(int i) => i < stepsHi.length && stepsHi[i].isNotEmpty ? stepsHi[i] : detail.steps[i];

  String? audioUrl(int i) => i < audioStepsHi.length ? audioStepsHi[i] : null;

  factory CookRecipe.fromJson(Json j) {
    final audio = j['audio'] is Map ? (j['audio'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return CookRecipe(
      detail: RecipeDetail.fromJson(j),
      audioStepsHi: [for (final u in (audio['steps_hi'] as List? ?? const [])) u is String && u.isNotEmpty ? u : null],
      stepsHi: [for (final s in (j['steps_hi'] as List? ?? const [])) '$s'],
      raw: j,
    );
  }
}
