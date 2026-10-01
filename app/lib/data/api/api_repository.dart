import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../core/network/network_status.dart';
import '../../features/members/domain/member.dart';
import '../../features/recipe/domain/recipe.dart';
import '../models.dart';
import '../repositories.dart';

/// Dio client for the backend's `/v1` API (OpenAPI shapes in
/// lib/data/models.dart).
class ApiRepository with ApiGuard implements DataRepository {
  ApiRepository(this.dio);

  final Dio dio;

  Json _map(Object? data) => (data as Map).cast<String, dynamic>();

  @override
  Future<Recommendations> recommendations({
    required Slot slot,
    required DateTime date,
    required List<Member> members,
  }) => guard(() async {
    final res = await dio.get<Object?>(
      '/v1/recommendations',
      queryParameters: {'slot': slot.wire, 'date': wireDate(date)},
    );
    return Recommendations.fromJson(_map(res.data));
  });

  @override
  Future<RecipeDetail> recipe(String id, {int? servings, required List<Member> members, DateTime? date}) =>
      guard(() async {
        try {
          final res = await dio.get<Object?>(
            '/v1/recipes/${Uri.encodeComponent(id)}',
            queryParameters: {'servings': ?servings},
          );
          return RecipeDetail.fromJson(_map(res.data)).withMembers(members);
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) throw RecipeNotFound(id);
          rethrow;
        }
      });
}

/// True when [e] means the backend could not be reached at all (as opposed
/// to a 4xx/5xx answer).
bool isConnectionError(Object e) =>
    e is OfflineError ||
    (e is DioException && (AppError.from(e) is OfflineError || (e.response == null && isOfflineDioError(e))));
