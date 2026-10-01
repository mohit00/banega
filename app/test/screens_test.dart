import 'package:banega/core/router/routes.dart';
import 'package:banega/data/data_source.dart';
import 'package:banega/features/account/presentation/consent_screen.dart';
import 'package:banega/features/home/home_screen.dart';
import 'package:banega/features/home/loading_screen.dart';
import 'package:banega/features/members/application/members_controller.dart';
import 'package:banega/features/members/domain/member.dart';
import 'package:banega/features/members/presentation/family_screen.dart';
import 'package:banega/features/members/presentation/prefs_screen.dart';
import 'package:banega/features/onboarding/splash_screen.dart';
import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('Splash', () {
    testWidgets('renders prototype copy and goes to Family (via consent on first run)', (tester) async {
      await pumpBanega(tester, Routes.splash);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('AI MAHARAJ'), findsOneWidget);
      expect(find.text('Aaj khaane\nmein kya hai?'), findsOneWidget);
      expect(find.textContaining('Har ghar ka roz ka sawaal.'), findsOneWidget);
      expect(find.text('Apna ghar set karo'), findsOneWidget);
      expect(find.text('Demo family ke saath dekho'), findsOneWidget);

      await tester.tap(find.text('Apna ghar set karo'));
      await settle(tester);
      expect(find.byType(ConsentScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('consent-accept')));
      await settle(tester);
      expect(find.byType(FamilyScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('demo link enters the sandbox through consent, then Home', (tester) async {
      final c = await pumpBanega(tester, Routes.splash);
      await tester.tap(find.text('Demo family ke saath dekho'));
      await settle(tester);
      expect(find.byType(ConsentScreen), findsOneWidget);
      expect(c.read(sandboxProvider), isTrue);
      await tester.tap(find.byKey(const ValueKey('consent-accept')));
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('works with reduce-motion on', (tester) async {
      await pumpBanega(tester, Routes.splash, reduceMotion: true);
      expect(find.text('Apna ghar set karo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Family', () {
    testWidgets('lists the demo family with summaries', (tester) async {
      await pumpBanega(tester, Routes.family);
      expect(find.text('STEP 1 OF 2'), findsOneWidget);
      expect(find.text('Ghar mein kaun\nkaun hai?'), findsOneWidget);
      for (final n in ['Papa', 'Mummy', 'Dadi', 'Daughter', 'Wife']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.text('Medium mirch · Low sugar, Low oil · North Indian, Rajasthani'), findsOneWidget);
      expect(find.text('Non-veg'), findsOneWidget);
      expect(find.text('Member jodo'), findsOneWidget);
      expect(find.text('5 log · Aage badho'), findsOneWidget);
    });

    testWidgets('Member jodo adds Chachu and opens his prefs', (tester) async {
      final c = await pumpBanega(tester, Routes.family);
      await tester.ensureVisible(find.text('Member jodo'));
      await tester.pump();
      await tester.tap(find.text('Member jodo'));
      await settle(tester);
      // Name dialog: the POOL names are one-tap suggestions.
      expect(find.text('Naya member'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('member-suggest-Chachu')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('member-add-confirm')));
      await settle(tester);
      expect(find.byType(PrefsScreen), findsOneWidget);
      expect(find.text('Chachu ki pasand'), findsOneWidget);
      expect(c.read(membersProvider).length, 6);

      await tester.tap(find.text('Save · Chachu'));
      await settle(tester);
      expect(find.text('6 log · Aage badho'), findsOneWidget);
    });

    testWidgets('CTA goes to Loading', (tester) async {
      await pumpBanega(tester, Routes.family);
      await tester.tap(find.text('5 log · Aage badho'));
      await tester.pump(); // router processes the location change
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LoadingScreen), findsOneWidget);
      // Let the 1.9 s hold elapse so no timer is left pending.
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('Prefs', () {
    testWidgets('shows sections and edits update the provider', (tester) async {
      final c = await pumpBanega(tester, Routes.prefs('m1'));
      expect(find.text('STEP 2 OF 2 · PASAND'), findsOneWidget);
      expect(find.text('Papa ki pasand'), findsOneWidget);
      expect(find.text('Maharaj isi hisaab se suggest karega'), findsOneWidget);
      expect(find.text('Kya khaate hain?'), findsOneWidget);
      for (final t in ['Shakahari', 'Bina pyaaz-lahsun', 'Veg + ande', 'Sab kuch']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.text('Mirch kitni?'), findsOneWidget);
      for (final t in ['Kam', 'Medium', 'Teekha']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.text('Koi zaroorat ya parhez?'), findsOneWidget);
      expect(find.text('Save · Papa'), findsOneWidget);

      await tester.tap(find.text('Bina pyaaz-lahsun'));
      await tester.tap(find.text('Teekha'));
      await tester.pump();
      var papa = c.read(membersProvider).first;
      expect(papa.diet, Diet.jain);
      expect(papa.spice, Spice.teekha);

      await tester.ensureVisible(find.text('No maida'));
      await tester.pump();
      await tester.tap(find.text('No maida'));
      await tester.ensureVisible(find.text('Bengali'));
      await tester.pump();
      await tester.tap(find.text('Bengali'));
      await tester.pump();
      papa = c.read(membersProvider).first;
      expect(papa.needs, [Need.lowSugar, Need.lowOil, Need.noMaida]);
      expect(papa.cuisines, [Cuisine.northIndian, Cuisine.rajasthani, Cuisine.bengali]);
      expect(find.text('Favourite cuisine'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('member tabs switch the edited member', (tester) async {
      await pumpBanega(tester, Routes.prefs('m1'));
      await tester.tap(find.text('Dadi'));
      await tester.pump();
      expect(find.text('Dadi ki pasand'), findsOneWidget);
      expect(find.text('Save · Dadi'), findsOneWidget);
    });
  });

  group('Loading', () {
    testWidgets('shows the constraint line then lands on Home', (tester) async {
      await pumpBanega(tester, Routes.loading);
      expect(find.text('Maharaj aapke ghar\nko samajh raha hai…'), findsOneWidget);
      expect(find.text('Dhyaan rakha: Papa (low sugar) · Dadi (Jain) · Daughter (kam mirch)'), findsOneWidget);
      expect(find.byType(LoadBar), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('Home', () {
    testWidgets('renders header and nav', (tester) async {
      await pumpBanega(tester, Routes.home);
      expect(find.text('DOPAHAR KA KHAANA'), findsOneWidget);
      expect(find.text('Purohit Parivaar'), findsOneWidget);
      expect(find.text('5 log · Papa (low sugar) · Dadi (Jain) · Daughter (kam mirch)'), findsOneWidget);
      expect(find.text('Pucho '), findsOneWidget);
      expect(find.text('MAHARAJ KA PICK'), findsOneWidget);
      expect(find.text('Ghar'), findsOneWidget);
      expect(find.text('Maharaj se pucho'), findsOneWidget);
      expect(find.text('Parivaar'), findsOneWidget);

      await tester.tap(find.text('Dinner'));
      await tester.pump();
      expect(find.text('RAAT KA KHAANA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Parivaar tab opens Family', (tester) async {
      await pumpBanega(tester, Routes.home);
      await tester.tap(find.text('Parivaar'));
      await settle(tester);
      expect(find.byType(FamilyScreen), findsOneWidget);
    });
  });
}
