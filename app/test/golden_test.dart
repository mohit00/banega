// Screen goldens at the prototype's 390×844 frame (reduce-motion, so looping
// art is still). Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden_test.dart
// Rendered with the bundled fonts on Windows; other platforms may differ by
// a few pixels of anti-aliasing (compare on the same OS).
import 'package:banega/core/router/router.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/features/menu/application/day_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Loads the bundled fonts so goldens show real text, not test blocks.
Future<void> _loadFonts() async {
  for (final (family, file) in const [
    ('Figtree', 'assets/fonts/Figtree.ttf'),
    ('BricolageGrotesque', 'assets/fonts/BricolageGrotesque.ttf'),
    ('NotoSansDevanagari', 'assets/fonts/NotoSansDevanagari.ttf'),
  ]) {
    final loader = FontLoader(family)..addFont(rootBundle.load(file));
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);
  final screens = <String, String>{
    'splash': Routes.splash,
    'home': Routes.home,
    'chat': Routes.chat,
    'detail': Routes.recipe('daltadka'),
    'plan': Routes.plan,
  };
  for (final e in screens.entries) {
    testWidgets('golden: ${e.key} at 390x844', (tester) async {
      final c = await pumpBanega(tester, Routes.home, reduceMotion: true);
      if (e.key == 'plan') {
        c.read(dayMenuProvider.notifier).toggle('daltadka', 'Dal Tadka');
        c.read(dayMenuProvider.notifier).toggle('lauki', 'Lauki Chana Dal');
      }
      if (e.value != Routes.home) c.read(routerProvider).go(e.value);
      await settle(tester);
      await expectLater(find.byType(WidgetsApp), matchesGoldenFile('goldens/${e.key}.png'));
    });
  }
}
