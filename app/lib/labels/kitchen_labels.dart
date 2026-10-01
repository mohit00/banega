// Maps Phase 5 enums and wire keys to locale strings.
import 'package:flutter/painting.dart';

import '../core/l10n/gen/app_localizations.dart';
import '../core/theme/tokens.dart';
import '../features/account/domain/account_models.dart';
import '../features/kitchen/domain/kitchen_models.dart';
import '../features/pantry/domain/pantry_models.dart';

extension KitchenLabels on AppLocalizations {
  String ticketStatus(TicketStatus s) => switch (s) {
    TicketStatus.fresh => statusNew,
    TicketStatus.unassigned => statusUnassigned,
    TicketStatus.accepted => statusAccepted,
    TicketStatus.cooking => statusCooking,
    TicketStatus.ready => statusReady,
    TicketStatus.completed => statusCompleted,
    TicketStatus.notConfirmed => statusNotConfirmed,
    TicketStatus.cancelled => statusCancelled,
    TicketStatus.unknown => statusUnknown,
  };

  /// Contract slot key → name.
  String slotKey(String key) => switch (key) {
    SlotKeys.nashta => slotBreakfast,
    SlotKeys.lunch => slotLunch,
    SlotKeys.dinner => slotDinner,
    SlotKeys.tiffin => slotTiffin,
    SlotKeys.shaam => slotShaam,
    _ => key,
  };

  String itemStatus(ItemStatus s) => switch (s) {
    ItemStatus.inStock => itemIn,
    ItemStatus.low => itemLow,
    ItemStatus.out => itemOut,
    ItemStatus.untracked => itemUntracked,
  };

  String guestDiet(GuestDiet d) => switch (d) {
    GuestDiet.veg => dietVeg,
    GuestDiet.jain => dietJain,
    GuestDiet.nonVeg => dietNonveg,
  };

  /// "Ramesh ji (hired)".
  String cookChip(Cook c) => cookChipLabel(c.name, c.kind == CookKind.hired ? cookKindHired : cookKindFamily);

  /// Date selector chip: "Aaj" / "Kal" / "Wed 30".
  String dateChip(DateTime d, DateTime today) {
    final diff = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (diff == 0) return dateToday;
    if (diff == 1) return dateTomorrow;
    return '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]} ${d.day}';
  }

  String changeAction(String action) => switch (action) {
    'created' => logCreated,
    'accepted' => logAccepted,
    'cooking' => logCooking,
    'ready' => logReady,
    'completed' => logCompleted,
    'cancelled' => logCancelled,
    'not_confirmed' => logNotConfirmed,
    'updated' => logUpdated,
    'item_out' => logItemOut,
    'claimed' => logClaimed,
    'reassigned' => logReassigned,
    'unassigned' => logUnassigned,
    'auto_cancelled' => logAutoCancelled,
    'new' => statusNew,
    LadderLog.skip => logSkip,
    LadderLog.swap => logSwap,
    LadderLog.changeDish => logChangeDish,
    LadderLog.approvalRequested => logApprovalRequested,
    LadderLog.approved => logApproved,
    LadderLog.rejected => logRejected,
    LadderLog.timeout => logTimeout,
    _ => action,
  };

  /// In / Low / Out on the stock pills.
  String stockLevel(ItemStatus s) => switch (s) {
    ItemStatus.inStock => stockLevelIn,
    ItemStatus.low => stockLevelLow,
    ItemStatus.out => stockLevelOut,
    ItemStatus.untracked => itemUntracked,
  };

  String stockCategory(String key) => switch (key) {
    StockCategory.sabzi => stockCatSabzi,
    StockCategory.dairy => stockCatDairy,
    StockCategory.dal => stockCatDal,
    StockCategory.anaaj => stockCatAnaaj,
    StockCategory.masale => stockCatMasale,
    StockCategory.telGhee => stockCatTelGhee,
    StockCategory.dryFruits => stockCatDryFruits,
    _ => stockCatOther,
  };

  String rationStatus(RationStatus s) => switch (s) {
    RationStatus.pending => rationStatusPending,
    RationStatus.approved => rationStatusApproved,
    RationStatus.rejected => rationStatusRejected,
    RationStatus.bought => rationStatusBought,
  };

  String subscriptionStatus(SubscriptionStatus s) => switch (s) {
    SubscriptionStatus.trial => subStatusTrial,
    SubscriptionStatus.active => subStatusActive,
    SubscriptionStatus.grace => subStatusGrace,
    SubscriptionStatus.expired => subStatusExpired,
    SubscriptionStatus.unknown => subStatusUnknown,
  };

  String ratingScore(RatingScore s) => switch (s) {
    RatingScore.bura => rateBura,
    RatingScore.theek => rateTheek,
    RatingScore.bahutAccha => rateBahutAccha,
  };

  String approvalText(Approval a) =>
      a.type == ApprovalType.changeDish ? approvalChangeDish(a.detail) : approvalSwap(a.detail);

  /// Notification event → name on the Settings toggles (raw key if unknown).
  String eventName(String event) => switch (event) {
    'ticket_created' => eventTicketCreated,
    'ticket_accepted' => eventTicketAccepted,
    'ticket_updated' => eventTicketUpdated,
    'ticket_completed' => eventTicketCompleted,
    'not_confirmed_prompt' => eventNotConfirmed,
    'cook_off_duty' => eventCookOffDuty,
    'no_show' => eventNoShow,
    'stock_low' => eventStockLow,
    'ration_request' => eventRationRequest,
    'ration_decided' => eventRationDecided,
    'stock_issue' => eventStockIssue,
    'approval_request' => eventApprovalRequest,
    'approval_decided' => eventApprovalDecided,
    'stock_issue_timeout' => eventStockTimeout,
    'rate_prompt' => eventRatePrompt,
    'expiry_reminder' => eventExpiry,
    'weekly_summary' => eventWeekly,
    'tomorrow_tickets' => eventTomorrow,
    _ => event,
  };
}

/// "1:30" (12-hour, as in the FRD's "Kab tak: 1:30").
String hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')}';
}

/// "1:30 PM" for the Plan's due chip.
String hmAmPm(DateTime t) => '${hm(t)} ${t.hour < 12 ? 'AM' : 'PM'}';

/// 4 → "4", 4.5 → "4.5".
String servingsText(double s) => s == s.roundToDouble() ? '${s.toInt()}' : s.toStringAsFixed(1);

/// Chip colours per ticket status (background, foreground).
(Color, Color) ticketStatusColours(TicketStatus s) => switch (s) {
  TicketStatus.fresh => (BColors.tweakBg, BColors.tweakFg),
  TicketStatus.unassigned || TicketStatus.notConfirmed => (BColors.noBg, BColors.noFg),
  TicketStatus.accepted || TicketStatus.completed => (BColors.fitBg, BColors.fitFg),
  TicketStatus.cooking => (BColors.haldi, BColors.ink),
  TicketStatus.ready => (BColors.green, BColors.card),
  TicketStatus.cancelled || TicketStatus.unknown => (BColors.segBg, BColors.ink3),
};

(Color, Color) itemStatusColours(ItemStatus s) => switch (s) {
  ItemStatus.inStock => (BColors.fitBg, BColors.fitFg),
  ItemStatus.low => (BColors.tweakBg, BColors.tweakFg),
  ItemStatus.out => (BColors.noBg, BColors.noFg),
  ItemStatus.untracked => (BColors.segBg, BColors.ink3),
};
