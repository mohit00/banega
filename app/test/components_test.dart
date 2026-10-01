import 'package:banega/core/engine/fit_engine.dart';
import 'package:banega/core/theme/tokens.dart';
import 'package:banega/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _tileData = RecipeCardData(
  name: 'Rajma Chawal',
  cuisine: 'North Indian',
  mins: 45,
  mark: DietMarkKind.veg,
  color: Color(0xFF8E3B2E),
  fitKind: FitKind.no,
  fitShort: '4/5 ke liye',
  note: 'Dadi ke liye nahi',
);

void main() {
  testWidgets('BCta is 52 high, full width, and shifts 3px when pressed', (tester) async {
    await pumpComponent(tester, BCta(label: 'Apna ghar set karo', trailing: BIcons.arrowRight, onPressed: () {}));
    final size = tester.getSize(find.byType(BCta));
    expect(size.height, BSizes.cta);
    expect(size.width, 390);

    final box = find.descendant(of: find.byType(BCta), matching: find.byType(AnimatedContainer));
    final restTop = tester.getTopLeft(find.text('Apna ghar set karo')).dy;
    final gesture = await tester.startGesture(tester.getCenter(box));
    // onTapDown fires after kPressTimeout; then the 120 ms press animation runs.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getTopLeft(find.text('Apna ghar set karo')).dy, closeTo(restTop + 3, .01));
    final deco = tester.widget<AnimatedContainer>(box).decoration! as BoxDecoration;
    expect(deco.boxShadow, BShadows.ctaPressed);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('RecipeTile layout matches the prototype', (tester) async {
    // Home grid: (390 - 2×16 - 10) / 2 = 174 px per tile.
    await pumpComponent(tester, const RecipeTile(data: _tileData, added: false), width: 174);
    final tile = find.byType(RecipeTile);
    expect(tester.getSize(tile).width, 174);
    expect(tester.takeException(), isNull);

    // Image area: 124 high, cream.
    final image = find.descendant(
      of: tile,
      matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == BColors.cream),
    );
    expect(tester.getSize(image).height, BSizes.tileImage);

    // Name block honours min-height 34.
    final name = find.text('Rajma Chawal');
    expect(name, findsOneWidget);
    expect(find.text('45 MIN'), findsOneWidget);
    expect(find.text('North Indian'), findsOneWidget);
    expect(find.text('4/5 ke liye'), findsOneWidget);

    // Diet mark 14×14, 8px from the image's top-left.
    final mark = find.byType(DietMark);
    expect(tester.getSize(mark), const Size(14, 14));
    expect(tester.getTopLeft(mark) - tester.getTopLeft(image), const Offset(8, 8));

    // ADD button 32 high, at least 68 wide.
    final add = tester.getSize(find.byType(BAddButton));
    expect(add.height, BSizes.add);
    expect(add.width, greaterThanOrEqualTo(BSizes.addMinWidth));
    expect(find.text('ADD'), findsOneWidget);

    // Total height = 124 image + 10 + max(34, name) + 4 + cuisine + 8 + 32 + 10 + 2 border.
    expect(tester.getSize(tile).height, greaterThanOrEqualTo(124 + 10 + 34 + 4 + 8 + 32 + 10 + 2));
  });

  testWidgets('RecipeMiniCard is 212 wide with a 112 image', (tester) async {
    await pumpComponent(
      tester,
      const Align(
        alignment: Alignment.topLeft,
        child: RecipeMiniCard(data: _tileData, added: true),
      ),
    );
    expect(tester.getSize(find.byType(RecipeMiniCard)).width, BSizes.miniWidth);
    final image = find.byWidgetPredicate((w) => w is ColoredBox && w.color == BColors.cream);
    expect(tester.getSize(image).height, BSizes.miniImage);
    expect(find.text('ADDED'), findsOneWidget);
    expect(find.text('Dadi ke liye nahi'), findsOneWidget);
  });

  testWidgets('small components have prototype sizes', (tester) async {
    await pumpComponent(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BAvatar(initial: 'P', color: Color(0xFF2F5FC4)),
          const StepNumber(1),
          const FitBadge(kind: FitKind.fit, label: 'Sabke liye'),
          BChip(label: 'Low oil', onTap: () {}),
          BSegmentControl<int>(
            value: 0,
            onChanged: (_) {},
            segments: const [BSegment(0, 'Nashta'), BSegment(1, 'Lunch'), BSegment(2, 'Dinner')],
          ),
        ],
      ),
    );
    expect(tester.getSize(find.byType(BAvatar)), const Size.square(BSizes.avatar));
    expect(tester.getSize(find.byType(StepNumber)), const Size.square(BSizes.stepNumber));
    expect(tester.getSize(find.byType(FitBadge)).height, BSizes.badge);
    expect(tester.getSize(find.byType(BChip)).height, BSizes.chip);
    expect(tester.getSize(find.byType(BSegmentControl<int>)).height, BSizes.seg + 8);
  });

  testWidgets('bottom nav bar is 68 high with a raised chef button', (tester) async {
    await pumpComponent(tester, BBottomNav(current: BNavTab.ghar, onTap: (_) {}));
    expect(tester.getSize(find.byType(BBottomNav)).height, BSizes.nav + BBottomNav.overhang);
    expect(tester.getSize(find.byType(ChefButton)), const Size.square(BSizes.chefButton));
    expect(find.text('Maharaj se pucho'), findsOneWidget);
  });

  testWidgets('typing indicator and ticker render', (tester) async {
    await pumpComponent(tester, const Column(children: [TypingIndicator(), TickerSearchBar()]));
    expect(find.text('rotiyaan sek raha hoon…'), findsOneWidget);
    expect(find.text('“15 min mein nashta”'), findsNWidgets(2)); // first line repeats at the end
    expect(tester.getSize(find.byType(TickerSearchBar)).height, BSizes.input);
  });

  test('every prototype icon path parses', () {
    for (final icon in [
      BIcons.arrowRight,
      BIcons.chevronRight,
      BIcons.chevronLeft,
      BIcons.chevronDown,
      BIcons.plus,
      BIcons.check,
      BIcons.search,
      BIcons.mic,
      BIcons.clock,
      BIcons.home,
      BIcons.chef,
      BIcons.users,
      BIcons.bowl,
    ]) {
      for (final d in icon.paths) {
        final b = parseSvgPath(d).getBounds();
        expect(b.left, greaterThanOrEqualTo(0), reason: d);
        expect(b.right, lessThanOrEqualTo(24), reason: d);
      }
    }
  });
}
