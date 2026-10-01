// Phase 6 wire models: stock, ration requests and approvals
// (docs/contracts/phase6-7-stock-ratings-billing.md). `category` on a
// StockItem is an addition the contract does not list (grouping on S15).
import 'package:flutter/foundation.dart';

import '../../../data/models.dart' show Json;
import '../../kitchen/domain/kitchen_models.dart';

DateTime? _time(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

String? _str(Object? v) => v == null ? null : '$v';

double? _numOrNull(Object? v) => v is num ? v.toDouble() : (v == null ? null : double.tryParse('$v'));

/// Stock level on the wire (`in | low | out`), as an [ItemStatus].
ItemStatus stockLevelFromWire(String? v) => switch (v) {
  'low' => ItemStatus.low,
  'out' => ItemStatus.out,
  _ => ItemStatus.inStock,
};

/// Staple categories used to group S15 (wire keys).
abstract final class StockCategory {
  static const anaaj = 'anaaj';
  static const dal = 'dal';
  static const masale = 'masale';
  static const sabzi = 'sabzi';
  static const dairy = 'dairy';
  static const telGhee = 'tel_ghee';
  static const dryFruits = 'dry_fruits';
  static const other = 'other';

  static const order = [sabzi, dairy, dal, anaaj, masale, telGhee, dryFruits, other];
}

/// `StockItem {ingredient_id, name, name_hi, level, qty?, unit?,
/// low_threshold?, updated_at, updated_by}` (+ `category`).
@immutable
class StockItem {
  const StockItem({
    required this.ingredientId,
    required this.name,
    this.nameHi = '',
    required this.level,
    this.qty,
    this.unit,
    this.lowThreshold,
    this.updatedAt,
    this.updatedBy,
    this.category = StockCategory.other,
  });

  final String ingredientId;
  final String name;
  final String nameHi;

  /// in / low / out (never [ItemStatus.untracked]).
  final ItemStatus level;
  final double? qty;
  final String? unit;
  final double? lowThreshold;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String category;

  /// Hindi name when present (cook mode), else [name].
  String nameFor({required bool hindi}) => hindi && nameHi.isNotEmpty ? nameHi : name;

  factory StockItem.fromJson(Json j) {
    final by = j['updated_by'];
    return StockItem(
      ingredientId: '${j['ingredient_id']}',
      name: j['name'] as String? ?? '',
      nameHi: j['name_hi'] as String? ?? '',
      level: stockLevelFromWire(j['level'] as String?),
      qty: _numOrNull(j['qty']),
      unit: _str(j['unit']),
      lowThreshold: _numOrNull(j['low_threshold']),
      updatedAt: _time(j['updated_at']),
      updatedBy: by is Map ? _str(by['name'] ?? by['id']) : _str(by),
      category: j['category'] as String? ?? StockCategory.other,
    );
  }

  Json toJson() => {
    'ingredient_id': ingredientId,
    'name': name,
    'name_hi': nameHi,
    'level': level.wire,
    'qty': qty,
    'unit': unit,
    'low_threshold': lowThreshold,
    'updated_at': updatedAt == null ? null : wireDateTime(updatedAt!),
    'updated_by': updatedBy,
    'category': category,
  };

  StockItem copyWith({ItemStatus? level, double? qty, DateTime? updatedAt, String? updatedBy}) => StockItem(
    ingredientId: ingredientId,
    name: name,
    nameHi: nameHi,
    level: level ?? this.level,
    qty: qty ?? this.qty,
    unit: unit,
    lowThreshold: lowThreshold,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
    category: category,
  );
}

enum RationStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  bought('bought');

  const RationStatus(this.wire);
  final String wire;

  static RationStatus fromWire(String? v) => values.firstWhere((s) => s.wire == v, orElse: () => pending);
}

/// One line of a ration request. [ingredientId] is null for a free-text item.
@immutable
class RationItem {
  const RationItem({this.ingredientId, required this.name, this.qty, this.unit, this.note});

  final String? ingredientId;
  final String name;
  final double? qty;
  final String? unit;
  final String? note;

  factory RationItem.fromJson(Json j) => RationItem(
    ingredientId: _str(j['ingredient_id']),
    name: j['name'] as String? ?? '',
    qty: _numOrNull(j['qty']),
    unit: _str(j['unit']),
    note: _str(j['note']),
  );

  Json toJson() => {'ingredient_id': ingredientId, 'name': name, 'qty': ?qty, 'unit': ?unit, 'note': ?note};
}

/// `RationRequest {id, ticket_id?, items, status, raised_by, decided_by?,
/// decided_at?, note?, created_at}`.
@immutable
class RationRequest {
  const RationRequest({
    required this.id,
    this.ticketId,
    this.items = const [],
    required this.status,
    this.raisedBy = '',
    this.decidedBy,
    this.decidedAt,
    this.note,
    this.createdAt,
  });

  final String id;
  final String? ticketId;
  final List<RationItem> items;
  final RationStatus status;
  final String raisedBy;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? note;
  final DateTime? createdAt;

  factory RationRequest.fromJson(Json j) {
    String? who(Object? v) => v is Map ? _str(v['name'] ?? v['id']) : _str(v);
    return RationRequest(
      id: '${j['id']}',
      ticketId: _str(j['ticket_id']),
      items: [
        for (final i in (j['items'] as List? ?? const [])) RationItem.fromJson((i as Map).cast<String, dynamic>()),
      ],
      status: RationStatus.fromWire(j['status'] as String?),
      raisedBy: who(j['raised_by']) ?? '',
      decidedBy: who(j['decided_by']),
      decidedAt: _time(j['decided_at']),
      note: _str(j['note']),
      createdAt: _time(j['created_at']),
    );
  }
}

enum ApprovalType {
  swap('swap'),
  changeDish('change_dish'),
  ration('ration');

  const ApprovalType(this.wire);
  final String wire;

  static ApprovalType fromWire(String? v) => values.firstWhere((s) => s.wire == v, orElse: () => swap);
}

/// Decision values for approvals and ration requests.
abstract final class Decision {
  static const approved = 'approved';
  static const rejected = 'rejected';

  /// Written by the 30-min timeout (demo; the server leaves it pending).
  static const expired = 'expired';
}

/// `Approval {id, ticket_id, type, requested_by, decided_by?, decision?,
/// decided_at?, auto, expires_at}` (+ optional `detail`: what is asked).
@immutable
class Approval {
  const Approval({
    required this.id,
    this.ticketId,
    required this.type,
    this.requestedBy = '',
    this.decidedBy,
    this.decision,
    this.decidedAt,
    this.auto = false,
    this.expiresAt,
    this.detail = '',
  });

  final String id;
  final String? ticketId;
  final ApprovalType type;
  final String requestedBy;
  final String? decidedBy;
  final String? decision;
  final DateTime? decidedAt;
  final bool auto;
  final DateTime? expiresAt;
  final String detail;

  bool get pending => decision == null;

  bool expiredAt(DateTime now) => expiresAt != null && now.isAfter(expiresAt!);

  factory Approval.fromJson(Json j) {
    String? who(Object? v) => v is Map ? _str(v['name'] ?? v['id']) : _str(v);
    return Approval(
      id: '${j['id']}',
      ticketId: _str(j['ticket_id']),
      type: ApprovalType.fromWire(j['type'] as String?),
      requestedBy: who(j['requested_by']) ?? '',
      decidedBy: who(j['decided_by']),
      decision: _str(j['decision']),
      decidedAt: _time(j['decided_at']),
      auto: j['auto'] as bool? ?? false,
      expiresAt: _time(j['expires_at']),
      detail: j['detail'] as String? ?? '',
    );
  }

  Approval decide(String decision, String by, DateTime at) => Approval(
    id: id,
    ticketId: ticketId,
    type: type,
    requestedBy: requestedBy,
    decidedBy: by,
    decision: decision,
    decidedAt: at,
    auto: auto,
    expiresAt: expiresAt,
    detail: detail,
  );
}
