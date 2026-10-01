import 'dart:convert';
import 'dart:typed_data';

import 'package:banega/core/config.dart';
import 'package:banega/core/engine/fit_engine.dart';
import 'package:banega/core/l10n/gen/app_localizations_hi.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/data/data_source.dart';
import 'package:banega/data/demo/demo_members.dart';
import 'package:banega/features/chat/application/chat_controller.dart';
import 'package:banega/features/chat/data/api_chat_repository.dart';
import 'package:banega/features/chat/data/demo_chat_repository.dart';
import 'package:banega/features/chat/domain/chat_models.dart';
import 'package:banega/features/chat/presentation/chat_labels.dart';
import 'package:banega/features/chat/presentation/chat_screen.dart';
import 'package:banega/features/home/home_screen.dart';
import 'package:banega/features/menu/application/day_menu.dart';
import 'package:banega/features/recipe/domain/recipe.dart';
import 'package:banega/features/recipe/presentation/recipe_detail_screen.dart';
import 'package:banega/ui/ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart' show keyValueStoreProvider;
import 'package:banega/features/kitchen/data/ticket_cache.dart' show MemoryStore;
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Dio adapter keyed by `METHOD path`. Each key holds a queue of answers; the
/// last one repeats. [failWith] makes every request a transport error.
class ChatAdapter implements HttpClientAdapter {
  ChatAdapter(this.routes, {this.failWith});

  final Map<String, List<(int, Object?)>> routes;
  final DioExceptionType? failWith;
  final List<RequestOptions> requests = [];

  int count(String key) => requests.where((r) => '${r.method} ${r.path}' == key).length;

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
    final queue = routes['${options.method} ${options.path}'];
    final (status, body) = queue == null || queue.isEmpty
        ? (404, {'detail': 'not found'})
        : (queue.length > 1 ? queue.removeAt(0) : queue.first);
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

Dio chatDio(ChatAdapter a) => Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = a;

Map<String, Object?> apiCard(String id, String name, {String badge = 'fit'}) => {
  'id': id,
  'name': name,
  'cuisine': 'north_indian',
  'mins': 30,
  'colour': '#E8B73A',
  'diet': 'veg',
  'summary': {
    'badge': badge,
    'label_key': badge == 'no' ? 'some' : 'all_perfect',
    'label_params': badge == 'no' ? {'can': 4, 'total': 5} : <String, Object>{},
    'note_key': badge == 'no' ? 'nobody_for' : 'everyone_happy',
    'note_params': badge == 'no'
        ? {
            'names': ['Dadi'],
          }
        : <String, Object>{},
  },
};

Map<String, Object?> firstStep({Object? text}) => {
  'message_id': 'msg1',
  'cards': [apiCard('api-dal', 'API Dal'), apiCard('api-sabzi', 'API Sabzi', badge: 'no')],
  'slot': 'dinner',
  'chips': ['Aur kuch?', 'Kuch teekha'],
  'text': text,
};

const _post = 'POST /v1/chat/sessions';
const _msgs = 'POST /v1/chat/sessions/s1/messages';
const _poll = 'GET /v1/chat/messages/msg1';

void main() {
  final l = AppLocalizationsHiLatn();

  String rendered(ReplyText t) => l.replyText(t, memberCount: demoMembers.length);

  group('Chat screen (demo)', () {
    testWidgets('opens with the welcome and its four chips', (tester) async {
      await pumpBanega(tester, Routes.chat);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Maharaj'), findsOneWidget);
      expect(find.text('5 logon ki pasand yaad hai'), findsOneWidget);
      expect(
        find.text('Namaste! Main Maharaj hoon. Ghar ke 5 logon ki pasand mujhe yaad hai.\nBas pucho — aaj kya banaun?'),
        findsOneWidget,
      );
      for (final c in ['Aaj lunch mein kya?', 'Kuch halka dinner', '15 min mein nashta', 'Mehmaan aa rahe hain']) {
        expect(find.widgetWithText(BChip, c), findsOneWidget);
      }
      expect(find.text('Aaj dinner mein kuch halka…'), findsOneWidget);
      expect(find.textContaining('Menu ·'), findsNothing);
      expect(find.byType(TypingIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('send: user bubble, typing row, then the reply with cards and chips', (tester) async {
      final c = await pumpBanega(tester, Routes.chat);
      await tester.enterText(find.byType(TextField), 'Kuch halka dinner');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(find.text('Kuch halka dinner'), findsNWidgets(2)); // welcome chip + bubble
      expect(find.byType(TypingIndicator), findsOneWidget);
      expect(find.text('rotiyaan sek raha hoon…'), findsOneWidget);
      expect(c.read(chatControllerProvider).thinking, isTrue);

      // Still thinking just before the prototype's 1.3 s.
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byType(TypingIndicator), findsOneWidget);
      expect(find.byType(RecipeMiniCard), findsNothing);

      await tester.pump(const Duration(milliseconds: 150));
      await settle(tester);
      expect(find.byType(TypingIndicator), findsNothing);
      expect(c.read(chatControllerProvider).thinking, isFalse);

      final expected = demoReply('Kuch halka dinner', slot: Slot.lunch, members: demoMembers);
      expect(expected.slot, Slot.dinner);
      expect(find.text(rendered(expected.text)), findsOneWidget);
      expect(rendered(expected.text), startsWith('Dinner ke liye ${expected.top.length} options — halka.\n'));
      expect(find.byType(RecipeMiniCard), findsNWidgets(expected.top.length));
      expect(find.text(expected.top.first.$1.name), findsOneWidget);
      // Dinner follow-ups (green-outlined chips).
      expect(find.widgetWithText(BChip, 'Kuch halka'), findsOneWidget);
      expect(find.widgetWithText(BChip, 'Baarish special'), findsOneWidget);
      // Home's slot follows the reply.
      expect(c.read(slotProvider), Slot.dinner);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty input and a second send while thinking are ignored', (tester) async {
      final c = await pumpBanega(tester, Routes.chat);
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      expect(c.read(chatControllerProvider).messages, hasLength(1));

      await tester.tap(find.widgetWithText(BChip, 'Mehmaan aa rahe hain'));
      await tester.pump();
      await tester.tap(find.widgetWithText(BChip, 'Aaj lunch mein kya?'));
      await tester.pump();
      expect(c.read(chatControllerProvider).messages.where((m) => m.isMe), hasLength(1));
      await tester.pump(const Duration(milliseconds: 1400));
      await settle(tester);
      expect(c.read(chatControllerProvider).messages, hasLength(3));
    });

    testWidgets('ADD on a mini card updates the day menu and shows "Menu · n"', (tester) async {
      final c = await pumpBanega(tester, Routes.chatAsk('Kuch halka'));
      await tester.pump(const Duration(milliseconds: 1400));
      await settle(tester);
      expect(find.byType(RecipeMiniCard), findsWidgets);
      expect(find.textContaining('Menu ·'), findsNothing);

      final reply = c.read(chatControllerProvider).messages.last;
      await tester.tap(find.descendant(of: find.byType(RecipeMiniCard).first, matching: find.text('ADD')));
      await settle(tester);
      expect(c.read(activeMenuProvider).map((e) => e.id), [reply.cards.first.id]);
      expect(find.text('Menu · 1'), findsOneWidget);
      expect(find.descendant(of: find.byType(RecipeMiniCard).first, matching: find.text('ADDED')), findsOneWidget);

      final second = find.descendant(of: find.byType(RecipeMiniCard).at(1), matching: find.text('ADD'));
      await tester.ensureVisible(second);
      await settle(tester);
      await tester.tap(second);
      await settle(tester);
      expect(find.text('Menu · 2'), findsOneWidget);

      await tester.tap(find.text('Menu · 2'));
      await settle(tester);
      expect(find.text('Aaj ka Lunch menu'), findsOneWidget);
    });

    testWidgets('mini card opens Detail; back returns to the chat', (tester) async {
      final c = await pumpBanega(tester, Routes.chatAsk('Paneer wala kuch'));
      await tester.pump(const Duration(milliseconds: 1400));
      await settle(tester);
      final first = c.read(chatControllerProvider).messages.last.cards.first;
      await tester.tap(find.descendant(of: find.byType(RecipeMiniCard).first, matching: find.text(first.name)));
      await settle(tester);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      await tester.tap(find.byWidgetPredicate((w) => w is BIconButton && w.semanticLabel == 'Back'));
      await settle(tester);
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('follow-up chip sends that query', (tester) async {
      final c = await pumpBanega(tester, Routes.chatAsk('15 min mein nashta'));
      await tester.pump(const Duration(milliseconds: 1400));
      await settle(tester);
      expect(c.read(slotProvider), Slot.breakfast);
      await tester.tap(find.widgetWithText(BChip, 'Protein wala nashta'));
      await tester.pump(const Duration(milliseconds: 1400));
      await settle(tester);
      final msgs = c.read(chatControllerProvider).messages;
      expect(msgs.where((m) => m.isMe).map((m) => (m.text! as PlainText).text), [
        '15 min mein nashta',
        'Protein wala nashta',
      ]);
      final expected = demoReply('Protein wala nashta', slot: Slot.breakfast, members: demoMembers);
      expect(msgs.last.cards.map((c) => c.id), expected.top.map((t) => t.$1.id));
    });

    testWidgets('mic shows the voice toast', (tester) async {
      await pumpBanega(tester, Routes.chat);
      await tester.tap(find.bySemanticsLabel('Voice'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Voice input — real app mein Hinglish mein bol sakte ho'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('back goes Home', (tester) async {
      await pumpBanega(tester, Routes.home);
      await tester.tap(find.text('Maharaj se pucho'));
      await settle(tester);
      expect(find.byType(ChatScreen), findsOneWidget);
      await tester.tap(find.byWidgetPredicate((w) => w is BIconButton && w.semanticLabel == 'Back'));
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
    });
  });

  group('Home → Chat', () {
    testWidgets('quick-ask chip opens chat with the query sent', (tester) async {
      final c = await pumpBanega(tester, Routes.home);
      await tester.ensureVisible(find.widgetWithText(BChip, 'Baarish special', skipOffstage: false));
      await tester.pump();
      await tester.tap(find.widgetWithText(BChip, 'Baarish special'));
      await settle(tester);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Baarish special'), findsOneWidget); // the user bubble
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      final expected = demoReply('Baarish special', slot: Slot.lunch, members: demoMembers);
      expect(c.read(chatControllerProvider).messages.last.cards.map((c) => c.id), expected.top.map((t) => t.$1.id));
      expect(find.text(rendered(expected.text)), findsOneWidget);
    });

    testWidgets('ticker bar opens an empty chat', (tester) async {
      final c = await pumpBanega(tester, Routes.home);
      await tester.tap(find.byType(TickerSearchBar));
      await settle(tester);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(c.read(chatControllerProvider).messages, hasLength(1));
      expect(c.read(chatControllerProvider).thinking, isFalse);
    });
  });

  group('demoReply', () {
    test('no match falls back to the slot with the prototype text', () {
      final r = demoReply('chinese mehmaan', slot: Slot.lunch, members: demoMembers);
      expect(r.text, isA<NoMatchText>());
      expect(rendered(r.text), 'Is combo mein exact match nahi mila. Lunch ke liye ye sabse kareeb hain:');
      expect(r.top, hasLength(4));
      expect(r.top.every((t) => t.$1.slots.contains(Slot.lunch)), isTrue);
    });

    test('member name filters to what they can eat', () {
      final r = demoReply('Dadi ke liye kya?', slot: Slot.dinner, members: demoMembers);
      final dadi = demoMembers.firstWhere((m) => m.name == 'Dadi');
      expect(r.top.every((t) => fitFor(dadi, t.$1).kind != FitKind.no), isTrue);
      expect(rendered(r.text), contains('Dadi ke hisaab se'));
    });

    test('options text has the constraint line', () {
      final r = demoReply('High protein', slot: Slot.lunch, members: demoMembers);
      expect(
        rendered(r.text),
        endsWith(
          'mein poora parivaar kha sakta hai. Dhyaan rakha: Papa (low sugar) · Dadi (Jain) · Daughter (kam mirch).',
        ),
      );
      expect(l.chips(r.chips), ['Kuch halka', 'Baarish special', 'Paneer wala kuch', 'Dadi ke liye kya?']);
    });
  });

  group('ApiChatRepository', () {
    test('cards first, then the text fills in from polling', () async {
      final a = ChatAdapter({
        _post: [
          (200, {'session_id': 's1'}),
        ],
        _msgs: [(200, firstStep())],
        _poll: [
          (200, {'text': null}),
          (200, {'text': null}),
          (200, {'text': 'Aaj dinner mein dal banao.'}),
        ],
      });
      final api = ApiChatRepository(chatDio(a), pollInterval: const Duration(milliseconds: 5));
      final steps = await api.ask('dinner', slot: Slot.lunch, members: demoMembers).toList();

      expect(steps, hasLength(2));
      expect(steps.first.complete, isFalse);
      expect(steps.first.text, isNull);
      expect(steps.first.cards.map((c) => c.id), ['api-dal', 'api-sabzi']);
      expect(steps.first.slot, Slot.dinner);
      expect(steps.first.chips, ['Aur kuch?', 'Kuch teekha']);
      expect(steps.last.complete, isTrue);
      expect((steps.last.text! as PlainText).text, 'Aaj dinner mein dal banao.');
      expect(steps.last.cards, hasLength(2));
      expect(a.count(_poll), 3);
      final sent = a.requests.firstWhere((r) => r.path == '/v1/chat/sessions/s1/messages');
      expect(sent.data, {'text': 'dinner', 'slot': 'lunch'});
    });

    test('text in the first response completes at once', () async {
      final a = ChatAdapter({
        _post: [
          (200, {'session_id': 's1'}),
        ],
        _msgs: [(200, firstStep(text: 'Seedha jawab'))],
      });
      final steps = await ApiChatRepository(chatDio(a)).ask('x', slot: Slot.lunch, members: demoMembers).toList();
      expect(steps, hasLength(1));
      expect((steps.single.text! as PlainText).text, 'Seedha jawab');
      expect(a.count(_poll), 0);
    });

    test('polling gives up after the timeout and uses the template', () async {
      final a = ChatAdapter({
        _post: [
          (200, {'session_id': 's1'}),
        ],
        _msgs: [(200, firstStep())],
        _poll: [
          (200, {'text': null}),
        ],
      });
      final api = ApiChatRepository(
        chatDio(a),
        pollInterval: const Duration(milliseconds: 2),
        pollTimeout: const Duration(milliseconds: 24),
      );
      final steps = await api.ask('dinner', slot: Slot.lunch, members: demoMembers).toList();
      expect(a.count(_poll), 12);
      final t = steps.last.text! as OptionsText;
      expect(t.slot, Slot.dinner);
      expect(t.count, 2);
      expect(t.allOk, 1);
      expect(
        rendered(t),
        'Dinner ke liye 2 options.\n1 mein poora parivaar kha sakta hai. '
        'Dhyaan rakha: Papa (low sugar) · Dadi (Jain) · Daughter (kam mirch).',
      );
    });

    test('session is reused, and replaced after 30 idle minutes or a 404', () async {
      var now = DateTime(2026, 9, 26, 12);
      final a = ChatAdapter({
        _post: [
          (200, {'session_id': 's1'}),
          (200, {'session_id': 's2'}),
          (200, {'session_id': 's3'}),
        ],
        _msgs: [(200, firstStep(text: 'ok'))],
        'POST /v1/chat/sessions/s2/messages': [
          (200, firstStep(text: 'ok2')),
          (404, {'detail': 'session expired'}),
        ],
        'POST /v1/chat/sessions/s3/messages': [(200, firstStep(text: 'ok3'))],
        'GET /v1/chat/sessions/s3/messages': [
          (
            200,
            [
              {'role': 'user', 'text': 'x'},
              {
                'role': 'bot',
                'text': 'ok3',
                'cards': [apiCard('api-dal', 'API Dal')],
                'chips': ['Aur?'],
              },
            ],
          ),
        ],
      });
      final api = ApiChatRepository(chatDio(a), now: () => now);
      Future<String> ask() async =>
          ((await api.ask('x', slot: Slot.lunch, members: demoMembers).last).text! as PlainText).text;

      expect(await ask(), 'ok');
      now = now.add(const Duration(minutes: 29));
      expect(await ask(), 'ok');
      expect(a.count(_post), 1);
      expect(api.sessionId, 's1');

      now = now.add(const Duration(minutes: 31));
      expect(api.sessionId, isNull);
      expect(await ask(), 'ok2');
      expect(a.count(_post), 2);

      // s2 now answers 404 → a fresh session and one retry.
      expect(await ask(), 'ok3');
      expect(a.count(_post), 3);
      expect(api.sessionId, 's3');

      final history = await api.history();
      expect(history.map((m) => m.role), [ChatRole.me, ChatRole.bot]);
      expect(history.last.cards.single.name, 'API Dal');
      expect(history.last.chips, ['Aur?']);
    });

    test('providers: a connection error is an error reply (no demo cards); retry re-asks', () async {
      final adapter = ChatAdapter(const {}, failWith: DioExceptionType.connectionError);
      final c = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          dioProvider.overrideWithValue(chatDio(adapter)),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 26, 12)),
          demoChatRepositoryProvider.overrideWithValue(const DemoChatRepository(thinkTime: Duration.zero)),
        ],
      );
      addTearDown(c.dispose);
      c.listen(chatControllerProvider, (_, _) {});
      expect(c.read(chatRepositoryProvider), isA<ApiChatRepository>());
      await c.read(chatControllerProvider.notifier).send('Kuch halka');
      expect(c.read(dataSourceProvider), DataSource.api);
      var msgs = c.read(chatControllerProvider).messages;
      expect(msgs, hasLength(3));
      expect(msgs.last.text, isA<ErrorText>());
      expect(msgs.last.cards, isEmpty);

      final sent = adapter.requests.length;
      await c.read(chatControllerProvider.notifier).retry();
      msgs = c.read(chatControllerProvider).messages;
      expect(msgs, hasLength(3), reason: 'the failed pair is replaced, not duplicated');
      expect(adapter.requests.length, greaterThan(sent));
    });

    test('the chat POST waits 15 s (longer than plain reads)', () {
      expect(ApiChatRepository(chatDio(ChatAdapter(const {}))).receiveTimeout, const Duration(seconds: 15));
    });
  });

  group('Chat screen (API)', () {
    testWidgets('cards render first, the text fills in after', (tester) async {
      final a = ChatAdapter({
        _post: [
          (200, {'session_id': 's1'}),
        ],
        _msgs: [(200, firstStep())],
        _poll: [
          (200, {'text': null}),
          (200, {'text': 'Dal aur sabzi — dono sabke liye theek.'}),
        ],
      });
      final c = await pumpBanega(
        tester,
        Routes.chat,
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          dioProvider.overrideWithValue(chatDio(a)),
        ],
      );
      await tester.enterText(find.byType(TextField), 'dinner');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Step one: cards and chips, text still being written.
      expect(find.byType(RecipeMiniCard), findsNWidgets(2));
      expect(find.text('API Dal'), findsOneWidget);
      expect(find.byType(TypingIndicator), findsOneWidget);
      expect(find.widgetWithText(BChip, 'Kuch teekha'), findsOneWidget);
      expect(c.read(chatControllerProvider).messages.last.pending, isTrue);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(find.text('Dal aur sabzi — dono sabke liye theek.'), findsOneWidget);
      expect(find.byType(TypingIndicator), findsNothing);
      expect(c.read(chatControllerProvider).thinking, isFalse);
      expect(c.read(slotProvider), Slot.dinner);
      expect(a.count(_poll), 2);
    });
  });
}
