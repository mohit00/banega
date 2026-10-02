// Phase 5 repository interfaces. Implementations: the Api* classes in
// kitchen_api.dart (Dio against the backend), [DemoKitchen] (in-memory state
// machine). Providers live in application/kitchen_providers.dart; API mode
// never falls back to the demo.
import '../domain/kitchen_models.dart';

abstract interface class MenusRepository {
  /// GET /v1/menus?date=&slot= (null on 404).
  Future<Menu?> menu(String date, String slot);

  /// GET /v1/menus?date= — that day's menus.
  Future<List<Menu>> menusForDate(String date);

  /// PUT /v1/menus/{date}/{slot}/dishes.
  Future<Menu> putDishes(String date, String slot, List<String> recipeIds);

  /// PATCH /v1/menus/{id}.
  Future<Menu> patchMenu(String id, MenuPatch patch);

  /// POST /v1/menus/{id}/confirm with Idempotency-Key and If-Match.
  Future<ConfirmResult> confirm(String id, {required int version, required String idempotencyKey});

  /// GET /v1/menus/{id}/share-text.
  Future<String> shareText(String id);
}

abstract interface class TicketsRepository {
  /// GET /v1/tickets?date=&status=&mine=.
  Future<List<Ticket>> tickets({String? date, String? status, bool mine = false});

  Future<Ticket> ticket(String id);

  /// POST /v1/tickets/{id}/transitions; throws [KitchenError] on 409.
  /// [assigneeCookId] picks the cook when an unassigned ticket moves to
  /// new (hired cook) or accepted (family cook); the server answers 422
  /// `assignee_required` without it.
  Future<Ticket> transition(
    String id,
    TicketStatus to, {
    required int version,
    required String idempotencyKey,
    String? reason,
    String? note,
    String? assigneeCookId,
  });

  /// PATCH /v1/tickets/{id} (If-Match version).
  Future<Ticket> patchTicket(String id, TicketPatch patch, {required int version});

  /// POST /v1/tickets/{id}/claim.
  Future<Ticket> claim(String id);

  /// POST /v1/tickets/{id}/items/{ingredient_id}/out (response carries `ladder`).
  Future<Ticket> markItemOut(String id, String ingredientId, {String? idempotencyKey});

  /// POST /v1/tickets/{id}/stock-issue/resolve `{action, substitute_ingredient_id? | recipe_id?}`.
  /// The ticket keeps `stock_issue_open` while an approval is pending.
  Future<Ticket> resolveStockIssue(
    String id,
    LadderAction action, {
    String? substituteIngredientId,
    String? recipeId,
    String? idempotencyKey,
  });

  Future<List<TicketMessage>> messages(String id);

  Future<TicketMessage> sendMessage(String id, String text, {String? idempotencyKey});

  /// GET /v1/tickets/{id}/recipes/{recipe_id}?servings=.
  Future<CookRecipe> recipe(String ticketId, String recipeId, {int? servings});
}

abstract interface class CooksRepository {
  Future<List<Cook>> cooks();

  /// PATCH /v1/cooks/{id} (duty toggle, primary / backup).
  Future<Cook> patchCook(String id, CookPatch patch);

  /// POST /v1/cooks `{kind, member_id? | phone, name, login_mode}`; 409
  /// `hired_cook_limit` / `phone_in_other_household`.
  Future<Cook> addCook({
    required CookKind kind,
    required String name,
    String? phone,
    String? memberId,
    String loginMode,
  });

  /// DELETE /v1/cooks/{id}.
  Future<void> removeCook(String id);

  /// GET /v1/me (modes + cook role).
  Future<Me> me();
}

abstract interface class InboxRepository {
  Future<List<InboxItem>> inbox({String? cursor});

  Future<void> markRead(String id);
}
