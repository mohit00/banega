import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/crash_reporting.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sentry only when built with --dart-define=SENTRY_DSN=...; otherwise a no-op.
  await runWithCrashReporting(() => runApp(const ProviderScope(child: BanegaApp())));
}
