// Demo household from design/prototype_logic.js (state.members and POOL).
import 'package:flutter/painting.dart';

import '../../features/members/domain/member.dart';

const List<Member> demoMembers = [
  Member(
    id: 'm1',
    name: 'Papa',
    color: Color(0xFF2F5FC4),
    diet: Diet.veg,
    spice: Spice.medium,
    needs: [Need.lowSugar, Need.lowOil],
    cuisines: [Cuisine.northIndian, Cuisine.rajasthani],
    // The fictional demo family opted in, matching the prototype's header.
    showOnHome: true,
  ),
  Member(
    id: 'm2',
    name: 'Mummy',
    color: Color(0xFFB8386A),
    diet: Diet.veg,
    spice: Spice.medium,
    needs: [Need.highProtein],
    cuisines: [Cuisine.gujarati, Cuisine.northIndian],
  ),
  Member(
    id: 'm3',
    name: 'Dadi',
    color: Color(0xFF7549BF),
    diet: Diet.jain,
    spice: Spice.kam,
    needs: [Need.lowOil],
    cuisines: [Cuisine.rajasthani, Cuisine.gujarati],
  ),
  Member(
    id: 'm4',
    name: 'Daughter',
    color: Color(0xFFB85A0C),
    diet: Diet.egg,
    spice: Spice.kam,
    needs: [Need.kidFriendly],
    isKid: true,
    cuisines: [Cuisine.indoChinese, Cuisine.southIndian],
    showOnHome: true,
  ),
  Member(
    id: 'm5',
    name: 'Wife',
    color: Color(0xFF0E7C3A),
    diet: Diet.nonveg,
    spice: Spice.teekha,
    needs: [Need.highProtein],
    cuisines: [Cuisine.bengali, Cuisine.southIndian],
  ),
];

/// Names and colours handed out, in order, by "Member jodo".
const List<MemberTemplate> demoMemberPool = [
  MemberTemplate('Chachu', Color(0xFF1F6F8B)),
  MemberTemplate('Bua', Color(0xFF9A4A1E)),
  MemberTemplate('Nani', Color(0xFF5B5BD6)),
  MemberTemplate('Ramesh bhaiya', Color(0xFF4A6A1E)),
];
