// lib/services/homonym_resolver.dart
// =====================================
// Context-aware homonym resolution for signs that are physically identical.
//
// PROBLEM:
//   Some BIM signs share the same handshape and can only be distinguished
//   by context — e.g. W and 6, D and 1, B and 4, 2 and V.
//   The model cannot distinguish these from keypoints alone.
//
// SOLUTION:
//   1. GUIDED MODE  — knows the target sign, so accepts any homonym of the
//      target as a correct answer. If target is W and model outputs 6, pass.
//
//   2. LIVE TEST    — no context, so output BOTH signs when a homonym is
//      detected. "W / 6" displayed instead of just one prediction.
//
// USAGE:
//   // Guided mode — check if prediction counts as correct for target:
//   HomonymResolver.isCorrectForTarget(predicted: '6', target: 'W') → true
//
//   // Live test — get display label including homonym if applicable:
//   HomonymResolver.getDisplayLabel('W') → 'W / 6'
//   HomonymResolver.getDisplayLabel('A') → 'A'  (no homonym)

class HomonymResolver {

  // ── Homonym groups ────────────────────────────────────────────────────────
  // Each inner set contains signs that are physically identical in BIM.
  // Add more groups as you discover them during testing.
  //
  // Sources of homonyms:
  //   - Number/letter overlap: same handshape used in different categories
  //   - Dialectal variation: some BIM signs have alternate forms
  static const List<Set<String>> _kHomonymGroups = [

    // Numbers ↔ Alphabet overlap
    {'W', '6'},

    // These may or may not be identical in your BIM dataset —
    // comment out any that your model can actually distinguish:
    {'2', 'V'},    // V = large spread, 2 = tighter — may be distinguishable
    // {'C', '0'}, // uncomment if confirmed
  ];

  // ── Precomputed lookup: sign → its homonym group ──────────────────────────
  // Built once at class load time for O(1) lookup.
  static final Map<String, Set<String>> _signToGroup = () {
    final map = <String, Set<String>>{};
    for (final group in _kHomonymGroups) {
      for (final sign in group) {
        map[sign] = group;
      }
    }
    return map;
  }();

  // ─────────────────────────────────────────────────────────────────────────
  // isCorrectForTarget
  //
  // Used in GUIDED MODE and QUIZ MODE.
  // Returns true if the predicted sign should count as correct for the target.
  //
  // Cases:
  //   predicted == target         → true  (direct match, normal case)
  //   predicted is homonym of target → true  (accept the alias)
  //   otherwise                   → false
  //
  // Example:
  //   target = 'W', predicted = '6' → true  (6 is a homonym of W)
  //   target = 'W', predicted = 'A' → false (different sign)
  //   target = 'A', predicted = 'A' → true  (direct match)
  // ─────────────────────────────────────────────────────────────────────────
  static bool isCorrectForTarget({
    required String predicted,
    required String target,
  }) {
    if (predicted == target) return true;

    final group = _signToGroup[target];
    if (group == null) return false;

    return group.contains(predicted);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // getDisplayLabel
  //
  // Used in LIVE TEST.
  // Returns a display string that shows both signs when a homonym is detected.
  //
  // Example:
  //   'W'  → 'W / 6'
  //   '6'  → 'W / 6'   (same group, same display)
  //   'A'  → 'A'        (no homonym)
  //   '2'  → '2 / V'
  // ─────────────────────────────────────────────────────────────────────────
  static String getDisplayLabel(String sign) {
    final group = _signToGroup[sign];
    if (group == null || group.length <= 1) return sign;

    // Sort the group so display is always consistent regardless of which
    // sign the model happened to output (W/6 not 6/W depending on prediction)
    final sorted = group.toList()..sort();

    // Put the predicted sign first so it is visually prominent
    if (sorted.first != sign) {
      sorted.remove(sign);
      sorted.insert(0, sign);
    }

    return sorted.join(' / ');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // getHomonymGroup
  //
  // Returns all signs in the same homonym group as the given sign,
  // or null if the sign has no homonyms.
  // ─────────────────────────────────────────────────────────────────────────
  static Set<String>? getHomonymGroup(String sign) {
    return _signToGroup[sign];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // hasHomonym
  //
  // Quick check — does this sign have any homonyms?
  // ─────────────────────────────────────────────────────────────────────────
  static bool hasHomonym(String sign) {
    final group = _signToGroup[sign];
    return group != null && group.length > 1;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // isHomonymOf
  //
  // Returns true if signA and signB are in the same homonym group.
  // ─────────────────────────────────────────────────────────────────────────
  static bool isHomonymOf(String signA, String signB) {
    if (signA == signB) return false;
    final group = _signToGroup[signA];
    return group != null && group.contains(signB);
  }
}