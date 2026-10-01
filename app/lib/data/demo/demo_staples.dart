// Demo pantry: the tracked staples behind the 22 seed recipes' ingredient
// lines, their starting levels, and the curated substitution rules
// (F-5.9-01: swaps come only from SubstitutionRule; the engine re-checks).
import 'package:flutter/foundation.dart';

@immutable
class DemoStaple {
  const DemoStaple(
    this.id,
    this.name,
    this.nameHi,
    this.category,
    this.keywords, {
    this.level = 'in',
    this.optional = false,
    this.perishable = false,
  });

  final String id;
  final String name;
  final String nameHi;
  final String category;

  /// Lower-case words matched (whole-word) against ingredient lines.
  final List<String> keywords;

  /// Starting level: `in` / `low` / `out`.
  final String level;

  /// A garnish / optional line: the dish can be made without it (ladder step 1).
  final bool optional;

  /// Drops in → low on ticket completion when auto-decrement is on.
  final bool perishable;
}

const List<DemoStaple> demoStaples = [
  // Sabzi
  DemoStaple('pyaaz', 'Pyaaz', 'प्याज़', 'sabzi', ['pyaaz'], perishable: true),
  DemoStaple('tamatar', 'Tamatar', 'टमाटर', 'sabzi', ['tamatar'], perishable: true),
  DemoStaple('aloo', 'Aloo', 'आलू', 'sabzi', ['aloo']),
  DemoStaple('adrak', 'Adrak', 'अदरक', 'sabzi', ['adrak'], perishable: true),
  DemoStaple('lahsun', 'Lahsun', 'लहसुन', 'sabzi', ['lahsun']),
  DemoStaple('hari_mirch', 'Hari mirch', 'हरी मिर्च', 'sabzi', ['hari mirch'], optional: true, perishable: true),
  DemoStaple('dhaniya', 'Dhaniya patta', 'धनिया', 'sabzi', ['dhaniya'], optional: true, perishable: true),
  DemoStaple('kadi_patta', 'Kadi patta', 'कड़ी पत्ता', 'sabzi', ['kadi patta'], level: 'low', optional: true),
  DemoStaple('nimbu', 'Nimbu', 'नींबू', 'sabzi', ['nimbu'], optional: true, perishable: true),
  DemoStaple('lauki', 'Lauki', 'लौकी', 'sabzi', ['lauki'], perishable: true),
  DemoStaple('bhindi', 'Bhindi', 'भिंडी', 'sabzi', ['bhindi'], perishable: true),
  DemoStaple('palak', 'Palak', 'पालक', 'sabzi', ['palak'], perishable: true),
  // Doodh-dahi
  DemoStaple('dahi', 'Dahi', 'दही', 'dairy', ['dahi'], level: 'low', perishable: true),
  DemoStaple('paneer', 'Paneer', 'पनीर', 'dairy', ['paneer'], level: 'out', perishable: true),
  DemoStaple('doodh', 'Doodh', 'दूध', 'dairy', ['doodh', 'milk'], perishable: true),
  DemoStaple('makhan', 'Makhan', 'मक्खन', 'dairy', ['makhan']),
  DemoStaple('malai', 'Malai', 'मलाई', 'dairy', ['malai'], optional: true, perishable: true),
  DemoStaple('ghee', 'Ghee', 'घी', 'tel_ghee', ['ghee'], level: 'low'),
  DemoStaple('tel', 'Tel', 'तेल', 'tel_ghee', ['tel']),
  // Dal
  DemoStaple('toor_dal', 'Toor dal', 'तूर दाल', 'dal', ['toor']),
  DemoStaple('moong_dal', 'Moong dal', 'मूंग दाल', 'dal', ['moong']),
  DemoStaple('chana_dal', 'Chana dal', 'चना दाल', 'dal', ['chana dal']),
  DemoStaple('masoor_dal', 'Masoor dal', 'मसूर दाल', 'dal', ['masoor']),
  DemoStaple('urad_dal', 'Urad dal', 'उड़द दाल', 'dal', ['urad']),
  DemoStaple('rajma', 'Rajma', 'राजमा', 'dal', ['rajma']),
  // Anaaj
  DemoStaple('atta', 'Aata', 'आटा', 'anaaj', ['aata', 'atta']),
  DemoStaple('chawal', 'Chawal', 'चावल', 'anaaj', ['chawal']),
  DemoStaple('poha', 'Poha', 'पोहा', 'anaaj', ['poha']),
  DemoStaple('sooji', 'Sooji', 'सूजी', 'anaaj', ['sooji']),
  DemoStaple('besan', 'Besan', 'बेसन', 'anaaj', ['besan'], level: 'low'),
  // Masale
  DemoStaple('haldi', 'Haldi', 'हल्दी', 'masale', ['haldi']),
  DemoStaple('jeera', 'Jeera', 'जीरा', 'masale', ['jeera']),
  DemoStaple('laal_mirch', 'Laal mirch', 'लाल मिर्च', 'masale', ['laal mirch']),
  DemoStaple('hing', 'Hing', 'हींग', 'masale', ['hing']),
  DemoStaple('rai', 'Rai', 'राई', 'masale', ['rai']),
  DemoStaple('ajwain', 'Ajwain', 'अजवाइन', 'masale', ['ajwain'], optional: true),
  DemoStaple('garam_masala', 'Garam masala', 'गरम मसाला', 'masale', ['garam masala']),
  DemoStaple('amchur', 'Amchur', 'अमचूर', 'masale', ['amchur'], level: 'low'),
  DemoStaple('kasuri_methi', 'Kasuri methi', 'कसूरी मेथी', 'masale', ['kasuri methi'], optional: true),
  DemoStaple('methi_dana', 'Methi dana', 'मेथी दाना', 'masale', ['methi dana']),
  DemoStaple('sambar_masala', 'Sambar masala', 'सांभर मसाला', 'masale', ['sambar masala']),
  // Dry fruits & others
  DemoStaple('moongphali', 'Moongphali', 'मूंगफली', 'dry_fruits', ['moongphali'], optional: true),
  DemoStaple('kaju', 'Kaju', 'काजू', 'dry_fruits', ['kaju'], level: 'low'),
  DemoStaple('imli', 'Imli', 'इमली', 'other', ['imli']),
  DemoStaple('ande', 'Ande', 'अंडे', 'other', ['ande', 'anda']),
];

/// `SubstitutionRule {from_ingredient_id, to_ingredient_id, ratio, note_hi}`.
/// [needs] are the staples the swap uses (all must be in stock); [text] is
/// what replaces the ingredient line for the engine re-check.
@immutable
class DemoSubstitution {
  const DemoSubstitution(this.from, this.to, this.name, this.ratio, this.noteHi, {required this.needs, String? text})
    : text = text ?? name;

  final String from;
  final String to;
  final String name;
  final String ratio;
  final String noteHi;
  final List<String> needs;
  final String text;
}

const List<DemoSubstitution> demoSubstitutions = [
  DemoSubstitution(
    'dahi',
    'doodh',
    'Doodh + nimbu',
    '1 cup dahi = 1 cup doodh + 1 bada chammach nimbu',
    'दूध में नींबू डालकर 10 मिनट रखो, फिर डालो',
    needs: ['doodh', 'nimbu'],
    text: 'Doodh + nimbu',
  ),
  DemoSubstitution(
    'paneer',
    'chhena',
    'Chhena (doodh se)',
    '250g paneer = 1 litre doodh ka chhena',
    'दूध फाड़कर छेना बनाओ, कपड़े में निचोड़ो',
    needs: ['doodh', 'nimbu'],
    text: 'Chhena (doodh)',
  ),
  DemoSubstitution('paneer', 'tofu', 'Tofu', '1:1', 'टोफू के टुकड़े हल्के सेंककर डालो', needs: [], text: 'Tofu (soya)'),
  DemoSubstitution('moongphali', 'kaju', 'Kaju', '1:1', 'मूंगफली की जगह थोड़े काजू भूनकर डालो', needs: ['kaju']),
  DemoSubstitution(
    'pyaaz',
    'hing',
    'Hing + patta gobhi (bina pyaaz)',
    '1 pyaaz = chutki hing',
    'प्याज़ की जगह चुटकी भर हींग, जैन के लिए भी ठीक',
    needs: ['hing'],
    text: 'Hing',
  ),
  DemoSubstitution(
    'tamatar',
    'amchur',
    'Amchur',
    '2 tamatar = 1 chhota chammach amchur',
    'खट्टापन के लिए अमचूर डालो',
    needs: ['amchur'],
  ),
  DemoSubstitution('ghee', 'makhan', 'Makhan', '1:1', 'घी की जगह मक्खन', needs: ['makhan']),
  DemoSubstitution('makhan', 'ghee', 'Ghee', '1:1', 'मक्खन की जगह घी', needs: ['ghee']),
  DemoSubstitution(
    'malai',
    'doodh',
    'Doodh + makhan',
    '2 bada chammach malai = 3 bada chammach doodh + 1 chhota chammach makhan',
    'मलाई की जगह गाढ़ा दूध',
    needs: ['doodh', 'makhan'],
  ),
  DemoSubstitution(
    'nimbu',
    'amchur',
    'Amchur',
    '1 nimbu = 1 chhota chammach amchur',
    'नींबू की जगह अमचूर',
    needs: ['amchur'],
  ),
  DemoSubstitution(
    'hari_mirch',
    'laal_mirch',
    'Laal mirch',
    '2 hari mirch = 1/2 chhota chammach laal mirch',
    'हरी मिर्च की जगह लाल मिर्च',
    needs: ['laal_mirch'],
  ),
  DemoSubstitution(
    'toor_dal',
    'masoor_dal',
    'Masoor dal',
    '1:1',
    'तूर की जगह मसूर दाल, जल्दी पकती है',
    needs: ['masoor_dal'],
  ),
  DemoSubstitution('kaju', 'moongphali', 'Moongphali', '1:1', 'काजू की जगह मूंगफली', needs: ['moongphali']),
  DemoSubstitution('besan', 'atta', 'Aata', '1 cup besan = 3/4 cup aata', 'बेसन की जगह थोड़ा आटा', needs: ['atta']),
];
