// Parity between the Dart demo reply (lib/features/chat/data/
// demo_chat_repository.dart, ranked by the Dart engine) and a verbatim port
// of the prototype's reply() / fitFor / summarize / ranked / constraintLine
// that reads its recipes straight from design/prototype_logic.js.
import 'dart:io';

import 'package:banega/core/l10n/gen/app_localizations_hi.dart';
import 'package:banega/data/demo/demo_members.dart';
import 'package:banega/data/demo/demo_recipes.dart';
import 'package:banega/features/chat/data/demo_chat_repository.dart';
import 'package:banega/features/chat/presentation/chat_labels.dart';
import 'package:banega/features/recipe/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------- the port

class PR {
  PR(this.id, this.name, this.mins, this.meals, this.diet, this.jain, this.spice, this.tags, this.cuisine);
  final String id, name, meals, diet, cuisine;
  final int mins, spice;
  final bool jain;
  final List<String> tags;
}

class PM {
  const PM(this.name, this.diet, this.spice, this.needs, this.cuisines);
  final String name, diet, spice;
  final List<String> needs, cuisines;
}

/// `state.members` from the prototype.
const protoMembers = [
  PM('Papa', 'Veg', 'Medium', ['Low sugar', 'Low oil'], ['North Indian', 'Rajasthani']),
  PM('Mummy', 'Veg', 'Medium', ['High protein'], ['Gujarati', 'North Indian']),
  PM('Dadi', 'Jain', 'Kam', ['Low oil'], ['Rajasthani', 'Gujarati']),
  PM('Daughter', 'Egg', 'Kam', ['Kid-friendly'], ['Indo-Chinese', 'South Indian']),
  PM('Wife', 'Non-veg', 'Teekha', ['High protein'], ['Bengali', 'South Indian']),
];

List<PR> loadProtoRecipes() {
  final src = File('../design/prototype_logic.js').readAsStringSync();
  final re = RegExp(
    r"R\('([^']*)','([^']*)','[^']*',(\d+),'([^']*)','([^']*)',(true|false),(\d+),\[([^\]]*)\],'([^']*)'",
  );
  return [
    for (final m in re.allMatches(src))
      PR(m[1]!, m[2]!, int.parse(m[3]!), m[4]!, m[5]!, m[6] == 'true', int.parse(m[7]!), [
        for (final t in m[8]!.split(',')) t.trim().replaceAll("'", ''),
      ], m[9]!),
  ];
}

String fitForS(PM m, PR r) {
  if (m.diet == 'Jain' && !r.jain) return 'no';
  if (m.diet == 'Veg' && r.diet != 'veg') return 'no';
  if (m.diet == 'Egg' && r.diet == 'nonveg') return 'no';
  if (m.needs.contains('No maida') && r.tags.contains('maida')) return 'no';
  final tw = <String>[];
  if (m.spice == 'Kam' && r.spice == 3) tw.add('x');
  if (m.spice == 'Teekha' && r.spice == 1) tw.add('x');
  if (m.needs.contains('Low sugar') && !r.tags.contains('lowSugar')) tw.add('x');
  if (m.needs.contains('Low oil') && !r.tags.contains('lowOil')) tw.add('x');
  if (m.needs.contains('High protein') && !r.tags.contains('protein')) tw.add('x');
  if (m.needs.contains('Kid-friendly') && !r.tags.contains('kid') && r.spice > 1) tw.add('x');
  if (tw.isNotEmpty) return 'tweak';
  return 'fit';
}

({int can, int score}) summarizeP(List<PM> ms, PR r) {
  var can = 0, perfect = 0, like = 0, nos = 0;
  for (final m in ms) {
    final f = fitForS(m, r);
    if (f != 'no') {
      can++;
    } else {
      nos++;
    }
    if (f == 'fit') perfect++;
    if (m.cuisines.contains(r.cuisine)) like++;
  }
  return (can: can, score: can * 10 + perfect * 3 + like * 2 - (nos > 0 ? 15 : 0));
}

/// JS Array.prototype.sort is stable: insertion sort keeps that.
List<(PR, ({int can, int score}))> rankedP(List<PM> ms, List<PR> list) {
  final out = <(PR, ({int can, int score}))>[];
  for (final r in list) {
    final e = (r, summarizeP(ms, r));
    var i = out.length;
    int cmp((PR, ({int can, int score})) a, (PR, ({int can, int score})) b) =>
        b.$2.score - a.$2.score != 0 ? b.$2.score - a.$2.score : a.$1.mins - b.$1.mins;
    while (i > 0 && cmp(out[i - 1], e) > 0) {
      i--;
    }
    out.insert(i, e);
  }
  return out;
}

String constraintLineP(List<PM> ms) {
  final bits = <String>[];
  for (final m in ms) {
    if (m.diet == 'Jain') bits.add('${m.name} (Jain)');
    if (m.needs.contains('Low sugar')) bits.add('${m.name} (low sugar)');
    if (m.spice == 'Kam' && m.needs.contains('Kid-friendly')) bits.add('${m.name} (kam mirch)');
  }
  return bits.isNotEmpty ? 'Dhyaan rakha: ${bits.take(3).join(' · ')}' : 'Sabki pasand dhyaan mein hai';
}

const slotLabels = {'b': 'Nashta', 'l': 'Lunch', 'd': 'Dinner'};

({String text, List<String> recipes, List<String> chips, String slot}) replyP(
  String q,
  String slot,
  List<PR> recipes,
  List<PM> ms,
) {
  final s = q.toLowerCase();
  var explicitSlot = false;
  final fs = <bool Function(PR)>[];
  final why = <String>[];
  if (RegExp('nashta|breakfast|subah').hasMatch(s)) {
    slot = 'b';
    explicitSlot = true;
  } else if (RegExp('lunch|dopahar').hasMatch(s)) {
    slot = 'l';
    explicitSlot = true;
  } else if (RegExp('dinner|raat').hasMatch(s)) {
    slot = 'd';
    explicitSlot = true;
  }
  void tag(String t, String w) {
    fs.add((r) => r.tags.contains(t));
    why.add(w);
  }

  if (RegExp('halka|light|bimaar|simple|hal?ka').hasMatch(s)) tag('light', 'halka');
  if (RegExp('protein|gym').hasMatch(s)) tag('protein', 'high protein');
  if (RegExp('guest|mehmaan|mehman|party|special').hasMatch(s)) tag('special', 'mehmaan-worthy');
  if (RegExp('baarish|barish|rain').hasMatch(s)) tag('rainy', 'baarish wala');
  if (RegExp('tiffin|bachch|kid|beti|daughter').hasMatch(s)) tag('kid', 'bachchon ko pasand');
  if (RegExp('jaldi|quick|fast|15|10 min|20 min').hasMatch(s)) {
    fs.add((r) => r.mins <= 20);
    why.add('20 min ke andar');
  }
  if (RegExp('paneer').hasMatch(s)) {
    fs.add((r) => RegExp('Paneer').hasMatch(r.name) || r.id == 'cheela');
    why.add('paneer wala');
  }
  const cmap = {
    'south': 'South Indian',
    'gujarat': 'Gujarati',
    'punjab': 'North Indian',
    'rajasthan': 'Rajasthani',
    'bengal': 'Bengali',
    'chinese': 'Indo-Chinese',
    'maharash': 'Maharashtrian',
  };
  for (final k in cmap.keys) {
    if (s.contains(k)) {
      fs.add((r) => r.cuisine == cmap[k]);
      why.add(cmap[k]!);
    }
  }
  PM? who;
  for (final m in ms) {
    if (s.contains(m.name.toLowerCase())) who = m;
  }
  if (who != null) {
    final w = who;
    fs.add((r) => fitForS(w, r) != 'no');
    why.add('${w.name} ke hisaab se');
  }
  var list = recipes.where((r) => fs.every((f) => f(r))).toList();
  final inSlot = list.where((r) => r.meals.contains(slot)).toList();
  if (explicitSlot || inSlot.length >= 2) list = inSlot;
  final label = slotLabels[slot]!;
  var top = rankedP(ms, list).take(4).toList();
  String text;
  if (top.isEmpty) {
    top = rankedP(ms, recipes.where((r) => r.meals.contains(slot)).toList()).take(4).toList();
    text = 'Is combo mein exact match nahi mila. $label ke liye ye sabse kareeb hain:';
  } else {
    final allOk = top.where((t) => t.$2.can == ms.length).length;
    text =
        '$label ke liye ${top.length} options${why.isNotEmpty ? ' — ${why.join(', ')}' : ''}.\n'
        '$allOk mein poora parivaar kha sakta hai. ${constraintLineP(ms)}.';
  }
  final follow = slot == 'b'
      ? ['Protein wala nashta', 'Daughter ka tiffin', 'Kuch South Indian']
      : ['Kuch halka', 'Baarish special', 'Paneer wala kuch', 'Dadi ke liye kya?'];
  return (text: text, recipes: [for (final t in top) t.$1.id], chips: follow, slot: slot);
}

// ---------------------------------------------------------------- the tests

void main() {
  final l = AppLocalizationsHiLatn();
  final protoRecipes = loadProtoRecipes();

  const quickAsks = [
    '15 min mein kuch',
    'Kuch halka',
    'Baarish special',
    'Daughter ka tiffin',
    'Mehmaan aa rahe hain',
    'High protein',
  ];
  const welcomeChips = ['Aaj lunch mein kya?', 'Kuch halka dinner', '15 min mein nashta', 'Mehmaan aa rahe hain'];
  const extra = [
    'Protein wala nashta',
    'Kuch South Indian',
    'Paneer wala kuch',
    'Dadi ke liye kya?',
    'Dadi ke liye Jain dinner',
    'baarish wala khaana',
    'gujarati jaldi nashta',
    'chinese mehmaan',
    'Wife ke liye bengali',
    'kuch bhi',
  ];
  const slots = {'b': Slot.breakfast, 'l': Slot.lunch, 'd': Slot.dinner};

  test('the prototype recipe table parses and matches the demo seed', () {
    expect(protoRecipes, hasLength(22));
    expect(protoRecipes.map((r) => r.id).toList(), demoRecipes.map((r) => r.id).toList());
  });

  for (final group in {'quick asks': quickAsks, 'welcome chips': welcomeChips, 'more intents': extra}.entries) {
    for (final q in group.value) {
      for (final slot in slots.entries) {
        test('${group.key}: "$q" from ${slot.value.name}', () {
          final proto = replyP(q, slot.key, protoRecipes, protoMembers);
          final dart = demoReply(q, slot: slot.value, members: demoMembers);
          expect(dart.top.map((t) => t.$1.id).toList(), proto.recipes, reason: 'recipe ids');
          expect(dart.slot, slots[proto.slot], reason: 'slot');
          expect(l.replyText(dart.text, memberCount: demoMembers.length), proto.text, reason: 'text');
          expect(l.chips(dart.chips), proto.chips, reason: 'follow-up chips');
        });
      }
    }
  }
}
