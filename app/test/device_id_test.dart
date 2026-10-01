import 'package:banega/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('InstallId creates one id and reuses it', () async {
    final store = <String, String>{};
    final id = InstallId((k) async => store[k], (k, v) async => store[k] = v);
    final a = await id();
    final b = await id();
    expect(a, isNotEmpty);
    expect(b, a);
    expect(store[InstallId.key], a);

    final again = InstallId((k) async => store[k], (k, v) async => store[k] = v);
    expect(await again(), a, reason: 'a second process reads the stored id');
  });

  test('DeviceIdInterceptor adds X-Device-Id to requests', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://x'));
    dio.interceptors.add(DeviceIdInterceptor(() async => 'dev-123'));
    RequestOptions? seen;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          seen = o;
          h.resolve(Response(requestOptions: o, statusCode: 200, data: const {}));
        },
      ),
    );
    await dio.post<Object?>('/v1/auth/otp', data: {'phone': '+919999999999'});
    expect(seen?.headers['X-Device-Id'], 'dev-123');
  });

  test('DeviceIdInterceptor still sends the request without an id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://x'));
    dio.interceptors.add(DeviceIdInterceptor(() async => throw StateError('no storage')));
    RequestOptions? seen;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          seen = o;
          h.resolve(Response(requestOptions: o, statusCode: 200, data: const {}));
        },
      ),
    );
    await dio.get<Object?>('/v1/health');
    expect(seen, isNotNull);
    expect(seen!.headers.containsKey('X-Device-Id'), isFalse);
  });
}
