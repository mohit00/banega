import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../../pantry/data/pantry_api.dart' show PantryDio;
import '../domain/account_models.dart';
import 'account_repositories.dart';

class ApiRatingsRepository with ApiGuard, PantryDio implements RatingsRepository {
  ApiRatingsRepository(this.dio);

  @override
  final Dio dio;

  @override
  Future<Ticket?> rate(String ticketId, List<RatingInput> ratings) => guard(() async {
    final res = await dio.post<Object?>(
      '/v1/tickets/${enc(ticketId)}/ratings',
      data: {
        'ratings': [for (final r in ratings) r.toJson()],
      },
    );
    final data = res.data;
    if (data is Map && data['status'] != null && data['id'] != null) return Ticket.fromJson(map(data));
    if (data is Map && data['ticket'] is Map) return Ticket.fromJson(map(data['ticket']));
    return null;
  });

  @override
  Future<RatingSummary?> summary(String recipeId) => guard(() async {
    try {
      final res = await dio.get<Object?>('/v1/ratings/summary', queryParameters: {'recipe_id': recipeId});
      final data = res.data;
      if (data is List) return data.isEmpty ? null : RatingSummary.fromJson((data.first as Map).cast());
      final s = RatingSummary.fromJson(map(data));
      return s.count == 0 ? null : s;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  });
}

class ApiSubscriptionRepository with ApiGuard, PantryDio implements SubscriptionRepository {
  ApiSubscriptionRepository(this.dio);

  @override
  final Dio dio;

  @override
  Future<Subscription> subscription() => guard(() async {
    final res = await dio.get<Object?>('/v1/subscription');
    return Subscription.fromJson(map(res.data));
  });

  @override
  Future<Subscription> restore({required String store, required String purchaseToken}) => guard(() async {
    final res = await dio.post<Object?>(
      '/v1/subscription/restore',
      data: {'store': store, if (store == 'appstore') 'receipt': purchaseToken else 'purchase_token': purchaseToken},
    );
    return Subscription.fromJson(map(res.data));
  });
}

class ApiAccountRepository with ApiGuard, PantryDio implements AccountRepository {
  ApiAccountRepository(this.dio);

  @override
  final Dio dio;

  @override
  Future<HouseholdSettings> household() => guard(() async {
    final res = await dio.get<Object?>('/v1/households/me');
    return HouseholdSettings.fromJson(map(res.data));
  });

  @override
  Future<HouseholdSettings> patchHousehold(HouseholdPatch patch) => guard(() async {
    final res = await dio.patch<Object?>('/v1/households/me', data: patch.toJson());
    return HouseholdSettings.fromJson(map(res.data));
  });

  @override
  Future<DeletionInfo> deleteHousehold() => guard(() async {
    final res = await dio.delete<Object?>('/v1/household');
    return DeletionInfo.fromJson(map(res.data));
  });

  @override
  Future<HouseholdSettings> restoreHousehold() => guard(() async {
    final res = await dio.post<Object?>('/v1/household/restore');
    return HouseholdSettings.fromJson(map(res.data));
  });

  @override
  Future<DeletionInfo> deleteMe() => guard(() async {
    final res = await dio.delete<Object?>('/v1/me');
    return DeletionInfo.fromJson(map(res.data));
  });

  @override
  Future<List<NotificationPref>> notificationPrefs() => guard(() async {
    final res = await dio.get<Object?>('/v1/me/notification-prefs');
    final data = res.data;
    final raw = data is Map ? data['prefs'] : data;
    return [for (final j in list(raw)) NotificationPref.fromJson(j)];
  });

  @override
  Future<List<NotificationPref>> putNotificationPrefs(List<NotificationPref> prefs) => guard(() async {
    final res = await dio.put<Object?>(
      '/v1/me/notification-prefs',
      data: {
        'prefs': [
          for (final p in prefs)
            if (!p.mandatory) {'event': p.event, 'enabled': p.enabled},
        ],
      },
    );
    final data = res.data;
    final raw = data is Map ? data['prefs'] : data;
    return [for (final j in list(raw)) NotificationPref.fromJson(j)];
  });

  @override
  Future<void> consent(String version) => guard(() async {
    await dio.post<Object?>('/v1/consent', data: {'version': version});
  });

  @override
  Future<void> export() => guard(() async {
    await dio.post<Object?>('/v1/export');
  });

  @override
  Future<WeeklyInsights> weekly() => guard(() async {
    final res = await dio.get<Object?>('/v1/insights/weekly');
    return WeeklyInsights.fromJson(map(res.data));
  });
}
