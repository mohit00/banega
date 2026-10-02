import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../data/models.dart' show Json;
import '../domain/kitchen_models.dart';
import 'kitchen_repositories.dart';

/// Shared plumbing: [ApiGuard] maps every failure to an `AppError`
/// (4xx → [KitchenError], offline → `OfflineError`, …) in one place.
mixin _KitchenDio on ApiGuard {
  Dio get dio;

  Json map(Object? data) => json(data);

  List<Json> list(Object? data) => jsonList(data);
}

class ApiMenusRepository with ApiGuard, _KitchenDio implements MenusRepository {
  ApiMenusRepository(this.dio);

  @override
  final Dio dio;

  @override
  Future<Menu?> menu(String date, String slot) => guard(() async {
    try {
      final res = await dio.get<Object?>('/v1/menus', queryParameters: {'date': date, 'slot': slot});
      final data = res.data;
      if (data is List) return data.isEmpty ? null : Menu.fromJson((data.first as Map).cast<String, dynamic>());
      return Menu.fromJson(map(data));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  });

  @override
  Future<List<Menu>> menusForDate(String date) => guard(() async {
    final res = await dio.get<Object?>('/v1/menus', queryParameters: {'date': date});
    return [for (final m in list(res.data)) Menu.fromJson(m)];
  });

  @override
  Future<Menu> putDishes(String date, String slot, List<String> recipeIds) => guard(() async {
    final res = await dio.put<Object?>('/v1/menus/${enc(date)}/${enc(slot)}/dishes', data: {'recipe_ids': recipeIds});
    return Menu.fromJson(map(res.data));
  });

  @override
  Future<Menu> patchMenu(String id, MenuPatch patch) => guard(() async {
    final res = await dio.patch<Object?>('/v1/menus/${enc(id)}', data: patch.toJson());
    return Menu.fromJson(map(res.data));
  });

  @override
  Future<ConfirmResult> confirm(String id, {required int version, required String idempotencyKey}) => guard(() async {
    final res = await dio.post<Object?>(
      '/v1/menus/${enc(id)}/confirm',
      options: headers(version: version, idempotencyKey: idempotencyKey),
    );
    return ConfirmResult.fromJson(map(res.data));
  });

  @override
  Future<String> shareText(String id) => guard(() async {
    final res = await dio.get<Object?>('/v1/menus/${enc(id)}/share-text');
    return '${map(res.data)['text'] ?? ''}';
  });
}

class ApiTicketsRepository with ApiGuard, _KitchenDio implements TicketsRepository {
  ApiTicketsRepository(this.dio);

  @override
  final Dio dio;

  @override
  Future<List<Ticket>> tickets({String? date, String? status, bool mine = false}) => guard(() async {
    final res = await dio.get<Object?>(
      '/v1/tickets',
      queryParameters: {'date': ?date, 'status': ?status, if (mine) 'mine': 'true'},
    );
    return [for (final t in list(res.data)) Ticket.fromJson(t)];
  });

  @override
  Future<Ticket> ticket(String id) => guard(() async {
    final res = await dio.get<Object?>('/v1/tickets/${enc(id)}');
    return Ticket.fromJson(map(res.data));
  });

  @override
  Future<Ticket> transition(
    String id,
    TicketStatus to, {
    required int version,
    required String idempotencyKey,
    String? reason,
    String? note,
    String? assigneeCookId,
  }) => guard(() async {
    final res = await dio.post<Object?>(
      '/v1/tickets/${enc(id)}/transitions',
      data: {'to': to.wire, 'reason': ?reason, 'note': ?note, 'assignee_cook_id': ?assigneeCookId},
      options: headers(version: version, idempotencyKey: idempotencyKey),
    );
    return Ticket.fromJson(map(res.data));
  });

  @override
  Future<Ticket> patchTicket(String id, TicketPatch patch, {required int version}) => guard(() async {
    final res = await dio.patch<Object?>(
      '/v1/tickets/${enc(id)}',
      data: patch.toJson(),
      options: headers(version: version),
    );
    return Ticket.fromJson(map(res.data));
  });

  @override
  Future<Ticket> claim(String id) => guard(() async {
    final res = await dio.post<Object?>('/v1/tickets/${enc(id)}/claim');
    return Ticket.fromJson(map(res.data));
  });

  @override
  Future<Ticket> markItemOut(String id, String ingredientId, {String? idempotencyKey}) => guard(() async {
    final res = await dio.post<Object?>(
      '/v1/tickets/${enc(id)}/items/${enc(ingredientId)}/out',
      options: headers(idempotencyKey: idempotencyKey),
    );
    return Ticket.fromJson(map(res.data));
  });

  @override
  Future<Ticket> resolveStockIssue(
    String id,
    LadderAction action, {
    String? substituteIngredientId,
    String? recipeId,
    String? idempotencyKey,
  }) => guard(() async {
    final res = await dio.post<Object?>(
      '/v1/tickets/${enc(id)}/stock-issue/resolve',
      data: {'action': action.wire, 'substitute_ingredient_id': ?substituteIngredientId, 'recipe_id': ?recipeId},
      options: headers(idempotencyKey: idempotencyKey),
    );
    return Ticket.fromJson(map(res.data));
  });

  @override
  Future<List<TicketMessage>> messages(String id) => guard(() async {
    final res = await dio.get<Object?>('/v1/tickets/${enc(id)}/messages');
    return [for (final m in list(res.data)) TicketMessage.fromJson(m)];
  });

  @override
  Future<TicketMessage> sendMessage(String id, String text, {String? idempotencyKey}) => guard(() async {
    final res = await dio.post<Object?>(
      '/v1/tickets/${enc(id)}/messages',
      data: {'text': text},
      options: headers(idempotencyKey: idempotencyKey),
    );
    return TicketMessage.fromJson(map(res.data));
  });

  @override
  Future<CookRecipe> recipe(String ticketId, String recipeId, {int? servings}) => guard(() async {
    final res = await dio.get<Object?>(
      '/v1/tickets/${enc(ticketId)}/recipes/${enc(recipeId)}',
      queryParameters: {'servings': ?servings},
    );
    return CookRecipe.fromJson(map(res.data));
  });
}

class ApiCooksRepository with ApiGuard, _KitchenDio implements CooksRepository {
  ApiCooksRepository(this.dio);

  @override
  final Dio dio;

  @override
  Future<List<Cook>> cooks() => guard(() async {
    final res = await dio.get<Object?>('/v1/cooks');
    return [for (final c in list(res.data)) Cook.fromJson(c)];
  });

  @override
  Future<Cook> patchCook(String id, CookPatch patch) => guard(() async {
    final res = await dio.patch<Object?>('/v1/cooks/${enc(id)}', data: patch.toJson());
    return Cook.fromJson(map(res.data));
  });

  @override
  Future<Cook> addCook({
    required CookKind kind,
    required String name,
    String? phone,
    String? memberId,
    String loginMode = 'app',
  }) => guard(() async {
    final res = await dio.post<Object?>(
      '/v1/cooks',
      data: {'kind': kind.name, 'name': name, 'phone': ?phone, 'member_id': ?memberId, 'login_mode': loginMode},
    );
    return Cook.fromJson(map(res.data));
  });

  @override
  Future<void> removeCook(String id) => guard(() async {
    await dio.delete<Object?>('/v1/cooks/${enc(id)}');
  });

  @override
  Future<Me> me() => guard(() async {
    final res = await dio.get<Object?>('/v1/me');
    return Me.fromJson(map(res.data));
  });
}

class ApiInboxRepository with ApiGuard, _KitchenDio implements InboxRepository {
  ApiInboxRepository(this.dio);

  @override
  final Dio dio;

  @override
  Future<List<InboxItem>> inbox({String? cursor}) => guard(() async {
    final res = await dio.get<Object?>('/v1/inbox', queryParameters: {'cursor': ?cursor});
    return [for (final i in list(res.data)) InboxItem.fromJson(i)];
  });

  @override
  Future<void> markRead(String id) => guard(() async {
    await dio.post<Object?>('/v1/inbox/${enc(id)}/read');
  });
}
