import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_source.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../data/pantry_api.dart';
import '../data/pantry_repositories.dart';
import '../domain/pantry_models.dart';

// ------------------------------------------------------------------ repositories

final stockRepositoryProvider = Provider<StockRepository>((ref) {
  final demo = ref.watch(demoKitchenProvider).pantry;
  if (ref.watch(dataSourceProvider) == DataSource.demo) return demo;
  return ApiStockRepository(ref.watch(dioProvider));
});

final rationRepositoryProvider = Provider<RationRepository>((ref) {
  final demo = ref.watch(demoKitchenProvider).pantry;
  if (ref.watch(dataSourceProvider) == DataSource.demo) return demo;
  return ApiRationRepository(ref.watch(dioProvider));
});

final approvalsRepositoryProvider = Provider<ApprovalsRepository>((ref) {
  final demo = ref.watch(demoKitchenProvider).pantry.approvalsRepo;
  if (ref.watch(dataSourceProvider) == DataSource.demo) return demo;
  return ApiApprovalsRepository(ref.watch(dioProvider));
});

/// Cook mode's stock (K-stock): the API, or the demo pantry as the cook.
final cookStockRepositoryProvider = Provider<StockRepository>((ref) {
  if (!ref.watch(cookUsesApiProvider)) return ref.watch(demoKitchenProvider).pantry.asCook;
  return ApiStockRepository(ref.watch(dioProvider));
});

/// Cook mode's ration requests (own requests; the server scopes the list).
final cookRationRepositoryProvider = Provider<RationRepository>((ref) {
  if (!ref.watch(cookUsesApiProvider)) return ref.watch(demoKitchenProvider).pantry.asCook;
  return ApiRationRepository(ref.watch(dioProvider));
});

// ------------------------------------------------------------------ reads

/// S15 / K-stock: tracked staples ([cook] picks the cook-mode repository).
final stockProvider = FutureProvider.family<List<StockItem>, bool>((ref, cook) {
  ref.watch(kitchenRevisionProvider);
  return (cook ? ref.watch(cookStockRepositoryProvider) : ref.watch(stockRepositoryProvider)).stock();
}, retry: (_, _) => null);

/// S13: ration requests (all, newest first); the tabs filter locally.
final rationRequestsProvider = FutureProvider.family<List<RationRequest>, bool>((ref, cook) {
  ref.watch(kitchenRevisionProvider);
  return (cook ? ref.watch(cookRationRepositoryProvider) : ref.watch(rationRepositoryProvider)).requests();
}, retry: (_, _) => null);

/// Approvals waiting for the family.
final pendingApprovalsProvider = FutureProvider<List<Approval>>((ref) {
  ref.watch(kitchenRevisionProvider);
  return ref.watch(approvalsRepositoryProvider).approvals(status: 'pending');
}, retry: (_, _) => null);

// ------------------------------------------------------------------ writes

/// Stock / ration / approval writes; each bumps the kitchen revision so the
/// Plan, tickets and lists re-read.
class PantryActions {
  PantryActions(this.ref, {required this.cook});

  final Ref ref;
  final bool cook;

  StockRepository get _stock => cook ? ref.read(cookStockRepositoryProvider) : ref.read(stockRepositoryProvider);

  RationRepository get _ration => cook ? ref.read(cookRationRepositoryProvider) : ref.read(rationRepositoryProvider);

  void _changed() => ref.read(kitchenRevisionProvider.notifier).bump();

  Future<StockItem> setLevel(String ingredientId, ItemStatus level) async {
    final s = await _stock.setLevel(ingredientId, level);
    _changed();
    return s;
  }

  /// "Sab In": every listed item back to In.
  Future<void> allIn(Iterable<String> ingredientIds) async {
    final ids = ingredientIds.toList();
    if (ids.isEmpty) return;
    await _stock.bulk([for (final id in ids) (id, ItemStatus.inStock)]);
    _changed();
  }

  Future<RationRequest> raise(List<RationItem> items, {String? ticketId}) async {
    final r = await _ration.create(ticketId: ticketId, items: items);
    _changed();
    return r;
  }

  Future<RationRequest> decide(String id, String decision, {String? note}) async {
    final r = await _ration.decide(id, decision, note: note);
    _changed();
    return r;
  }

  Future<RationRequest> bought(String id) async {
    final r = await _ration.bought(id);
    _changed();
    return r;
  }

  Future<Approval> decideApproval(String id, String decision) async {
    final a = await ref.read(approvalsRepositoryProvider).decide(id, decision);
    _changed();
    return a;
  }
}

final familyPantryActionsProvider = Provider<PantryActions>((ref) => PantryActions(ref, cook: false));
final cookPantryActionsProvider = Provider<PantryActions>((ref) => PantryActions(ref, cook: true));

/// Low / out tracked items of a menu or ticket, as ration lines.
List<RationItem> missingItems(List<RequiredItem> items) => [
  for (final i in items)
    if (i.status == ItemStatus.low || i.status == ItemStatus.out)
      RationItem(ingredientId: i.ingredientId, name: i.displayText),
];
