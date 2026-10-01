// Phase 7 wire models: subscription, household settings, notification
// prefs, deletion, consent, weekly insights and ratings
// (docs/contracts/phase6-7-stock-ratings-billing.md).
import 'package:flutter/foundation.dart';

import '../../../data/models.dart' show Json;

DateTime? _time(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

String? _str(Object? v) => v == null ? null : '$v';

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

// ------------------------------------------------------------------ subscription

enum SubscriptionStatus {
  trial('trial'),
  active('active'),
  grace('grace'),
  expired('expired'),

  /// Could not be read (offline / error) or not understood. The app does
  /// not guess: nothing is locked client-side and the server enforces.
  unknown('unknown');

  const SubscriptionStatus(this.wire);
  final String wire;

  static SubscriptionStatus fromWire(String? v) => values.firstWhere((s) => s.wire == v, orElse: () => unknown);
}

/// `GET /v1/subscription` → `{status, trial_ends_at, renews_at, product_id, store}`.
@immutable
class Subscription {
  const Subscription({required this.status, this.trialEndsAt, this.renewsAt, this.productId, this.store});

  final SubscriptionStatus status;
  final DateTime? trialEndsAt;
  final DateTime? renewsAt;
  final String? productId;
  final String? store;

  /// Expired → read-only: no new menus, chats or tickets (F-5.1-05).
  bool get readOnly => status == SubscriptionStatus.expired;

  /// Whole days left in the trial (rounded up), 0 when over.
  int trialDaysLeft(DateTime now) {
    final end = trialEndsAt;
    if (end == null || !end.isAfter(now)) return 0;
    return (end.difference(now).inHours / 24).ceil();
  }

  factory Subscription.fromJson(Json j) => Subscription(
    status: SubscriptionStatus.fromWire(j['status'] as String?),
    trialEndsAt: _time(j['trial_ends_at']),
    renewsAt: _time(j['renews_at']),
    productId: _str(j['product_id']),
    store: _str(j['store']),
  );
}

// ------------------------------------------------------------------ household

/// The parts of `GET /v1/households/me` → `household` that Settings edits.
/// `ratings_enabled` and `auto_decrement` are the Phase 6/7 additions.
@immutable
class HouseholdSettings {
  const HouseholdSettings({
    required this.id,
    required this.name,
    this.cookCanApproveSwaps = true,
    this.showNamesToCook = false,
    this.ratingsEnabled = true,
    this.autoDecrement = false,
    this.deletedAt,
    this.undoUntil,
    this.timezone = 'Asia/Kolkata',
  });

  final String id;
  final String name;

  /// IANA zone the household plans in ("today", due times).
  final String timezone;
  final bool cookCanApproveSwaps;
  final bool showNamesToCook;
  final bool ratingsEnabled;
  final bool autoDecrement;

  /// Set while a deletion is pending (7-day undo).
  final DateTime? deletedAt;
  final DateTime? undoUntil;

  bool get pendingDeletion => deletedAt != null;

  factory HouseholdSettings.fromJson(Json j) {
    final h = j['household'] is Map ? (j['household'] as Map).cast<String, dynamic>() : j;
    return HouseholdSettings(
      id: '${h['id'] ?? ''}',
      name: h['name'] as String? ?? '',
      cookCanApproveSwaps: h['cook_can_approve_swaps'] as bool? ?? true,
      showNamesToCook: h['show_names_to_cook'] as bool? ?? false,
      ratingsEnabled: h['ratings_enabled'] as bool? ?? true,
      autoDecrement: h['auto_decrement'] as bool? ?? false,
      deletedAt: _time(h['deleted_at']),
      undoUntil: _time(h['undo_until']),
      timezone: h['timezone'] is String && (h['timezone'] as String).isNotEmpty
          ? h['timezone'] as String
          : 'Asia/Kolkata',
    );
  }

  HouseholdSettings copyWith({
    String? name,
    bool? cookCanApproveSwaps,
    bool? showNamesToCook,
    bool? ratingsEnabled,
    bool? autoDecrement,
    DateTime? deletedAt,
    DateTime? undoUntil,
    bool clearDeletion = false,
  }) => HouseholdSettings(
    id: id,
    name: name ?? this.name,
    cookCanApproveSwaps: cookCanApproveSwaps ?? this.cookCanApproveSwaps,
    showNamesToCook: showNamesToCook ?? this.showNamesToCook,
    ratingsEnabled: ratingsEnabled ?? this.ratingsEnabled,
    autoDecrement: autoDecrement ?? this.autoDecrement,
    deletedAt: clearDeletion ? null : (deletedAt ?? this.deletedAt),
    undoUntil: clearDeletion ? null : (undoUntil ?? this.undoUntil),
    timezone: timezone,
  );
}

/// PATCH /v1/households/me (only set fields are sent).
@immutable
class HouseholdPatch {
  const HouseholdPatch({
    this.name,
    this.cookCanApproveSwaps,
    this.showNamesToCook,
    this.ratingsEnabled,
    this.autoDecrement,
  });

  final String? name;
  final bool? cookCanApproveSwaps;
  final bool? showNamesToCook;
  final bool? ratingsEnabled;
  final bool? autoDecrement;

  Json toJson() => {
    'name': ?name,
    'cook_can_approve_swaps': ?cookCanApproveSwaps,
    'show_names_to_cook': ?showNamesToCook,
    'ratings_enabled': ?ratingsEnabled,
    'auto_decrement': ?autoDecrement,
  };
}

/// `DELETE /v1/household` / `DELETE /v1/me` → `{deleted_at, undo_until}`.
@immutable
class DeletionInfo {
  const DeletionInfo({this.deletedAt, this.undoUntil});

  final DateTime? deletedAt;
  final DateTime? undoUntil;

  factory DeletionInfo.fromJson(Json j) =>
      DeletionInfo(deletedAt: _time(j['deleted_at']), undoUntil: _time(j['undo_until']));
}

// ------------------------------------------------------------------ notification prefs

/// `GET /v1/me/notification-prefs` → `{prefs: [{event, enabled, mandatory}]}`.
@immutable
class NotificationPref {
  const NotificationPref({required this.event, required this.enabled, this.mandatory = false});

  final String event;
  final bool enabled;
  final bool mandatory;

  factory NotificationPref.fromJson(Json j) => NotificationPref(
    event: '${j['event']}',
    enabled: j['enabled'] as bool? ?? true,
    mandatory: j['mandatory'] as bool? ?? false,
  );

  NotificationPref withEnabled(bool v) => NotificationPref(event: event, enabled: v, mandatory: mandatory);
}

// ------------------------------------------------------------------ insights

/// `GET /v1/insights/weekly` (Should). Shape chosen by the app:
/// `{top_dishes: [{recipe_id, name, count}], on_time_pct, coverage_pct, meals_cooked}`.
@immutable
class WeeklyInsights {
  const WeeklyInsights({this.topDishes = const [], this.onTimePct, this.coveragePct, this.mealsCooked = 0});

  final List<(String, String, int)> topDishes;
  final double? onTimePct;
  final double? coveragePct;
  final int mealsCooked;

  bool get isEmpty => mealsCooked == 0 && topDishes.isEmpty;

  factory WeeklyInsights.fromJson(Json j) {
    final cov = j['coverage_pct'] ?? (j['coverage'] is Map ? (j['coverage'] as Map)['pct'] : j['coverage']);
    return WeeklyInsights(
      topDishes: [
        for (final d in (j['top_dishes'] as List? ?? const []))
          if (d is Map) ('${d['recipe_id'] ?? ''}', '${d['name'] ?? ''}', (d['count'] as num?)?.toInt() ?? 0),
      ],
      onTimePct: j['on_time_pct'] == null ? null : _num(j['on_time_pct']),
      coveragePct: cov == null ? null : _num(cov),
      mealsCooked: (j['meals_cooked'] as num?)?.toInt() ?? 0,
    );
  }
}

// ------------------------------------------------------------------ ratings

/// 1..3: bura | theek | bahut accha.
enum RatingScore {
  bura(1),
  theek(2),
  bahutAccha(3);

  const RatingScore(this.value);
  final int value;

  static RatingScore? fromValue(int? v) {
    for (final s in values) {
      if (s.value == v) return s;
    }
    return null;
  }
}

/// One `{recipe_id, member_id, score, note?}` for POST /tickets/{id}/ratings.
@immutable
class RatingInput {
  const RatingInput({required this.recipeId, required this.memberId, required this.score, this.note});

  final String recipeId;
  final String memberId;
  final RatingScore score;
  final String? note;

  Json toJson() => {
    'recipe_id': recipeId,
    'member_id': memberId,
    'score': score.value,
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
  };
}

/// `GET /v1/ratings/summary?recipe_id=` → `{recipe_id, average, count,
/// members: [{member_id, name?, average, count}]}`. A hired cook gets no
/// `members` unless `show_names_to_cook`.
@immutable
class RatingSummary {
  const RatingSummary({required this.recipeId, required this.average, required this.count, this.members = const []});

  final String recipeId;
  final double average;
  final int count;
  final List<MemberRating> members;

  factory RatingSummary.fromJson(Json j) {
    final ms = [
      for (final m in (j['members'] as List? ?? const []))
        if (m is Map) MemberRating.fromJson(m.cast<String, dynamic>()),
    ];
    final count = (j['count'] as num?)?.toInt() ?? ms.fold<int>(0, (s, m) => s + m.count);
    final avg = j['average'] != null
        ? _num(j['average'])
        : (count == 0 ? 0.0 : ms.fold<double>(0, (s, m) => s + m.average * m.count) / count);
    return RatingSummary(recipeId: '${j['recipe_id'] ?? ''}', average: avg, count: count, members: ms);
  }
}

@immutable
class MemberRating {
  const MemberRating({required this.memberId, this.name, required this.average, required this.count});

  final String memberId;
  final String? name;
  final double average;
  final int count;

  factory MemberRating.fromJson(Json j) => MemberRating(
    memberId: '${j['member_id'] ?? ''}',
    name: _str(j['name']),
    average: _num(j['average']),
    count: (j['count'] as num?)?.toInt() ?? 0,
  );
}
