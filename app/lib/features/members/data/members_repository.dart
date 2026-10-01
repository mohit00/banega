import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../data/demo/demo_members.dart';
import '../../../data/models.dart' show memberFromJson, memberToJson;
import '../domain/member.dart';

/// Household members. Demo: in memory; API: /v1/members CRUD.
abstract interface class MembersRepository {
  /// Members shown before [fetchMembers] returns: the demo family in the
  /// sandbox, nothing in API mode (never placeholder people).
  List<Member> initialMembers();

  /// Name + colour suggestions for "Member jodo" (prototype `POOL`).
  List<MemberTemplate> get suggestions;

  /// Template for the next add; [index] counts previous adds.
  MemberTemplate templateFor(int index);

  /// GET /v1/members (active only).
  Future<List<Member>> fetchMembers();

  /// POST /v1/members → the created member (server id).
  Future<Member> createMember(Member draft);

  /// PATCH /v1/members/{id} → the stored member.
  Future<Member> updateMember(Member m);

  /// DELETE /v1/members/{id} (archive).
  Future<void> archiveMember(String id);
}

/// The prototype's demo family (Purohit Parivaar), kept in memory.
class DemoMembersRepository implements MembersRepository {
  const DemoMembersRepository();

  @override
  List<Member> initialMembers() => List.of(demoMembers);

  @override
  List<MemberTemplate> get suggestions => demoMemberPool;

  @override
  MemberTemplate templateFor(int index) => demoMemberPool[index % demoMemberPool.length];

  @override
  Future<List<Member>> fetchMembers() async => initialMembers();

  @override
  Future<Member> createMember(Member draft) async => draft;

  @override
  Future<Member> updateMember(Member m) async => m;

  @override
  Future<void> archiveMember(String id) async {}
}

class ApiMembersRepository with ApiGuard implements MembersRepository {
  ApiMembersRepository(this.dio);

  final Dio dio;

  @override
  List<Member> initialMembers() => const [];

  @override
  List<MemberTemplate> get suggestions => demoMemberPool;

  @override
  MemberTemplate templateFor(int index) => demoMemberPool[index % demoMemberPool.length];

  @override
  Future<List<Member>> fetchMembers() => guard(() async {
    final res = await dio.get<Object?>('/v1/members', queryParameters: {'limit': 100});
    return [for (final m in jsonList(res.data)) memberFromJson(m)];
  });

  @override
  Future<Member> createMember(Member draft) => guard(() async {
    final res = await dio.post<Object?>('/v1/members', data: memberToJson(draft));
    return memberFromJson(json(res.data));
  });

  @override
  Future<Member> updateMember(Member m) => guard(() async {
    final res = await dio.patch<Object?>('/v1/members/${enc(m.id)}', data: memberToJson(m));
    return memberFromJson(json(res.data));
  });

  @override
  Future<void> archiveMember(String id) => guard(() async {
    await dio.delete<Object?>('/v1/members/${enc(id)}');
  });
}
