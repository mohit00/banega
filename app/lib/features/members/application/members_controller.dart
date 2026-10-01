import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_source.dart';
import '../../kitchen/application/kitchen_providers.dart' show keyValueStoreProvider;
import '../data/members_repository.dart';
import '../domain/member.dart';

/// Demo: the in-memory family; API: /v1/members.
final membersRepositoryProvider = Provider<MembersRepository>((ref) {
  if (ref.watch(dataSourceProvider) == DataSource.demo) return const DemoMembersRepository();
  return ApiMembersRepository(ref.watch(dioProvider));
});

/// Loading / error state of the members list (API mode).
@immutable
class MembersStatus {
  const MembersStatus({this.loading = false, this.error});

  final bool loading;
  final Object? error;
}

final membersStatusProvider = NotifierProvider<MembersStatusController, MembersStatus>(MembersStatusController.new);

class MembersStatusController extends Notifier<MembersStatus> {
  @override
  MembersStatus build() => const MembersStatus();

  void set(MembersStatus s) => state = s;
}

/// The household's members. Edits are optimistic: the list changes at once,
/// the write goes to the repository, and a failed write rolls that member
/// back (the returned future throws so the screen can say so).
final membersProvider = NotifierProvider<MembersController, List<Member>>(MembersController.new);

class MembersController extends Notifier<List<Member>> {
  int _added = 0;
  int _seq = 0;

  /// Latest edit per member: only its answer (or failure) is applied.
  final Map<String, int> _editSeq = {};

  /// Last state the server confirmed, per member (rollback target).
  final Map<String, Member> _confirmed = {};

  static String _localKey(String id) => 'member.local.$id';

  MembersRepository get _repo => ref.read(membersRepositoryProvider);

  @override
  List<Member> build() {
    final repo = ref.watch(membersRepositoryProvider);
    final initial = repo.initialMembers();
    if (ref.watch(dataSourceProvider) == DataSource.api) {
      Future.microtask(refresh);
    }
    return initial;
  }

  /// GET the members (API mode) and merge the device-only fields.
  Future<void> refresh() async {
    final status = ref.read(membersStatusProvider.notifier);
    status.set(const MembersStatus(loading: true));
    try {
      final fetched = await _repo.fetchMembers();
      final merged = [for (final m in fetched) await _withLocal(m)];
      if (!ref.mounted) return;
      _confirmed
        ..clear()
        ..addEntries(merged.map((m) => MapEntry(m.id, m)));
      state = merged;
      status.set(const MembersStatus());
    } catch (e) {
      if (ref.mounted) status.set(MembersStatus(error: e));
    }
  }

  /// Vrat days and "show on Home" live on the device until the API has them.
  Future<Member> _withLocal(Member m) async {
    try {
      final raw = await ref.read(keyValueStoreProvider).get(_localKey(m.id));
      if (raw == null) return m;
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return m.copyWith(
        vratDays: {for (final d in (j['vrat_days'] as List? ?? const [])) (d as num).toInt()},
        showOnHome: j['show_on_home'] as bool? ?? false,
      );
    } catch (_) {
      return m;
    }
  }

  Future<void> _saveLocal(Member m) async {
    try {
      await ref
          .read(keyValueStoreProvider)
          .set(_localKey(m.id), jsonEncode({'vrat_days': m.vratDays.toList()..sort(), 'show_on_home': m.showOnHome}));
    } catch (_) {}
  }

  Member? byId(String id) {
    for (final m in state) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _replace(String id, Member m) => state = [for (final x in state) x.id == id ? m : x];

  /// Applies [edit] to the member with [id] and writes it. Rolls back on
  /// failure (and rethrows).
  Future<void> update(String id, Member Function(Member m) edit) async {
    final before = byId(id);
    if (before == null) return;
    final next = edit(before);
    if (next == before) return;
    _confirmed.putIfAbsent(id, () => before);
    _replace(id, next);
    final seq = _editSeq[id] = (_editSeq[id] ?? 0) + 1;
    unawaited(_saveLocal(next));
    try {
      final saved = await _repo.updateMember(next);
      final withLocal = saved.copyWith(vratDays: next.vratDays, showOnHome: next.showOnHome);
      _confirmed[id] = withLocal;
      if (ref.mounted && _editSeq[id] == seq && byId(id) != null) _replace(id, withLocal);
    } catch (e) {
      if (ref.mounted && _editSeq[id] == seq) {
        final back = _confirmed[id] ?? before;
        if (byId(id) != null) _replace(id, back);
        unawaited(_saveLocal(back));
      }
      rethrow;
    }
  }

  Future<void> setDiet(String id, Diet diet) => update(
    id,
    (m) => m.copyWith(
      diet: diet,
      // Exclusions only mean something for non-veg.
      nonvegExclusions: diet == Diet.nonveg ? m.nonvegExclusions : const [],
    ),
  );
  Future<void> setSpice(String id, Spice spice) => update(id, (m) => m.copyWith(spice: spice));
  Future<void> toggleNeed(String id, Need need) => update(id, (m) => m.toggleNeed(need));
  Future<void> toggleCuisine(String id, Cuisine c) => update(id, (m) => m.toggleCuisine(c));
  Future<void> setKid(String id, bool v) => update(id, (m) => m.copyWith(isKid: v));
  Future<void> setNoDairy(String id, bool v) => update(id, (m) => m.copyWith(noDairy: v));
  Future<void> setShowOnHome(String id, bool v) => update(id, (m) => m.copyWith(showOnHome: v));

  Future<void> toggleAllergen(String id, String key) =>
      update(id, (m) => m.copyWith(allergens: _toggle(m.allergens, key)));

  Future<void> toggleNonvegExclusion(String id, String key) =>
      update(id, (m) => m.copyWith(nonvegExclusions: _toggle(m.nonvegExclusions, key)));

  Future<void> toggleVratDay(String id, int weekday) => update(id, (m) {
    final d = {...m.vratDays};
    if (!d.remove(weekday)) d.add(weekday);
    return m.copyWith(vratDays: d);
  });

  Future<void> addDislike(String id, String item) {
    final v = item.trim().toLowerCase();
    if (v.isEmpty) return Future.value();
    return update(id, (m) => m.dislikes.contains(v) ? m : m.copyWith(dislikes: [...m.dislikes, v]));
  }

  Future<void> removeDislike(String id, String item) => update(
    id,
    (m) => m.copyWith(
      dislikes: [
        for (final d in m.dislikes)
          if (d != item) d,
      ],
    ),
  );

  static List<String> _toggle(List<String> list, String key) => list.contains(key)
      ? [
          for (final x in list)
            if (x != key) x,
        ]
      : [...list, key];

  /// Name + colour for the next "Member jodo" (the prototype's pool).
  MemberTemplate nextTemplate() => ref.read(membersRepositoryProvider).templateFor(_added);

  /// Adds a member (Veg, Medium, no needs) named [name]; returns it with the
  /// server's id in API mode. Throws when the POST fails (nothing added).
  Future<Member> addMember([String? name]) async {
    final t = _repo.templateFor(_added++);
    final draft = Member(
      id: 'x${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
      name: (name == null || name.trim().isEmpty) ? t.name : name.trim(),
      color: t.color,
    );
    final created = await _repo.createMember(draft);
    if (ref.mounted) {
      _confirmed[created.id] = created;
      state = [...state, created];
    }
    return created;
  }

  /// Archives a member (optimistic; restored at its place on failure).
  Future<void> remove(String id) async {
    final i = state.indexWhere((m) => m.id == id);
    if (i < 0) return;
    final m = state[i];
    state = [
      for (final x in state)
        if (x.id != id) x,
    ];
    try {
      await _repo.archiveMember(id);
      _confirmed.remove(id);
      try {
        await ref.read(keyValueStoreProvider).remove(_localKey(id));
      } catch (_) {}
    } catch (e) {
      if (ref.mounted) {
        final list = [...state];
        list.insert(i.clamp(0, list.length), m);
        state = list;
      }
      rethrow;
    }
  }
}
