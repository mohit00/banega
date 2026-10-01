import 'dart:convert';
import 'dart:typed_data';

import 'package:banega/core/config.dart';
import 'package:banega/core/engine/fit_engine.dart';
import 'package:banega/core/network/network_status.dart';
import 'package:banega/core/l10n/gen/app_localizations_hi.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/data/api/api_repository.dart';
import 'package:banega/data/data_source.dart';
import 'package:banega/data/demo/demo_repository.dart';
import 'package:banega/features/home/home_providers.dart';
import 'package:banega/features/members/application/members_controller.dart';
import 'package:banega/features/members/data/members_repository.dart';
import 'package:banega/features/members/domain/member.dart';
import 'package:banega/features/recipe/application/recipe_providers.dart';
import 'package:banega/features/recipe/domain/recipe.dart';
import 'package:banega/labels/labels.dart';
import 'package:banega/ui/ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart' show keyValueStoreProvider;
import 'package:banega/features/kitchen/data/ticket_cache.dart' show MemoryStore;
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// In-memory Dio adapter: answers by path, or fails every request.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes, {this.failWith});

  final Map<String, (int, Object)> routes;
  final DioExceptionType? failWith;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (failWith != null) {
      throw DioException(requestOptions: options, type: failWith!, message: 'fake ${failWith!.name}');
    }
    final hit = routes[options.path];
    final (status, body) = hit ?? (404, {'detail': 'not found'});
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio fakeDio(FakeAdapter adapter) => Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = adapter;

Map<String, Object?> card(String id, String name, {String badge = 'fit', String label = 'all_perfect'}) => {
  'id': id,
  'name': name,
  'cuisine': 'south_indian',
  'mins': 25,
  'colour': '#F3EFE6',
  'image_url': null,
  'diet': 'veg',
  'summary': {
    'badge': badge,
    'label_key': label,
    'label_params': label == 'all_with_tweaks' ? {'count': 2} : <String, Object>{},
    'note_key': label == 'all_with_tweaks' ? 'less_oil' : 'everyone_happy',
    'note_params': label == 'all_with_tweaks' ? {'name': 'Papa'} : <String, Object>{},
  },
};

final recommendationsJson = {
  'pick': card('api-pick', 'API Pesarattu'),
  'tiles': [for (var i = 0; i < 8; i++) card('api-$i', 'API Dish $i', badge: 'tweak', label: 'all_with_tweaks')],
  'constraint_line': {
    'key': 'items',
    'params': {'count': 3},
  },
};

final recipeJson = {
  'id': 'api-pick',
  'name': 'API Pesarattu',
  'sub': 'Hari moong ka dosa',
  'cuisine': 'South Indian',
  'mins': 25,
  'diet': 'veg',
  'jain_safe': true,
  'colour': '#8DBF5A',
  'image_url': null,
  'video_url': 'https://example.com/v',
  'base_servings': 4,
  'servings': 6,
  'batch_warning': false,
  'ingredients': [
    {'display_text': 'Hari moong 1 cup', 'qty': 1, 'unit': 'cup', 'scaled_text': 'Hari moong 1½ cup'},
    {'display_text': 'Adrak', 'scaled_text': 'Adrak'},
  ],
  'steps': ['Moong bhigo do.', 'Pees ke dosa banao.'],
  'fits': [
    {
      'member_id': 'u1',
      'name': 'Papa',
      'colour': '#2F5FC4',
      'status': 'tweak',
      'reason_key': 'less_oil',
      'reason_params': <String, Object>{},
    },
    {
      'member_id': 'u2',
      'name': 'Dadi',
      'colour': '#7549BF',
      'status': 'no',
      'reason_key': 'allergen',
      'reason_params': {'item': 'peanut'},
    },
  ],
  'summary': {
    'badge': 'no',
    'label_key': 'some',
    'label_params': {'can': 1, 'total': 2},
    'note_key': 'nobody_for',
    'note_params': {
      'names': ['Dadi'],
    },
  },
};

final membersJson = [
  {
    'id': 'u1',
    'name': 'Papa',
    'colour': '#2F5FC4',
    'diet': 'eggetarian',
    'spice': 'teekha',
    'needs': ['low_sugar', 'diabetic', 'unknown_need'],
    'cuisines': ['north_indian', 'Bengali', 'martian'],
    'is_kid': false,
    'allergens': ['peanut'],
    'dislikes': ['baingan'],
  },
  {'id': 'u2', 'name': 'Chhotu', 'diet': 'no_onion_garlic', 'spice': 'kam', 'is_kid': true},
];

bool? lastOffline;

void main() {
  final l = AppLocalizationsHiLatn();

  group('ApiRepository parsing', () {
    late FakeAdapter adapter;
    late ApiRepository api;

    setUp(() {
      adapter = FakeAdapter({
        '/v1/recommendations': (200, recommendationsJson),
        '/v1/recipes/api-pick': (200, recipeJson),
        '/v1/members': (200, membersJson),
      });
      api = ApiRepository(fakeDio(adapter));
    });

    test('recommendations', () async {
      final r = await api.recommendations(slot: Slot.breakfast, date: DateTime(2026, 9, 26, 8), members: const []);
      expect(adapter.requests.single.queryParameters, {'slot': 'nashta', 'date': '2026-09-26'});
      expect(r.pick.name, 'API Pesarattu');
      expect(r.pick.colour, const Color(0xFFF3EFE6));
      expect(r.pick.imageUrl, isNull);
      expect(r.tiles, hasLength(8));
      expect(r.tiles.first.summary.badge, FitKind.tweak);
      expect(l.summaryLabel(r.tiles.first.summary), 'Sabke liye · 2 tweak');
      expect(l.summaryShort(r.tiles.first.summary), 'Sab · 2 tweak');
      expect(l.summaryNote(r.tiles.first.summary), 'Papa: kam tel mein banao');
      expect(l.cuisineLabel(r.pick.cuisine), 'South Indian');
      expect(r.constraintKey, 'items');
    });

    test('recipe detail with servings', () async {
      final d = await api.recipe('api-pick', servings: 6, members: const []);
      expect(adapter.requests.single.path, '/v1/recipes/api-pick');
      expect(adapter.requests.single.queryParameters, {'servings': 6});
      expect(d.jainSafe, isTrue);
      expect(d.servings, 6);
      expect(d.videoUrl, 'https://example.com/v');
      expect(d.ingredients.first.qty, 1);
      expect(d.ingredients.first.scaledText, 'Hari moong 1½ cup');
      expect(d.ingredients.last.scaledText, 'Adrak');
      expect(d.steps, hasLength(2));
      expect(d.fits.map((f) => f.status), [FitKind.tweak, FitKind.no]);
      expect(l.reasonText(d.fits.last.reasonKey, d.fits.last.reasonParams), 'Moongphali se allergy');
      expect(l.summaryLabel(d.summary), '1/2 ke liye');
      expect(l.summaryNote(d.summary), 'Dadi ke liye nahi');
    });

    test('unknown recipe is RecipeNotFound', () async {
      await expectLater(api.recipe('nope', members: const []), throwsA(isA<Exception>()));
      expect(adapter.requests.single.queryParameters, isEmpty);
    });

    test('members', () async {
      final ms = await ApiMembersRepository(fakeDio(adapter)).fetchMembers();
      expect(ms, hasLength(2));
      final papa = ms.first;
      expect(papa.diet, Diet.egg);
      expect(papa.spice, Spice.teekha);
      expect(papa.needs, [Need.lowSugar]);
      expect(papa.cuisines, [Cuisine.northIndian, Cuisine.bengali]);
      expect(papa.allergens, ['peanut']);
      expect(papa.dislikes, ['baingan']);
      expect(ms.last.diet, Diet.noOnionGarlic);
      expect(ms.last.isKid, isTrue);
      expect(ms.last.spice, Spice.kam);
    });
  });

  group('no silent demo fallback', () {
    test('providers: a connection error stays in API mode, marks offline and surfaces', () async {
      final c = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          dioProvider.overrideWithValue(
            fakeDio(FakeAdapter(const {}, failWith: DioExceptionType.connectionError))
              ..interceptors.add(NetworkStatusInterceptor((o) => lastOffline = o)),
          ),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 26, 12)),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(dataSourceProvider), DataSource.api);
      c.listen(membersProvider, (_, _) {});
      c.listen(recommendationsProvider(Slot.lunch), (_, _) {});
      await expectLater(c.read(recommendationsProvider(Slot.lunch).future), throwsA(anything));
      expect(c.read(dataSourceProvider), DataSource.api, reason: 'never flips to demo on its own');
      expect(c.read(dataRepositoryProvider), isA<ApiRepository>());
      expect(lastOffline, isTrue);
    });

    test('the sandbox is an explicit choice', () {
      final c = ProviderContainer(
        overrides: [appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test'))],
      );
      addTearDown(c.dispose);
      expect(c.read(dataSourceProvider), DataSource.api);
      c.read(sandboxProvider.notifier).enter();
      expect(c.read(dataSourceProvider), DataSource.demo);
      expect(c.read(dataRepositoryProvider), isA<DemoRepository>());
    });

    test('providers: API mode uses the API when it answers', () async {
      final c = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          dioProvider.overrideWithValue(
            fakeDio(
              FakeAdapter({
                '/v1/recommendations': (200, recommendationsJson),
                '/v1/members': (200, membersJson),
                '/v1/recipes/api-pick': (200, recipeJson),
              }),
            ),
          ),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 26, 12)),
        ],
      );
      addTearDown(c.dispose);
      // Riverpod 3 pauses unlistened providers; keep these alive like the UI does.
      c.listen(membersProvider, (_, _) {});
      c.listen(recommendationsProvider(Slot.lunch), (_, _) {});
      final recs = await c.read(recommendationsProvider(Slot.lunch).future);
      expect(recs.pick.name, 'API Pesarattu');
      await Future<void>.delayed(Duration.zero);
      expect(c.read(membersProvider).map((m) => m.name), ['Papa', 'Chhotu']);
      c.listen(recipeDetailProvider(('api-pick', 6)), (_, _) {});
      final d = await c.read(recipeDetailProvider(('api-pick', 6)).future);
      expect(d.name, 'API Pesarattu');
      expect(c.read(dataSourceProvider), DataSource.api);
    });
  });

  group('Home in API mode', () {
    testWidgets('shows API data and no demo pill', (tester) async {
      await pumpBanega(
        tester,
        Routes.home,
        tall: true,
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          dioProvider.overrideWithValue(
            fakeDio(
              FakeAdapter({'/v1/recommendations': (200, recommendationsJson), '/v1/members': (200, membersJson)}),
            ),
          ),
        ],
      );
      await settle(tester);
      expect(find.text('API Pesarattu'), findsOneWidget);
      expect(find.byType(RecipeTile), findsNWidgets(8));
      expect(find.text('Demo data'), findsNothing);
      // Privacy: Papa's low sugar stays off Home until he opts in.
      expect(find.textContaining('low sugar'), findsNothing);
    });

    testWidgets('connection error: offline banner and retry, never the demo family', (tester) async {
      final adapter = FakeAdapter(const {}, failWith: DioExceptionType.connectionError);
      await pumpBanega(
        tester,
        Routes.home,
        tall: true,
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          dioProvider.overrideWith(
            (ref) =>
                fakeDio(adapter)
                  ..interceptors.add(NetworkStatusInterceptor(ref.read(networkOfflineProvider.notifier).set)),
          ),
        ],
      );
      await settle(tester);
      expect(find.text('Demo data'), findsNothing);
      expect(find.text('Purohit Parivaar'), findsNothing);
      expect(find.byKey(const ValueKey('offline-banner')), findsOneWidget);
      final before = adapter.requests.length;
      await tester.tap(find.byKey(const ValueKey('offline-retry')));
      await settle(tester);
      expect(adapter.requests.length, greaterThan(before), reason: 'retry re-reads');
      expect(tester.takeException(), isNull);
    });
  });
}
