import 'package:banega/core/engine/fit_engine.dart';
import 'package:banega/core/l10n/gen/app_localizations_hi.dart';
import 'package:banega/data/demo/demo_members.dart';
import 'package:banega/data/demo/demo_recipes.dart';
import 'package:banega/data/models.dart';
import 'package:banega/features/members/domain/member.dart';
import 'package:banega/features/recipe/domain/recipe.dart';
import 'package:banega/labels/labels.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l = AppLocalizationsHiLatn();
  Member member(String name) => demoMembers.firstWhere((m) => m.name == name);
  final byId = {for (final r in demoRecipes) r.id: r};

  test('demo data matches the prototype counts', () {
    expect(demoMembers, hasLength(5));
    expect(demoRecipes, hasLength(22));
    expect(demoMemberPool.map((t) => t.name), ['Chachu', 'Bua', 'Nani', 'Ramesh bhaiya']);
  });

  test('fitFor follows the prototype rule order', () {
    expect(fitFor(member('Dadi'), byId['rajma']!).reason, FitReason.onionGarlic);
    expect(fitFor(member('Papa'), byId['omelette']!).reason, FitReason.egg);
    expect(fitFor(member('Daughter'), byId['chicken']!).reason, FitReason.nonveg);
    expect(fitFor(member('Papa'), byId['rajma']!).reason, FitReason.lowSugar);
    expect(fitFor(member('Wife'), byId['poha']!).reason, FitReason.extraChilli);
    expect(fitFor(member('Mummy'), byId['rajma']!).reason, FitReason.favCuisine);
    expect(fitFor(member('Wife'), byId['rajma']!).reason, FitReason.perfect);
    final noMaida = member('Daughter').toggleNeed(Need.noMaida);
    expect(fitFor(noMaida, byId['noodles']!).reason, FitReason.maida);
  });

  test('summary labels match the prototype strings', () {
    final rajma = summarize(demoMembers, byId['rajma']!);
    expect(l.fitLabel(rajma), '4/5 ke liye');
    expect(l.fitNote(rajma), 'Dadi ke liye nahi');

    final khichdi = summarize(demoMembers, byId['khichdi']!);
    expect(khichdi.kind, FitKind.tweak);
    expect(l.fitLabel(khichdi), 'Sabke liye · 1 tweak');
    expect(l.fitShort(khichdi), 'Sab · 1 tweak');
    expect(l.fitNote(khichdi), 'Wife: upar se laal mirch / achaar');
  });

  test('constraint line and family line', () {
    expect(l.constraintLineFor(demoMembers), 'Dhyaan rakha: Papa (low sugar) · Dadi (Jain) · Daughter (kam mirch)');
    expect(l.familyLineFor(demoMembers), '5 log · Papa (low sugar) · Dadi (Jain) · Daughter (kam mirch)');
    // Health needs are private unless the member opts in (F-5.3-05).
    final private = [for (final m in demoMembers) m.copyWith(showOnHome: false)];
    expect(l.constraintLineFor(private), 'Dhyaan rakha: Dadi (Jain)');
    expect(l.familyLineFor(private), '5 log · Dadi (Jain)');
    expect(l.constraintLineFor([member('Mummy')]), 'Sabki pasand dhyaan mein hai');
  });

  test('ranking puts full-family dishes first', () {
    final top = ranked(demoMembers, demoRecipes.where((r) => r.slots.isNotEmpty)).first;
    expect(top.$2.can, 5);
  });

  group('prototype parity', () {
    // Verbatim port of design/prototype_logic.js `fitFor`, kept as the
    // oracle: the extended engine must give the same verdict and reason for
    // every seed recipe × demo member.
    (String, String) prototypeFitFor(Member m, Recipe r) {
      if (m.diet == Diet.jain && !r.jain) return ('no', 'onion_garlic');
      if (m.diet == Diet.veg && r.diet != RecipeDiet.veg) {
        return ('no', r.diet == RecipeDiet.egg ? 'has_egg' : 'non_veg');
      }
      if (m.diet == Diet.egg && r.diet == RecipeDiet.nonveg) return ('no', 'non_veg');
      if (m.needs.contains(Need.noMaida) && r.tags.contains(RecipeTag.maida)) return ('no', 'maida');
      final tw = <String>[
        if (m.spice == Spice.kam && r.spice == 3) 'less_chilli_katori',
        if (m.spice == Spice.teekha && r.spice == 1) 'add_chilli',
        if (m.needs.contains(Need.lowSugar) && !r.tags.contains(RecipeTag.lowSugar)) 'small_portion_salad',
        if (m.needs.contains(Need.lowOil) && !r.tags.contains(RecipeTag.lowOil)) 'less_oil',
        if (m.needs.contains(Need.highProtein) && !r.tags.contains(RecipeTag.protein)) 'add_dahi_paneer',
        if (m.needs.contains(Need.kidFriendly) && !r.tags.contains(RecipeTag.kid) && r.spice > 1) 'kid_separate_mild',
      ];
      if (tw.isNotEmpty) return ('tweak', tw.first);
      return ('fit', m.cuisines.contains(r.cuisine) ? 'favourite_cuisine' : 'perfect');
    }

    test('all 22 × 5 seed verdicts match the prototype', () {
      for (final r in demoRecipes) {
        for (final m in demoMembers) {
          final f = fitFor(m, r, date: DateTime(2026, 9, 28)); // a Monday
          expect((f.kind.wire, f.reason.key), prototypeFitFor(m, r), reason: '${m.name} x ${r.id}');
        }
      }
    });

    test('the no-maida variant matches too', () {
      final ms = [for (final m in demoMembers) m.toggleNeed(Need.noMaida)];
      for (final r in demoRecipes) {
        for (final m in ms) {
          final f = fitFor(m, r);
          expect((f.kind.wire, f.reason.key), prototypeFitFor(m, r), reason: '${m.name} x ${r.id}');
        }
      }
    });
  });

  group('extended rules', () {
    final mummy = member('Mummy');
    final wife = member('Wife');

    test('allergen is a hard no with the allergen as param', () {
      final f = fitFor(mummy.copyWith(allergens: ['peanut']), byId['poha']!);
      expect((f.kind, f.reason), (FitKind.no, FitReason.allergen));
      expect(l.reason(f.reason, f.params), 'Moongphali se allergy');
      expect(fitFor(mummy.copyWith(allergens: ['tree_nut']), byId['pbm']!).reason, FitReason.allergen);
    });

    test('allergen outranks every other rule', () {
      final dadi = member('Dadi').copyWith(allergens: ['dairy']);
      expect(fitFor(dadi, byId['pbm']!).reason, FitReason.allergen);
    });

    test('dislikes: main ingredient -> no, minor -> tweak', () {
      final main = fitFor(mummy.copyWith(dislikes: ['rajma']), byId['rajma']!);
      expect((main.kind, main.reason), (FitKind.no, FitReason.dislikeMain));
      expect(l.reason(main.reason, main.params), 'Unko rajma pasand nahi');
      final minor = fitFor(wife.copyWith(dislikes: ['dhaniya']), byId['cheela']!);
      expect((minor.kind, minor.reason), (FitKind.tweak, FitReason.dislikeSkip));
      expect(l.reason(minor.reason, minor.params), 'Unki katori mein dhaniya mat daalo');
    });

    test('vrat day blocks non-vrat recipes only on that weekday', () {
      final fasting = mummy.copyWith(vratDays: {DateTime.monday});
      final monday = DateTime(2026, 9, 28);
      final tuesday = DateTime(2026, 9, 29);
      expect(fitFor(fasting, byId['rajma']!, date: monday).reason, FitReason.vrat);
      expect(fitFor(fasting, byId['rajma']!, date: tuesday).kind, isNot(FitKind.no));
      const sabudana = Recipe(
        id: 'sabudana',
        name: 'Sabudana Khichdi',
        sub: '',
        mins: 25,
        slots: {Slot.breakfast},
        diet: RecipeDiet.veg,
        jain: false,
        spice: 1,
        tags: {RecipeTag.protein},
        cuisine: Cuisine.maharashtrian,
        color: Color(0xFFEFE6C8),
        ingredients: ['Sabudana 1 cup', 'Moongphali'],
        steps: [],
        vratOk: true,
      );
      expect(fitFor(fasting, sabudana, date: monday).kind, isNot(FitKind.no));
      expect(l.reason(FitReason.vrat), 'Aaj vrat hai');
    });

    test('pescatarian eats fish and eggs, not chicken', () {
      final p = wife.copyWith(diet: Diet.pescatarian);
      expect(fitFor(p, byId['macher']!).kind, isNot(FitKind.no));
      expect(fitFor(p, byId['chicken']!).reason, FitReason.nonveg);
      expect(fitFor(p, byId['omelette']!).kind, isNot(FitKind.no));
    });

    test('non-veg exclusions', () {
      final f = fitFor(wife.copyWith(nonvegExclusions: ['chicken']), byId['chicken']!);
      expect((f.kind, f.reason), (FitKind.no, FitReason.nonveg));
      expect(l.reason(f.reason, f.params), 'Isme chicken hai');
      expect(fitFor(wife.copyWith(nonvegExclusions: ['chicken']), byId['macher']!).kind, isNot(FitKind.no));
    });

    test('no-onion-garlic diet', () {
      final nog = mummy.copyWith(diet: Diet.noOnionGarlic);
      expect(fitFor(nog, byId['rajma']!).reason, FitReason.onionGarlic);
      expect(fitFor(nog, byId['lauki']!).kind, isNot(FitKind.no));
      // Onion/garlic outranks egg (FRD H7 priority); still a No either way.
      expect(fitFor(nog, byId['omelette']!).kind, FitKind.no);
    });

    test('Jain + root veg reason when the recipe has no onion/garlic', () {
      const aloo = Recipe(
        id: 'jeera_aloo',
        name: 'Jeera Aloo',
        sub: '',
        mins: 20,
        slots: {Slot.lunch},
        diet: RecipeDiet.veg,
        jain: false,
        spice: 2,
        tags: {},
        cuisine: Cuisine.northIndian,
        color: Color(0xFFD9A441),
        ingredients: ['Aloo 4'],
        steps: [],
        onionGarlic: false,
        rootVeg: true,
      );
      expect(fitFor(member('Dadi'), aloo).reason, FitReason.rootVeg);
      expect(l.reason(FitReason.rootVeg), 'Zameen ke neeche ki sabzi hai');
    });

    test('no dairy', () {
      expect(fitFor(wife.copyWith(noDairy: true), byId['pbm']!).reason, FitReason.dairy);
      expect(fitFor(wife.copyWith(noDairy: true), byId['poha']!).kind, isNot(FitKind.no));
    });

    test('reason keys round-trip and cover the wire list', () {
      for (final r in FitReason.values) {
        expect(FitReason.fromKey(r.key), r);
      }
      const wire = [
        'allergen',
        'root_veg',
        'has_egg',
        'non_veg',
        'maida',
        'dislike_main',
        'dislike_skip',
        'vrat',
        'less_chilli_katori',
        'add_chilli',
        'small_portion_salad',
        'less_oil',
        'add_dahi_paneer',
        'kid_separate_mild',
        'favourite_cuisine',
        'perfect',
        'onion_garlic',
      ];
      for (final k in wire) {
        expect(FitReason.fromKey(k), isNotNull, reason: k);
        expect(l.reasonText(k, const {'item': 'x'}), isNot(k));
      }
      expect(l.reasonText('brand_new_key'), 'brand_new_key');
    });
  });

  group('home selection', () {
    test('lunch: pick excluded, 8 tiles, max 2 per dish category', () {
      final list = ranked(demoMembers, demoRecipes.where((r) => r.slots.contains(Slot.lunch)));
      final sel = homeSelection(list);
      expect(sel.pick.$1.id, list.first.$1.id);
      expect(sel.tiles, hasLength(8));
      expect(sel.tiles.map((t) => t.$1.id), isNot(contains(sel.pick.$1.id)));
      final perCat = <String, int>{};
      for (final (r, _) in sel.tiles) {
        perCat.update(r.dishCategory, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(perCat.values.every((n) => n <= 2), isTrue, reason: '$perCat');
    });

    test('small slots backfill instead of showing fewer tiles', () {
      final list = ranked(demoMembers, demoRecipes.where((r) => r.slots.contains(Slot.breakfast)));
      final sel = homeSelection(list);
      expect(sel.tiles, hasLength(list.length - 1));
    });
  });

  group('wire labels', () {
    test('summary labels from keys match the engine labels', () {
      for (final r in demoRecipes) {
        final s = summarize(demoMembers, r);
        final c = CardSummary.fromEngine(s);
        expect(l.summaryLabel(c), l.fitLabel(s));
        expect(l.summaryShort(c), l.fitShort(s));
      }
      final khichdi = CardSummary.fromEngine(summarize(demoMembers, byId['khichdi']!));
      expect(l.summaryNote(khichdi), 'Wife: upar se laal mirch / achaar');
      final rajma = CardSummary.fromEngine(summarize(demoMembers, byId['rajma']!));
      expect(l.summaryNote(rajma), 'Dadi ke liye nahi');
    });

    test('API-shaped keys resolve', () {
      const c = CardSummary(
        badge: FitKind.tweak,
        labelKey: 'all_with_tweaks',
        labelParams: {'count': 2},
        noteKey: 'less_oil',
        noteParams: {'name': 'Papa'},
      );
      expect(l.summaryLabel(c), 'Sabke liye · 2 tweak');
      expect(l.summaryShort(c), 'Sab · 2 tweak');
      expect(l.summaryNote(c), 'Papa: kam tel mein banao');
      const n = CardSummary(
        badge: FitKind.no,
        labelKey: 'some',
        labelParams: {'can': 3, 'total': 5},
        noteKey: 'nobody_for',
        noteParams: {
          'names': ['Dadi', 'Papa'],
        },
      );
      expect(l.summaryLabel(n), '3/5 ke liye');
      expect(l.summaryNote(n), 'Dadi, Papa ke liye nahi');
      const p = CardSummary(badge: FitKind.fit, labelKey: 'all_perfect', noteKey: 'everyone_happy');
      expect(l.summaryLabel(p), 'Sabke liye perfect');
      expect(l.summaryNote(p), 'Sab khush, koi badlaav nahi');
    });
  });
}
