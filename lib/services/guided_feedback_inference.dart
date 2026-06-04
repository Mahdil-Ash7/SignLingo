// lib/services/guided_feedback_engine.dart
// ==========================================
// Guided mode evaluation engine for BIM sign language learning.
//
// CLASSES:
//   DetailedGuidedResult   — evaluation result per frame (scores + feedback)
//   DetailedFeedbackEngine — computes finger/pose/face scores against reference
//   SignProfile            — per-sign reference template, weights, hints
//   SignProfileService     — loads sign_profiles.json from assets
//
// DEPENDS ON:
//   lib/services/on_device_inference.dart  (kHandFeatures, kFaceFeatures,
//                                           kPoseFeatures, normalizeKeypoints)
//
// ASSET PATH:
//   assets/models/sign_profiles.json

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'on_device_inference.dart' show
    kHandFeatures, kFaceFeatures, kPoseFeatures;

// ─────────────────────────────────────────────────────────────────────────────
// DETAILED GUIDED RESULT
// ─────────────────────────────────────────────────────────────────────────────
class DetailedGuidedResult {
  final double overallScore;
  final double handScore;
  final double faceScore;
  final double poseScore;

  /// Individual finger scores — purely curl + tip height, no spread blended in.
  /// Keys: thumb / index / middle / ring / pinky
  final Map<String, double> leftFingers;
  final Map<String, double> rightFingers;

  /// Spread scores stored separately so one bad finger cannot contaminate others.
  /// 1.0 = fingers correctly spaced, 0.0 = wrong spread.
  final double leftSpreadScore;
  final double rightSpreadScore;

  final Map<String, double> faceZones;   // mouth / lips / left eye / right eye / brows
  final Map<String, double> poseJoints;  // left shoulder / elbow / wrist etc.

  final String feedback;
  final bool   passed;
  final String scoreLabel;

  const DetailedGuidedResult({
    required this.overallScore,   required this.handScore,
    required this.faceScore,      required this.poseScore,
    required this.leftFingers,    required this.rightFingers,
    required this.faceZones,      required this.poseJoints,
    required this.feedback,       required this.passed,
    required this.scoreLabel,
    this.leftSpreadScore  = 1.0,
    this.rightSpreadScore = 1.0,
  });

  static DetailedGuidedResult empty() => const DetailedGuidedResult(
    overallScore: 0, handScore: 0, faceScore: 0, poseScore: 0,
    leftFingers: {}, rightFingers: {}, faceZones: {}, poseJoints: {},
    feedback: 'Position yourself in front of the camera',
    passed: false, scoreLabel: '',
    leftSpreadScore: 1.0, rightSpreadScore: 1.0,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// DETAILED FEEDBACK ENGINE
// ─────────────────────────────────────────────────────────────────────────────
// MediaPipe hand landmark indices per finger [MCP, PIP, DIP, TIP]:
//   Wrist : 0
//   Thumb : [1,  2,  3,  4]
//   Index : [5,  6,  7,  8]
//   Middle: [9,  10, 11, 12]
//   Ring  : [13, 14, 15, 16]
//   Pinky : [17, 18, 19, 20]
//
// Face zone mapping (indices into SELECTED_FACE_IDX list):
//   mouth:[0,1]  lips:[2..5]  left eye:[6,7]  right eye:[8,9]
//   left brow:[10..14]  right brow:[15..19]
//
// Pose slot mapping (POSE_IDX = [11,13,15,12,14,16]):
//   slot 0=L.shoulder  1=L.elbow  2=L.wrist
//   slot 3=R.shoulder  4=R.elbow  5=R.wrist
// ─────────────────────────────────────────────────────────────────────────────
class DetailedFeedbackEngine {

  static const _fingerLM = {
    'thumb' : [1,  2,  3,  4],
    'index' : [5,  6,  7,  8],
    'middle': [9,  10, 11, 12],
    'ring'  : [13, 14, 15, 16],
    'pinky' : [17, 18, 19, 20],
  };

  static const _faceZones = {
    'mouth'     : [0, 1],
    'lips'      : [2, 3, 4, 5],
    'left eye'  : [6, 7],
    'right eye' : [8, 9],
    'left brow' : [10, 11, 12, 13, 14],
    'right brow': [15, 16, 17, 18, 19],
  };

  static const _poseSlots = {
    'left shoulder' : 0, 'left elbow'    : 1, 'left wrist'    : 2,
    'right shoulder': 3, 'right elbow'   : 4, 'right wrist'   : 5,
  };

  // ── Landmark helpers ────────────────────────────────────────────────────
  static List<double> _lm(List<double> kp, int base, int idx) {
    final off = base + idx * 3;
    return [kp[off], kp[off + 1]];
  }

  // Finger curl: angle at PIP joint → 0.0 (straight) to 1.0 (fully curled)
  static double _fingerCurl(List<double> kp, int base, List<int> lms) {
    final mcp = _lm(kp, base, lms[0]);
    final pip = _lm(kp, base, lms[1]);
    final dip = _lm(kp, base, lms[2]);
    if ((mcp[0] == 0 && mcp[1] == 0) ||
        (pip[0] == 0 && pip[1] == 0) ||
        (dip[0] == 0 && dip[1] == 0)) return -1.0;
    final v1   = [mcp[0] - pip[0], mcp[1] - pip[1]];
    final v2   = [dip[0] - pip[0], dip[1] - pip[1]];
    final dot  = v1[0]*v2[0] + v1[1]*v2[1];
    final mag1 = sqrt(v1[0]*v1[0] + v1[1]*v1[1]);
    final mag2 = sqrt(v2[0]*v2[0] + v2[1]*v2[1]);
    if (mag1 < 1e-6 || mag2 < 1e-6) return 0.0;
    final cosA = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    return ((1.0 + cosA) / 2.0).clamp(0.0, 1.0);
  }

  static double _tipHeight(List<double> kp, int base, List<int> lms) {
    final mcp = _lm(kp, base, lms[0]);
    final tip = _lm(kp, base, lms[3]);
    if (mcp[0] == 0 && mcp[1] == 0) return 0.0;
    if (tip[0] == 0 && tip[1] == 0) return 0.0;
    return mcp[1] - tip[1];
  }

  // Pure individual finger score — curl + tip height only, no spread
  static double _fingerSim(
      List<double> sKp, int stuBase,
      List<double> rKp, int refBase,
      List<int> lms) {
    final sC = _fingerCurl(sKp, stuBase, lms);
    final rC = _fingerCurl(rKp, refBase, lms);
    if (sC < 0 || rC < 0) return 1.0;

    double curlDiff = (sC - rC).abs();

    if (curlDiff < 0.05) curlDiff = 0;  // golden zone — tiny differences ignored
    final curlSim = (1.0 - pow(curlDiff, 1.2) * 1.5).clamp(0.0, 1.0);

    final sH = _tipHeight(sKp, stuBase, lms);
    final rH = _tipHeight(rKp, refBase, lms);
    double hDiff = (sH - rH).abs();
    if (hDiff < 0.04) hDiff = 0;
    final hSim = (1.0 - hDiff * 2.5).clamp(0.0, 1.0);

    return (0.8 * curlSim + 0.2 * hSim).clamp(0.0, 1.0);
  }

  // Individual finger scores — spread NOT blended in, kept separate
  static Map<String, double> _scoreFingers(
      List<double> sKp, int stuBase,
      List<double> rKp, int refBase) {
    return {
      for (final e in _fingerLM.entries)
        e.key: _fingerSim(sKp, stuBase, rKp, refBase, e.value)
    };
  }

  // ── Spread scoring (scale-normalised, survives keypoint normalisation) ──
  static double _handScale(List<double> kp, int base) {
    final wx = kp[base],          wy = kp[base + 1];
    final mx = kp[base + 12 * 3], my = kp[base + 12 * 3 + 1];
    if (wx == 0 && wy == 0) return 1.0;
    if (mx == 0 && my == 0) return 1.0;
    final d = sqrt(pow(mx - wx, 2) + pow(my - wy, 2));
    return d > 0 ? d : 1.0;
  }

  static double _fingerSpreadScore(
      List<double> sKp, int stuBase,
      List<double> rKp, int refBase) {
    final sScale = _handScale(sKp, stuBase);
    final rScale = _handScale(rKp, refBase);
    const tipIndices = [8, 12, 16, 20];
    double totalSim = 0.0; int count = 0;

    for (int i = 0; i < tipIndices.length - 1; i++) {
      final tipA = tipIndices[i], tipB = tipIndices[i + 1];
      final sAx = sKp[stuBase + tipA * 3], sAy = sKp[stuBase + tipA * 3 + 1];
      final sBx = sKp[stuBase + tipB * 3], sBy = sKp[stuBase + tipB * 3 + 1];
      final rAx = rKp[refBase + tipA * 3], rAy = rKp[refBase + tipA * 3 + 1];
      final rBx = rKp[refBase + tipB * 3], rBy = rKp[refBase + tipB * 3 + 1];
      if ((sAx == 0 && sAy == 0) || (sBx == 0 && sBy == 0)) continue;
      if ((rAx == 0 && rAy == 0) || (rBx == 0 && rBy == 0)) continue;
      final sDistNorm = sqrt(pow(sBx - sAx, 2) + pow(sBy - sAy, 2)) / sScale;
      final rDistNorm = sqrt(pow(rBx - rAx, 2) + pow(rBy - rAy, 2)) / rScale;
      final sim = (1.0 - (sDistNorm - rDistNorm).abs() * 2.0).clamp(0.0, 1.0);
      totalSim += sim; count++;
    }
    return count > 0 ? totalSim / count : 1.0;
  }

  static double _averageAdjacentSpread(List<double> kp, int base) {
    final wx    = kp[base], wy = kp[base + 1];
    final mx    = kp[base + 12 * 3], my = kp[base + 12 * 3 + 1];
    final scale = sqrt(pow(mx - wx, 2) + pow(my - wy, 2));
    if (scale < 1e-6) return 0.0;
    const tips = [8, 12, 16, 20];
    double total = 0.0; int count = 0;
    for (int i = 0; i < tips.length - 1; i++) {
      final ax = kp[base + tips[i] * 3],     ay = kp[base + tips[i] * 3 + 1];
      final bx = kp[base + tips[i+1] * 3],   by = kp[base + tips[i+1] * 3 + 1];
      if ((ax == 0 && ay == 0) || (bx == 0 && by == 0)) continue;
      total += sqrt(pow(bx - ax, 2) + pow(by - ay, 2)) / scale;
      count++;
    }
    return count > 0 ? total / count : 0.0;
  }

  // Add this helper to DetailedFeedbackEngine:
  static double _thumbTipGapScore(
      List<double> sKp, int stuBase,
      List<double> rKp, int refBase) {
    // Distance between thumb tip (idx 4) and index tip (idx 8)
    // This catches the O vs C distinction — O has them touching, C has a gap
    final sTx = sKp[stuBase + 4 * 3],     sTy = sKp[stuBase + 4 * 3 + 1];
    final sIx = sKp[stuBase + 8 * 3],     sIy = sKp[stuBase + 8 * 3 + 1];
    final rTx = rKp[refBase + 4 * 3],     rTy = rKp[refBase + 4 * 3 + 1];
    final rIx = rKp[refBase + 8 * 3],     rIy = rKp[refBase + 8 * 3 + 1];

    if ((sTx == 0 && sTy == 0) || (sIx == 0 && sIy == 0)) return 1.0;
    if ((rTx == 0 && rTy == 0) || (rIx == 0 && rIy == 0)) return 1.0;

    // Scale by hand size
    final scale = _handScale(sKp, stuBase);

    final sDist = sqrt(pow(sIx - sTx, 2) + pow(sIy - sTy, 2)) / scale;
    final rDist = sqrt(pow(rIx - rTx, 2) + pow(rIy - rTy, 2)) / scale;

    final diff = (sDist - rDist).abs();
    return (1.0 - diff * 4.0).clamp(0.0, 1.0);
  }
  // ── Face zones ───────────────────────────────────────────────────────────
  static Map<String, double> _scoreFaceZones(List<double> sKp, List<double> rKp) {
    const base = kHandFeatures;
    return {
      for (final e in _faceZones.entries)
        e.key: () {
          double total = 0.0; int count = 0;
          for (final idx in e.value) {
            final off = base + idx * 3;
            final rx = rKp[off], ry = rKp[off + 1];
            if (rx == 0 && ry == 0) continue;
            final dx = sKp[off] - rx, dy = sKp[off + 1] - ry;
            total += (1.0 - sqrt(dx*dx + dy*dy) * 5.0).clamp(0.0, 1.0);
            count++;
          }
          return count > 0 ? total / count : 1.0;
        }()
    };
  }

  // ── Pose joints ──────────────────────────────────────────────────────────
  static Map<String, double> _scorePoseJoints(List<double> sKp, List<double> rKp) {
    const base = kHandFeatures + kFaceFeatures;
    return {
      for (final e in _poseSlots.entries)
        e.key: () {
          final off = base + e.value * 3;
          final rx = rKp[off], ry = rKp[off + 1];
          if (rx == 0 && ry == 0) return 1.0;
          final dx = sKp[off] - rx, dy = sKp[off + 1] - ry;
          return (1.0 - sqrt(dx*dx + dy*dy) * 4.0).clamp(0.0, 1.0);
        }()
    };
  }

  // ── Main evaluation entry point ──────────────────────────────────────────
    static DetailedGuidedResult evaluate(
      List<double> sKp, List<double> rKp,
      Map<String, double> weights, Map<String, String> hints,
      {bool isDynamic = false}) {

    //------------------ STATIC CHECKING ----------------
    final lA = !(sKp[0]  == 0 && sKp[1]  == 0);  // student left slot
    final rA = !(sKp[63] == 0 && sKp[64] == 0);  // student right slot
    final lR = !(rKp[0]  == 0 && rKp[1]  == 0);  // reference left slot
    final rR = !(rKp[63] == 0 && rKp[64] == 0);  // reference right slot

    Map<String, double> lF = {};
    Map<String, double> rF = {};
    double lSpread = 1.0, rSpread = 1.0;
    bool   handMissing = false;

    if (lR && rR) {
      // ── TWO-HANDED SIGN: both slots must be present ──────────────────────
      if (lA && rA) {
        lF      = _scoreFingers(sKp, 0,  rKp, 0);
        rF      = _scoreFingers(sKp, 63, rKp, 63);
        lSpread = _fingerSpreadScore(sKp, 0,  rKp, 0);
        rSpread = _fingerSpreadScore(sKp, 63, rKp, 63);

        // Thumb-tip gap blend for O/C discrimination — both hands
        if (lF.containsKey('thumb') || lF.containsKey('index')) {
          final gap = _thumbTipGapScore(sKp, 0, rKp, 0);
          lF = Map.from(lF);
          lF['thumb'] = ((lF['thumb'] ?? 1.0) * 0.6 + gap * 0.4).clamp(0.0, 1.0);
        }
        if (rF.containsKey('thumb') || rF.containsKey('index')) {
          final gap = _thumbTipGapScore(sKp, 63, rKp, 63);
          rF = Map.from(rF);
          rF['thumb'] = ((rF['thumb'] ?? 1.0) * 0.6 + gap * 0.4).clamp(0.0, 1.0);
        }
      } else {
        handMissing = true;
      }

    } else if (lR || rR) {
      // ── SINGLE-HANDED SIGN: accept whichever hand the student raised ──────
      // The reference may have the shape in slot 0 or slot 63 depending on
      // how data was collected. The student may use either physical hand.
      // We compare the student's active hand shape against the reference shape
      // regardless of which slot each occupies. This makes guided mode robust
      // to mirror inconsistencies and works for both left and right-handed users.

      final refBase = lR ? 0 : 63;  // which slot has the reference shape

      if (!lA && !rA) {
        // No hand visible at all
        handMissing = true;
      } else {
        // Pick the student's active hand. If both hands are raised,
        // prefer the one that matches the reference slot — this avoids
        // accidentally comparing the wrong hand when both are briefly visible.
        final int stuBase;
        if (lA && rA) {
          stuBase = refBase;  // both raised → use same slot as reference
        } else {
          stuBase = lA ? 0 : 63;  // only one raised → use that one
        }

        // Score student's active hand against reference shape
        if (stuBase == 0) {
          lF      = _scoreFingers(sKp, stuBase, rKp, refBase);
          lSpread = _fingerSpreadScore(sKp, stuBase, rKp, refBase);

          // Thumb-tip gap blend for O/C discrimination
          if (lF.containsKey('thumb') || lF.containsKey('index')) {
            final gap = _thumbTipGapScore(sKp, stuBase, rKp, refBase);
            lF = Map.from(lF);
            lF['thumb'] = ((lF['thumb'] ?? 1.0) * 0.6 + gap * 0.4).clamp(0.0, 1.0);
          }
        } else {
          rF      = _scoreFingers(sKp, stuBase, rKp, refBase);
          rSpread = _fingerSpreadScore(sKp, stuBase, rKp, refBase);

          // Thumb-tip gap blend for O/C discrimination
          if (rF.containsKey('thumb') || rF.containsKey('index')) {
            final gap = _thumbTipGapScore(sKp, stuBase, rKp, refBase);
            rF = Map.from(rF);
            rF['thumb'] = ((rF['thumb'] ?? 1.0) * 0.6 + gap * 0.4).clamp(0.0, 1.0);
          }
        }
      }
    }

    final fZ = weights['face']! > 0.05 ? _scoreFaceZones(sKp, rKp)  : <String, double>{};
    final pJ = weights['pose']! > 0.05 ? _scorePoseJoints(sKp, rKp) : <String, double>{};

    // Helper
    double avgOf(Iterable<double> v) =>
        v.isEmpty ? 1.0 : v.reduce((a, b) => a + b) / v.length;

    final fS = avgOf(fZ.values);
    final pS = avgOf(pJ.values);

    final fingerAvg = avgOf([...lF.values, ...rF.values]);

    final spreadAvg = avgOf([
      if (lF.isNotEmpty) lSpread,
      if (rF.isNotEmpty) rSpread,
    ]);

    // Hand score: 75% individual finger accuracy + 25% spread accuracy
    final hS = handMissing
        ? 0.0
        : (0.75 * fingerAvg + 0.25 * spreadAvg);

    final overall = handMissing
        ? 0.0
        : (weights['hand']! * hS + weights['face']! * fS + weights['pose']! * pS)
            .clamp(0.0, 1.0);

    final fb = _priorityFeedback(
      weights: weights, hS: hS, fS: fS, pS: pS,
      lF: lF, rF: rF, fZ: fZ, pJ: pJ,
      lA: lA, rA: rA, lR: lR, rR: rR, isDynamic: isDynamic,
      sKp: sKp, rKp: rKp, hints: hints,
    );

    debugPrint("[Overall]: $overall");
    return DetailedGuidedResult(
      overallScore: overall, handScore: hS, faceScore: fS, poseScore: pS,
      leftFingers: lF, rightFingers: rF,
      faceZones: fZ, poseJoints: pJ,
      feedback: fb,
      passed: overall >= 0.70,
      scoreLabel: _scoreLabel(overall),
      leftSpreadScore:  lSpread,
      rightSpreadScore: rSpread,
    );
  }
  // In DetailedFeedbackEngine — new method:
static DetailedGuidedResult evaluateDynamic(
    List<double> sKp, List<double> rKp,
    Map<String, double> weights, Map<String, String> hints) {

  final lA = !(sKp[0]  == 0 && sKp[1]  == 0);
  final rA = !(sKp[63] == 0 && sKp[64] == 0);
  final lR = !(rKp[0]  == 0 && rKp[1]  == 0);
  final rR = !(rKp[63] == 0 && rKp[64] == 0);

  // ── STRICT HAND MATCHING ────────────────────────────────────────────────
  // The student must raise the SAME hand(s) as shown in the reference.
  // Raising the wrong hand is an immediate fail with a specific message.
  bool correctHandPresent;
  String? wrongHandMessage;

  if (lR && rR) {
    // Two-handed sign — both must be present
    correctHandPresent = lA && rA;
    if (!correctHandPresent) wrongHandMessage = 'Raise both hands for this sign';
  } else if (rR) {
    // Right-hand sign — must use right hand specifically
    correctHandPresent = rA;
    if (!correctHandPresent) {
      wrongHandMessage = lA
          ? 'Use your right hand — this sign is performed with the right hand'
          : 'Raise your right hand to perform this sign';
    }
  } else if (lR) {
    // Left-hand sign — must use left hand specifically
    correctHandPresent = lA;
    if (!correctHandPresent) {
      wrongHandMessage = rA
          ? 'Use your left hand — this sign is performed with the left hand'
          : 'Raise your left hand to perform this sign';
    }
  } else {
    // No hand in reference — any hand is fine
    correctHandPresent = lA || rA;
    wrongHandMessage   = correctHandPresent ? null : 'Raise your hand to perform the sign';
  }

  if (!correctHandPresent) {
    return DetailedGuidedResult(
      overallScore: 0, handScore: 0, faceScore: 1.0, poseScore: 1.0,
      leftFingers: {}, rightFingers: {}, faceZones: {}, poseJoints: {},
      feedback: wrongHandMessage ?? 'Raise the correct hand',
      passed: false, scoreLabel: 'Try again',
    );
  }

  // ── POSE CHECK (only if pose matters for this sign) ─────────────────────
  final pJ = weights['pose']! > 0.05
      ? _scorePoseJoints(sKp, rKp)
      : <String, double>{};
  double avgOf(Iterable<double> v) =>
      v.isEmpty ? 1.0 : v.reduce((a, b) => a + b) / v.length;
  final pS = avgOf(pJ.values);

  // ── OVERALL ─────────────────────────────────────────────────────────────
  // For dynamic signs with no pose weight: just being present with the
  // correct hand is NOT enough to pass. We require minimum confidence.
  // Use a simple "motion quality" proxy: the student must have been
  // moving — we check pose arm position as a proxy.
  // If pose weight = 0, fall back to a fixed moderate score (0.70)
  // so the student cannot trivially pass by just holding up a hand.
  final baseScore = weights['pose']! > 0.05 ? pS : 0.75;
  final overall   = baseScore.clamp(0.0, 1.0);

  final String feedback;
  if (overall < 0.60) {
    feedback = hints['general'] ?? 'Perform the full sign movement from start to finish';
  } else {
    feedback = '';
  }

  debugPrint("[Overall]: $overall");
  return DetailedGuidedResult(
    overallScore: overall,
    handScore: 1.0,  // correct hand is present
    faceScore: 1.0,
    poseScore: pS,
    leftFingers: {}, rightFingers: {},
    faceZones: {}, poseJoints: pJ,
    feedback: feedback,
    //Pass Score
    passed: overall >= 0.95,
    scoreLabel: overall >= 0.60 ? 'Good motion!' : 'Try again',
  );
}

  // ── Priority feedback ────────────────────────────────────────────────────
    static String _priorityFeedback({
      required Map<String, double> weights,
      required double hS, fS, pS,
      required Map<String, double> lF, rF, fZ, pJ,
      required bool lA, rA, lR, rR, isDynamic,
      required List<double> sKp, required List<double> rKp,
      required Map<String, String> hints,
    }) {
      // Hand presence check
      if (lR && rR) {
        // Two-handed sign — both must be visible
        if (!lA || !rA) return 'Raise both hands for this sign';
      } else if (lR || rR) {
        // Single-handed sign — any hand is accepted
        if (!lA && !rA) return 'Raise your hand';
        // Do NOT tell the user which hand to use
      }

      final rs = <String, double>{};
      if (weights['hand']! > 0.05) rs['hand'] = hS;
      if (weights['face']! > 0.05) rs['face'] = fS;
      if (weights['pose']! > 0.05) rs['pose'] = pS;
      if (rs.isEmpty) return '';

      final sorted = rs.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
      final worst  = sorted.first.key;
      final ws     = sorted.first.value;
      if (ws > 0.85) return '';

      switch (worst) {
        case 'hand':
          if (isDynamic) return 'Keep your hand movement smooth and consistent';
          return _handFeedback(lF, rF, lR, rR, lA, rA, sKp, rKp, hints);
        case 'face': return _faceFeedback(fZ);
        case 'pose': return _poseFeedback(pJ);
        default:     return 'Adjust your technique';
      }
    }

    static String _handFeedback(
        Map<String, double> lF, Map<String, double> rF,
        bool lR, bool rR, bool lA, bool rA,
        List<double> studentKp, List<double> refKp,
        Map<String, String> hints) {

      // Presence check — no side-specific message for single-handed signs
      if (lR && rR) {
        if (!lA || !rA) return 'Raise both hands for this sign';
      } else if (lR || rR) {
        if (!lA && !rA) return 'Raise your hand to perform the sign';
      }

      final allScores = [...lF.values, ...rF.values];
      final avgScore  = allScores.isEmpty
          ? 1.0
          : allScores.reduce((a, b) => a + b) / allScores.length;

      // General hint when overall hand score is poor
      if (avgScore < 0.70 && hints.containsKey('general')) {
        return hints['general']!;
      }

      // Determine which bases to use for spread and finger checks
      // For single-handed signs, use whichever hand was actually scored
      final int stuBase = lF.isNotEmpty ? 0 : 63;
      final int refBase = lR ? 0 : 63;

      // Spread check — before individual finger feedback
      final spread = lF.isNotEmpty
          ? _fingerSpreadScore(studentKp, stuBase, refKp, refBase)
          : _fingerSpreadScore(studentKp, stuBase, refKp, refBase);

      if (spread < 0.50) {
        print ("SpreadSCORE: ${spread}");
        final sSpread = _averageAdjacentSpread(studentKp, stuBase);
        final rSpread = _averageAdjacentSpread(refKp, refBase);
        return sSpread > rSpread
            ? 'Press your fingers closer together — they should be touching'
            : 'Spread your fingers apart more — they are too close together';
      }

      // Find worst individual finger across whichever hand was scored
      String? worst; double worstS = 1.0; bool isLeft = false;
      void check(Map<String, double> f, bool left) {
        for (final e in f.entries) {
          if (e.value < worstS) { worstS = e.value; worst = e.key; isLeft = left; }
        }
      }
      check(lF, true); check(rF, false);
      if (worst == null || worstS > 0.78) return 'Fine-tune your overall hand shape';

      // Finger-specific hint
      if (hints.containsKey(worst)) return hints[worst]!;

      // Use the correct bases for geometric instruction
      final instructStuBase = isLeft ? 0 : 63;
      final instructRefBase = refBase;
      final handName = 'your';  // avoid "left"/"right" — both hands are accepted
      return _fingerInstruction(
          worst!, handName, worstS, studentKp, instructStuBase, refKp, instructRefBase);
    }
  static String _fingerInstruction(
      String finger, String handName, double score,
      List<double> studentKp, int stuBase,
      List<double> refKp,     int refBase) {

    final lms         = _fingerLM[finger]!;
    final studentCurl = _fingerCurl(studentKp, stuBase, lms);
    final refCurl     = _fingerCurl(refKp,     refBase, lms);

    if (studentCurl < 0 || refCurl < 0) {
      return '${_severity(score)} your $handName $finger finger';
    }

    final diff      = studentCurl - refCurl;
    final direction = diff > 0.30  ? 'Straighten'
                    : diff < -0.32 ? 'Curl'
                    : 'Fine-tune';
    final severity  = score < 0.40 ? 'completely'
                    : score < 0.60 ? 'significantly'
                    : 'slightly';
    return '$direction your $handName $finger finger $severity';
  }

  static String _severity(double score) =>
      score < 0.40 ? 'Completely change'
      : score < 0.60 ? 'Significantly adjust'
      : 'Slightly adjust';

  static String _faceFeedback(Map<String, double> fZ) {
    if (fZ.isEmpty) return '';
    final sorted = fZ.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final worst  = sorted.first.key;
    final s      = sorted.first.value;
    if (s > 0.80) return 'Fine-tune your facial expression slightly';
    final sev = s < 0.50 ? 'Change' : s < 0.65 ? 'Adjust' : 'Fine-tune';
    return switch (worst) {
      'mouth'      => '$sev your mouth — open, closed, rounded, or relaxed as the sign requires',
      'lips'       => '$sev your lip shape — the sign requires a specific lip position',
      'left brow'  => '$sev your left eyebrow — raise, lower, or furrow it as the sign requires',
      'right brow' => '$sev your right eyebrow — raise, lower, or furrow it as the sign requires',
      'left eye'   => '$sev your left eye expression — wider open or slightly narrowed',
      'right eye'  => '$sev your right eye expression — wider open or slightly narrowed',
      _            => '$sev your facial expression',
    };
  }

  static String _poseFeedback(Map<String, double> pJ) {
    if (pJ.isEmpty) return '';
    final sorted = pJ.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final worst  = sorted.first.key;
    final s      = sorted.first.value;
    if (s > 0.80) return 'Fine-tune your arm position slightly';
    final sev   = s < 0.50 ? 'Reposition' : s < 0.65 ? 'Adjust' : 'Fine-tune';
    final parts = worst.split(' ');
    final side  = parts[0], joint = parts[1];
    return switch (joint) {
      'shoulder' => '$sev your $side shoulder — your upper body angle needs adjustment',
      'elbow'    => '$sev your $side elbow angle — '
          '${s < 0.50 ? "your arm needs to be in a completely different position" : "raise or lower your forearm slightly"}',
      'wrist'    => '$sev your $side wrist height — '
          '${s < 0.50 ? "check the overall arm position" : "move your arm up or down slightly"}',
      _          => '$sev your $side arm position',
    };
  }

  static String _scoreLabel(double s) {
    if (s >= 0.90) return 'Perfect!';
    if (s >= 0.75) return 'Great!';
    if (s >= 0.65) return 'Good';
    return 'Try again';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIGN PROFILE
// ─────────────────────────────────────────────────────────────────────────────
class SignProfile {
  final String              label;
  final List<double>        reference;
  final Map<String, double> weights;
  final Map<String, double> variance;
  final Map<String, String> hints;
  final bool                isDynamic;

  final List<String> rejectIfSimilarTo; // new field
  final double rejectThreshold;          // new field — default 0.82

  static const double passThreshold   = 0.72;
  static const double activeThreshold = 0.10;

  const SignProfile({
    required this.label,     required this.reference,
    required this.weights,   required this.variance,
    required this.hints,     required this.isDynamic,
    required this.rejectIfSimilarTo, required this.rejectThreshold
  });

  factory SignProfile.fromJson(String label, Map<String, dynamic> json) {
    final w = (json['weights']  as Map<String, dynamic>? ?? {});
    final v = (json['variance'] as Map<String, dynamic>? ?? {});
    final h = (json['hints']    as Map<String, dynamic>? ?? {});
    return SignProfile(
      label    : label,
      reference: (json['reference'] as List).map((e) => (e as num).toDouble()).toList(),
      weights  : {
        'hand': (w['hand'] as num? ?? 1.0).toDouble(),
        'face': (w['face'] as num? ?? 0.0).toDouble(),
        'pose': (w['pose'] as num? ?? 0.0).toDouble(),
      },
      variance : {
        'hand': (v['hand'] as num? ?? 0.5).toDouble(),
        'face': (v['face'] as num? ?? 0.5).toDouble(),
        'pose': (v['pose'] as num? ?? 0.5).toDouble(),
      },
      isDynamic: (json['is_dynamic'] as bool? ?? false),
      hints    : h.map((k, v) => MapEntry(k, v.toString())),
      rejectIfSimilarTo: (json['reject_if_similar_to'] as List? ?? []).map((e) => e.toString()).toList(),
      rejectThreshold: (json['reject_threshold'] as num? ?? 0.82).toDouble(),
    );
  }

  List<String> get activeRegions => ['hand', 'face', 'pose']
      .where((r) => (weights[r] ?? 0.0) > activeThreshold).toList();

  // In SignProfile:
  DetailedGuidedResult evaluate(List<double> kp) {
    if (isDynamic) {
      return DetailedFeedbackEngine.evaluateDynamic(kp, reference, weights, hints);
    }
    return DetailedFeedbackEngine.evaluate(kp, reference, weights, hints);
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// SIGN PROFILE SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class SignProfileService {
  Map<String, SignProfile> _profiles = {};
  bool _isLoaded = false;
  String? _currentCategory;

  bool         get isLoaded  => _isLoaded;
  int          get count     => _profiles.length;
  List<String> get allLabels => _profiles.keys.toList()..sort();
  String?      get currentCategory => _currentCategory;

Future<bool> load({int? categoryId, String? categoryName}) async {
    try {
      String assetPath;
      
      if (categoryId == null && categoryName == null) {
        // Load default profiles
        assetPath = 'assets/models/sign_profiles.json';
        _currentCategory = null;
        debugPrint('[profiles] loading default sign_profiles.json...');
      } else {
        // Load category-specific profiles
        // You can use either categoryId or categoryName for the path
        final pathComponent = categoryName;
        assetPath = 'assets/models/categories/$pathComponent/sign_profiles.json';
        _currentCategory = categoryName ;
        debugPrint('[profiles] loading category-specific profiles from $assetPath...');
        debugPrint('$_currentCategory');
      }
 
      final raw  = await rootBundle.loadString(assetPath);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _profiles  = data.map((label, profile) => MapEntry(
          label,
          SignProfile.fromJson(label, profile as Map<String, dynamic>)));
      _isLoaded  = true;
      debugPrint('[profiles] ${_profiles.length} profiles loaded from category: $_currentCategory');
      for (final e in _profiles.entries) {
        final w = e.value.weights;
        debugPrint('   ${e.key.padRight(20)} '
            'hand=${w["hand"]!.toStringAsFixed(2)} '
            'face=${w["face"]!.toStringAsFixed(2)} '
            'pose=${w["pose"]!.toStringAsFixed(2)} '
            '| active: ${e.value.activeRegions.join(", ")} '
            '| dynamic: ${e.value.isDynamic}');
      }
      return true;
    } catch (e) {
      debugPrint('[profiles] load failed: $e');
      _isLoaded = false;
      return false;
    }
  }

   bool isRejectedByConfusable(String targetSign, List<double> studentKp) {
    final target = _profiles[targetSign];
    if (target == null) return false;

    for (final confusableLabel in target.rejectIfSimilarTo) {
      final confusable = _profiles[confusableLabel];
      if (confusable == null) continue;

      // Score student kp against the CONFUSABLE sign's reference
      final confusableResult = DetailedFeedbackEngine.evaluate(
        studentKp,
        confusable.reference,
        confusable.weights,
        confusable.hints,
      );

      // If student matches the confusable sign well → reject the pass
      debugPrint("Confuse: ${confusableResult.overallScore}");
      if (confusableResult.overallScore >= target.rejectThreshold) {
        return true;
      }
    }
    return false;
  }

  /// Clear loaded profiles and reset state
  void clear() {
    _profiles.clear();
    _isLoaded = false;
    _currentCategory = null;
  }

  SignProfile? getProfile(String label) => _profiles[label];
  bool hasProfile(String label)         => _profiles.containsKey(label);
}