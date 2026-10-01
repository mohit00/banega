import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the last backend request failed for lack of network (and no
/// request has succeeded since). Drives the [OfflineBanner]; screens keep
/// showing what they have and offer a retry. API mode never switches to demo
/// data on its own.
final networkOfflineProvider = NotifierProvider<NetworkStatus, bool>(NetworkStatus.new);

class NetworkStatus extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool offline) {
    if (state != offline) state = offline;
  }
}

/// True when [e] means the backend could not be reached at all (no network,
/// DNS, refused, timeouts), as opposed to an HTTP answer.
bool isOfflineDioError(DioException e) => switch (e.type) {
  DioExceptionType.connectionError ||
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout => true,
  // dart:io's SocketException, matched by name so this file stays web-safe.
  DioExceptionType.unknown => '${e.error.runtimeType}'.contains('SocketException'),
  _ => false,
};

/// Reports reachability to [status]: any HTTP answer → online, a transport
/// failure → offline.
class NetworkStatusInterceptor extends Interceptor {
  NetworkStatusInterceptor(this.status);

  final void Function(bool offline) status;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    status(false);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    status(err.response == null && isOfflineDioError(err));
    handler.next(err);
  }
}
