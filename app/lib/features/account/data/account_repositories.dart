// Phase 7 repository interfaces: ratings, subscription, household settings /
// consent / export / deletion / insights. Api* in account_api.dart, the demo
// in kitchen/data/demo_account.dart, providers in account/application.
import '../../kitchen/domain/kitchen_models.dart';
import '../domain/account_models.dart';

abstract interface class RatingsRepository {
  /// POST /v1/tickets/{id}/ratings `{ratings: [...]}` → the ticket when the
  /// server returns it (sets `rated_at` on the first rating).
  Future<Ticket?> rate(String ticketId, List<RatingInput> ratings);

  /// GET /v1/ratings/summary?recipe_id= (null when nothing is rated yet).
  Future<RatingSummary?> summary(String recipeId);
}

abstract interface class SubscriptionRepository {
  /// GET /v1/subscription.
  Future<Subscription> subscription();

  /// POST /v1/subscription/restore `{store, receipt | purchase_token}`.
  Future<Subscription> restore({required String store, required String purchaseToken});
}

abstract interface class AccountRepository {
  /// GET /v1/households/me → household.
  Future<HouseholdSettings> household();

  /// PATCH /v1/households/me.
  Future<HouseholdSettings> patchHousehold(HouseholdPatch patch);

  /// DELETE /v1/household (7-day undo).
  Future<DeletionInfo> deleteHousehold();

  /// POST /v1/household/restore.
  Future<HouseholdSettings> restoreHousehold();

  /// DELETE /v1/me.
  Future<DeletionInfo> deleteMe();

  /// GET /v1/me/notification-prefs.
  Future<List<NotificationPref>> notificationPrefs();

  /// PUT /v1/me/notification-prefs `{prefs: [{event, enabled}]}`.
  Future<List<NotificationPref>> putNotificationPrefs(List<NotificationPref> prefs);

  /// POST /v1/consent `{version}`.
  Future<void> consent(String version);

  /// GET /v1/export (async job; the link arrives in the inbox).
  Future<void> export();

  /// GET /v1/insights/weekly (Should).
  Future<WeeklyInsights> weekly();
}
