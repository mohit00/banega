// Phase 6 out-of-stock ladder shapes (docs/contracts/phase6-7-stock-ratings-billing.md
// "Out-of-stock ladder"): `ladder: {step, options}` on the item-out response,
// the resolve actions, and the ticket's open stock issue.
part of 'kitchen_models.dart';

/// FR §5.9 steps as the contract names them.
enum LadderStep {
  saveDish('save_dish'),
  swap('swap'),
  changeDish('change_dish');

  const LadderStep(this.wire);
  final String wire;

  static LadderStep fromWire(String? v) => values.firstWhere((s) => s.wire == v, orElse: () => saveDish);
}

/// `POST /v1/tickets/{id}/stock-issue/resolve` actions.
enum LadderAction {
  skip('skip'),
  swap('swap'),
  changeDish('change_dish');

  const LadderAction(this.wire);
  final String wire;

  static LadderAction? fromWire(String? v) {
    for (final a in values) {
      if (a.wire == v) return a;
    }
    return null;
  }
}

/// Step 1: `{type: "skip", ingredient, ok}`; [ok] when the ingredient is
/// optional in the recipe.
@immutable
class SkipOption {
  const SkipOption({required this.ingredientId, required this.name, required this.ok});

  final String ingredientId;
  final String name;
  final bool ok;

  factory SkipOption.fromJson(Json j) {
    final ing = j['ingredient'];
    return SkipOption(
      ingredientId: ing is Map ? '${ing['ingredient_id'] ?? ing['id'] ?? ''}' : '${j['ingredient_id'] ?? ing ?? ''}',
      name: ing is Map ? '${ing['name'] ?? ''}' : '${j['name'] ?? ing ?? ''}',
      ok: j['ok'] as bool? ?? false,
    );
  }

  Json toJson() => {
    'type': 'skip',
    'ingredient': {'ingredient_id': ingredientId, 'name': name},
    'ok': ok,
  };
}

/// Step 2: one SubstitutionRule candidate, re-checked by the engine.
@immutable
class SwapOption {
  const SwapOption({
    required this.substituteIngredientId,
    required this.name,
    this.ratio = '',
    this.noteHi = '',
    this.fitAfter,
  });

  final String substituteIngredientId;
  final String name;
  final String ratio;
  final String noteHi;

  /// Household summary for the dish after the swap.
  final CardSummary? fitAfter;

  factory SwapOption.fromJson(Json j) => SwapOption(
    substituteIngredientId: '${j['substitute_ingredient_id']}',
    name: j['name'] as String? ?? '',
    ratio: j['ratio'] == null ? '' : '${j['ratio']}',
    noteHi: j['note_hi'] as String? ?? '',
    fitAfter: j['fit_after'] is Map ? CardSummary.fromJson((j['fit_after'] as Map).cast<String, dynamic>()) : null,
  );

  Json toJson() => {
    'substitute_ingredient_id': substituteIngredientId,
    'name': name,
    'ratio': ratio,
    'note_hi': noteHi,
    'fit_after': fitAfter?.toJson(),
  };
}

/// `ladder: {step, options}`. [step] is where the engine starts; `options`
/// carries every step's candidates as `{save_dish, swap, change_dish}` (a
/// bare list / skip object is read as [step]'s options).
@immutable
class StockLadder {
  const StockLadder({
    required this.step,
    required this.ingredientId,
    required this.ingredientName,
    this.skip,
    this.swaps = const [],
    this.dishes = const [],
  });

  final LadderStep step;
  final String ingredientId;
  final String ingredientName;
  final SkipOption? skip;
  final List<SwapOption> swaps;
  final List<RecipeCard> dishes;

  /// Step 1 applies (skipping keeps the dish).
  bool get canSkip => skip?.ok ?? false;

  static StockLadder? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    final step = LadderStep.fromWire(j['step'] as String?);
    final opts = j['options'];
    Object? saveRaw = j['save_dish'];
    Object? swapRaw = j['swap'];
    Object? dishRaw = j['change_dish'];
    if (opts is Map) {
      saveRaw ??= opts['save_dish'] ?? (opts['type'] == 'skip' ? opts : null);
      swapRaw ??= opts['swap'];
      dishRaw ??= opts['change_dish'];
    } else if (opts is List) {
      switch (step) {
        case LadderStep.saveDish:
          saveRaw ??= opts.isEmpty ? null : opts.first;
        case LadderStep.swap:
          swapRaw ??= opts;
        case LadderStep.changeDish:
          dishRaw ??= opts;
      }
    }
    final skip = saveRaw is Map ? SkipOption.fromJson(saveRaw.cast<String, dynamic>()) : null;
    final ing = j['ingredient'];
    return StockLadder(
      step: step,
      ingredientId: ing is Map
          ? '${ing['ingredient_id'] ?? ing['id'] ?? ''}'
          : '${j['ingredient_id'] ?? skip?.ingredientId ?? ''}',
      ingredientName: ing is Map ? '${ing['name'] ?? ''}' : '${j['ingredient_name'] ?? skip?.name ?? ''}',
      skip: skip,
      swaps: [for (final s in _maps(swapRaw)) SwapOption.fromJson(s)],
      dishes: [for (final d in _maps(dishRaw)) RecipeCard.fromJson(d)],
    );
  }

  Json toJson() => {
    'step': step.wire,
    'ingredient': {'ingredient_id': ingredientId, 'name': ingredientName},
    'options': {
      'save_dish': skip?.toJson(),
      'swap': [for (final s in swaps) s.toJson()],
      'change_dish': [for (final d in dishes) d.toJson()],
    },
  };
}

/// Where a ticket's open stock issue stands.
enum StockIssueState {
  /// The cook is choosing a ladder step.
  open('open'),

  /// A swap / dish change waits for the family (Approval pending).
  pending('pending_approval'),

  /// Nobody answered within 30 min; the admin was alerted.
  timedOut('timed_out'),
  resolved('resolved');

  const StockIssueState(this.wire);
  final String wire;

  static StockIssueState fromWire(String? v) => values.firstWhere((s) => s.wire == v, orElse: () => open);
}

/// `stock_issue` on a ticket. Optional on the wire: [Ticket.issue] derives
/// it from `stock_issue_open` and the change log when absent.
@immutable
class StockIssue {
  const StockIssue({
    required this.ingredientId,
    required this.name,
    required this.state,
    this.action,
    this.approvalId,
    this.expiresAt,
    this.detail = '',
  });

  final String ingredientId;
  final String name;
  final StockIssueState state;
  final LadderAction? action;
  final String? approvalId;
  final DateTime? expiresAt;

  /// What was asked ("Dahi → Doodh + nimbu", "Kadhi → Dal Tadka").
  final String detail;

  static StockIssue? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    return StockIssue(
      ingredientId: '${j['ingredient_id'] ?? ''}',
      name: j['name'] as String? ?? '',
      state: StockIssueState.fromWire(j['state'] as String?),
      action: LadderAction.fromWire(j['action'] as String?),
      approvalId: _str(j['approval_id']),
      expiresAt: _time(j['expires_at']),
      detail: j['detail'] as String? ?? '',
    );
  }

  Json toJson() => {
    'ingredient_id': ingredientId,
    'name': name,
    'state': state.wire,
    'action': action?.wire,
    'approval_id': approvalId,
    'expires_at': expiresAt == null ? null : wireDateTime(expiresAt!),
    'detail': detail,
  };
}

/// Change-log actions the ladder writes (shared with the backend).
abstract final class LadderLog {
  static const itemOut = 'item_out';
  static const skip = 'stock_skip';
  static const swap = 'stock_swap';
  static const changeDish = 'stock_change_dish';
  static const approvalRequested = 'approval_requested';
  static const approved = 'approval_approved';
  static const rejected = 'approval_rejected';
  static const timeout = 'stock_issue_timeout';
}

/// [Ticket.stockIssue], or one derived from `stock_issue_open` and the last
/// ladder entries in the change log.
StockIssue? _deriveIssue(Ticket t) {
  if (t.stockIssue != null) return t.stockIssue;
  if (!t.stockIssueOpen) return null;
  var state = StockIssueState.open;
  var name = '';
  DateTime? since;
  for (final c in t.changeLog) {
    switch (c.action) {
      case LadderLog.itemOut:
        state = StockIssueState.open;
        name = c.detail;
      case LadderLog.approvalRequested:
        state = StockIssueState.pending;
        since = c.at;
      case LadderLog.rejected:
        state = StockIssueState.open;
      case LadderLog.timeout:
        state = StockIssueState.timedOut;
    }
  }
  return StockIssue(
    ingredientId: t.ladder?.ingredientId ?? '',
    name: t.ladder?.ingredientName ?? name,
    state: state,
    expiresAt: since?.add(const Duration(minutes: 30)),
  );
}
