// Servings scaling for the Detail screen (F-5.5-01, F-5.5-05).
//
// Seed recipes store ingredients as display text ("Chana dal 1/2 cup"), so
// the scaling rule per ingredient is a heuristic on that text:
// - fixed: whistle ("seeti") counts — never scaled;
// - sublinear: salt, chilli, spices, oil, ghee, butter — ×0.75 per doubling
//   relative to linear (2× servings → 1.5×, the build-plan's test gate);
// - linear: everything else.
// The backend's Ingredient.scaling_rule replaces the heuristic in API mode.
import 'dart:math' as math;

import '../../members/domain/member.dart';

enum ScalingRule { linear, sublinear, fixed }

const _fixedWords = ['seeti', 'whistle'];

const _sublinearWords = [
  'namak',
  'salt',
  'mirch',
  'chilli',
  'haldi',
  'jeera',
  'hing',
  'masala',
  'rai',
  'ajwain',
  'amchur',
  'kasuri methi',
  'methi dana',
  'panch phoron',
  'dhaniya powder',
  'tel',
  'oil',
  'ghee',
  'makhan',
  'butter',
];

/// Vegetables whose names contain a spice word ("Shimla mirch" is capsicum).
const _linearExceptions = ['shimla mirch'];

ScalingRule scalingRuleFor(String ingredient) {
  final t = ingredient.toLowerCase();
  if (_fixedWords.any(t.contains)) return ScalingRule.fixed;
  if (_linearExceptions.any(t.contains)) return ScalingRule.linear;
  if (_sublinearWords.any((w) => RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(t))) return ScalingRule.sublinear;
  return ScalingRule.linear;
}

/// Multiplier for [rule] when servings change by [factor] (new / base).
double ruleFactor(ScalingRule rule, double factor) => switch (rule) {
  ScalingRule.linear => factor,
  // factor^log2(1.5): each doubling multiplies by 1.5 (= 2 × 0.75).
  ScalingRule.sublinear => math.pow(factor, math.log(1.5) / math.ln2).toDouble(),
  ScalingRule.fixed => 1,
};

/// A quantity found in ingredient text.
class ParsedQty {
  const ParsedQty(this.start, this.end, this.value, this.unit);

  /// Character range of the number + unit in the source text.
  final int start;
  final int end;
  final double value;
  final String? unit;
}

final _qtyRe = RegExp(
  r'(\d+\s*/\s*\d+|\d+(?:\.\d+)?)(?:\s*(kg|gm|g|ml|l|cups?|tsp|tbsp|gaddi|pcs|seeti))?(?![\w/])',
  caseSensitive: false,
);

/// First quantity in [text], or null ("Moongphali", "Haldi").
ParsedQty? parseQty(String text) {
  final m = _qtyRe.firstMatch(text);
  if (m == null) return null;
  final raw = m.group(1)!;
  double value;
  if (raw.contains('/')) {
    final parts = raw.split('/').map((s) => double.parse(s.trim())).toList();
    if (parts[1] == 0) return null;
    value = parts[0] / parts[1];
  } else {
    value = double.parse(raw);
  }
  return ParsedQty(m.start, m.end, value, m.group(2)?.toLowerCase());
}

/// Rounds [v] to a kitchen-friendly step for [unit].
double roundForUnit(double v, String? unit) {
  final step = switch (unit) {
    'g' || 'gm' || 'ml' => v >= 100 ? 10.0 : 5.0,
    'kg' || 'l' => 0.05,
    'cup' || 'cups' || 'tsp' || 'tbsp' => 0.25,
    _ => 0.5, // counts: pyaaz 1, ande 3, gaddi
  };
  final r = (v / step).round() * step;
  return r <= 0 ? step : r;
}

/// "1¼", "½", "3", "0.35".
String formatQty(double v) {
  final whole = v.floor();
  final frac = v - whole;
  const glyphs = [(0.25, '¼'), (0.5, '½'), (0.75, '¾')];
  for (final (f, g) in glyphs) {
    if ((frac - f).abs() < 0.001) return whole == 0 ? g : '$whole$g';
  }
  if (frac.abs() < 0.001) return '$whole';
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// [text] with its quantity scaled from [base] to [servings] servings.
/// Text without a quantity, and fixed-rule text, is returned unchanged.
String scaleIngredientText(String text, {required int base, required int servings}) {
  if (base <= 0 || servings == base) return text;
  final q = parseQty(text);
  if (q == null) return text;
  final rule = scalingRuleFor(text);
  if (rule == ScalingRule.fixed) return text;
  final v = roundForUnit(q.value * ruleFactor(rule, servings / base), q.unit);
  final unit = q.unit == null
      ? ''
      : (q.unit == 'g' || q.unit == 'gm' || q.unit == 'kg' || q.unit == 'ml' ? q.unit! : ' ${q.unit}');
  return text.replaceRange(q.start, q.end, '${formatQty(v)}$unit');
}

/// Default servings for the household: adults 1.0, kids 0.5, rounded up.
int defaultServings(List<Member> members) {
  final total = members.fold<double>(0, (s, m) => s + (m.isKid ? 0.5 : 1.0));
  return math.max(1, total.ceil());
}

/// Big-batch hint: more than twice the recipe's base servings.
bool isBatchWarning({required int base, required int servings}) => servings > base * 2;
