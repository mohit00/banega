// Phase 6 repository interfaces: stock, ration requests, approvals. The
// Api* classes are in pantry_api.dart, the demo in kitchen/data/demo_pantry.dart,
// providers in pantry/application/pantry_providers.dart.
import '../../kitchen/domain/kitchen_models.dart';
import '../domain/pantry_models.dart';

abstract interface class StockRepository {
  /// GET /v1/stock.
  Future<List<StockItem>> stock();

  /// PUT /v1/stock/{ingredient_id} `{level, qty?}`.
  Future<StockItem> setLevel(String ingredientId, ItemStatus level, {double? qty});

  /// POST /v1/stock/bulk `{items: [{ingredient_id, level}]}`.
  Future<List<StockItem>> bulk(List<(String, ItemStatus)> items);
}

abstract interface class RationRepository {
  /// GET /v1/ration-requests?status=.
  Future<List<RationRequest>> requests({RationStatus? status});

  /// POST /v1/ration-requests `{ticket_id?, items}`.
  Future<RationRequest> create({String? ticketId, required List<RationItem> items});

  /// POST /v1/ration-requests/{id}/decide `{decision, note?}`.
  Future<RationRequest> decide(String id, String decision, {String? note});

  /// POST /v1/ration-requests/{id}/bought.
  Future<RationRequest> bought(String id);

  /// GET /v1/ration-requests/suggest?days= (Should).
  Future<List<RationItem>> suggest({int days = 7});
}

abstract interface class ApprovalsRepository {
  /// GET /v1/approvals?status=.
  Future<List<Approval>> approvals({String? status});

  /// POST /v1/approvals/{id}/decide `{decision}`.
  Future<Approval> decide(String id, String decision);
}
