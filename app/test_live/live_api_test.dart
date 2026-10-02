// Live end-to-end check of the app's REAL data layer (Dio client, auth
// controller, Api* repositories, model parsers) against a running backend.
//
// Not part of the normal suite (lives outside test/). Run from app/:
//
//   flutter test test_live
//   BANEGA_LIVE_API=http://127.0.0.1:8765 flutter test test_live
//
// Every call goes through the app's providers; the raw JSON is only captured
// (RecordingInterceptor) as an oracle so a silent parse fallback (enum →
// unknown/default, null → 0, missing list → []) is caught.
//
// Data the run touches on the demo household, and how it is restored:
// - one member PATCH (dislikes) → restored to the original JSON;
// - TOMORROW's lunch menu + ticket (created, cooked, completed, rated);
//   cancelled instead if the run stops before completion;
// - stock levels changed by item-out / bought / the level test → every level
//   that differs from the snapshot taken at the start is put back;
// - one ration request (approved + bought), ticket thread messages, chat
//   session, inbox items marked read, ratings: not undoable through the API.
@Timeout(Duration(minutes: 12))
library;

import 'dart:io';

import 'package:banega/core/config.dart';
import 'package:banega/data/data_source.dart';
import 'package:banega/data/models.dart';
import 'package:banega/data/repositories.dart' show wireDate;
import 'package:banega/features/account/application/account_providers.dart';
import 'package:banega/features/account/domain/account_models.dart';
import 'package:banega/features/auth/application/auth_controller.dart';
import 'package:banega/features/auth/data/token_store.dart';
import 'package:banega/features/auth/domain/auth_models.dart';
import 'package:banega/features/chat/application/chat_controller.dart';
import 'package:banega/features/chat/domain/chat_models.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:banega/features/members/application/members_controller.dart';
import 'package:banega/features/members/domain/member.dart';
import 'package:banega/features/pantry/application/pantry_providers.dart';
import 'package:banega/features/pantry/domain/pantry_models.dart';
import 'package:banega/features/recipe/domain/recipe.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

// ------------------------------------------------------------------ config

final String baseUrl = Platform.environment['BANEGA_LIVE_API'] ?? 'http://127.0.0.1:8765';
const adminPhone = '+919999999999';
const cookPhone = '+919999999990';

/// Stable device ids (OTP limits are per device); override to dodge a lock.
final String adminDevice = Platform.environment['BANEGA_LIVE_ADMIN_DEVICE'] ?? 'live-test-admin-device';
final String cookDevice = Platform.environment['BANEGA_LIVE_COOK_DEVICE'] ?? 'live-test-cook-device';

void log(Object? m) => print('[live] $m'); // ignore: avoid_print

// ------------------------------------------------------------------ raw oracle

/// Records every response body by `METHOD path` (last one wins) so tests can
/// compare the parsed model with what the server actually sent.
class RecordingInterceptor extends Interceptor {
  final Map<String, Object?> last = {};
  final List<String> calls = [];

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final k = '${response.requestOptions.method} ${response.requestOptions.path}';
    last[k] = response.data;
    calls.add('$k -> ${response.statusCode}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final k = '${err.requestOptions.method} ${err.requestOptions.path}';
    last[k] = err.response?.data;
    calls.add('$k -> ${err.response?.statusCode ?? err.type}');
    handler.next(err);
  }

  Object? body(String method, String path) => last['$method $path'];

  Map<String, dynamic> map(String method, String path) =>
      ((body(method, path) ?? const {}) as Map).cast<String, dynamic>();

  List<Map<String, dynamic>> list(String method, String path) {
    final b = body(method, path);
    final l = b is List ? b : (b is Map ? (b['items'] as List? ?? const []) : const []);
    return [for (final x in l) (x as Map).cast<String, dynamic>()];
  }
}

// ------------------------------------------------------------------ soft checks

/// Collects every mismatch in a step, then fails once with all of them.
class Checks {
  Checks(this.step);
  final String step;
  final List<String> problems = [];
  final List<String> notes = [];

  void check(bool ok, String msg) {
    if (!ok) problems.add(msg);
  }

  void eq(Object? actual, Object? expected, String what) {
    if (!_same(actual, expected)) problems.add('$what: parsed=$actual, expected(raw)=$expected');
  }

  // Collections compare by content (a parsed List/Set is never identical to the raw one).
  static bool _same(Object? a, Object? b) => switch ((a, b)) {
    (final Set<Object?> x, final Set<Object?> y) => setEquals(x, y),
    (final List<Object?> x, final List<Object?> y) => listEquals(x, y),
    (final Map<Object?, Object?> x, final Map<Object?, Object?> y) => mapEquals(x, y),
    _ => a == b,
  };

  void note(String msg) {
    notes.add(msg);
    log('NOTE [$step] $msg');
  }

  void done() {
    for (final p in problems) {
      log('FAIL [$step] $p');
    }
    allProblems.addAll(problems.map((p) => '[$step] $p'));
    allNotes.addAll(notes.map((n) => '[$step] $n'));
    expect(problems, isEmpty, reason: '$step: ${problems.length} mismatch(es)');
  }
}

final allProblems = <String>[];
final allNotes = <String>[];

/// Logs an AppError with the TypeError stack when a parser threw.
String describe(Object e, [StackTrace? st]) {
  final b = StringBuffer('$e');
  if (e is UnknownError && e.cause is Error) {
    b.write('\n  cause: ${e.cause}\n  at: ${(e.cause as Error).stackTrace}');
  } else if (e is KitchenError) {
    b.write(' message=${e.message}');
  } else if (st != null) {
    b.write('\n$st');
  }
  return b.toString();
}

Future<T> step<T>(String what, Future<T> Function() f) async {
  try {
    return await f();
  } catch (e, st) {
    log('ERROR in $what: ${describe(e, st)}');
    rethrow;
  }
}

// ------------------------------------------------------------------ session

class Session {
  Session(this.container, this.rec, this.tokens);
  final ProviderContainer container;
  final RecordingInterceptor rec;
  final AuthTokens tokens;

  Dio get dio => container.read(dioProvider);
}

ProviderContainer _container(String deviceId) => ProviderContainer(
  overrides: [
    appConfigProvider.overrideWithValue(AppConfig(apiBaseUrl: baseUrl, connectTimeout: const Duration(seconds: 8))),
    tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
    keyValueStoreProvider.overrideWithValue(MemoryStore({'app.install_id': deviceId})),
    acceptLanguageProvider.overrideWithValue(() => 'en'),
  ],
);

/// Logs in through the app's AuthController with the dev OTP. Waits out the
/// 30 s resend window (a repeat request inside it carries no dev_code).
Future<Session> login(String phone, String deviceId) async {
  final c = _container(deviceId);
  final auth = c.read(authControllerProvider.notifier);
  await auth.ready();
  OtpChallenge? ch;
  for (var attempt = 1; attempt <= 5; attempt++) {
    try {
      ch = await auth.requestOtp(phone);
      if (ch.devCode != null) break;
      log('OTP for $phone: no dev_code (resend window), waiting ${ch.resendAfter + 2}s (attempt $attempt)');
      await Future<void>.delayed(Duration(seconds: ch.resendAfter + 2));
    } on AppError catch (e) {
      log('OTP for $phone failed: $e, waiting 32s (attempt $attempt)');
      await Future<void>.delayed(const Duration(seconds: 32));
    }
  }
  if (ch?.devCode == null) throw StateError('no dev_code for $phone (is the server ENV=dev?)');
  expect(ch!.expiresIn, greaterThan(0));
  final t = await auth.verify(phone, ch.devCode!);
  expect(t.accessToken, isNotEmpty);
  expect(t.refreshToken, isNotEmpty);
  expect(t.userId, isNotEmpty, reason: 'TokenPair.user_id');
  expect(c.read(authControllerProvider).signedIn, isTrue);
  final rec = RecordingInterceptor();
  c.read(dioProvider).interceptors.add(rec); // the signed-in client
  return Session(c, rec, t);
}

// ------------------------------------------------------------------ shared state

Session? admin;
Session? cook;
List<Member> members = [];
Me? adminMe;
String? hiredCookId;
String? gatteId; // optional ingredient (Dhaniya (optional)) + dahi (swap rule)
String? dalMakhaniId; // decimal qty (Namak 1.5 tsp)
String? thirdId;
Menu? menu;
Ticket? ticket;
Map<String, (ItemStatus, double?)> stockSnapshot = {};
final touchedStock = <String>{};
bool ticketCompleted = false;

String istDate(int addDays) {
  final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  return wireDate(DateTime(ist.year, ist.month, ist.day + addDays));
}

final String today = istDate(0);
// A fresh future date per run (2-49 days out), so a ticket completed by an earlier run
// (which the server rightly refuses to confirm again) never collides with this one.
final String tomorrow = istDate(2 + (DateTime.now().millisecondsSinceEpoch ~/ 60000) % 48);
const slot = 'lunch';
const uuid = Uuid();

Future<String?> findRecipe(Session s, String q, String slugWanted) async {
  final res = await s.dio.get<Object?>('/v1/recipes', queryParameters: {'q': q, 'limit': 20});
  final items = (res.data as Map)['items'] as List;
  for (final i in items) {
    final m = (i as Map).cast<String, dynamic>();
    if (m['slug'] == slugWanted) return '${m['id']}';
  }
  return items.isEmpty ? null : '${(items.first as Map)['id']}';
}

// ------------------------------------------------------------------ main

Future<bool> _reachable() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final req = await client.getUrl(Uri.parse('$baseUrl/v1/health'));
    final res = await req.close().timeout(const Duration(seconds: 4));
    await res.drain<void>();
    return res.statusCode < 500;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final up = await _reachable();
  if (!up) log('server $baseUrl unreachable: skipping all live tests');

  group('live API ($baseUrl)', skip: up ? false : 'server $baseUrl unreachable', () {
    tearDownAll(() async {
      await cleanup();
      log('==================== SUMMARY ====================');
      log('${allProblems.length} problem(s):');
      for (final p in allProblems) {
        log('  - $p');
      }
      log('${allNotes.length} note(s):');
      for (final n in allNotes) {
        log('  - $n');
      }
    });

    test('0 login admin + cook (AuthController, dev OTP)', () async {
      admin = await step('admin login', () => login(adminPhone, adminDevice));
      cook = await step('cook login', () => login(cookPhone, cookDevice));
    }, timeout: const Timeout(Duration(minutes: 6)));

    test('1 /me, members (+PATCH round trip), household settings', () async {
      final s = admin!;
      final c = Checks('1-me-members');

      final me = await step('me', () => s.container.read(cooksRepositoryProvider).me());
      adminMe = me;
      final raw = s.rec.map('GET', '/v1/me');
      c.check(me.hasHousehold, 'Me.householdId empty (membership.household_id=${(raw['membership'] as Map?)?['household_id']})');
      c.eq(me.userId, '${(raw['user'] as Map?)?['id']}', 'Me.userId');
      c.check(me.isAdmin, 'Me.isAdmin false for the admin');
      c.check(me.hasFamily, 'Me.modes lacks family: ${me.modes}');
      c.check(!me.cookOnly, 'admin parsed as cookOnly');
      c.eq(me.consentRequired, (raw['consent'] as Map?)?['required'] == true, 'Me.consentRequired');
      c.eq(me.consentVersion, (raw['consent'] as Map?)?['current_version'], 'Me.consentVersion');

      members = await step('members', () => s.container.read(membersRepositoryProvider).fetchMembers());
      final rawMembers = s.rec.list('GET', '/v1/members');
      c.eq(members.length, rawMembers.length, 'members count');
      c.check(members.length >= 5, 'expected >= 5 members, got ${members.length}');
      for (var i = 0; i < members.length && i < rawMembers.length; i++) {
        final m = members[i];
        final r = rawMembers[i];
        c.check(m.name.isNotEmpty, 'member $i name empty');
        c.eq(m.id, '${r['id']}', 'member $i id');
        c.eq(m.diet.wire, r['diet'], 'member ${m.name} diet');
        c.eq(m.spice.name, r['spice'], 'member ${m.name} spice');
        c.eq(m.isKid, r['is_kid'], 'member ${m.name} is_kid');
        c.eq(m.needs.length, (r['needs'] as List).length, 'member ${m.name} needs (unknown values dropped: ${r['needs']})');
        c.eq(m.cuisines.length, (r['cuisines'] as List).length, 'member ${m.name} cuisines (unknown dropped: ${r['cuisines']})');
        c.eq(m.allergens.length, (r['allergens'] as List).length, 'member ${m.name} allergens');
      }

      // PATCH round trip through the app's model (memberToJson / memberFromJson).
      final target = members.first;
      final before = Map<String, dynamic>.from(rawMembers.first);
      final marker = 'live-test-${DateTime.now().millisecondsSinceEpoch}';
      final repo = s.container.read(membersRepositoryProvider);
      try {
        final patched = await step('member patch', () => repo.updateMember(target.copyWith(dislikes: [...target.dislikes, marker])));
        c.check(patched.dislikes.contains(marker), 'PATCH response lacks the new dislike');
        c.eq(patched.name, target.name, 'patched name');
        c.eq(patched.diet, target.diet, 'patched diet');
        c.eq(patched.vratDays, target.vratDays, 'patched vrat_days');
      } finally {
        final restored = await step('member restore', () => repo.updateMember(target));
        c.check(!restored.dislikes.contains(marker), 'restore did not remove the marker');
        final after = (await s.dio.get<Object?>('/v1/members/${target.id}')).data as Map;
        for (final k in before.keys) {
          if (k == 'updated_at' || k == 'created_at' || k == 'version') continue;
          if ('${before[k]}' != '${after[k]}') {
            // The app saves chip keys ("low_sugar", "north_indian") where the seed stored
            // labels; the server engine reads both spellings, so that is a format note.
            if (k == 'needs' || k == 'cuisines') {
              c.note('member round trip rewrote "$k" as keys: ${before[k]} -> ${after[k]}');
            } else {
              c.check(false, 'member round trip changed "$k": ${before[k]} -> ${after[k]} (app model is lossy)');
            }
          }
        }
      }

      final hh = await step('household', () => s.container.read(accountRepositoryProvider).household());
      final rawH = s.rec.map('GET', '/v1/households/me');
      final h = (rawH['household'] is Map ? rawH['household'] as Map : rawH).cast<String, dynamic>();
      c.eq(hh.id, '${h['id']}', 'household id');
      c.eq(hh.name, h['name'], 'household name');
      c.check(hh.name.contains('Purohit'), 'household name ${hh.name}');
      c.eq(hh.timezone, h['timezone'] ?? 'Asia/Kolkata', 'household timezone');
      for (final (k, v) in [
        ('cook_can_approve_swaps', hh.cookCanApproveSwaps),
        ('show_names_to_cook', hh.showNamesToCook),
        ('ratings_enabled', hh.ratingsEnabled),
        ('auto_decrement', hh.autoDecrement),
      ]) {
        if (!h.containsKey(k)) {
          c.check(false, 'household.$k missing on the wire (app falls back to $v)');
        } else {
          c.eq(v, h[k], 'household.$k');
        }
      }
      c.done();
    });

    test('2 recommendations, recipe detail (optional + decimal), scaling', () async {
      final s = admin!;
      final c = Checks('2-recs-recipes');
      final repo = s.container.read(dataRepositoryProvider);
      for (final sl in Slot.values) {
        final r = await step('recs $sl', () => repo.recommendations(slot: sl, date: DateTime.now(), members: members));
        final raw = s.rec.map('GET', '/v1/recommendations');
        c.check(r.pick.id.isNotEmpty && r.pick.id != 'null', '$sl pick id empty');
        c.check(r.pick.name.isNotEmpty, '$sl pick name empty');
        c.check(r.pick.mins > 0, '$sl pick mins 0');
        c.check(r.pick.cuisine.isNotEmpty, '$sl pick cuisine empty');
        c.check(r.pick.summary.labelKey.isNotEmpty, '$sl pick summary.label_key empty');
        c.check(r.tiles.isNotEmpty, '$sl tiles empty');
        final rawPick = (raw['pick'] as Map).cast<String, dynamic>();
        final rawCard = (rawPick['recipe'] ?? rawPick) as Map;
        final rawSummary = (rawPick['summary'] ?? rawCard['summary']) as Map;
        c.eq(r.pick.summary.badge.wire, rawSummary['badge'], '$sl pick badge');
        c.eq(r.pick.diet.name == 'nonveg' ? 'non_veg' : r.pick.diet.name, rawCard['diet'] ?? rawCard['mark'], '$sl pick diet/mark');
        for (final t in r.tiles) {
          c.check(t.name.isNotEmpty && t.id != 'null', '$sl tile name/id empty');
        }
        final cl = raw['constraint_line'];
        if (cl is Map) c.eq(r.constraintKey, cl['key'], '$sl constraint_line.key');
        if (thirdId == null && r.tiles.isNotEmpty && sl == Slot.lunch) thirdId = r.tiles.first.id;
      }

      gatteId = await findRecipe(s, 'Gatte', 'gatte-ki-sabzi');
      dalMakhaniId = await findRecipe(s, 'Dal Makhani', 'dal-makhani');
      c.check(gatteId != null && dalMakhaniId != null, 'could not find gatte-ki-sabzi / dal-makhani');

      for (final id in [gatteId, dalMakhaniId, thirdId].whereType<String>()) {
        final d = await step('recipe $id', () => repo.recipe(id, members: members));
        final raw = s.rec.map('GET', '/v1/recipes/$id');
        c.eq(d.id, raw['id'], 'recipe id');
        c.check(d.name.isNotEmpty, 'recipe $id name empty');
        c.check(d.steps.isNotEmpty, '${d.name}: steps empty (raw keys: steps=${raw['steps'] != null}, steps_en=${raw['steps_en'] != null})');
        c.check(d.ingredients.isNotEmpty, '${d.name}: ingredients empty');
        c.eq(d.baseServings, raw['base_servings'], '${d.name} base_servings');
        c.eq(d.servings, raw['servings'], '${d.name} servings');
        c.eq(d.mins, raw['mins'], '${d.name} mins');
        c.eq(d.summary.badge.wire, (raw['summary'] as Map?)?['badge'], '${d.name} summary.badge');
        c.eq(d.jainSafe, (raw['flags'] as Map?)?['jain_safe'] ?? raw['jain_safe'], '${d.name} jain_safe');
        c.eq(d.fits.length, (raw['fits'] as List).length, '${d.name} fits');
        for (final f in d.fits) {
          c.check(f.memberId.isNotEmpty && f.memberId != 'null', '${d.name} fit memberId empty');
          c.check(f.name.isNotEmpty, '${d.name} fit name empty');
        }
        for (final rf in (raw['fits'] as List)) {
          final st = (rf as Map)['status'];
          c.check(['fit', 'tweak', 'no'].contains(st) || st == 'perfect', '${d.name} unknown fit status "$st" (app maps it to no)');
        }
        final rawIngs = [for (final i in raw['ingredients'] as List) (i as Map).cast<String, dynamic>()];
        for (final ri in rawIngs) {
          final line = d.ingredients.where((l) => l.displayText == ri['display_text']).firstOrNull;
          c.check(line != null, '${d.name}: ingredient "${ri['display_text']}" missing after parse');
          if (line == null) continue;
          final q = wireDouble(ri['qty']);
          c.eq(line.qty, q, '${d.name} "${ri['display_text']}" qty (raw ${ri['qty']} ${ri['qty'].runtimeType})');
          if (ri['qty'] != null && q == null) c.check(false, 'qty "${ri['qty']}" not parseable');
        }
        if (id == dalMakhaniId) {
          final dec = rawIngs.where((i) {
            final q = wireDouble(i['qty']);
            return q != null && q != q.roundToDouble();
          }).toList();
          c.check(dec.isNotEmpty, 'dal makhani: no decimal qty on the wire');
          for (final i in dec) {
            final line = d.ingredients.firstWhere((l) => l.displayText == i['display_text']);
            c.check(line.qty != null && (line.qty! - wireDouble(i['qty'])!).abs() < 1e-9, 'decimal qty ${i['qty']} -> ${line.qty}');
          }
          c.note('decimal qty wire type: ${dec.map((i) => '${i['qty']} (${i['qty'].runtimeType})').join(', ')}');
        }
        if (id == gatteId) {
          final opt = rawIngs.where((i) => i['optional'] == true).toList();
          c.check(opt.isNotEmpty, 'gatte: server sends no optional=true ingredient');
          c.note('optional ingredients on the wire: ${opt.map((i) => i['display_text']).toList()}; '
              'IngredientLine has no `optional` / `ingredient_id` field, so the app cannot mark them');
        }
      }

      // Scaling: double the servings.
      final base = await repo.recipe(dalMakhaniId!, members: members);
      final want = base.baseServings * 2;
      final scaled = await step('scaled', () => repo.recipe(dalMakhaniId!, servings: want, members: members));
      final raw = s.rec.map('GET', '/v1/recipes/$dalMakhaniId');
      c.eq(scaled.servings, want, 'scaled servings');
      final rawIngs = [for (final i in raw['ingredients'] as List) (i as Map).cast<String, dynamic>()];
      var changed = 0;
      for (final ri in rawIngs) {
        final sq = wireDouble(ri['scaled_qty']);
        final q = wireDouble(ri['qty']);
        if (sq == null || q == null || (sq - q).abs() < 1e-9) continue;
        final line = scaled.ingredients.firstWhere((l) => l.displayText == ri['display_text']);
        if (line.scaledText != line.displayText) changed++;
        c.check(line.scaledText.contains(formatQty(sq)) || line.scaledText == ri['scaled_text'],
            'scaled "${ri['display_text']}" ${ri['qty']}→${ri['scaled_qty']} shown as "${line.scaledText}"');
      }
      c.check(changed > 0, 'no ingredient line changed after scaling x2');
      c.done();
    });

    test('3 chat: session + 2 messages (+ two-step text)', () async {
      final s = admin!;
      final c = Checks('3-chat');
      final chat = s.container.read(apiChatRepositoryProvider);
      for (final (text, sl) in [('Aaj lunch mein kuch halka batao', Slot.lunch), ('Paneer wala kuch dinner ke liye?', Slot.dinner)]) {
        final replies = await step('chat "$text"', () => chat.ask(text, slot: sl, members: members).toList());
        c.check(replies.isNotEmpty, 'no reply for "$text"');
        final last = replies.last;
        c.check(last.complete, '"$text": last reply not complete');
        c.check(last.cards.isNotEmpty, '"$text": no cards');
        for (final card in last.cards) {
          c.check(card.name.isNotEmpty && card.id != 'null', '"$text": card name/id empty');
          c.check(card.summary.labelKey.isNotEmpty, '"$text": card ${card.name} summary.label_key empty');
        }
        final rawPost = s.rec.last.entries.where((e) => e.key.startsWith('POST /v1/chat/sessions/') && e.key.endsWith('/messages')).lastOrNull?.value;
        if (rawPost is Map) {
          c.eq(last.cards.length, (rawPost['cards'] as List?)?.length, '"$text" cards count');
          for (var i = 0; i < last.cards.length && i < (rawPost['cards'] as List).length; i++) {
            final rc = ((rawPost['cards'] as List)[i] as Map).cast<String, dynamic>();
            final card = (rc['recipe'] ?? rc) as Map;
            final summ = (rc['summary'] ?? card['summary']) as Map?;
            c.eq(last.cards[i].summary.badge.wire, summ?['badge'], '"$text" card $i badge');
          }
          if (rawPost['text'] == null) c.note('"$text": text null inline → two-step fill used (${replies.length} yields)');
        }
        final t = last.text;
        if (t is PlainText) {
          c.check(t.text.trim().isNotEmpty, '"$text": empty text');
        } else {
          c.check(false, '"$text": text fell back to local template ${t.runtimeType} (server text never arrived)');
        }
        c.check(last.slot != null, '"$text": reply slot null');
      }
      final history = await step('chat history', () => chat.history());
      c.check(history.length >= 4, 'history has ${history.length} messages, expected >= 4');
      c.check(history.any((m) => m.isMe) && history.any((m) => !m.isMe), 'history roles not parsed (all one role)');
      final rawHist = s.rec.last.entries.where((e) => e.key.startsWith('GET /v1/chat/sessions/')).lastOrNull?.value;
      final rh = rawHist is List ? rawHist : (rawHist is Map ? rawHist['items'] as List? ?? const [] : const []);
      c.note('history senders on the wire: ${rh.map((m) => (m as Map)['author'] ?? (m)['role']).toSet()}');
      c.done();
    });

    test('4 day menu for TOMORROW → confirm → ticket, share text', () async {
      final s = admin!;
      final c = Checks('4-menu');
      final menus = s.container.read(menusRepositoryProvider);
      final tickets = s.container.read(ticketsRepositoryProvider);

      // Stock snapshot (restored in cleanup).
      final stock = await step('stock snapshot', () => s.container.read(stockRepositoryProvider).stock());
      stockSnapshot = {for (final i in stock) i.ingredientId: (i.level, i.qty)};

      final cooks = await step('cooks', () => s.container.read(cooksRepositoryProvider).cooks());
      hiredCookId = cooks.where((k) => k.kind == CookKind.hired).firstOrNull?.id;
      c.check(hiredCookId != null, 'no hired cook in /v1/cooks');

      // Residue from an earlier run: cancel tomorrow's open lunch ticket.
      final existing = await step('menu tomorrow', () => menus.menu(tomorrow, slot));
      if (existing?.ticketId != null) {
        final t = await tickets.ticket(existing!.ticketId!);
        if (t.status.isOpen) {
          log('cancelling leftover ticket ${t.id} (${t.status.wire})');
          await tickets.transition(t.id, TicketStatus.cancelled, version: t.version, idempotencyKey: uuid.v4(), reason: 'live test cleanup');
        }
      }

      var m = await step('put dishes', () => menus.putDishes(tomorrow, slot, [gatteId!, dalMakhaniId!]));
      final rawPut = s.rec.map('PUT', '/v1/menus/$tomorrow/$slot/dishes');
      c.eq(m.id, '${rawPut['id']}', 'menu id');
      c.eq(m.date, tomorrow, 'menu date');
      c.eq(m.slot, slot, 'menu slot');
      c.eq(m.dishes.map((d) => d.recipeId).toList(), [gatteId, dalMakhaniId], 'menu dishes');
      for (final d in m.dishes) {
        c.check(d.name.isNotEmpty, 'dish name empty');
        c.check(d.mins > 0, 'dish ${d.name} mins 0');
      }
      c.check(m.eaters.isNotEmpty, 'menu eaters empty');
      for (final e in m.eaters) {
        c.check(e.name.isNotEmpty && e.memberId != 'null', 'eater name/id empty');
      }
      c.check(m.version > 0, 'menu version ${m.version}');
      c.eq(m.servings, (rawPut['servings'] as num?)?.toDouble() ?? double.tryParse('${rawPut['servings']}'), 'menu servings');
      c.check(m.requiredItems.isNotEmpty, 'menu required_items empty');
      final rawReq = [for (final i in rawPut['required_items'] as List? ?? const []) (i as Map).cast<String, dynamic>()];
      for (var i = 0; i < m.requiredItems.length && i < rawReq.length; i++) {
        c.eq(m.requiredItems[i].status.wire, rawReq[i]['status'], 'required_items[$i].status');
        c.check(m.requiredItems[i].displayText.isNotEmpty, 'required_items[$i] display_text empty');
      }
      c.eq(m.coverage.allCovered, (rawPut['coverage'] as Map?)?['all_covered'], 'coverage.all_covered');
      if (m.assignee != null) {
        c.check(m.assignee!.name.isNotEmpty, 'menu assignee name empty');
        c.eq(m.assignee!.kind.name, (rawPut['assignee'] as Map)['kind'], 'assignee kind');
      } else {
        c.note('menu has no pre-filled assignee');
      }

      final eaterIds = [for (final e in m.eaters) e.memberId];
      final keep = eaterIds.length > 1 ? eaterIds.sublist(0, eaterIds.length - 1) : eaterIds;
      final dueLocal = DateTime.parse('${tomorrow}T13:15:00+05:30');
      m = await step('patch menu', () => menus.patchMenu(m.id, MenuPatch(
            eaters: keep,
            guests: const Guests(adults: 1, kids: 1, diet: GuestDiet.veg),
            dueAt: dueLocal,
            assigneeCookId: hiredCookId,
            assigneeSet: true,
          )));
      c.eq(m.eaters.length, keep.length, 'patched eaters count');
      c.eq(m.guests, const Guests(adults: 1, kids: 1, diet: GuestDiet.veg), 'patched guests');
      c.check(m.dueAt != null && m.dueAt!.isAtSameMomentAs(dueLocal), 'patched due_at ${m.dueAt} != $dueLocal');
      c.eq(m.assignee?.cookId, hiredCookId, 'patched assignee');
      c.eq(m.assignee?.kind, CookKind.hired, 'patched assignee kind');
      c.check(m.servings > 0, 'patched servings ${m.servings}');
      menu = m;

      final res = await step('confirm', () => menus.confirm(m.id, version: m.version, idempotencyKey: uuid.v4()));
      final t = res.ticket;
      c.check(t.id.isNotEmpty && t.id != 'null', 'ticket id empty');
      c.eq(t.status, TicketStatus.fresh, 'confirmed ticket status (raw ${s.rec.map('POST', '/v1/menus/${m.id}/confirm')['ticket']?['status']})');
      c.eq(t.menuId, m.id, 'ticket menu_id');
      c.eq(t.date, tomorrow, 'ticket date');
      c.eq(t.dishes.length, 2, 'ticket dishes');
      c.eq(t.assignee?.cookId, hiredCookId, 'ticket assignee');
      c.check(t.version > 0, 'ticket version');
      c.check(t.dueAt != null && t.dueAt!.isAtSameMomentAs(dueLocal), 'ticket due_at ${t.dueAt}');
      c.check(res.shareText.trim().isNotEmpty, 'confirm share_text empty');
      c.check(t.requiredItems.isNotEmpty, 'ticket required_items empty');

      final again = await step('get ticket', () => tickets.ticket(t.id));
      final rawT = s.rec.map('GET', '/v1/tickets/${t.id}');
      c.eq(again.status.wire, rawT['status'], 'GET ticket status');
      c.eq(again.version, rawT['version'], 'GET ticket version');
      c.eq(again.eaters.length, (rawT['eaters'] as List).length, 'GET ticket eaters');
      c.eq(again.guests.adults, 1, 'GET ticket guests.adults');
      c.eq(again.changeLog.length, (rawT['change_log'] as List?)?.length ?? 0, 'GET ticket change_log');
      for (final e in again.changeLog) {
        c.check(e.action.isNotEmpty && e.at != null, 'change_log entry action/at empty');
      }
      if (rawT.containsKey('stock_issues')) c.note('ticket carries `stock_issues` (list); app reads only `stock_issue` (object)');
      ticket = again;

      final share = await step('share text', () => menus.shareText(m.id));
      c.check(share.trim().isNotEmpty, 'share-text empty');
      c.check(share.contains('Gatte') || share.contains('Dal'), 'share-text lacks dish names: $share');
      c.done();
    });

    test('5 cook flow (hired cook): me, mine, transitions, item out ladder, thread', () async {
      final s = cook!;
      final c = Checks('5-cook');
      final tickets = s.container.read(ticketsRepositoryProvider);
      final me = await step('cook me', () => s.container.read(cooksRepositoryProvider).me());
      final rawMe = s.rec.map('GET', '/v1/me');
      c.check(me.canCook, 'cook Me.canCook false (modes ${me.modes}, cook ${rawMe['cook']})');
      c.check(me.cookOnly, 'hired cook not cookOnly (modes ${me.modes})');
      c.eq(me.cook?.kind, CookKind.hired, 'Me.cook.kind');
      c.eq(me.cook?.id, hiredCookId, 'Me.cook.id');
      final rc = rawMe['cook'];
      if (rc is Map && rc.containsKey('on_duty')) {
        c.note('/me.cook.on_duty=${rc['on_duty']} off_duty_until=${rc['off_duty_until']} on the wire; MeCook does not parse them');
      }

      final mine = await step('mine', () => tickets.tickets(date: tomorrow, mine: true));
      c.check(mine.any((t) => t.id == ticket!.id), 'tomorrow mine=true lacks our ticket');
      for (final t in mine) {
        c.check(t.status != TicketStatus.unknown, 'ticket ${t.id} status unknown');
        c.check(t.dishes.every((d) => d.name.isNotEmpty), 'ticket ${t.id} dish name empty');
      }
      final hiredView = mine.firstWhere((t) => t.id == ticket!.id);
      c.note('hired cook sees eaters=${hiredView.eaters.map((e) => e.name).toList()}');

      var t = await tickets.ticket(ticket!.id);
      // Illegal: new → cooking.
      try {
        await tickets.transition(t.id, TicketStatus.cooking, version: t.version, idempotencyKey: uuid.v4());
        c.check(false, 'new→cooking accepted (expected 409)');
      } on KitchenError catch (e) {
        c.eq(e.status, 409, 'illegal transition status');
        c.eq(e.code, KitchenError.invalidTransition, 'illegal transition code');
        c.check(e.allowed.contains(TicketStatus.accepted), 'allowed ${e.allowed.map((a) => a.wire)} lacks accepted');
        c.check(!e.allowed.contains(TicketStatus.unknown), 'allowed has unknown: ${s.rec.body('POST', '/v1/tickets/${t.id}/transitions')}');
      }
      t = await step('accept', () => tickets.transition(t.id, TicketStatus.accepted, version: t.version, idempotencyKey: uuid.v4()));
      c.eq(t.status, TicketStatus.accepted, 'after accept');
      c.check(t.acceptedAt != null, 'accepted_at null');
      t = await step('cooking', () => tickets.transition(t.id, TicketStatus.cooking, version: t.version, idempotencyKey: uuid.v4()));
      c.eq(t.status, TicketStatus.cooking, 'after cooking');
      c.check(t.startedAt != null, 'started_at null');

      // Cook-mode recipe.
      final cr = await step('cook recipe', () => tickets.recipe(t.id, gatteId!, servings: t.servingsInt));
      c.check(cr.detail.name.isNotEmpty && cr.detail.steps.isNotEmpty, 'cook recipe name/steps empty');
      c.eq(cr.detail.servings, t.servingsInt, 'cook recipe servings');
      c.eq(cr.audioStepsHi.length, ((s.rec.map('GET', '/v1/tickets/${t.id}/recipes/$gatteId')['audio'] as Map?)?['steps_hi'] as List?)?.length, 'audio.steps_hi');

      // Item out: optional Dhaniya → save_dish skip; Dahi → swap.
      RequiredItem? item(String word) =>
          t.requiredItems.where((i) => i.displayText.toLowerCase().contains(word)).firstOrNull;
      // required_items are named in English and leave out optional lines ("Dhaniya (optional)").
      final dhaniya = item('coriander') ?? item('dhaniya');
      final dahi = item('curd') ?? item('dahi');
      if (dhaniya == null) {
        c.note('optional Dhaniya is not in required_items (by design): ${t.requiredItems.map((i) => i.displayText).toList()}');
      }
      c.check(dahi != null, 'required_items lacks Curd/Dahi: ${t.requiredItems.map((i) => i.displayText).toList()}');

      Future<void> outAndResolve(RequiredItem it, {required bool expectSkip}) async {
        touchedStock.add(it.ingredientId);
        final r = await step('item out ${it.displayText}', () => tickets.markItemOut(t.id, it.ingredientId, idempotencyKey: uuid.v4()));
        final raw = s.rec.map('POST', '/v1/tickets/${t.id}/items/${it.ingredientId}/out');
        final rl = (raw['ladder'] as Map?)?.cast<String, dynamic>();
        log('ladder raw for ${it.displayText}: $rl');
        c.check(r.stockIssueOpen, '${it.displayText}: stock_issue_open false after out');
        final l = r.ladder;
        c.check(l != null, '${it.displayText}: ladder not parsed');
        if (l == null || rl == null) return;
        c.eq(l.step.wire, rl['step'], '${it.displayText} ladder.step');
        c.eq(l.ingredientId, it.ingredientId, '${it.displayText} ladder.ingredient_id');
        c.check(l.ingredientName.isNotEmpty, '${it.displayText} ladder ingredient name empty');
        final opts = (rl['options'] as Map?)?.cast<String, dynamic>() ?? const {};
        final rs = opts['save_dish'];
        if (rs is Map) {
          c.check(l.skip != null, 'save_dish not parsed');
          c.eq(l.skip?.ok, rs['ok'], '${it.displayText} save_dish.ok');
          c.check((l.skip?.name ?? '').isNotEmpty, 'save_dish name empty');
        }
        c.eq(l.swaps.length, (opts['swap'] as List?)?.length ?? 0, '${it.displayText} swap options');
        for (final sw in l.swaps) {
          c.check(sw.name.isNotEmpty && sw.substituteIngredientId != 'null', 'swap name/id empty');
          c.check(sw.noteHi.isNotEmpty, 'swap ${sw.name} note_hi empty');
        }
        c.eq(l.dishes.length, (opts['change_dish'] as List?)?.length ?? 0, '${it.displayText} change_dish options');
        for (final d in l.dishes) {
          c.check(d.name.isNotEmpty && d.id != 'null', 'change_dish card name/id empty');
        }
        c.note('${it.displayText}: step=${l.step.wire} skipOk=${l.skip?.ok} swaps=${l.swaps.map((s) => s.name).toList()} '
            'dishes=${l.dishes.map((d) => d.name).toList()}');
        if (expectSkip) c.check(l.canSkip, '${it.displayText} (optional) should be skippable');

        // Resolve: skip when allowed, else the first swap.
        Ticket after;
        if (l.canSkip) {
          after = await step('resolve skip', () => tickets.resolveStockIssue(t.id, LadderAction.skip, idempotencyKey: uuid.v4()));
        } else if (l.swaps.isNotEmpty) {
          after = await step('resolve swap', () => tickets.resolveStockIssue(t.id, LadderAction.swap,
              substituteIngredientId: l.swaps.first.substituteIngredientId, idempotencyKey: uuid.v4()));
        } else {
          c.note('${it.displayText}: neither skip nor swap offered; left open');
          return;
        }
        final rawAfter = s.rec.map('POST', '/v1/tickets/${t.id}/stock-issue/resolve');
        c.eq(after.stockIssueOpen, rawAfter['stock_issue_open'], 'resolve stock_issue_open');
        c.note('after resolve: stock_issue_open=${after.stockIssueOpen} issue=${after.issue?.state.wire} '
            'raw stock_issues=${rawAfter['stock_issues']}');
        t = after;
      }

      if (dhaniya != null) await outAndResolve(dhaniya, expectSkip: true);
      if (dahi != null) await outAndResolve(dahi, expectSkip: false);
      t = await tickets.ticket(t.id);

      // Thread.
      final text = 'Live test message ${DateTime.now().toIso8601String()}';
      final msg = await step('send message', () => tickets.sendMessage(t.id, text, idempotencyKey: uuid.v4()));
      c.eq(msg.text, text, 'message text');
      c.check(msg.author.isNotEmpty, 'message author empty');
      c.check(msg.fromCook, 'cook message not fromCook');
      c.check(msg.at != null, 'message created_at null');
      final thread = await step('messages', () => tickets.messages(t.id));
      c.check(thread.any((m) => m.text == text), 'thread lacks the message');

      // Duty: read only. The app has no repository for duty-history.
      try {
        final h = await s.dio.get<Object?>('/v1/cooks/$hiredCookId/duty-history');
        c.note('duty-history (no app repository; raw): ${h.data}');
      } on DioException catch (e) {
        c.note('duty-history as hired cook → ${e.response?.statusCode} ${e.response?.data}');
      }

      // Ration request raised by the cook (decided by the admin in step 6).
      final ration = s.container.read(rationRepositoryProvider);
      final anyStock = stockSnapshot.keys.firstWhere((k) => !touchedStock.contains(k), orElse: () => stockSnapshot.keys.first);
      touchedStock.add(anyStock);
      final rr = await step('ration create', () => ration.create(ticketId: t.id, items: [
            RationItem(ingredientId: anyStock, name: 'live-test item', qty: 1, unit: 'kg'),
          ]));
      final rawR = s.rec.map('POST', '/v1/ration-requests');
      c.eq(rr.status.wire, rawR['status'], 'ration status');
      c.check(rr.id.isNotEmpty && rr.id != 'null', 'ration id');
      c.eq(rr.ticketId, t.id, 'ration ticket_id');
      c.check(rr.items.isNotEmpty && rr.items.first.name.isNotEmpty, 'ration items/name');
      c.eq(rr.items.firstOrNull?.qty, 1.0, 'ration item qty');
      c.check(rr.raisedBy.isNotEmpty, 'ration raised_by empty (raw ${rawR['raised_by']})');
      rationId = rr.id;

      // Finish cooking: cooking → ready → completed.
      t = await step('ready', () => tickets.transition(t.id, TicketStatus.ready, version: t.version, idempotencyKey: uuid.v4()));
      c.eq(t.status, TicketStatus.ready, 'after ready');
      t = await step('completed', () => tickets.transition(t.id, TicketStatus.completed, version: t.version, idempotencyKey: uuid.v4()));
      c.eq(t.status, TicketStatus.completed, 'after completed');
      c.check(t.completedAt != null, 'completed_at null');
      ticketCompleted = t.status == TicketStatus.completed;
      ticket = t;
      c.done();
    });

    test('6 admin: approvals, stock, ration, ratings, inbox, subscription, insights, cooks', () async {
      final s = admin!;
      final c = Checks('6-admin');

      // Approvals.
      final approvals = s.container.read(approvalsRepositoryProvider);
      final pending = await step('approvals', () => approvals.approvals(status: 'pending'));
      final rawA = s.rec.list('GET', '/v1/approvals');
      c.eq(pending.length, rawA.length, 'approvals count');
      for (var i = 0; i < pending.length; i++) {
        c.eq(pending[i].type.wire, rawA[i]['type'], 'approval $i type');
        c.check(pending[i].pending, 'approval $i not pending (decision ${pending[i].decision})');
        c.check(pending[i].requestedBy.isNotEmpty, 'approval $i requested_by empty');
      }
      final ours = pending.where((a) => a.ticketId == ticket?.id).toList();
      if (ours.isNotEmpty) {
        final d = await step('approval decide', () => approvals.decide(ours.first.id, Decision.approved));
        c.eq(d.decision, Decision.approved, 'approval decision');
        c.check(d.decidedAt != null, 'approval decided_at null');
      } else {
        c.note('no pending approval for our ticket (${pending.length} pending overall)');
      }

      // Stock list + one level change and restore.
      final stockRepo = s.container.read(stockRepositoryProvider);
      final stock = await step('stock', () => stockRepo.stock());
      final rawS = s.rec.list('GET', '/v1/stock');
      c.eq(stock.length, rawS.length, 'stock count');
      for (var i = 0; i < stock.length && i < rawS.length; i++) {
        c.eq(stock[i].level.wire, rawS[i]['level'], 'stock ${stock[i].name} level');
        c.check(stock[i].name.isNotEmpty, 'stock $i name empty');
        c.eq(stock[i].category, rawS[i]['category'] ?? StockCategory.other, 'stock ${stock[i].name} category');
        if (rawS[i]['qty'] != null) c.eq(stock[i].qty, wireDouble(rawS[i]['qty']), 'stock ${stock[i].name} qty');
      }
      final target = stock.firstWhere((i) => i.level == ItemStatus.inStock && !touchedStock.contains(i.ingredientId),
          orElse: () => stock.first);
      touchedStock.add(target.ingredientId);
      final changed = await step('stock set low', () => stockRepo.setLevel(target.ingredientId, ItemStatus.low));
      c.eq(changed.level, ItemStatus.low, 'stock level after PUT');
      c.eq(changed.ingredientId, target.ingredientId, 'stock PUT ingredient_id');
      c.check(changed.updatedAt != null, 'stock updated_at null');
      final back = await step('stock restore', () => stockRepo.setLevel(target.ingredientId, target.level, qty: target.qty));
      c.eq(back.level, target.level, 'stock level restored');

      // Ration: decide approved → bought.
      final ration = s.container.read(rationRepositoryProvider);
      final list = await step('ration list', () => ration.requests());
      c.check(list.any((r) => r.id == rationId), 'ration list lacks our request');
      if (rationId != null) {
        final cur = list.firstWhere((r) => r.id == rationId);
        if (cur.status == RationStatus.pending) {
          final d = await step('ration decide', () => ration.decide(rationId!, Decision.approved));
          c.eq(d.status, RationStatus.approved, 'ration after decide');
          c.check(d.decidedBy != null && d.decidedBy!.isNotEmpty, 'ration decided_by empty');
        } else {
          c.note('ration already ${cur.status.wire} (auto-approved?)');
        }
        final b = await step('ration bought', () => ration.bought(rationId!));
        c.eq(b.status, RationStatus.bought, 'ration after bought');
      }

      // Ratings on the completed ticket.
      final ratings = s.container.read(ratingsRepositoryProvider);
      if (ticketCompleted) {
        final t = ticket!;
        final inputs = [
          for (final d in t.dishes)
            for (final e in t.eaters.take(2)) RatingInput(recipeId: d.recipeId, memberId: e.memberId, score: RatingScore.bahutAccha),
        ];
        c.check(inputs.isNotEmpty, 'no eaters/dishes to rate (eaters ${t.eaters.length})');
        final rated = await step('rate', () => ratings.rate(t.id, inputs));
        c.check(rated != null, 'rate returned no ticket (raw ${s.rec.body('POST', '/v1/tickets/${t.id}/ratings')})');
        c.check(rated?.ratedAt != null, 'rated_at null after rating');
        final sum = await step('rating summary', () => ratings.summary(gatteId!));
        final rawSum = s.rec.body('GET', '/v1/ratings/summary');
        c.check(sum != null, 'summary null (raw $rawSum)');
        if (sum != null) {
          c.check(sum.count >= 1, 'summary count ${sum.count}');
          c.check(sum.average >= 1 && sum.average <= 3, 'summary average ${sum.average}');
          c.eq(sum.recipeId, gatteId, 'summary recipe_id');
          c.check(sum.members.isNotEmpty, 'summary members empty (raw $rawSum)');
          for (final m in sum.members) {
            c.check(m.memberId.isNotEmpty && m.count > 0, 'summary member id/count');
          }
        }
      } else {
        c.check(false, 'ticket not completed: ratings skipped');
      }

      // Inbox.
      final inbox = s.container.read(inboxRepositoryProvider);
      final items = await step('inbox', () => inbox.inbox());
      final rawI = s.rec.list('GET', '/v1/inbox');
      c.eq(items.length, rawI.length, 'inbox count');
      c.check(items.isNotEmpty, 'inbox empty');
      for (final i in items) {
        c.check(i.event.isNotEmpty && i.title.isNotEmpty, 'inbox ${i.id} event/title empty');
        c.check(i.createdAt != null, 'inbox ${i.id} created_at null');
      }
      final unread = items.where((i) => i.unread).firstOrNull;
      if (unread != null) {
        await step('mark read', () => inbox.markRead(unread.id));
        final again = await inbox.inbox();
        c.check(again.firstWhere((i) => i.id == unread.id, orElse: () => unread).readAt != null, 'inbox item still unread after read');
      } else {
        c.note('no unread inbox item to mark');
      }

      // Subscription.
      final sub = await step('subscription', () => s.container.read(subscriptionRepositoryProvider).subscription());
      final rawSub = s.rec.map('GET', '/v1/subscription');
      c.eq(sub.status.wire, rawSub['status'], 'subscription status');
      c.check(sub.status != SubscriptionStatus.unknown, 'subscription status unknown');
      c.eq(sub.trialEndsAt == null, rawSub['trial_ends_at'] == null, 'subscription trial_ends_at presence');

      // Weekly insights.
      final w = await step('weekly', () => s.container.read(accountRepositoryProvider).weekly());
      final rawW = s.rec.map('GET', '/v1/insights/weekly');
      c.eq(w.mealsCooked, rawW['meals_cooked'], 'weekly meals_cooked');
      c.eq(w.topDishes.length, (rawW['top_dishes'] as List?)?.length ?? 0, 'weekly top_dishes');
      for (final d in w.topDishes) {
        c.check(d.$2.isNotEmpty && d.$3 > 0, 'weekly top dish name/count: $d (raw ${rawW['top_dishes']})');
      }
      if (rawW['on_time_pct'] != null) c.eq(w.onTimePct, (rawW['on_time_pct'] as num).toDouble(), 'weekly on_time_pct');
      if (rawW['coverage_pct'] != null) c.eq(w.coveragePct, (rawW['coverage_pct'] as num).toDouble(), 'weekly coverage_pct');

      // Cooks.
      final cooks = await step('cooks', () => s.container.read(cooksRepositoryProvider).cooks());
      final rawC = s.rec.list('GET', '/v1/cooks');
      c.eq(cooks.length, rawC.length, 'cooks count');
      for (var i = 0; i < cooks.length; i++) {
        c.eq(cooks[i].kind.name, rawC[i]['kind'], 'cook $i kind');
        c.eq(cooks[i].onDuty, rawC[i]['on_duty'], 'cook $i on_duty');
        c.eq(cooks[i].isPrimary, rawC[i]['is_primary'], 'cook $i is_primary');
        c.check(cooks[i].name.isNotEmpty, 'cook $i name empty');
      }
      final hired = cooks.where((k) => k.kind == CookKind.hired).firstOrNull;
      c.check(hired != null && hired.name.contains('Ramesh'), 'hired cook Ramesh ji missing');
      c.check(hired?.isPrimary ?? false, 'hired cook not primary');
      c.check(hired?.onDuty ?? false, 'hired cook not on duty');
      c.check((hired?.phoneMasked ?? '').isNotEmpty, 'hired cook phone_masked empty');
      final fam = cooks.where((k) => k.kind == CookKind.family).firstOrNull;
      c.check(fam != null && fam.isBackup, 'family backup cook missing');
      c.done();
    });
  });
}

String? rationId;

/// Puts back what the run changed (where the API allows it).
Future<void> cleanup() async {
  final s = admin;
  if (s == null) return;
  try {
    if (ticket != null && !ticketCompleted) {
      final tickets = s.container.read(ticketsRepositoryProvider);
      final t = await tickets.ticket(ticket!.id);
      if (t.status.isOpen) {
        final res = await tickets.transition(t.id, TicketStatus.cancelled,
            version: t.version, idempotencyKey: uuid.v4(), reason: 'live test cleanup');
        log('cleanup: cancelled ticket ${t.id} → ${res.status.wire}');
      }
    }
  } catch (e) {
    log('cleanup: cancel failed: ${describe(e)}');
  }
  try {
    final repo = s.container.read(stockRepositoryProvider);
    final now = await repo.stock();
    for (final i in now) {
      final before = stockSnapshot[i.ingredientId];
      if (before == null) continue;
      if (before.$1 != i.level || before.$2 != i.qty) {
        await repo.setLevel(i.ingredientId, before.$1, qty: before.$2);
        log('cleanup: stock ${i.name} ${i.level.wire}/${i.qty} → ${before.$1.wire}/${before.$2}');
      }
    }
  } catch (e) {
    log('cleanup: stock restore failed: ${describe(e)}');
  }
  for (final x in [admin, cook]) {
    if (x == null) continue;
    try {
      await x.container.read(authRepositoryProvider).logout(x.container.read(authControllerProvider).tokens!.accessToken);
    } catch (_) {}
    x.container.dispose();
  }
}

