// lib/services/on_device_inference.dart
// =======================================
// General on-device BIM sign language inference pipeline.
//
// CLASSES:
//   SessionState              — motion detection, buffering
//   OnDeviceInferenceService  — TFLite model inference (general prediction)
//   OnDeviceKeypointService   — MediaPipe platform channel to Kotlin
//
// Guided-mode classes (DetailedFeedbackEngine, DetailedGuidedResult,
// SignProfile, SignProfileService) live in:
//   lib/services/guided_feedback_engine.dart
//
// ASSET PATHS:
//   assets/models/labels.json
//   assets/models/handface_pose_cnn_gru.tflite

import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS — must always match 02_train_model.py
// ─────────────────────────────────────────────────────────────────────────────
const int    kSequenceLength      = 8;
const int    kHandFeatures        = 126;
const int    kFaceFeatures        = 60;
const int    kPoseFeatures        = 6;
const int    kFeatureSize         = 192;
const double kMinNonzero          = 0.15;
const List<int> kStrides          = [1, 2];
const int    kRawBufferLen        = 8;

const double kConfThreshold       = 0.85;
const int    kSmoothingDynamic    = 3;
const int    kSmoothingStatic     = 1;

const double kStaticThreshold     = 0.006;
const double kDynamicThreshold    = 0.028;
const int    kStaticConfirmFrames = 1;
const int    kVelocityHistoryLen  = 4;

const int    kHandHistoryLen      = 10;
const double kRestingYThreshold   = 0.72;
const double kCenterTie           = 0.05;
const int    kMinFramesToStart    = 2;

// ─────────────────────────────────────────────────────────────────────────────
// REFRACTORY PERIOD CONFIG
//
// After a dynamic sign is accepted, static signs that share the same terminal
// handshape are suppressed for _kRefractoryMs milliseconds. This prevents
// the settling frames of a dynamic sign (e.g. the 5-shaped end of "15")
// from triggering a false static prediction (e.g. "5").
//
// _kTerminalLookalikes maps each dynamic sign to the set of static signs
// that look like its final held frame. Extend this as you discover new pairs
// during testing.
// ─────────────────────────────────────────────────────────────────────────────
const int _kRefractoryMs = 2000;

const Map<String, Set<String>> _kTerminalLookalikes = {
  '15': {'5', 'B'},
  '20': {'2', 'V', 'U'},
  '14': {'4'},
  '13': {'3', 'W', '6'},
  '12': {'2', 'V'},
  '11': {'1', 'D', 'G'},
  'J' : {'I'},
  'Z' : {'1', 'G', 'D'},
};

// ─────────────────────────────────────────────────────────────────────────────
// MOTION ONSET CONFIG
//
// A gesture's buffer is cleared the moment the hand starts moving so that
// settling frames from a previous sign never bleed into the next prediction.
// ─────────────────────────────────────────────────────────────────────────────
const double _kOnsetVelocityThreshold    = 0.015; // hand starts moving
const double _kSettlingVelocityThreshold = 0.005; // hand nearly stopped
const int    _kOnsetConfirmFrames        = 2;      // frames above onset before clearing

// ─────────────────────────────────────────────────────────────────────────────
// PREDICTION RESULT
// ─────────────────────────────────────────────────────────────────────────────
class PredictionResult {
  final String? sign;
  final double  confidence;
  final int     bufferSize;
  final bool    ready;
  final bool    dualHandDetected;
  final String  motionState;
  final double  velocity;
  final bool    userVisible;
  final String  visibilityReason;
  final double  processingMs;
  final Map<String, bool> landmarks;

  const PredictionResult({
    required this.sign,
    required this.confidence,
    required this.bufferSize,
    required this.ready,
    required this.dualHandDetected,
    required this.motionState,
    required this.velocity,
    required this.userVisible,
    required this.visibilityReason,
    required this.processingMs,
    required this.landmarks,
  });

  static PredictionResult empty() => const PredictionResult(
    sign: null, confidence: 0, bufferSize: 0, ready: false,
    dualHandDetected: false, motionState: 'static', velocity: 0,
    userVisible: false, visibilityReason: 'not started',
    processingMs: 0, landmarks: {},
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION STATE
// ─────────────────────────────────────────────────────────────────────────────
class SessionState {
  final Queue<List<double>> rawBuffer    = Queue();
  final Queue<int>          smoothBuffer = Queue();
  int _smoothMaxLen = kSmoothingStatic;

  final Queue<double> velocityHistory = Queue();
  List<double>?       prevWristPos;
  double?             prevSpread;
  int                 stillFrameCount = 0;
  String              motionState     = 'static';
  bool                arcStarted      = false;
  bool                bufferCleared   = false;
  final Queue<bool>   handHistory     = Queue();
  int                 accepted        = 0;
  int                 _dynamicFrameCount = 0;
  static const int    _kDynamicConfirmFrames = 2;

    // Add these fields:
  double _frameConsistency = 0.0;  // 1.0 = perfectly stable, 0.0 = wildly changing
  static const double _kTransitionThreshold = 0.06; // hand is reshaping
  static const double _kTransitionClearThreshold = 0.035; // hysteresis — must settle lower to clear

bool get isHandTransition => _frameConsistency > _kTransitionThreshold;

  // ── Motion onset tracking ──────────────────────────────────────────────────
  // Counts consecutive frames above _kOnsetVelocityThreshold. When this
  // reaches _kOnsetConfirmFrames we know a new gesture has genuinely started
  // and the buffer is cleared so settling frames from the previous sign
  // cannot contaminate this prediction.
  int  _onsetFrameCount   = 0;
  bool _onsetCleared      = false; // true once buffer was cleared for this arc

  // ── Refractory period ──────────────────────────────────────────────────────
  // After a dynamic sign is accepted, _lastDynamicSign holds its label and
  // _lastDynamicAcceptedAt records when. isSuppressedByRefractory() uses both
  // to decide whether a candidate static prediction should be suppressed.
  String?  _lastDynamicSign;
  DateTime _lastDynamicAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const int _kPostDynamicCooldownMs = 1000;
  DateTime _postDynamicCooldownEnd = DateTime.fromMillisecondsSinceEpoch(0);

  /// PREVENTS TRAILING POSES: 
  /// If true, the system is locked and will ignore all static frames 
  /// until a high-velocity movement is detected again.
  bool requireMotionReset = false;
  bool waitingForCompleteStop = false;

  // Exposed so processFrame can read it for settling condition
  int get smoothMaxLen => _smoothMaxLen;

  void reset() {
    rawBuffer.clear();     smoothBuffer.clear();
    velocityHistory.clear(); handHistory.clear();
    prevWristPos       = null;  prevSpread      = null;
    stillFrameCount    = 0;     motionState     = 'static';
    arcStarted         = false; bufferCleared   = false;
    accepted           = 0;     _dynamicFrameCount = 0;
    _smoothMaxLen      = kSmoothingStatic;
    _onsetFrameCount   = 0;
    _onsetCleared      = false;
    _lastDynamicSign   = null;
    _lastDynamicAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _postDynamicCooldownEnd = DateTime.fromMillisecondsSinceEpoch(0);
    _frameConsistency = 0.0;

  }

  bool get isDualHand {
    if (handHistory.isEmpty) return false;
    return handHistory.where((v) => v).length / handHistory.length >= 0.5;
  }

  void updateHandHistory(bool bothHands) {
    handHistory.addLast(bothHands);
    while (handHistory.length > kHandHistoryLen) handHistory.removeFirst();
  }

  // ── Refractory helpers ─────────────────────────────────────────────────────

  /// Returns true if [candidateSign] should be suppressed because a dynamic
  /// sign was recently accepted whose terminal frame looks the same.
  bool isSuppressedByRefractory(String candidateSign) {
    if (_lastDynamicSign == null) return false;
    final msSince = DateTime.now()
        .difference(_lastDynamicAcceptedAt)
        .inMilliseconds;
    if (msSince > _kRefractoryMs) return false;
    final suppressed = _kTerminalLookalikes[_lastDynamicSign!];
    final blocked = suppressed != null && suppressed.contains(candidateSign);
    if (blocked) {
      debugPrint(
        '[Refractory] Suppressing "$candidateSign" '
        '(terminal bleed from "$_lastDynamicSign", ${msSince}ms ago)',
      );
    }
    return blocked;
  }

  /// Call this immediately after a dynamic prediction is accepted so that
  /// the refractory window begins from the correct moment.
  void recordDynamicAccepted(String sign) {
    _lastDynamicSign       = sign;
    _lastDynamicAcceptedAt = DateTime.now();
    // NEW: start the cooldown window so static predictions are blocked
    _postDynamicCooldownEnd = DateTime.now()
        .add(const Duration(milliseconds: _kPostDynamicCooldownMs));
    debugPrint('[Refractory] Dynamic "$sign" accepted — '
        'static blocked for ${_kPostDynamicCooldownMs}ms');
  }

  // ── Motion onset helper ────────────────────────────────────────────────────

  /// Called from [updateMotion] when the rolling velocity average crosses
  /// the onset threshold for [_kOnsetConfirmFrames] consecutive frames.
  ///
  /// Clears the raw buffer so that any settling frames from the *previous*
  /// sign are evicted before the new gesture starts accumulating samples.
  /// The flag [_onsetCleared] ensures we only clear once per arc, not on
  /// every frame while the hand is moving.
  void _handleOnset() {
    if (_onsetCleared) return;
    _onsetCleared = true;
    rawBuffer.clear();
    smoothBuffer.clear();
    bufferCleared = false; // already done here; prevent double-clear below
    debugPrint('[Onset] Motion confirmed — buffer cleared for new gesture');
  }

  double updateMotion(List<double> kp) {
    const fingertipOffsets = [12, 24, 36, 48, 60];

    List<double>? wristXY(int base) {
      final x = kp[base], y = kp[base + 1];
      return (x == 0 && y == 0) ? null : [x, y];
    }

    double fingertipSpread(int base) {
      final tips = <List<double>>[];
      for (final off in fingertipOffsets) {
        final x = kp[base + off], y = kp[base + off + 1];
        if (x != 0 || y != 0) tips.add([x, y]);
      }
      if (tips.length < 2) return 0.0;
      double total = 0; int count = 0;
      for (int i = 0; i < tips.length; i++) {
        for (int j = i + 1; j < tips.length; j++) {
          final dx = tips[i][0] - tips[j][0], dy = tips[i][1] - tips[j][1];
          total += sqrt(dx * dx + dy * dy); count++;
        }
      }
      return count > 0 ? total / count : 0.0;
    }

    final rightWrist = wristXY(63);
    final leftWrist  = wristXY(0);
    List<double>? wrist; double spread;

    if (rightWrist != null) {
      wrist = rightWrist; spread = fingertipSpread(63);
    } else if (leftWrist != null) {
      wrist = leftWrist;  spread = fingertipSpread(0);
    } else {
      velocityHistory.addLast(0.0);
      while (velocityHistory.length > kVelocityHistoryLen) velocityHistory.removeFirst();
      _updateMotionState(0.0);
      return 0.0;
    }

    double wristVel = 0.0;
    if (prevWristPos != null) {
      wristVel = ((wrist[0] - prevWristPos![0]).abs() +
                  (wrist[1] - prevWristPos![1]).abs()) / 2;
    }
    prevWristPos = wrist;

    double spreadVel = 0.0;
    if (prevSpread != null) spreadVel = (spread - prevSpread!).abs();
    prevSpread = spread;

    final velocity = 0.6 * wristVel + 0.4 * spreadVel;
    velocityHistory.addLast(velocity);
    while (velocityHistory.length > kVelocityHistoryLen) velocityHistory.removeFirst();
    _updateMotionState(velocity);
    return velocity;
  }

void _updateMotionState(double velocity) {
    final avg = velocityHistory.isEmpty
        ? 0.0
        : velocityHistory.reduce((a, b) => a + b) / velocityHistory.length;
    final prev = motionState;

    // 1. CHECK FOR COMPLETE STOP
    if (avg < kStaticThreshold) {
      waitingForCompleteStop = false; // The hand has finally stopped! Shield off.
      
      _dynamicFrameCount = 0;
      _onsetFrameCount   = 0;  
      _onsetCleared      = false; 
      stillFrameCount++;
      
      if (arcStarted && stillFrameCount >= kStaticConfirmFrames) {
        motionState = 'settling';
        arcStarted  = false;
      } else if (!arcStarted) {
        motionState = 'static';
      }
      _smoothMaxLen = kSmoothingStatic;
    } 
    // 2. CHECK FOR MOVEMENT
    else {
      // A. Early warning onset (Unlocks the predictor)
      if (avg > _kOnsetVelocityThreshold && !waitingForCompleteStop) {
        _onsetFrameCount++;
        if (_onsetFrameCount >= _kOnsetConfirmFrames) {
          requireMotionReset = false; // Unlock! A genuine new movement started.
          _handleOnset();
        }
      } else {
        _onsetFrameCount = 0;
      }

      // B. Full dynamic confirmation
      if (avg > kDynamicThreshold) {
        _dynamicFrameCount++;
        if (_dynamicFrameCount >= _kDynamicConfirmFrames) {
          if (prev == 'static' || prev == 'settling') {
            if (!_onsetCleared) {
              bufferCleared = true;
              smoothBuffer.clear();
            }
            _smoothMaxLen = kSmoothingDynamic;
          }
          motionState     = 'dynamic';
          arcStarted      = true;
          stillFrameCount = 0;
          _smoothMaxLen   = kSmoothingDynamic;
        }
      } else {
        _dynamicFrameCount = 0;
      }
    }
  }

  int get weightedMajorityVote {
    if (smoothBuffer.isEmpty) return -1;
    final counts = <int, double>{};
    final list   = smoothBuffer.toList();
    for (int i = 0; i < list.length; i++) {
      final weight = 1.0 + (i / list.length);
      counts[list[i]] = (counts[list[i]] ?? 0.0) + weight;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

bool get shouldPredict {
    // ENFORCE THE LOCK: If a dynamic sign just finished, block all static
    // predictions until the user moves their hand again.
    if (motionState == 'static' && requireMotionReset) {
      return false;
    }

    // Suppress if hand is mid-transition
    if (motionState == 'static' && isHandTransition) {
      return false;
    }

if (motionState == 'settling') return true;
    
    if (motionState == 'static') {
      // if (rawBuffer.length >= kRawBufferLen) return true;
      // return stillFrameCount >= kStaticConfirmFrames;

      return rawBuffer.length >= kRawBufferLen;
    }
    return false;
  }

  void markSettlingDone() {
  motionState = 'static';
  stillFrameCount = 0;

  arcStarted = false;

  requireMotionReset = true;
  waitingForCompleteStop = true;

  rawBuffer.clear();     // ← evict all terminal handshape frames
  smoothBuffer.clear();  // ← reset smooth vote so old sign can't persist
  debugPrint('[Settling] Buffer evicted on settling→static transition');
}

// Add this method — call it inside pushRaw BEFORE adding the new frame:
void _updateConsistency(List<double> newFrame) {
  if (rawBuffer.length < 2) {
    _frameConsistency = 0.0;
    return;
  }
  
  final bufList = rawBuffer.toList();
  final compareStart = (bufList.length - 3).clamp(0, bufList.length - 1);
  
  double maxInstantDiff = 0.0;

  for (int i = compareStart; i < bufList.length; i++) {
    double maxJointDiff = 0.0;
    
    // Check only the hand features (indices 0 to 125)
    for (int j = 0; j < 126; j++) {
      // Ignore zeroed-out features from the resting/missing hand
      if (newFrame[j] != 0 && bufList[i][j] != 0) {
        double diff = (newFrame[j] - bufList[i][j]).abs();
        if (diff > maxJointDiff) {
          maxJointDiff = diff;
        }
      }
    }
    
    if (maxJointDiff > maxInstantDiff) {
      maxInstantDiff = maxJointDiff;
    }
  }
  
  // Exponential moving average — smooths out single noisy frames
  _frameConsistency = _frameConsistency * 0.5 + maxInstantDiff * 0.5;
  
  debugPrint('[Consistency] maxJointDiff=${_frameConsistency.toStringAsFixed(4)}');
}

  // In SessionState.pushRaw — replace current implementation:
void pushRaw(List<double> frame) {
  // Deduplication (keep as-is)
  if (rawBuffer.length >= kRawBufferLen && motionState == 'static') {
    final last = rawBuffer.last;
    double diff = 0;
    for (int i = 0; i < frame.length; i++) diff += (frame[i] - last[i]).abs();
    diff /= frame.length;
    //if (diff < 0.005) return;
  }

  // Update consistency BEFORE adding new frame
  _updateConsistency(frame);

  // If hand is actively reshaping, clear the buffer
  // so transition frames never reach the model
  if (motionState == 'static' && _frameConsistency > _kTransitionThreshold) {

    requireMotionReset = false;

    rawBuffer.clear();
    smoothBuffer.clear();
    debugPrint('[Transition] Hand reshaping — buffer cleared '
        '(consistency=${_frameConsistency.toStringAsFixed(4)})');
  }

  rawBuffer.addLast(frame);
  while (rawBuffer.length > kRawBufferLen) rawBuffer.removeFirst();
}

  void pushSmooth(int classIdx) {
    smoothBuffer.addLast(classIdx);
    while (smoothBuffer.length > _smoothMaxLen) smoothBuffer.removeFirst();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NORMALIZATION — identical to Python training code
// ─────────────────────────────────────────────────────────────────────────────
List<double> _normalizeHand(List<double> frame) {
  final f = List<double>.from(frame);
  final xs     = [for (int i = 0; i < f.length; i += 3) f[i]];
  final ys     = [for (int i = 1; i < f.length; i += 3) f[i]];
  final validX = xs.where((x) => x != 0).toList();
  if (validX.isEmpty) return f;
  final minX = validX.reduce(min), maxX = validX.reduce(max);
  final validY = ys.where((y) => y != 0).toList();
  final minY   = validY.isEmpty ? 0.0 : validY.reduce(min);
  final maxY   = validY.isEmpty ? 0.0 : validY.reduce(max);
  double scale = max(maxX - minX, maxY - minY);
  if (scale == 0) scale = 1;
  for (int i = 0; i < f.length; i += 3) {
    f[i]     = (f[i]     - minX) / scale;
    f[i + 1] = (f[i + 1] - minY) / scale;
  }
  return f;
}

List<double> _normalizeHandPair(List<double> h) => [
  ..._normalizeHand(h.sublist(0, 63)),
  ..._normalizeHand(h.sublist(63, 126)),
];

List<double> _normalizeFaceOrPose(List<double> frame) {
  final f = List<double>.from(frame);
  final xs     = [for (int i = 0; i < f.length; i += 3) f[i]];
  final ys     = [for (int i = 1; i < f.length; i += 3) f[i]];
  final validX = xs.where((x) => x != 0).toList();
  if (validX.isEmpty) return f;
  final cx = f[0], cy = f[1];
  final validY = ys.where((y) => y != 0).toList();
  double scale = max(
    validX.reduce(max) - validX.reduce(min),
    validY.isEmpty ? 0.0 : validY.reduce(max) - validY.reduce(min),
  );
  if (scale == 0) scale = 1;
  for (int i = 0; i < f.length; i += 3) {
    f[i]     = (f[i]     - cx) / scale;
    f[i + 1] = (f[i + 1] - cy) / scale;
  }
  return f;
}

// ─────────────────────────────────────────────────────────────────────────────
// UNIFIED BODY-CENTRIC NORMALIZER (Syncs with 192-feature Python pipeline)
// ─────────────────────────────────────────────────────────────────────────────
List<double> normalizeKeypoints(List<double> frame) {
  final f = List<double>.from(frame);

  // 1. Grab Shoulders (Indices 186-191)
  // Left: x=186, y=187 | Right: x=189, y=190
  final double lsX = f[186], lsY = f[187];
  final double rsX = f[189], rsY = f[190];

  // Layer 2 Defense: If shoulders are completely missing, try to fall back to face.
  if (lsX == 0 && rsX == 0) {
    final double faceX = f[126], faceY = f[127]; // Center-ish of face
    
    if (faceX != 0) {
      // Index 144 is Right Eye (MediaPipe 33), Index 153 is Left Eye (MediaPipe 263)
      final double scale = (f[144] - f[153]).abs() * 2.5; // Approx face width scaled to shoulder width
      final double finalScale = scale < 1e-5 ? 1.0 : scale;
      
      for (int i = 0; i < f.length; i += 3) {
        if (f[i] != 0) {
          f[i]   = (f[i] - faceX) / finalScale;
          f[i+1] = (f[i+1] - faceY) / finalScale;
          f[i+2] = f[i+2] / finalScale;
        }
      }
      return f;
    }
    
    // PLAN C: GHOST ANCHOR (Hand-Only Fallback)
    // The face is also missing. We must fake a body anchor so the model doesn't get raw coordinates.
    final double rightWristX = f[63], rightWristY = f[64];
    final double leftWristX  = f[0],  leftWristY  = f[1];
    
    double wristX = 0, wristY = 0;
    
    if (rightWristX != 0) {
      wristX = rightWristX; wristY = rightWristY;
    } else if (leftWristX != 0) {
      wristX = leftWristX;  wristY = leftWristY;
    }

    if (wristX != 0) {
      // Fake a chest slightly below and to the side of the wrist
      final double ghostAnchorX = wristX;
      final double ghostAnchorY = wristY + 0.25; 
      final double genericScale = 0.35; // A standard, hardcoded shoulder width
      
      for (int i = 0; i < f.length; i += 3) {
        if (f[i] != 0) {
          f[i]   = (f[i] - ghostAnchorX) / genericScale;
          f[i+1] = (f[i+1] - ghostAnchorY) / genericScale;
          f[i+2] = f[i+2] / genericScale;
        }
      }

      // ── Step 2: Re-express face relative to dominant wrist ──────────────
  // Must happen AFTER the main normalization loop so wrist coords
  // are already in chest-relative space.
  final double rwX = f[63], rwY = f[64];
  final double lwX = f[0],  lwY = f[1];

  bool hasWrist = false;

  if (rwX != 0) {
    wristX = rwX; wristY = rwY; hasWrist = true;
  } else if (lwX != 0) {
    wristX = lwX; wristY = lwY; hasWrist = true;
  }

  if (hasWrist) {
    for (int i = 126; i < 186; i += 3) {
      if (f[i] != 0) {
        f[i]   -= wristX;
        f[i+1] -= wristY;
        // f[i+2] unchanged
      }
    }
  }


      return f;
    }

    // Absolute worst-case scenario (glitched frame, return raw)
    return f; 
  }

  // PLAN A: Normal Body-Centric Anchoring
  final double anchorX = (lsX + rsX) / 2.0;
  final double anchorY = (lsY + rsY) / 2.0;
  
  double scale = (lsX - rsX).abs();
  if (scale < 1e-5) scale = 1.0;

  // Shift EVERYTHING (Hands, Face, Shoulders) relative to the chest
  for (int i = 0; i < f.length; i += 3) {
    if (f[i] != 0) {
      f[i]   = (f[i] - anchorX) / scale;
      f[i+1] = (f[i+1] - anchorY) / scale;
      f[i+2] = f[i+2] / scale;
    }
  }

  return f;
}
// ─────────────────────────────────────────────────────────────────────────────
// VISIBILITY + HAND FILTER
// ─────────────────────────────────────────────────────────────────────────────
(bool, String) checkUserVisibility(List<double> kp) {
  final leftHand  = !(kp[0]  == 0 && kp[1]  == 0);
  final rightHand = !(kp[63] == 0 && kp[64] == 0);
  if (!leftHand && !rightHand) {
    return (false, 'Raise your hand to start signing');
  }
  return (true, 'ok');
}

List<double> applySingleHandFilter(List<double> kp) {
  final lY = kp[1], rY = kp[64];
  final lP = !(kp[0] == 0 && kp[1] == 0);
  final rP = !(kp[63] == 0 && kp[64] == 0);
  if (!lP || !rP) return kp;
  final lR = lY > kRestingYThreshold, rR = rY > kRestingYThreshold;
  if (lR && rR) return kp;
  if (lR) { final f = List<double>.from(kp); for (int i = 0;  i < 63;  i++) f[i] = 0; return f; }
  if (rR) { final f = List<double>.from(kp); for (int i = 63; i < 126; i++) f[i] = 0; return f; }
  final lD = (kp[0] - 0.5).abs(), rD = (kp[63] - 0.5).abs();
  if ((lD - rD).abs() <= kCenterTie) {
    final f = List<double>.from(kp); for (int i = 63; i < 126; i++) f[i] = 0; return f;
  }
  if (lD < rD) { final f = List<double>.from(kp); for (int i = 63; i < 126; i++) f[i] = 0; return f; }
  final f = List<double>.from(kp); for (int i = 0; i < 63; i++) f[i] = 0; return f;
}

List<List<double>> padSequence(List<List<double>> frames, int targetLen) {
  if (frames.length >= targetLen) return frames.sublist(frames.length - targetLen);
  final pad = targetLen - frames.length;
  return [for (int i = 0; i < pad; i++) frames.first, ...frames];
}

// ─────────────────────────────────────────────────────────────────────────────
// ON-DEVICE INFERENCE SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class OnDeviceInferenceService {
  Interpreter?       _interpreter;
  List<String>       _labels   = [];
  bool               _isLoaded = false;
  final SessionState _session  = SessionState();

  bool         get isLoaded => _isLoaded;
  List<String> get labels   => _labels;

  Future<bool> load() async {
    try {
      debugPrint('[load] loading labels.json...');
      final labelJson = await rootBundle.loadString('assets/models/labels.json');
      _labels = (jsonDecode(labelJson) as List).map((e) => e.toString()).toList();
      debugPrint('[load] ${_labels.length} labels: $_labels');

      debugPrint('[load] loading TFLite model...');
      final options = InterpreterOptions()..threads = 4;  // was 2
      _interpreter  = await Interpreter.fromAsset(
          'assets/models/handface_pose_cnn_gru.tflite', options: options);

      final inputShape  = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      debugPrint('[load] input=$inputShape  output=$outputShape');
      if (inputShape.length < 3 || inputShape[1] != 8 || inputShape[2] != 204) {
        debugPrint('[load] WARNING: unexpected input shape $inputShape');
      }

      // Warm-up
      final numClasses = outputShape[1];
      final dummy = [List.generate(kSequenceLength, (_) => List.filled(kFeatureSize, 0.0))];
      final dOut  = [List.filled(numClasses, 0.0)];
      _interpreter!.run(dummy, dOut);
      debugPrint('[load] warm-up done — ${_labels.length} classes ready');

      _isLoaded = true;
      return true;
    } catch (e, stack) {
      debugPrint('[load] FATAL: $e\n$stack');
      _isLoaded = false;
      return false;
    }
  }

  void resetSession() => _session.reset();

  PredictionResult processFrame(List<double> rawKp) {
    final startMs = DateTime.now().millisecondsSinceEpoch.toDouble();

    final leftPresent  = !(rawKp[0]  == 0 && rawKp[1]  == 0);
    final rightPresent = !(rawKp[63] == 0 && rawKp[64] == 0);
    _session.updateHandHistory(leftPresent && rightPresent);
    final isDual   = _session.isDualHand;
    final kp       = isDual ? rawKp : applySingleHandFilter(rawKp);
    final velocity = _session.updateMotion(kp);

    // Buffer flush on static→dynamic transition (original path).
    // Motion onset detection in SessionState may have already flushed the
    // buffer earlier; bufferCleared is only set when that hasn't happened.
    if (_session.bufferCleared) {
      _session.rawBuffer.clear();
      _session.smoothBuffer.clear();
      _session.bufferCleared = false;
    }

    // Settling trim — keep only the most recent kSequenceLength frames so
    // inference sees the sign at completion, not smeared across all movement.
    if (_session.motionState == 'settling') {
      while (_session.rawBuffer.length > kSequenceLength) {
        _session.rawBuffer.removeFirst();
      }
    }

    final (userVisible, visibilityReason) = checkUserVisibility(kp);

    final landmarks = {
      'left_hand' : leftPresent,
      'right_hand': rightPresent,
      'face'      : !(kp[kHandFeatures] == 0 && kp[kHandFeatures + 1] == 0),
      'pose'      : !(kp[kHandFeatures + kFaceFeatures] == 0 &&
                      kp[kHandFeatures + kFaceFeatures + 1] == 0),
    };

    String? sign; double conf = 0.0;

    if (userVisible) {
      final nonzero = kp.where((v) => v != 0).length / kp.length;
      if (nonzero >= kMinNonzero) {
        _session.pushRaw(normalizeKeypoints(kp));
      }
    } else {
      if (_session.rawBuffer.isNotEmpty) {
        _session.rawBuffer.clear();
        _session.smoothBuffer.clear();
        _session.stillFrameCount = 0;

        _session.requireMotionReset = false;
      }
    }

    final bufSize = _session.rawBuffer.length;
    final ready   = bufSize >= kMinFramesToStart && userVisible && _isLoaded;

    if (ready && _session.shouldPredict) {
      final (bestIdx, bestConf) = _predictMultiscale(_session.rawBuffer);

      if (bestIdx != null && bestConf >= kConfThreshold) {
        final candidateLabel = _labels[bestIdx];
        final isDynamicMotion = _session.motionState == 'dynamic' ||
                                _session.motionState == 'settling';

        // ── Refractory suppression check ──────────────────────────────────────
        // Static predictions that match the terminal handshape of a recently
        // accepted dynamic sign are suppressed to prevent bleed-through.
        // Dynamic predictions are never suppressed — a second distinct
        // dynamic sign is always valid even within the refractory window.
        final suppressed = !isDynamicMotion &&
            _session.isSuppressedByRefractory(candidateLabel);

        if (!suppressed) {
          // If new prediction disagrees with current majority, reset smooth buffer
          // so the old sign does not delay the new one
          final currentMajority = _session.weightedMajorityVote;
          if (currentMajority >= 0 && currentMajority != bestIdx) {
            _session.smoothBuffer.clear();
            debugPrint('[SmoothReset] New sign $bestIdx differs from '
                'current $currentMajority — smooth buffer cleared');
          }
          _session.pushSmooth(bestIdx);

          final majority = _session.weightedMajorityVote;
          if (majority >= 0 && majority < _labels.length) {
            sign = _labels[majority];
            conf = bestConf;
            debugPrint('Prediction: $sign (${(conf * 100).toStringAsFixed(1)}%)');

            // Record dynamic sign acceptance to start the refractory window.
            if (isDynamicMotion) {
              _session.recordDynamicAccepted(sign!);
            }
          }
          if (isDynamicMotion &&
              _session.smoothBuffer.length >= _session.smoothMaxLen) {
            _session.markSettlingDone();
            _session.smoothBuffer.clear();
          }
        }
      } else {
        _session.smoothBuffer.clear();
      }
    }

    return PredictionResult(
      sign: sign, confidence: conf, bufferSize: bufSize, ready: ready,
      dualHandDetected: isDual, motionState: _session.motionState,
      velocity: double.parse(velocity.toStringAsFixed(4)),
      userVisible: userVisible, visibilityReason: visibilityReason,
      processingMs: DateTime.now().millisecondsSinceEpoch - startMs,
      landmarks: landmarks,
    );
  }

  (int?, double) _predictMultiscale(Queue<List<double>> rawBuffer) {
    // 1. Convert Queue to List
    final buf = rawBuffer.toList();
    if (buf.isEmpty) return (null, 0.0);

    // 2. Mathematically squash or stretch the entire movement down to exactly 8 frames
    List<List<double>> modelInput = resampleSequence(buf, kSequenceLength);

    // 3. Run the prediction
    final (idx, conf) = _runInference(modelInput);
    
    // If the model is confident enough, return it
    if (idx >= 0) {
      return (idx, conf);
    }
    
    return (null, 0.0);
  }

  (int, double) _runInference(List<List<double>> sequence) {
    if (_interpreter == null) return (-1, 0.0);
    try {
      final numClasses = _interpreter!.getOutputTensor(0).shape[1];
      final input  = [List.generate(kSequenceLength,
          (t) => List.generate(kFeatureSize, (f) => sequence[t][f]))];
      final output = [List.filled(numClasses, 0.0)];
      _interpreter!.run(input, output);
      final probs = output[0];

      int top1Idx = 0; double top1Val = 0;
      int top2Idx = 0; double top2Val = 0;
      for (int i = 0; i < probs.length; i++) {
        if (probs[i] > top1Val) {
          top2Val = top1Val; top2Idx = top1Idx;
          top1Val = probs[i]; top1Idx = i;
        } else if (probs[i] > top2Val) {
          top2Val = probs[i]; top2Idx = i;
        }
      }

      final requiredMargin = (_session.motionState == 'dynamic')   ? 0.08
                     : (_session.motionState == 'settling')  ? 0.10
                     : 0.18;  
      if (top1Val - top2Val < requiredMargin) return (-1, 0.0);
      return (top1Idx, top1Val);
    } catch (e) {
      debugPrint('TFLite inference error: $e');
      return (-1, 0.0);
    }
  }
  
  /// Mathematically resamples a sequence of ANY length down to exactly [targetLength] frames.
/// This normalizes the speed of the user's sign.
List<List<double>> resampleSequence(List<List<double>> rawSequence, int targetLength) {
  int originalLength = rawSequence.length;
  int featureSize = rawSequence[0].length; // Should be 204 (or 186 if you dropped Pose)
  
  // If it's already perfectly 8 frames, just return it.
  if (originalLength == targetLength) {
    return rawSequence;
  }

  List<List<double>> resampled = [];

  for (int i = 0; i < targetLength; i++) {
    // Calculate where this new frame would sit in the original timeline
    double fractionalIndex = i * (originalLength - 1) / (targetLength - 1);
    
    // Find the two real frames it sits between
    int leftIndex = fractionalIndex.floor();
    int rightIndex = fractionalIndex.ceil();
    double weight = fractionalIndex - leftIndex; // How close is it to the right frame?

    List<double> newFrame = List.filled(featureSize, 0.0);

    // Interpolate (blend) the features of the two real frames
    for (int j = 0; j < featureSize; j++) {
      if (leftIndex == rightIndex) {
        newFrame[j] = rawSequence[leftIndex][j];
      } else {
        newFrame[j] = rawSequence[leftIndex][j] * (1 - weight) + 
                      rawSequence[rightIndex][j] * weight;
      }
    }
    resampled.add(newFrame);
  }

  return resampled;
}
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded    = false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLATFORM CHANNEL SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class OnDeviceKeypointService {
  static const _channel = MethodChannel('com.signlingo/keypoints');

  Future<bool> checkAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('checkAvailable') ?? false;
    } catch (e) {
      debugPrint('checkAvailable error: $e');
      return false;
    }
  }

  Future<List<double>?> extractKeypoints({
    required List<int> yPlane,   required List<int> uPlane,
    required List<int> vPlane,
    required int yRowStride,     required int uvRowStride,
    required int uvPixelStride,  required int width,
    required int height,         required int rotationDeg,
    required int cropLeft,       required int cropTop,
    required int cropWidth,      required int cropHeight,
  }) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'extractKeypoints',
        {
          'yPlane'       : Uint8List.fromList(yPlane),
          'uPlane'       : Uint8List.fromList(uPlane),
          'vPlane'       : Uint8List.fromList(vPlane),
          'yRowStride'   : yRowStride,   'uvRowStride'  : uvRowStride,
          'uvPixelStride': uvPixelStride,'width'        : width,
          'height'       : height,       'rotationDeg'  : rotationDeg,
          'cropLeft'     : cropLeft,     'cropTop'      : cropTop,
          'cropWidth'    : cropWidth,    'cropHeight'   : cropHeight,
        },
      );
      return result?.map((v) => (v as num).toDouble()).toList();
    } catch (e) {
      debugPrint('extractKeypoints error: $e');
      return null;
    }
  }

  Future<Uint8List?> getDebugJpg({
    required Uint8List yPlane, required Uint8List uPlane,
    required Uint8List vPlane,
    required int yRowStride,   required int uvRowStride,
    required int uvPixelStride,required int width, required int height,
  }) async {
    try {
      return await _channel.invokeMethod<Uint8List>('saveDebugImage', {
        'yPlane': yPlane, 'uPlane': uPlane, 'vPlane': vPlane,
        'yRowStride': yRowStride, 'uvRowStride': uvRowStride,
        'uvPixelStride': uvPixelStride, 'width': width, 'height': height,
      });
    } catch (e) {
      debugPrint('getDebugJpg error: $e');
      return null;
    }
  }
}