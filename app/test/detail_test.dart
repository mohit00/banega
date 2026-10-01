import 'package:banega/core/router/routes.dart';
import 'package:banega/features/home/home_screen.dart';
import 'package:banega/features/menu/application/day_menu.dart';
import 'package:banega/features/recipe/application/recipe_providers.dart';
import 'package:banega/features/recipe/presentation/recipe_detail_screen.dart';
import 'package:banega/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Finder badge(String label) => find.byWidgetPredicate((w) => w is FitBadge && w.label == label);

void main() {
  group('Recipe detail', () {
    testWidgets('renders prototype sections with per-member badges', (tester) async {
      await pumpBanega(tester, Routes.recipe('rajma'), tall: true);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      expect(find.text('Veg · North Indian · 45 min'), findsOneWidget);
      expect(find.text('Rajma Chawal'), findsOneWidget);
      expect(find.text('Sunday wala comfort food'), findsOneWidget);
      expect(badge('4/5 ke liye'), findsOneWidget);
      expect(find.byType(KenBurns), findsOneWidget);

      expect(find.text('Kaun khayega'), findsOneWidget);
      for (final n in ['Papa', 'Mummy', 'Dadi', 'Daughter', 'Wife']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(badge('Perfect'), findsNWidgets(3));
      expect(badge('Tweak'), findsOneWidget);
      expect(badge('Nahi'), findsOneWidget);
      expect(find.text('Pyaaz-lahsun hai'), findsOneWidget); // Dadi
      expect(find.text('Portion chhota, salad zyada'), findsOneWidget); // Papa
      expect(find.text('Favourite cuisine bhi'), findsOneWidget); // Mummy

      expect(find.text('Saaman'), findsOneWidget);
      expect(find.text('Kaise banega'), findsOneWidget);
      expect(find.text('Rajma 5-6 seeti tak pakao.'), findsOneWidget);
      expect(find.byType(StepNumber), findsNWidgets(4));
      expect(find.text('Video recipe'), findsOneWidget);
      expect(find.text('Menu mein daalo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Jain-safe recipes say Jain-friendly', (tester) async {
      await pumpBanega(tester, Routes.recipe('lauki'), tall: true);
      expect(find.text('Jain-friendly · North Indian · 35 min'), findsOneWidget);
    });

    testWidgets('servings stepper scales the Saaman text', (tester) async {
      await pumpBanega(tester, Routes.recipe('rajma'), tall: true);
      // Household default: 4 adults + 1 kid (0.5) → 5; recipe base is 4.
      expect(find.text('5 log'), findsOneWidget);
      expect(find.text('Rajma 1¼ cup (raat bhar bhiga)'), findsOneWidget);
      expect(find.text('Garam masala'), findsOneWidget);

      await tester.tap(find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == 'Zyada log'));
      await settle(tester);
      expect(find.text('6 log'), findsOneWidget);
      expect(find.text('Rajma 1½ cup (raat bhar bhiga)'), findsOneWidget);

      final less = find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == 'Kam log');
      await tester.tap(less);
      await tester.pump();
      await tester.tap(less);
      await settle(tester);
      expect(find.text('4 log'), findsOneWidget);
      expect(find.text('Rajma 1 cup (raat bhar bhiga)'), findsOneWidget);
    });

    testWidgets('sublinear salt/oil and batch warning', (tester) async {
      await pumpBanega(tester, Routes.recipe('upma'), tall: true);
      final more = find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == 'Zyada log');
      // 5 → 8 servings: base 4 doubles, so ghee goes ×1.5 while sooji goes ×2.
      for (var i = 0; i < 3; i++) {
        await tester.tap(more);
        await tester.pump();
      }
      await settle(tester);
      expect(find.text('8 log'), findsOneWidget);
      expect(find.text('Sooji 2 cup'), findsOneWidget);
      expect(find.text('Ghee 1½ tsp'), findsOneWidget);
      expect(find.text('Itne logon ke liye do batch mein pakao'), findsNothing);
      await tester.tap(more);
      await settle(tester);
      expect(find.text('Itne logon ke liye do batch mein pakao'), findsOneWidget);
    });

    testWidgets('Menu mein daalo toggles the day menu', (tester) async {
      final c = await pumpBanega(tester, Routes.recipe('poha'), tall: true);
      await tester.tap(find.text('Menu mein daalo'));
      await settle(tester);
      expect(find.text('Menu mein hai'), findsOneWidget);
      expect(c.read(activeMenuProvider).single.name, 'Kanda Poha');
      await tester.tap(find.text('Menu mein hai'));
      await settle(tester);
      expect(c.read(activeMenuProvider), isEmpty);
    });

    testWidgets('Video recipe opens a YouTube search', (tester) async {
      final opened = <Uri>[];
      await pumpBanega(
        tester,
        Routes.recipe('poha'),
        tall: true,
        overrides: [
          urlLauncherProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
      );
      await tester.tap(find.text('Video recipe'));
      await tester.pump();
      expect(opened.single.host, 'www.youtube.com');
      expect(opened.single.queryParameters['search_query'], 'Kanda Poha recipe');
    });

    testWidgets('back returns to the screen it came from', (tester) async {
      await pumpBanega(tester, Routes.home, tall: true);
      await tester.tap(find.byType(RecipeTile).first);
      await settle(tester);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      await tester.tap(find.byWidgetPredicate((w) => w is BIconButton && w.semanticLabel == 'Back'));
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(RecipeDetailScreen), findsNothing);
    });

    testWidgets('direct link back falls back to Home', (tester) async {
      await pumpBanega(tester, Routes.recipe('idli'));
      await tester.tap(find.byWidgetPredicate((w) => w is BIconButton && w.semanticLabel == 'Back'));
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('works with reduce-motion on', (tester) async {
      await pumpBanega(tester, Routes.recipe('chicken'), reduceMotion: true);
      expect(find.text('Chicken Curry'), findsOneWidget);
      expect(find.text('Non-veg · North Indian · 50 min'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
