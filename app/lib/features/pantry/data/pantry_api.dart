import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../data/models.dart' show Json;
import '../../kitchen/domain/kitchen_models.dart';
import '../domain/pantry_models.dart';
import 'pantry_repositories.dart';

/// JSON helpers over [ApiGuard] (every failure → `AppError`, one mapping).
mixin PantryDio on ApiGuard {
  Dio get dio;

  Json map(Object? data) => json(data);

  List<Json> list(Object? data) => jsonList(data);
}

class ApiStockRepository with ApiGuard, PantryDio implements StockRepository {
  ApiStockRepository(this.dio);

  @override
  final Dio dio;

  @override
  Future<List<StockItem>> stock() => guard(() async {
    final res = await dio.get<Object?>('/v1/stock');
    return [for (final j in list(res.data)) StockItem.fromJson(j)];
  });

  @override
  Future<StockItem> setLevel(String ingredientId, ItemStatus level, {double? qty}) => guard(() async {
    final res = await dio.put<Object?>('/v1/stock/${enc(ingredientId)}', data: {'level': level.wire, 'qty': ?qty});
    return StockItem.fromJson(map(res.data));
  });

  @override
  Future<List<StockItem>> bulk(List<(String, ItemStatus)> items) => guard(() async {
    final res = await dio.post<Object?>(
      '/v1/stock/bulk',
      data: {
        'items': [
          for (final (id, level) in items) {'ingredient_id': id, 'level': level.wire},
        ],
      },
    );
    return [for (final j in list(res.data)) StockItem.fromJson(j)];
  });
}

class ApiRationRepository with ApiGuard, PantryDio implements RationRepository {
  ApiRationRepository(this.dio);

  @override
  final Dio dio;

  @override
  Future<List<RationRequest>> requests({RationStatus? status}) => guard(() async {
    final res = await dio.get<Object?>('/v1/ration-requests', queryParameters: {'status': ?status?.wire});
    return [for (final j in list(res.data)) RationRequest.fromJson(j)];
  });

  @override
  Future<RationRequest> create({String? ticketId, required List<RationItem> items}) => guard(() async {
    final res = await dio.post<Object?>(
      '/v1/ration-requests',
      data: {
        'ticket_id': ?ticketId,
        'items': [for (final i in items) i.toJson()],
      },
    );
    return RationRequest.fromJson(map(res.data));
  });

  @override
  Future<RationRequest> decide(String id, String decision, {String? note}) => guard(() async {
    final res = await dio.post<Object?>(
      '/v1/ration-requests/${enc(id)}/decide',
      data: {'decision': decision, 'note': ?note},
    );
    return RationRequest.fromJson(map(res.data));
  });

  @override
  Future<RationRequest> bought(String id) => guard(() async {
    final res = await dio.post<Object?>('/v1/ration-requests/${enc(id)}/bought');
    return RationRequest.fromJson(map(res.data));
  });

  @override
  Future<List<RationItem>> suggest({int days = 7}) => guard(() async {
    final res = await dio.get<Object?>('/v1/ration-requests/suggest', queryParameters: {'days': days});
    return [for (final j in list(res.data)) RationItem.fromJson(j)];
  });
}

class ApiApprovalsRepository with ApiGuard, PantryDio implements ApprovalsRepository {
  ApiApprovalsRepository(this.dio);

  @override
  final Dio dio;

  @override
  Future<List<Approval>> approvals({String? status}) => guard(() async {
    final res = await dio.get<Object?>('/v1/approvals', queryParameters: {'status': ?status});
    return [for (final j in list(res.data)) Approval.fromJson(j)];
  });

  @override
  Future<Approval> decide(String id, String decision) => guard(() async {
    final res = await dio.post<Object?>('/v1/approvals/${enc(id)}/decide', data: {'decision': decision});
    return Approval.fromJson(map(res.data));
  });
}
