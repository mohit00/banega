import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../core/network/api_client.dart';
import '../core/network/network_status.dart';
import '../features/auth/application/auth_controller.dart';
import 'api/api_repository.dart';
import 'demo/demo_repository.dart';
import 'repositories.dart';

enum DataSource { demo, api }

/// The demo sandbox, entered explicitly from Splash ("Demo family ke saath
/// dekho"). Without an API base URL the app is always in the sandbox.
final sandboxProvider = NotifierProvider<SandboxController, bool>(SandboxController.new);

class SandboxController extends Notifier<bool> {
  @override
  bool build() => false;

  void enter() => state = true;

  void exit() => state = false;
}

/// Which data source the app reads and writes. Decided by configuration and
/// the explicit sandbox choice only: API mode never routes a read or a write
/// to the demo; a network failure is an offline / error state with retry.
final dataSourceProvider = Provider<DataSource>(
  (ref) => ref.watch(appConfigProvider).hasApi && !ref.watch(sandboxProvider) ? DataSource.api : DataSource.demo,
);

/// The one API client: Dio against the configured backend with the
/// `Accept-Language` / `X-Request-Id` headers, bearer auth with single-flight
/// refresh-and-replay on 401 (logout when the refresh is rejected), and the
/// reachability report behind the offline banner. Repositories map every
/// failure to an `AppError` through `ApiGuard`.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final status = ref.read(networkOfflineProvider.notifier);
  final auth = ref.read(authControllerProvider.notifier);
  // Rebuild the client on sign-in / sign-out so every repository and data
  // provider built on it refetches with the new session.
  ref.watch(authControllerProvider.select((s) => s.signedIn));
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl ?? '',
      connectTimeout: config.connectTimeout,
      receiveTimeout: const Duration(seconds: 8),
      responseType: ResponseType.json,
    ),
  );
  dio.interceptors
    ..add(RequestHeadersInterceptor(language: ref.read(acceptLanguageProvider)))
    ..add(DeviceIdInterceptor(ref.read(installIdProvider).call))
    ..add(
      AuthInterceptor(dio: ref.watch(plainDioProvider), accessToken: () => auth.accessToken, refresh: auth.refreshFor),
    )
    ..add(NetworkStatusInterceptor(status.set));
  final adapter = ref.watch(httpClientAdapterProvider);
  if (adapter != null) dio.httpClientAdapter = adapter;
  ref.onDispose(dio.close);
  return dio;
});

final demoRepositoryProvider = Provider<DemoRepository>((ref) => const DemoRepository());

/// The active repository: the demo sandbox or the API.
final dataRepositoryProvider = Provider<DataRepository>((ref) {
  if (ref.watch(dataSourceProvider) == DataSource.demo) return ref.watch(demoRepositoryProvider);
  return ApiRepository(ref.watch(dioProvider));
});
