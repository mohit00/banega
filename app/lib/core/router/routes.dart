/// Route paths.
abstract final class Routes {
  /// Cold start: the startup gate decides where to go.
  static const start = '/start';
  static const splash = '/splash';

  /// OTP login and first-run household creation.
  static const phone = '/phone';
  static const otp = '/otp';
  static const createHousehold = '/household/new';
  static const family = '/family';
  static const prefsPattern = '/prefs/:memberId';
  static String prefs(String memberId) => '/prefs/$memberId';
  static const loading = '/loading';
  static const home = '/home';

  static const recipePattern = '/recipe/:recipeId';
  static String recipe(String id) => '/recipe/${Uri.encodeComponent(id)}';

  /// Detail opened from Plan: "Menu mein daalo" edits that (date, slot).
  static String recipeFor(String id, {required String date, required String slot}) =>
      '/recipe/${Uri.encodeComponent(id)}?date=${Uri.encodeQueryComponent(date)}&slot=${Uri.encodeQueryComponent(slot)}';

  /// Maharaj chat; `?q=` is sent on open.
  static const chat = '/chat';
  static String chatAsk(String q) => '/chat?q=${Uri.encodeQueryComponent(q)}';

  /// S8 day menu.
  static const plan = '/plan';

  /// Family ticket detail (S12) and its thread.
  static const ticketPattern = '/tickets/:ticketId';
  static String ticket(String id) => '/tickets/${Uri.encodeComponent(id)}';
  static const ticketThreadPattern = '/tickets/:ticketId/thread';
  static String ticketThread(String id) => '/tickets/${Uri.encodeComponent(id)}/thread';

  static const inbox = '/inbox';
  static const settings = '/settings';

  /// S15 Rasoi stock and S13 ration requests (family side).
  static const stock = '/stock';
  static const ration = '/ration';

  /// S10 paywall and the first-run consent screen.
  static const paywall = '/paywall';
  static const consent = '/consent';
  static String consentThen(String next) => '/consent?next=${Uri.encodeQueryComponent(next)}';

  /// Cook mode: K1 list, K2 ticket, K5 recipe, K6 thread.
  static const cook = '/cook';
  static const cookTicketPattern = '/cook/tickets/:ticketId';
  static String cookTicket(String id) => '/cook/tickets/${Uri.encodeComponent(id)}';
  static const cookRecipePattern = '/cook/tickets/:ticketId/recipe/:recipeId';
  static String cookRecipe(String ticketId, String recipeId) =>
      '/cook/tickets/${Uri.encodeComponent(ticketId)}/recipe/${Uri.encodeComponent(recipeId)}';
  static const cookThreadPattern = '/cook/tickets/:ticketId/thread';
  static String cookThread(String id) => '/cook/tickets/${Uri.encodeComponent(id)}/thread';

  /// Cook mode: K-stock (Hindi S15) and the cook's own ration requests.
  static const cookStock = '/cook/stock';
  static const cookRation = '/cook/ration';

  /// Design-system gallery (internal sign-off screen).
  static const gallery = '/gallery';
}
