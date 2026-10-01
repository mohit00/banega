import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/data_source.dart';
import '../../../data/models.dart';
import '../../home/home_providers.dart';
import '../../members/application/members_controller.dart';
import '../domain/scaling.dart';

/// Servings the Detail stepper starts at: adults 1.0, kids 0.5, rounded up.
final defaultServingsProvider = Provider<int>((ref) => defaultServings(ref.watch(membersProvider)));

/// GET /v1/recipes/{id}?servings=N, keyed by (id, servings).
final recipeDetailProvider = FutureProvider.autoDispose.family<RecipeDetail, (String, int)>(
  (ref, key) => ref
      .watch(dataRepositoryProvider)
      .recipe(key.$1, servings: key.$2, members: ref.watch(membersProvider), date: ref.watch(planDateProvider)),
  retry: (_, _) => null,
);

/// Opens a URL outside the app. Overridden in tests.
final urlLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// The link "Video recipe" opens: the recipe's own video when it is a
/// well-formed https URL, else a YouTube search for the dish (never another
/// scheme such as intent:, file: or javascript:).
Uri videoUriFor(String name, String? videoUrl) {
  final u = videoUrl == null ? null : Uri.tryParse(videoUrl.trim());
  if (u != null && u.scheme == 'https' && u.host.isNotEmpty) return u;
  return videoSearchUri(name);
}

/// Opens [uri] without throwing; false when nothing could open it.
Future<bool> openExternal(Future<bool> Function(Uri) launcher, Uri uri) async {
  try {
    return await launcher(uri);
  } catch (_) {
    return false;
  }
}

/// The prototype's "Video recipe" link: a YouTube search for the dish.
Uri videoSearchUri(String name) => Uri.https('www.youtube.com', '/results', {'search_query': '$name recipe'});
