import 'package:dio/dio.dart';

import '../../../core/engine/fit_engine.dart';
import '../../../core/network/api_client.dart';
import '../../../data/models.dart';
import '../../../data/repositories.dart' show SlotWire;
import '../../members/domain/member.dart';
import '../../recipe/domain/recipe.dart';
import '../domain/chat_models.dart';
import 'chat_repository.dart';

/// Maharaj over the backend:
///
/// - POST /v1/chat/sessions → `{session_id}`; sessions expire after
///   [sessionIdle] without a message, so a stale id is replaced (and a 404 /
///   410 from the server triggers one retry on a fresh session).
/// - POST /v1/chat/sessions/{id}/messages `{text, slot}` →
///   `{message_id, cards, slot, chips, text}`. Cards arrive first; when
///   `text` is null it is polled from GET /v1/chat/messages/{message_id}
///   every [pollInterval] up to [pollTimeout], then a local template stands in.
/// - GET /v1/chat/sessions/{id}/messages → history.
class ApiChatRepository with ApiGuard implements ChatRepository {
  ApiChatRepository(
    this.dio, {
    DateTime Function()? now,
    this.sessionIdle = const Duration(minutes: 30),
    this.pollInterval = const Duration(milliseconds: 500),
    this.pollTimeout = const Duration(seconds: 6),
    this.receiveTimeout = const Duration(seconds: 15),
  }) : _now = now ?? DateTime.now;

  final Dio dio;
  final DateTime Function() _now;
  final Duration sessionIdle;
  final Duration pollInterval;
  final Duration pollTimeout;

  /// Maharaj's answer can take longer than a plain read (the app default is
  /// 8 s), so the message POST waits up to this long.
  final Duration receiveTimeout;

  String? _sessionId;
  DateTime? _lastUsed;

  /// The current session id, if one is open and fresh (for tests / history).
  String? get sessionId => _fresh ? _sessionId : null;

  bool get _fresh => _sessionId != null && _lastUsed != null && _now().difference(_lastUsed!) < sessionIdle;

  Json _map(Object? data) => (data as Map).cast<String, dynamic>();

  Future<String> _session() async {
    if (_fresh) return _sessionId!;
    final res = await dio.post<Object?>('/v1/chat/sessions');
    _sessionId = '${_map(res.data)['session_id']}';
    _lastUsed = _now();
    return _sessionId!;
  }

  Future<Json> _post(String sid, String text, Slot slot) async {
    final res = await dio.post<Object?>(
      '/v1/chat/sessions/${Uri.encodeComponent(sid)}/messages',
      data: {'text': text, 'slot': slot.wire},
      options: Options(receiveTimeout: receiveTimeout),
    );
    return _map(res.data);
  }

  @override
  Stream<ChatReply> ask(String text, {required Slot slot, required List<Member> members, DateTime? date}) async* {
    final j = await guard(() async {
      try {
        return await _post(await _session(), text, slot);
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        if (code != 404 && code != 410) rethrow;
        _sessionId = null; // expired server-side
        return _post(await _session(), text, slot);
      }
    });
    _lastUsed = _now();

    final cards = [
      for (final c in (j['cards'] as List? ?? const [])) RecipeCard.fromJson((c as Map).cast<String, dynamic>()),
    ];
    final replySlot = slotFromWire(j['slot']) ?? slot;
    final chips = [for (final c in (j['chips'] as List? ?? const [])) '$c'];
    ChatReply reply(ReplyText? t, {bool complete = true}) =>
        ChatReply(slot: replySlot, cards: cards, chips: chips, text: t, complete: complete);

    final first = _text(j['text']);
    if (first != null) {
      yield reply(PlainText(first));
      return;
    }
    yield reply(null, complete: false);

    final id = j['message_id'];
    if (id != null) {
      final tries = pollTimeout.inMicroseconds ~/ pollInterval.inMicroseconds;
      for (var i = 0; i < tries; i++) {
        await Future<void>.delayed(pollInterval);
        try {
          final res = await dio.get<Object?>('/v1/chat/messages/${Uri.encodeComponent('$id')}');
          final t = _text(_map(res.data)['text']);
          if (t != null) {
            _lastUsed = _now();
            yield reply(PlainText(t));
            return;
          }
        } catch (_) {
          break; // write step unreachable: use the template below
        }
      }
    }
    // The prototype's template reply, built from the cards we have.
    yield reply(
      OptionsText(
        slot: replySlot,
        count: cards.length,
        allOk: cards.where((c) => c.summary.badge != FitKind.no).length,
        members: List.of(members),
      ),
    );
  }

  /// GET /v1/chat/sessions/{id}/messages for the open session (empty when
  /// there is none or it went stale).
  Future<List<ChatMessage>> history() async {
    final sid = sessionId;
    if (sid == null) return const [];
    final res = await guard(() => dio.get<Object?>('/v1/chat/sessions/${Uri.encodeComponent(sid)}/messages'));
    final data = res.data;
    final list = data is List ? data : (data is Map ? data['items'] as List? ?? const [] : const []);
    var i = 0;
    return [
      for (final m in list)
        if ((m as Map).cast<String, dynamic>() case final j)
          ChatMessage(
            id: -(++i),
            // The server names the sender `author` (user | bot); older shapes used `role`.
            role: const {'user', 'me'}.contains(j['author'] ?? j['role']) ? ChatRole.me : ChatRole.bot,
            text: _text(j['text']) == null ? null : PlainText(_text(j['text'])!),
            cards: [
              for (final c in (j['cards'] as List? ?? const []))
                RecipeCard.fromJson((c as Map).cast<String, dynamic>()),
            ],
            chips: [for (final c in (j['chips'] as List? ?? const [])) '$c'],
          ),
    ];
  }

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
}
