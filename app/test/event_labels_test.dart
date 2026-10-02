import 'package:banega/core/l10n/gen/app_localizations_en.dart';
import 'package:banega/core/l10n/gen/app_localizations_hi.dart';
import 'package:banega/labels/kitchen_labels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every notification event in the server's MATRIX (backend/app/services/notifications.py)
/// has a name on the Settings toggles; an unknown one would show its raw key.
const serverEvents = [
  'approval_decided',
  'approval_request',
  'at_risk',
  'chef_claimed',
  'cook_message',
  'cook_off_duty',
  'cook_on_duty',
  'expiry_reminder',
  'export_ready',
  'family_message',
  'no_show',
  'not_confirmed_prompt',
  'rate_prompt',
  'ration_bought',
  'ration_decided',
  'ration_request',
  'stock_issue',
  'stock_issue_resolved',
  'stock_issue_timeout',
  'stock_low',
  'ticket_accepted',
  'ticket_cancelled',
  'ticket_completed',
  'ticket_created',
  'ticket_unassigned',
  'ticket_updated',
  'tomorrow_tickets',
  'weekly_summary',
];

void main() {
  for (final l in [AppLocalizationsHiLatn(), AppLocalizationsEn(), AppLocalizationsHi()]) {
    test('every server event has a label (${l.localeName})', () {
      for (final e in serverEvents) {
        expect(l.eventName(e), isNot(e), reason: 'no label for $e');
      }
    });
  }
}
