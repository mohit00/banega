part of 'demo_kitchen.dart';

/// What an approved swap / dish change will do to the ticket.
class _PendingChange {
  _PendingChange({required this.ticketId, required this.action, this.swap, this.recipeId, this.fromRecipeId});

  final String ticketId;
  final LadderAction action;
  final DemoSubstitution? swap;
  final String? recipeId;
  final String? fromRecipeId;
}

/// Demo stock, ration requests, the out-of-stock ladder (engine-checked
/// swaps and dish changes) and approvals with a 30-min timeout. Lives inside
/// [DemoKitchen] so tickets, stock and the inbox stay consistent.
class DemoPantry implements StockRepository, RationRepository {
  DemoPantry(this.k) {
    final at = k.now();
    for (final s in demoStaples) {
      _stock[s.id] = StockItem(
        ingredientId: s.id,
        name: s.name,
        nameHi: s.nameHi,
        level: stockLevelFromWire(s.level),
        updatedAt: at.subtract(const Duration(days: 1)),
        updatedBy: 'Aap',
        category: s.category,
      );
    }
  }

  final DemoKitchen k;
  final Map<String, StockItem> _stock = {};
  final List<RationRequest> _ration = [];
  final Map<String, Approval> _approvals = {};
  final Map<String, _PendingChange> _changes = {};

  late final DemoCookPantry asCook = DemoCookPantry(this);

  late final ApprovalsRepository approvalsRepo = _DemoApprovals(this);

  static const approvalTimeout = Duration(minutes: 30);

  // ---------------------------------------------------------------- matching

  static final Map<String, DemoStaple> _staples = {for (final s in demoStaples) s.id: s};

  static DemoStaple? staple(String id) => _staples[id];

  /// Staple ids mentioned (whole word) in an ingredient line, in order.
  static List<String> staplesIn(String line) {
    final t = ' ${line.toLowerCase()} ';
    return [
      for (final s in demoStaples)
        if (s.keywords.any((w) => RegExp(r'(^|[^a-z])' + RegExp.escape(w) + r'([^a-z]|$)').hasMatch(t))) s.id,
    ];
  }

  /// Level of a tracked staple, or [ItemStatus.untracked].
  ItemStatus levelOf(String id) => _stock[id]?.level ?? ItemStatus.untracked;

  bool tracked(String id) => _stock.containsKey(id);

  String nameOf(String id) => _stock[id]?.name ?? id;

  /// Required items for [recipeIds]: one row per tracked staple (the line
  /// text when a line names one staple), untracked lines keep a slug id.
  List<RequiredItem> requiredFor(List<String> recipeIds) {
    final seen = <String>{};
    final out = <RequiredItem>[];
    for (final id in recipeIds) {
      for (final line in k._recipe(id)?.ingredients ?? const <String>[]) {
        final ids = staplesIn(line);
        if (ids.isEmpty) {
          final slug = DemoKitchen.ingredientId(line);
          if (seen.add(slug)) {
            out.add(RequiredItem(ingredientId: slug, displayText: line, status: ItemStatus.untracked));
          }
          continue;
        }
        for (final sid in ids) {
          if (seen.add(sid)) {
            out.add(
              RequiredItem(ingredientId: sid, displayText: ids.length == 1 ? line : nameOf(sid), status: levelOf(sid)),
            );
          }
        }
      }
    }
    return out;
  }

  /// Required items with tracked statuses read from the pantry (F-5.6-04:
  /// the pantry is the single source of truth).
  List<RequiredItem> live(List<RequiredItem> items) => [
    for (final i in items) tracked(i.ingredientId) ? i.withStatus(levelOf(i.ingredientId)) : i,
  ];

  // ---------------------------------------------------------------- stock

  @override
  Future<List<StockItem>> stock() async => _stock.values.toList();

  StockItem _set(String id, ItemStatus level, {double? qty, required String by}) {
    final before = _stock[id];
    if (before == null) throw const KitchenError(status: 404, code: 'staple_not_found');
    if (level == ItemStatus.untracked) throw const KitchenError(status: 422, code: 'invalid_level');
    final after = before.copyWith(level: level, qty: qty, updatedAt: k.now(), updatedBy: by);
    _stock[id] = after;
    if (before.level == ItemStatus.inStock && level != ItemStatus.inStock) {
      k._event(
        'stock_low',
        level == ItemStatus.out ? '${after.name} khatam ho gaya' : '${after.name} kam hai',
        null,
        body: 'Rasoi stock: $by ne badla',
      );
    }
    return after;
  }

  @override
  Future<StockItem> setLevel(String ingredientId, ItemStatus level, {double? qty}) async {
    final s = _set(ingredientId, level, qty: qty, by: 'Aap');
    return s;
  }

  @override
  Future<List<StockItem>> bulk(List<(String, ItemStatus)> items) async {
    final out = [for (final (id, level) in items) _set(id, level, by: 'Aap')];
    return out;
  }

  // ---------------------------------------------------------------- ration

  @override
  Future<List<RationRequest>> requests({RationStatus? status}) async => [
    for (final r in _ration.reversed)
      if (status == null || r.status == status) r,
  ];

  /// F-2-04: a self-raise by the admin or a family cook is auto-approved.
  RationRequest _create({String? ticketId, required List<RationItem> items, required String by, required bool auto}) {
    if (items.isEmpty) throw const KitchenError(status: 422, code: 'ration_empty');
    final at = k.now();
    final r = RationRequest(
      id: k._id('rr'),
      ticketId: ticketId,
      items: items,
      status: auto ? RationStatus.approved : RationStatus.pending,
      raisedBy: by,
      decidedBy: auto ? by : null,
      decidedAt: auto ? at : null,
      note: auto ? 'self_approved' : null,
      createdAt: at,
    );
    _ration.add(r);
    if (!auto) {
      k._event(
        'ration_request',
        '$by ne ration maanga: ${items.length} cheez${items.length == 1 ? '' : 'ein'}',
        ticketId,
        body: items.map((i) => i.name).join(', '),
        rationRequestId: r.id,
      );
    }
    return r;
  }

  @override
  Future<RationRequest> create({String? ticketId, required List<RationItem> items}) async =>
      _create(ticketId: ticketId, items: items, by: 'Aap', auto: true);

  RationRequest _find(String id) =>
      _ration.where((r) => r.id == id).firstOrNull ?? (throw const KitchenError(status: 404, code: 'ration_not_found'));

  void _replace(RationRequest r) => _ration[_ration.indexWhere((x) => x.id == r.id)] = r;

  @override
  Future<RationRequest> decide(String id, String decision, {String? note}) async {
    final r = _find(id);
    if (r.status != RationStatus.pending) throw const KitchenError(status: 409, code: 'already_decided');
    final next = RationRequest(
      id: r.id,
      ticketId: r.ticketId,
      items: r.items,
      status: decision == Decision.approved ? RationStatus.approved : RationStatus.rejected,
      raisedBy: r.raisedBy,
      decidedBy: 'Aap',
      decidedAt: k.now(),
      note: note,
      createdAt: r.createdAt,
    );
    _replace(next);
    k._event(
      'ration_decided',
      decision == Decision.approved ? 'Ration request approve hui' : 'Ration request mana hui',
      r.ticketId,
      body: note ?? '',
      rationRequestId: r.id,
    );
    return next;
  }

  @override
  Future<RationRequest> bought(String id) async {
    final r = _find(id);
    if (r.status != RationStatus.approved) throw const KitchenError(status: 409, code: 'not_approved');
    for (final i in r.items) {
      if (i.ingredientId != null && tracked(i.ingredientId!)) _set(i.ingredientId!, ItemStatus.inStock, by: 'Aap');
    }
    final next = RationRequest(
      id: r.id,
      ticketId: r.ticketId,
      items: r.items,
      status: RationStatus.bought,
      raisedBy: r.raisedBy,
      decidedBy: r.decidedBy,
      decidedAt: r.decidedAt,
      note: r.note,
      createdAt: r.createdAt,
    );
    _replace(next);
    k._event('ration_decided', 'Ration aa gaya — saaman stock mein', r.ticketId, rationRequestId: r.id);
    return next;
  }

  @override
  Future<List<RationItem>> suggest({int days = 7}) async {
    final today = parseWireDate(k.today);
    final end = today.add(Duration(days: days));
    final seen = <String>{};
    return [
      for (final t in k._tickets.values)
        if (t.status.isOpen && !parseWireDate(t.date).isBefore(today) && parseWireDate(t.date).isBefore(end))
          for (final i in live(t.requiredItems))
            if ((i.status == ItemStatus.low || i.status == ItemStatus.out) && seen.add(i.ingredientId))
              RationItem(ingredientId: i.ingredientId, name: nameOf(i.ingredientId)),
    ];
  }

  // ---------------------------------------------------------------- ladder

  /// The engine's view of who eats this ticket (members + guest stand-in).
  List<Member> _people(Ticket t) => [
    ...k._eatersOf([for (final e in t.eaters) e.memberId]),
    ?DemoKitchen._guestMember(t.guests),
  ];

  /// First recipe on the ticket whose lines use [ingredientId].
  Recipe? _dishUsing(Ticket t, String ingredientId) {
    for (final d in t.dishes) {
      final r = k._recipe(d.recipeId);
      if (r == null) continue;
      if (r.ingredients.any(
        (l) => staplesIn(l).contains(ingredientId) || DemoKitchen.ingredientId(l) == ingredientId,
      )) {
        return r;
      }
    }
    return null;
  }

  /// [r] with the line naming [from] replaced by [text] (null → removed);
  /// flags re-derived so the engine re-checks allergens and pyaaz-lahsun.
  static Recipe _modified(Recipe r, String from, String? text) {
    final lines = <String>[];
    for (final l in r.ingredients) {
      if (!staplesIn(l).contains(from)) {
        lines.add(l);
      } else if (text != null) {
        lines.add(text);
      }
    }
    final og = lines.any((l) => RegExp(r'pyaaz|lahsun|onion|garlic').hasMatch(l.toLowerCase()));
    return Recipe(
      id: r.id,
      name: r.name,
      sub: r.sub,
      mins: r.mins,
      slots: r.slots,
      diet: r.diet,
      jain: r.jain || !og,
      spice: r.spice,
      tags: r.tags,
      cuisine: r.cuisine,
      color: r.color,
      ingredients: lines,
      steps: r.steps,
      dishCategory: r.dishCategory,
      meatType: r.meatType,
      vratOk: r.vratOk,
      baseServings: r.baseServings,
      onionGarlic: og,
    );
  }

  /// FR §5.9 ladder for [ingredientId] on [t], computed with the engine.
  StockLadder ladderFor(Ticket t, String ingredientId, String name) {
    final people = _people(t);
    final recipe = _dishUsing(t, ingredientId);
    final st = staple(ingredientId);
    final jainEater = people.any((m) => m.diet == Diet.jain);
    final skipOk =
        recipe != null &&
        ((st?.optional ?? false) || ((ingredientId == 'pyaaz' || ingredientId == 'lahsun') && jainEater));
    final swaps = <SwapOption>[];
    if (recipe != null) {
      final before = {for (final m in people) m.id: fitFor(m, recipe).kind};
      for (final rule in demoSubstitutions.where((s) => s.from == ingredientId)) {
        if (rule.needs.any((n) => levelOf(n) == ItemStatus.out)) continue;
        final after = _modified(recipe, ingredientId, rule.text);
        // Never introduce a No for anyone who could eat the original.
        final breaks = people.any((m) => before[m.id] != FitKind.no && fitFor(m, after).kind == FitKind.no);
        if (breaks) continue;
        swaps.add(
          SwapOption(
            substituteIngredientId: rule.to,
            name: rule.name,
            ratio: rule.ratio,
            noteHi: rule.noteHi,
            fitAfter: CardSummary.fromEngine(summarize(people, after)),
          ),
        );
      }
    }
    return StockLadder(
      step: skipOk
          ? LadderStep.saveDish
          : swaps.isNotEmpty
          ? LadderStep.swap
          : LadderStep.changeDish,
      ingredientId: ingredientId,
      ingredientName: name,
      skip: SkipOption(ingredientId: ingredientId, name: name, ok: skipOk),
      swaps: swaps,
      dishes: _alternatives(t, people),
    );
  }

  /// Up to 3 dishes for the same slot using only in / low stock, ranked by
  /// the engine; never one that is No for everyone.
  List<RecipeCard> _alternatives(Ticket t, List<Member> people) {
    final slot = slotFromKey(t.slot);
    final onTicket = {for (final d in t.dishes) d.recipeId};
    final candidates = [
      for (final r in k.recipes.recipes)
        if (!onTicket.contains(r.id) &&
            (slot == null || r.slots.contains(slot)) &&
            requiredFor([r.id]).every((i) => i.status != ItemStatus.out))
          r,
    ];
    return [
      for (final (r, s) in ranked(people, candidates))
        if (s.kind != FitKind.no || s.can > 0) RecipeCard.fromRecipe(r, s),
    ].take(3).toList();
  }

  // ---------------------------------------------------------------- resolve

  /// POST /tickets/{id}/stock-issue/resolve. [asCook] is the cook acting
  /// from cook mode; the family side self-approves.
  Ticket resolve(
    String ticketId,
    LadderAction action, {
    String? substituteIngredientId,
    String? recipeId,
    required bool asCook,
  }) {
    final t = k._get(ticketId);
    final ladder = t.ladder;
    if (!t.stockIssueOpen || ladder == null) throw const KitchenError(status: 409, code: 'no_stock_issue');
    if (t.issue?.state == StockIssueState.pending) throw const KitchenError(status: 409, code: 'approval_pending');
    final by = asCook ? (t.assignee?.name ?? 'Cook') : 'Aap';
    final familyCook = t.assignee?.kind == CookKind.family;
    switch (action) {
      case LadderAction.skip:
        if (!ladder.canSkip) throw const KitchenError(status: 422, code: 'skip_not_allowed');
        return k._store(_close(k._log(t, t.status, by, LadderLog.skip, 'Bina ${ladder.ingredientName}')));
      case LadderAction.swap:
        final rule = demoSubstitutions
            .where((s) => s.from == ladder.ingredientId && s.to == substituteIngredientId)
            .firstOrNull;
        if (rule == null || !ladder.swaps.any((s) => s.substituteIngredientId == substituteIngredientId)) {
          throw const KitchenError(status: 422, code: 'invalid_substitute');
        }
        final change = _PendingChange(ticketId: t.id, action: action, swap: rule);
        final selfOk = !asCook || familyCook || k.account.settings.cookCanApproveSwaps;
        if (selfOk) return k._store(_apply(t, change, by));
        return _ask(t, change, by, ApprovalType.swap, '${ladder.ingredientName} → ${rule.name}');
      case LadderAction.changeDish:
        final r = recipeId == null ? null : k._recipe(recipeId);
        if (r == null || !ladder.dishes.any((d) => d.id == recipeId)) {
          throw const KitchenError(status: 422, code: 'invalid_recipe');
        }
        final from = _dishUsing(t, ladder.ingredientId) ?? k._recipe(t.dishes.first.recipeId);
        final change = _PendingChange(ticketId: t.id, action: action, recipeId: r.id, fromRecipeId: from?.id);
        if (!asCook || familyCook) {
          final next = k._store(_apply(t, change, by));
          if (asCook) k._event('approval_decided', '$by ne dish badli: ${from?.name ?? ''} → ${r.name}', t.id);
          return next;
        }
        return _ask(t, change, by, ApprovalType.changeDish, '${from?.name ?? ''} → ${r.name}');
    }
  }

  Ticket _ask(Ticket t, _PendingChange change, String by, ApprovalType type, String detail) {
    final at = k.now();
    final a = Approval(
      id: k._id('ap'),
      ticketId: t.id,
      type: type,
      requestedBy: by,
      expiresAt: at.add(approvalTimeout),
      detail: detail,
    );
    _approvals[a.id] = a;
    _changes[a.id] = change;
    final logged = k._log(t, t.status, by, LadderLog.approvalRequested, detail);
    final next = k._withIssue(
      logged,
      StockIssue(
        ingredientId: t.ladder!.ingredientId,
        name: t.ladder!.ingredientName,
        state: StockIssueState.pending,
        action: change.action,
        approvalId: a.id,
        expiresAt: a.expiresAt,
        detail: detail,
      ),
    );
    k._event('approval_request', '$by poochh rahe hain: $detail', t.id, body: 'Haan ya nahi batao', approvalId: a.id);
    return k._store(next);
  }

  /// Applies a swap / dish change and closes the issue.
  Ticket _apply(Ticket t, _PendingChange c, String by) {
    final j = t.toJson();
    final ladder = t.ladder!;
    String action;
    String detail;
    if (c.action == LadderAction.swap) {
      final rule = c.swap!;
      j['required_items'] = [
        for (final i in t.requiredItems)
          if (i.ingredientId == ladder.ingredientId)
            RequiredItem(
              ingredientId: rule.to,
              displayText: '${rule.name} (${ladder.ingredientName} ki jagah)',
              status: tracked(rule.to) ? levelOf(rule.to) : ItemStatus.untracked,
            ).toJson()
          else
            i.toJson(),
      ];
      action = LadderLog.swap;
      detail = '${ladder.ingredientName} → ${rule.name} (${rule.ratio})';
    } else {
      final ids = [for (final d in t.dishes) d.recipeId == c.fromRecipeId ? c.recipeId! : d.recipeId];
      if (!ids.contains(c.recipeId)) ids[0] = c.recipeId!;
      final eaters = k._eatersOf([for (final e in t.eaters) e.memberId]);
      j['dishes'] = [for (final d in k._dishes(ids, eaters)) d.toJson()];
      j['required_items'] = [for (final i in requiredFor(ids)) i.toJson()];
      action = LadderLog.changeDish;
      detail = '${k._recipe(c.fromRecipeId ?? '')?.name ?? ''} → ${k._recipe(c.recipeId!)?.name ?? ''}';
    }
    return _close(k._log(Ticket.fromJson(j), t.status, by, action, detail));
  }

  Ticket _close(Ticket t) =>
      Ticket.fromJson({...t.toJson(), 'stock_issue_open': false, 'ladder': null, 'stock_issue': null});

  // ---------------------------------------------------------------- approvals

  /// Lazily fires the 30-min timeout on a pending approval.
  Ticket expire(Ticket t) {
    final issue = t.stockIssue;
    if (issue == null || issue.state != StockIssueState.pending) return t;
    final a = _approvals[issue.approvalId];
    if (a == null || !a.pending || !a.expiredAt(k.now())) return t;
    _approvals[a.id] = a.decide(Decision.expired, 'System', k.now());
    final logged = k._log(t, t.status, 'System', LadderLog.timeout, a.detail);
    final next = k._withIssue(
      logged,
      StockIssue(
        ingredientId: issue.ingredientId,
        name: issue.name,
        state: StockIssueState.timedOut,
        action: issue.action,
        approvalId: a.id,
        expiresAt: a.expiresAt,
        detail: issue.detail,
      ),
    );
    k._event(
      'stock_issue_timeout',
      'Kisi ne jawab nahi diya: ${a.detail}',
      t.id,
      body: '30 min ho gaye',
      approvalId: a.id,
    );
    return next;
  }

  Future<List<Approval>> listApprovals({String? status}) async {
    for (final t in k._tickets.values.toList()) {
      k._tick(t);
    }
    return [
      for (final a in _approvals.values.toList().reversed)
        if (status == null ||
            (status == 'pending' && a.pending) ||
            (status == 'decided' && !a.pending) ||
            a.decision == status)
          a,
    ];
  }

  Future<Approval> decideApproval(String id, String decision) async {
    var a = _approvals[id];
    if (a == null) throw const KitchenError(status: 404, code: 'approval_not_found');
    if (a.decision == Decision.approved || a.decision == Decision.rejected) {
      throw const KitchenError(status: 409, code: 'already_decided');
    }
    // Answered after the timeout: the answer still counts.
    a = a.decide(decision, 'Aap', k.now());
    _approvals[id] = a;
    final change = _changes.remove(id);
    final t = a.ticketId == null ? null : k._get(a.ticketId!);
    if (t != null && change != null) {
      if (decision == Decision.approved) {
        final logged = k._log(t, t.status, 'Aap', LadderLog.approved, a.detail);
        k._store(_apply(logged, change, 'Aap'));
      } else {
        final logged = k._log(t, t.status, 'Aap', LadderLog.rejected, a.detail);
        k._store(
          k._withIssue(
            logged,
            StockIssue(
              ingredientId: t.ladder?.ingredientId ?? '',
              name: t.ladder?.ingredientName ?? '',
              state: StockIssueState.open,
            ),
          ),
        );
      }
    }
    k._event(
      'approval_decided',
      decision == Decision.approved ? 'Family ne haan kaha: ${a.detail}' : 'Family ne mana kiya: ${a.detail}',
      a.ticketId,
      approvalId: a.id,
    );
    return a;
  }
}

/// Stock and ration from cook mode: writes are by the cook; a hired cook's
/// ration request waits for the admin, a family cook's is auto-approved.
class DemoCookPantry implements StockRepository, RationRepository {
  DemoCookPantry(this.p);

  final DemoPantry p;

  DemoKitchen get k => p.k;

  Cook? get _me => k._cook(k.meCookId);

  String get _by => _me?.name ?? 'Cook';

  @override
  Future<List<StockItem>> stock() => p.stock();

  @override
  Future<StockItem> setLevel(String ingredientId, ItemStatus level, {double? qty}) async {
    final s = p._set(ingredientId, level, qty: qty, by: _by);
    return s;
  }

  @override
  Future<List<StockItem>> bulk(List<(String, ItemStatus)> items) async {
    final out = [for (final (id, level) in items) p._set(id, level, by: _by)];
    return out;
  }

  /// Only the cook's own requests.
  @override
  Future<List<RationRequest>> requests({RationStatus? status}) async => [
    for (final r in await p.requests(status: status))
      if (r.raisedBy == _by) r,
  ];

  @override
  Future<RationRequest> create({String? ticketId, required List<RationItem> items}) async =>
      p._create(ticketId: ticketId, items: items, by: _by, auto: _me?.kind == CookKind.family);

  @override
  Future<RationRequest> decide(String id, String decision, {String? note}) =>
      Future.error(const KitchenError(status: 403, code: 'forbidden'));

  @override
  Future<RationRequest> bought(String id) => Future.error(const KitchenError(status: 403, code: 'forbidden'));

  @override
  Future<List<RationItem>> suggest({int days = 7}) => p.suggest(days: days);
}

class _DemoApprovals implements ApprovalsRepository {
  _DemoApprovals(this.p);

  final DemoPantry p;

  @override
  Future<List<Approval>> approvals({String? status}) => p.listApprovals(status: status);

  @override
  Future<Approval> decide(String id, String decision) => p.decideApproval(id, decision);
}
