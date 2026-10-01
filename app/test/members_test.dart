import 'package:banega/core/config.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/data/data_source.dart';
import 'package:banega/data/models.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:banega/features/members/application/members_controller.dart';
import 'package:banega/features/members/domain/member.dart';
import 'package:banega/features/members/presentation/prefs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'auth_test.dart' show RouteAdapter;
import 'helpers.dart';

Map<String, Object?> memberJson(String id, String name, {String diet = 'veg'}) => {
  'id': id,
  'household_id': 'h1',
  'name': name,
  'colour': '#FFB4A2',
  'is_kid': false,
  'diet': diet,
  'nonveg_exclusions': <String>[],
  'no_dairy': false,
  'spice': 'medium',
  'needs': <String>[],
  'cuisines': <String>[],
  'allergens': <String>[],
  'dislikes': <String>[],
  'archived_at': null,
  'created_at': '2026-09-26T00:00:00Z',
  'updated_at': '2026-09-26T00:00:00Z',
};

List<Override> apiOverrides(RouteAdapter a, {MemoryStore? store}) => [
  appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
  keyValueStoreProvider.overrideWithValue(store ?? MemoryStore()),
  httpClientAdapterProvider.overrideWithValue(a),
];

void main() {
  group('members API', () {
    test('API mode starts empty + loading, then the server list (never placeholder people)', () async {
      final a = RouteAdapter({
        'GET /v1/members': (_) => (
          200,
          {
            'items': [memberJson('m1', 'Papa'), memberJson('m2', 'Dadi')],
          },
        ),
      });
      final c = containerAt(testNoon, overrides: apiOverrides(a));
      c.listen(membersProvider, (_, _) {});
      expect(c.read(dataSourceProvider), DataSource.api);
      expect(c.read(membersProvider), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(membersStatusProvider).loading, isTrue);
      await pumpEventQueue();
      expect(c.read(membersProvider).map((m) => m.name), ['Papa', 'Dadi']);
      expect(c.read(membersStatusProvider).loading, isFalse);
    });

    test('an edit is optimistic, PATCHes the member, and rolls back on failure', () async {
      var fail = false;
      final a = RouteAdapter({
        'GET /v1/members': (_) => (
          200,
          {
            'items': [memberJson('m1', 'Papa')],
          },
        ),
        'PATCH /v1/members/m1': (o) {
          if (fail) return (500, {'code': 'boom'});
          final body = (o.data as Map).cast<String, dynamic>();
          return (200, {...memberJson('m1', 'Papa'), ...body});
        },
      });
      final c = containerAt(testNoon, overrides: apiOverrides(a));
      c.listen(membersProvider, (_, _) {});
      await pumpEventQueue();
      final ctrl = c.read(membersProvider.notifier);

      final write = ctrl.setDiet('m1', Diet.jain);
      expect(c.read(membersProvider).single.diet, Diet.jain, reason: 'optimistic');
      await write;
      final patch = a.requests.lastWhere((r) => r.method == 'PATCH');
      expect((patch.data as Map)['diet'], 'jain');
      expect(c.read(membersProvider).single.diet, Diet.jain);

      fail = true;
      await expectLater(ctrl.toggleAllergen('m1', 'peanut'), throwsA(anything));
      expect(c.read(membersProvider).single.allergens, isEmpty, reason: 'rolled back');
      expect(c.read(membersProvider).single.diet, Diet.jain, reason: 'earlier confirmed edit kept');
    });

    test('add POSTs and uses the server id; remove DELETEs (archive) and restores on failure', () async {
      var deleteFails = true;
      final a = RouteAdapter({
        'GET /v1/members': (_) => (200, {'items': <Object>[]}),
        'POST /v1/members': (o) => (201, memberJson('srv-1', (o.data as Map)['name'] as String)),
        'DELETE /v1/members/srv-1': (_) => deleteFails ? (503, {'code': 'down'}) : (204, null),
      });
      final c = containerAt(testNoon, overrides: apiOverrides(a));
      c.listen(membersProvider, (_, _) {});
      await pumpEventQueue();
      final ctrl = c.read(membersProvider.notifier);
      final m = await ctrl.addMember('Bua');
      expect(m.id, 'srv-1');
      expect(c.read(membersProvider).single.name, 'Bua');

      await expectLater(ctrl.remove('srv-1'), throwsA(anything));
      expect(c.read(membersProvider).single.id, 'srv-1', reason: 'restored');
      deleteFails = false;
      await ctrl.remove('srv-1');
      expect(c.read(membersProvider), isEmpty);
    });

    test('vrat days and show-on-Home stay on the device and survive a refetch', () async {
      final store = MemoryStore();
      final a = RouteAdapter({
        'GET /v1/members': (_) => (
          200,
          {
            'items': [memberJson('m1', 'Papa')],
          },
        ),
        'PATCH /v1/members/m1': (o) => (200, memberJson('m1', 'Papa')),
      });
      final c = containerAt(testNoon, overrides: apiOverrides(a, store: store));
      c.listen(membersProvider, (_, _) {});
      await pumpEventQueue();
      await c.read(membersProvider.notifier).toggleVratDay('m1', DateTime.monday);
      expect(c.read(membersProvider).single.vratDays, {DateTime.monday});
      await c.read(membersProvider.notifier).refresh();
      expect(c.read(membersProvider).single.vratDays, {DateTime.monday});
    });

    test('memberToJson matches MemberIn', () {
      final j = memberToJson(
        const Member(
          id: 'x',
          name: 'Papa',
          color: Color(0xFFFFB4A2),
          diet: Diet.nonveg,
          needs: [Need.lowSugar],
          cuisines: [Cuisine.southIndian],
          nonvegExclusions: ['no_beef'],
          isKid: true,
          allergens: ['peanut'],
        ),
      );
      expect(j['diet'], 'non_veg');
      expect(j['needs'], ['low_sugar']);
      expect(j['cuisines'], ['south_indian']);
      expect(j['colour'], '#FFB4A2');
      expect(j['spice'], 'medium');
      expect(j['nonveg_exclusions'], ['no_beef']);
      expect(j['is_kid'], isTrue);
      expect(j.containsKey('id'), isFalse);
    });
  });

  group('Prefs', () {
    testWidgets('all six diets, allergens, kid, vrat, dislikes; non-veg limits only for non-veg', (tester) async {
      final c = await pumpBanega(tester, Routes.prefs('m1'), tall: true);
      expect(find.byType(PrefsScreen), findsOneWidget);
      for (final d in ['Veg', 'Jain', 'Egg', 'Non-veg']) {
        expect(find.textContaining(d), findsWidgets, reason: d);
      }
      final m0 = c.read(membersProvider).firstWhere((m) => m.id == 'm1');

      await tester.tap(find.byKey(const ValueKey('allergen-peanut')));
      await tester.tap(find.byKey(const ValueKey('vrat-1')));
      await tester.tap(find.byKey(const ValueKey('prefs-kid')).first);
      await settle(tester);
      var m = c.read(membersProvider).firstWhere((m) => m.id == 'm1');
      expect(m.allergens, contains('peanut'));
      expect(m.vratDays, {DateTime.monday});

      await tester.enterText(find.byKey(const ValueKey('dislike-input')), 'Baingan');
      await tester.tap(find.byKey(const ValueKey('dislike-add')));
      await settle(tester);
      m = c.read(membersProvider).firstWhere((m) => m.id == 'm1');
      expect(m.dislikes, contains('baingan'));

      if (m0.diet != Diet.nonveg) expect(find.byKey(const ValueKey('nonveg-no_beef')), findsNothing);
      await c.read(membersProvider.notifier).setDiet('m1', Diet.nonveg);
      await settle(tester);
      expect(find.byKey(const ValueKey('nonveg-no_beef')), findsOneWidget);
      await c.read(membersProvider.notifier).setDiet('m1', Diet.pescatarian);
      expect(c.read(membersProvider).firstWhere((m) => m.id == 'm1').diet, Diet.pescatarian);
      expect(tester.takeException(), isNull);
    });

    testWidgets('remove member asks first, then archives', (tester) async {
      final c = await pumpBanega(tester, Routes.prefs('m1'), tall: true);
      final before = c.read(membersProvider).length;
      await tester.ensureVisible(find.byKey(const ValueKey('member-remove')));
      await tester.tap(find.byKey(const ValueKey('member-remove')));
      await settle(tester);
      expect(find.byKey(const ValueKey('member-remove-yes')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('member-remove-yes')));
      await settle(tester);
      expect(c.read(membersProvider), hasLength(before - 1));
      expect(c.read(membersProvider).any((m) => m.id == 'm1'), isFalse);
    });

    testWidgets('no members yet: Prefs does not crash', (tester) async {
      final a = RouteAdapter({
        'GET /v1/members': (_) => (200, {'items': <Object>[]}),
      });
      await pumpBanega(tester, Routes.prefs('nobody'), overrides: apiOverrides(a));
      expect(find.byType(PrefsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
