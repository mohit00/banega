part of 'demo_kitchen.dart';

/// Demo household settings, subscription, notification prefs, consent,
/// export, weekly insights and ratings.
class DemoAccount implements AccountRepository, SubscriptionRepository, RatingsRepository {
  DemoAccount(this.k) {
    final at = k.now();
    // Trial started two days ago: 5 days left.
    _subscription = Subscription(
      status: SubscriptionStatus.trial,
      trialEndsAt: at.add(const Duration(days: 5)),
      productId: weeklyProductId,
    );
    // Older family ratings so Recipe detail has a "Ghar ki rating".
    for (final (recipe, member, score) in const [
      ('daltadka', 'm1', 3),
      ('daltadka', 'm2', 3),
      ('daltadka', 'm3', 2),
      ('rajma', 'm1', 3),
      ('rajma', 'm4', 3),
      ('rajma', 'm5', 2),
    ]) {
      _ratings['seed|$recipe|$member'] = (recipe, member, score, null);
    }
  }

  final DemoKitchen k;

  static const weeklyProductId = 'banega_weekly_50';

  HouseholdSettings settings = const HouseholdSettings(id: 'h1', name: 'Purohit Parivaar');
  late Subscription _subscription;
  String? consentVersion;
  DeletionInfo? meDeleted;

  /// (ticket|recipe|member) → (recipe, member, score, note).
  final Map<String, (String, String, int, String?)> _ratings = {};

  final Map<String, NotificationPref> _prefs = {
    for (final (event, mandatory) in const [
      ('ticket_created', true),
      ('ticket_accepted', false),
      ('ticket_updated', true),
      ('ticket_completed', false),
      ('not_confirmed_prompt', false),
      ('cook_off_duty', false),
      ('no_show', false),
      ('stock_low', false),
      ('ration_request', false),
      ('ration_decided', false),
      ('stock_issue', false),
      ('approval_request', true),
      ('approval_decided', false),
      ('stock_issue_timeout', false),
      ('rate_prompt', false),
      ('expiry_reminder', false),
      ('weekly_summary', false),
      ('tomorrow_tickets', false),
    ])
      event: NotificationPref(event: event, enabled: true, mandatory: mandatory),
  };

  // ---------------------------------------------------------------- subscription

  Subscription get current => _subscription;

  @override
  Future<Subscription> subscription() async => _subscription;

  @override
  Future<Subscription> restore({required String store, required String purchaseToken}) async {
    if (purchaseToken.isEmpty) throw const KitchenError(status: 422, code: 'invalid_receipt');
    return _subscription;
  }

  /// Demo purchase: the store "answered", the plan is active for a week.
  Subscription subscribe() => _subscription = Subscription(
    status: SubscriptionStatus.active,
    renewsAt: k.now().add(const Duration(days: 7)),
    productId: weeklyProductId,
    store: 'play',
  );

  /// Demo switch for the paywall states (trial / grace / expired / active).
  void setStatus(SubscriptionStatus s) {
    final at = k.now();
    _subscription = switch (s) {
      SubscriptionStatus.trial => Subscription(
        status: s,
        trialEndsAt: at.add(const Duration(days: 5)),
        productId: weeklyProductId,
      ),
      SubscriptionStatus.active => subscribe(),
      SubscriptionStatus.grace => Subscription(
        status: s,
        renewsAt: at.add(const Duration(days: 3)),
        productId: weeklyProductId,
        store: 'play',
      ),
      SubscriptionStatus.expired => Subscription(
        status: s,
        trialEndsAt: at.subtract(const Duration(days: 1)),
        productId: weeklyProductId,
      ),
      SubscriptionStatus.unknown => Subscription(status: s),
    };
    if (s == SubscriptionStatus.expired) {
      k._event('expiry_reminder', 'Plan band ho gaya — ₹50/hafta mein chalu karo', null);
    }
  }

  // ---------------------------------------------------------------- household

  @override
  Future<HouseholdSettings> household() async => settings;

  @override
  Future<HouseholdSettings> patchHousehold(HouseholdPatch p) async {
    if (p.name != null && p.name!.trim().isEmpty) throw const KitchenError(status: 422, code: 'name_required');
    settings = settings.copyWith(
      name: p.name?.trim(),
      cookCanApproveSwaps: p.cookCanApproveSwaps,
      showNamesToCook: p.showNamesToCook,
      ratingsEnabled: p.ratingsEnabled,
      autoDecrement: p.autoDecrement,
    );
    return settings;
  }

  @override
  Future<DeletionInfo> deleteHousehold() async {
    final at = k.now();
    settings = settings.copyWith(deletedAt: at, undoUntil: at.add(const Duration(days: 7)));
    return DeletionInfo(deletedAt: settings.deletedAt, undoUntil: settings.undoUntil);
  }

  @override
  Future<HouseholdSettings> restoreHousehold() async => settings = settings.copyWith(clearDeletion: true);

  @override
  Future<DeletionInfo> deleteMe() async {
    final at = k.now();
    return meDeleted = DeletionInfo(deletedAt: at, undoUntil: at.add(const Duration(days: 7)));
  }

  @override
  Future<List<NotificationPref>> notificationPrefs() async => _prefs.values.toList();

  @override
  Future<List<NotificationPref>> putNotificationPrefs(List<NotificationPref> prefs) async {
    for (final p in prefs) {
      final cur = _prefs[p.event];
      if (cur == null) throw KitchenError(status: 404, code: 'unknown_event', message: p.event);
      if (!cur.mandatory) _prefs[p.event] = cur.withEnabled(p.enabled);
    }
    return _prefs.values.toList();
  }

  @override
  Future<void> consent(String version) async => consentVersion = version;

  @override
  Future<void> export() async {
    k._event(
      'export_ready',
      'Aapke ghar ka data export taiyaar hai',
      null,
      body: 'Link 24 ghante chalega',
      link: 'https://banega.app/export/demo.json',
    );
  }

  /// Completed tickets of the last 7 days: top dishes, on-time %, coverage.
  @override
  Future<WeeklyInsights> weekly() async {
    final today = parseWireDate(k.today);
    final from = today.subtract(const Duration(days: 6));
    final done = [
      for (final t in k._tickets.values)
        if (t.status == TicketStatus.completed && !parseWireDate(t.date).isBefore(from)) t,
    ];
    if (done.isEmpty) return const WeeklyInsights();
    final counts = <String, (String, int)>{};
    for (final t in done) {
      for (final d in t.dishes) {
        final c = counts[d.recipeId];
        counts[d.recipeId] = (d.name, (c?.$2 ?? 0) + 1);
      }
    }
    final top = counts.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    final onTime = done.where((t) => t.completedAt != null && t.dueAt != null && !t.completedAt!.isAfter(t.dueAt!));
    final covered = done.where((t) {
      final people = k.pantry._people(t);
      final rs = [for (final d in t.dishes) ?k._recipe(d.recipeId)];
      return people.every((m) => rs.any((r) => fitFor(m, r).kind != FitKind.no));
    });
    return WeeklyInsights(
      topDishes: [for (final e in top.take(3)) (e.key, e.value.$1, e.value.$2)],
      onTimePct: 100 * onTime.length / done.length,
      coveragePct: 100 * covered.length / done.length,
      mealsCooked: done.length,
    );
  }

  // ---------------------------------------------------------------- ratings

  @override
  Future<Ticket?> rate(String ticketId, List<RatingInput> ratings) async {
    final t = k._get(ticketId);
    if (t.status != TicketStatus.completed) throw const KitchenError(status: 409, code: 'not_completed');
    if (!settings.ratingsEnabled) throw const KitchenError(status: 409, code: 'ratings_disabled');
    if (ratings.isEmpty) throw const KitchenError(status: 422, code: 'ratings_empty');
    for (final r in ratings) {
      _ratings['$ticketId|${r.recipeId}|${r.memberId}'] = (r.recipeId, r.memberId, r.score.value, r.note);
    }
    if (t.ratedAt != null) return t;
    return k._store(t.copyWith(ratedAt: k.now(), version: t.version + 1));
  }

  /// Per-member averages; names only for the family (a hired cook viewing
  /// gets the aggregate unless show_names_to_cook).
  RatingSummary? summaryFor(String recipeId, {bool forHiredCook = false}) {
    final rows = [
      for (final v in _ratings.values)
        if (v.$1 == recipeId) v,
    ];
    if (rows.isEmpty) return null;
    final byMember = <String, List<int>>{};
    for (final r in rows) {
      (byMember[r.$2] ??= []).add(r.$3);
    }
    final names = {for (final m in k.members()) m.id: m.name};
    final showNames = !forHiredCook || settings.showNamesToCook;
    return RatingSummary(
      recipeId: recipeId,
      average: rows.fold<int>(0, (s, r) => s + r.$3) / rows.length,
      count: rows.length,
      members: showNames
          ? [
              for (final e in byMember.entries)
                MemberRating(
                  memberId: e.key,
                  name: names[e.key],
                  average: e.value.fold<int>(0, (s, v) => s + v) / e.value.length,
                  count: e.value.length,
                ),
            ]
          : const [],
    );
  }

  @override
  Future<RatingSummary?> summary(String recipeId) async {
    final me = k._cook(k.meCookId);
    return summaryFor(recipeId, forHiredCook: me?.kind == CookKind.hired && !k.meIsFamily);
  }
}
