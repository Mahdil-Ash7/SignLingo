// lib/screens/guided_mode_screen.dart
// ================================================
// Simplified guided mode - directly compare student sign with target sign
// No complex feedback engine, just use confidence matching
//
// HOMONYM HANDLING (Solution B):
//   If target is W and model predicts 6 (a known homonym), count it as correct.
//   HomonymResolver.isCorrectForTarget() handles this transparently.
//   No changes needed to the pipeline — only the pass check changes.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:signlingo/services/camera_service.dart';
import 'package:signlingo/services/on_device_inference.dart';
import 'package:signlingo/services/homonym_resolver.dart';
import 'package:signlingo/main.dart';
import 'package:audioplayers/audioplayers.dart';

const Color bgColor     = Color(0xFF131415);
const Color cardColor   = Color(0xFF1E2124);
const Color borderColor = Color(0xFF373A3F);

const int    kPassFramesRequired = 5;
const int    kGuidedThrottleMs   = 60;
int?         _computedCropHeight;
const double kCameraFraction     = 0.65;
const double kPanelFraction      = 0.35;

class _CropRect {
  final int left, top, width, height;
  const _CropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

_CropRect _computeCropRect(int effectiveW, int effectiveH) {
  final cropH = (_computedCropHeight ?? effectiveH).clamp(1, effectiveH);
  return _CropRect(left: 0, top: 0, width: effectiveW, height: cropH);
}

(int, int) _effectiveDimensions(int w, int h, int rot) =>
    (rot == 90 || rot == 270) ? (h, w) : (w, h);

// ─────────────────────────────────────────────────────────────────────────────
// GUIDED MODE RESULT
// ─────────────────────────────────────────────────────────────────────────────
class SimplifiedGuidedResult {
  final String? detectedSign;
  final double  confidence;
  final bool    passed;
  final String  feedback;

  // Whether the pass was via a homonym rather than a direct match.
  // Used to show a subtle hint to the user that the sign has an alias.
  final bool passedViaHomonym;

  const SimplifiedGuidedResult({
    required this.detectedSign,
    required this.confidence,
    required this.passed,
    required this.feedback,
    this.passedViaHomonym = false,
  });

  static SimplifiedGuidedResult empty() => const SimplifiedGuidedResult(
    detectedSign    : null,
    confidence      : 0.0,
    passed          : false,
    feedback        : 'Position yourself in the frame',
    passedViaHomonym: false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// GUIDED MODE SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class GuidedModeScreen extends StatefulWidget {
  final String                 targetSign;
  final OnDeviceKeypointService keypointService;
  final String?                referenceImageUrl;

  const GuidedModeScreen({
    super.key,
    required this.targetSign,
    required this.keypointService,
    this.referenceImageUrl,
  });

  @override
  State<GuidedModeScreen> createState() => _GuidedModeScreenState();
}

class _GuidedModeScreenState extends State<GuidedModeScreen>
    with TickerProviderStateMixin, RouteAware {

  final OnDeviceInferenceService _inferenceService = OnDeviceInferenceService();
  bool _inferenceReady = false;

  SimplifiedGuidedResult _result    = SimplifiedGuidedResult.empty();
  int  _passStreak  = 0;
  bool _completed   = false;
  bool _isProcessing = false;
  bool _showReference = true;

  int       _rotationDeg = -1;
  _CropRect? _cropRect;
  int _lastEffW = 0, _lastEffH = 0;

  DateTime _lastProcessed    = DateTime.fromMillisecondsSinceEpoch(0);
  String   _stableFeedback   = 'Position yourself in the frame';
  DateTime _lastFeedbackUpdate = DateTime.now();
  static const Duration _kFeedbackCooldown = Duration(milliseconds: 500);

  double   _lightLevel = 1.0;
  bool     _lightingOk = true;
  DateTime _lastLightCheck = DateTime.fromMillisecondsSinceEpoch(0);

  bool    _useScreenLight     = true;
  double? _originalBrightness;
  double  _displayScore       = 0.0;

  DateTime _lastPassAt = DateTime.now();
  static const int _kMaxPassGapMs = 1500; // max gap between consecutive pass frames
  int _streakGeneration = 0; // increments on every failure/reset


  late final AnimationController _pulseAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _initInference();
    _saveAndSetMaxBrightness();
  }

  void _initInference() {
    _inferenceService.load().then((ok) {
      if (mounted) setState(() => _inferenceReady = ok);
    });
  }

  Future<void> _saveAndSetMaxBrightness() async {
    try {
      // _originalBrightness = await ScreenBrightness().current;
      // await ScreenBrightness().setScreenBrightness(1.0);
    } catch (e) {
      debugPrint('Error setting brightness: $e');
    }
  }

  Future<void> _restoreBrightness() async {
    if (_originalBrightness != null) {
      try {
        //await ScreenBrightness().setScreenBrightness(_originalBrightness!);
      } catch (e) {
        debugPrint('Error restoring brightness: $e');
      }
    }
  }

  bool _shouldProcess() {
    final now = DateTime.now();
    if (now.difference(_lastProcessed).inMilliseconds < kGuidedThrottleMs) return false;
    _lastProcessed = now;
    return true;
  }

  _CropRect _getCropRect(int effW, int effH) {
    if (_cropRect == null || _lastEffW != effW || _lastEffH != effH) {
      _cropRect = _computeCropRect(effW, effH);
      _lastEffW = effW;
      _lastEffH = effH;
    }
    return _cropRect!;
  }

  void _playCompleteSfx() {
    final player = AudioPlayer();
    player.onPlayerComplete.listen((_) => player.dispose());
    player.play(AssetSource('audio/correct.mp3'));
  }

  void _processFrame(CameraImage image, CameraDescription camera) {
    if (!_inferenceReady)            return;
    if (!_shouldProcess())           return;
    if (_isProcessing || _completed) return;

    if (_rotationDeg == -1) _rotationDeg = camera.sensorOrientation;

    // Lighting check
    final nowL = DateTime.now();
    if (nowL.difference(_lastLightCheck).inMilliseconds >= 500) {
      _lastLightCheck = nowL;
      final yBytes  = image.planes[0].bytes;
      final yStride = image.planes[0].bytesPerRow;
      int total = 0, count = 0;
      final h = image.height, w = image.width;
      for (int r = h ~/ 5; r < h - h ~/ 5; r += 20) {
        for (int c = w ~/ 5; c < w - w ~/ 5; c += 20) {
          final idx = r * yStride + c;
          if (idx < yBytes.length) { total += yBytes[idx] & 0xFF; count++; }
        }
      }
      final lum = count > 0 ? (total / count) / 255.0 : 1.0;
      if ((lum - _lightLevel).abs() > 0.02) {
        _lightLevel = lum;
        _lightingOk = lum >= 0.25 && lum <= 0.92;
      }
    }

    final (effW, effH) = _effectiveDimensions(
        image.width, image.height, _rotationDeg);
    final crop = _getCropRect(effW, effH);
    final planes = image.planes;

    _isProcessing = true;
    _dispatchFrame(
      yPlane       : Uint8List.fromList(planes[0].bytes),
      uPlane       : Uint8List.fromList(planes[1].bytes),
      vPlane       : Uint8List.fromList(planes[2].bytes),
      yRowStride   : planes[0].bytesPerRow,
      uvRowStride  : planes[1].bytesPerRow,
      uvPixelStride: planes[1].bytesPerPixel ?? 1,
      width        : image.width,
      height       : image.height,
      rotationDeg  : _rotationDeg,
      cropLeft     : crop.left,
      cropTop      : crop.top,
      cropWidth    : crop.width,
      cropHeight   : crop.height,
    );
  }

  Future<void> _dispatchFrame({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int width,
    required int height,
    required int rotationDeg,
    required int cropLeft,
    required int cropTop,
    required int cropWidth,
    required int cropHeight,
  }) async {

      final dispatchGeneration = _streakGeneration;   // ← add this line at top

    try {
      final rawKp = await widget.keypointService.extractKeypoints(
        yPlane       : yPlane,
        uPlane       : uPlane,
        vPlane       : vPlane,
        yRowStride   : yRowStride,
        uvRowStride  : uvRowStride,
        uvPixelStride: uvPixelStride,
        width        : width,
        height       : height,
        rotationDeg  : rotationDeg,
        cropLeft     : cropLeft,
        cropTop      : cropTop,
        cropWidth    : cropWidth,
        cropHeight   : cropHeight,
      );

      if (rawKp == null) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      print("rawkp: $rawKp");

      final result = _inferenceService.processFrame(rawKp);
      if (!mounted || _completed) {
        setState(() => _isProcessing = false);
        return;
      }

    //discard result if a failure occurred while we were awaiting
    if (dispatchGeneration != _streakGeneration) {
      debugPrint('[Guided] Discarding stale frame (generation mismatch)');
      setState(() => _isProcessing = false);
      return;
    }


      final predicted  = result.sign;
      final confidence = result.confidence;

      print("confidense: ${confidence}");

      // ── HOMONYM-AWARE PASS CHECK ────────────────────────────────────────
      // Instead of: predicted == targetSign
      // We use:     HomonymResolver.isCorrectForTarget(predicted, target)
      //
      // This means:
      //   target = 'W', predicted = '6' → counts as correct (homonym)
      //   target = 'W', predicted = 'A' → wrong
      //   target = 'A', predicted = 'A' → correct (direct match)
      final isDirectMatch   = predicted == widget.targetSign;
      final isHomonymMatch  = predicted != null &&
          HomonymResolver.isCorrectForTarget(
            predicted: predicted,
            target   : widget.targetSign,
          );
      final signCorrect     = isHomonymMatch && confidence >= 0.90;
      final viaHomonym      = signCorrect && !isDirectMatch;

      final guidedResult = SimplifiedGuidedResult(
        detectedSign    : predicted,
        confidence      : confidence,
        passed          : signCorrect,
        passedViaHomonym: viaHomonym,
        feedback        : _generateFeedback(result, isHomonymMatch, viaHomonym),
      );

      _handleGuidedResult(guidedResult);

    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Feedback message ─────────────────────────────────────────────────────
  String _generateFeedback(
    PredictionResult result,
    bool signCorrect,
    bool viaHomonym,
  ) {
    if (!result.userVisible) {
      return 'Raise your hand to perform the sign';
    }
    if (result.sign == null) {
      return 'Perform the sign clearly in front of the camera';
    }
    if (!signCorrect) {
      // Tell the user what was detected, so they know what to adjust
      return 'That looks like "${result.sign}" — try "${widget.targetSign}" again';
    }
    if (result.confidence < 0.70) {
      return 'Good! Do it again more clearly';
    }
    if (viaHomonym) {
      // Detected the homonym — still a valid pass, but inform the user
      // so they understand both forms are accepted
      return 'Correct! "${result.sign}" and "${widget.targetSign}" '
          'share the same handshape';
    }
    return 'Perfect!';
  }

    void _handleGuidedResult(SimplifiedGuidedResult newResult) {
    if (!mounted || _completed) return;
    final now = DateTime.now();

    setState(() {
      _result       = newResult;
      _displayScore = newResult.confidence;

      if (now.difference(_lastFeedbackUpdate) > _kFeedbackCooldown ||
          newResult.passed) {
        _stableFeedback     = newResult.feedback;
        _lastFeedbackUpdate = now;
      }

      print("newResult: ${newResult.detectedSign}");
      print("newResult: ${newResult.passed}");

      if (newResult.passed) {
        final gapMs = now.difference(_lastPassAt).inMilliseconds;

        // If streak was building but too much time passed, reset it first
        // and wait for the next frame rather than counting this one
        if (_passStreak > 0 && gapMs > _kMaxPassGapMs) {
          debugPrint('[Guided] Streak timeout (${gapMs}ms gap) — reset');
          _passStreak       = 0;
          _streakGeneration++;
          _lastPassAt       = now;   // ← reset to now so next frame has a small gap
          _isProcessing     = false;
          // Do NOT return — fall through naturally, _isProcessing is already set
        } else {
          // Normal pass — increment streak
          _passStreak++;
          _lastPassAt = now;

          if (_passStreak >= kPassFramesRequired) {
            _playCompleteSfx();
            _completed = true;
          }
        }

      } else {
        if (_passStreak > 0) {
          debugPrint('[Guided] Streak broken at $_passStreak');
          _streakGeneration++;
        }
        _passStreak = 0;
        _lastPassAt = now;   // ← reset to now so next pass starts fresh
      }

      _isProcessing = false;
    });
  }

  bool get _isReady => _inferenceReady;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    _inferenceService.dispose();
    _pulseAnim.dispose();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPop() => _restoreBrightness();

  @override
  void didPopNext() {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mq          = MediaQuery.of(context);
            final usableH     = mq.size.height - mq.padding.top - mq.padding.bottom;
            final maxPanelH   = usableH * kPanelFraction;
            const minPanelH   = 150.0;

            return Column(
              mainAxisSize     : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraService(throttleMs: 0, onImageStream: _processFrame),

                      if (_useScreenLight)
                        IgnorePointer(
                          child: Container(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),

                      if (widget.referenceImageUrl != null && _showReference)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 0.15,
                              child: Image.asset(
                                widget.referenceImageUrl ?? '',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),

                      Positioned(
                        top: 16, left: 16,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color : cardColor,
                              shape : BoxShape.circle,
                              border: Border.all(color: borderColor, width: 2),
                            ),
                            child: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),

                      if (!_isReady)
                        Container(
                          color: bgColor.withOpacity(0.85),
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth : 4,
                              valueColor  : AlwaysStoppedAnimation<Color>(
                                  Colors.teal),
                            ),
                          ),
                        ),

                      if (_completed)
                        _CompletionOverlay(
                          signLabel    : widget.targetSign,
                          viaHomonym   : _result.passedViaHomonym,
                          detectedSign : _result.detectedSign,
                          onNext  : () => Navigator.pop(context),
                          onRetry : () => setState(() {
                            _completed  = false;
                            _passStreak = 0;
                            _result     = SimplifiedGuidedResult.empty();
                            _inferenceService.resetSession();
                          }),
                        ),

                      if (_isProcessing && _isReady && !_completed)
                        const Positioned(
                          bottom: 16, right: 16,
                          child: _ProcessingDot(),
                        ),

                      if (_isReady && !_completed && !_lightingOk)
                        Positioned(
                          top: 80, left: 16, right: 16,
                          child: _LightingBanner(lightLevel: _lightLevel),
                        ),
                    ],
                  ),
                ),

                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: minPanelH,
                    maxHeight: maxPanelH,
                  ),
                  child: _isReady && !_completed
                      ? _SimplifiedFeedbackPanel(
                          targetSign      : widget.targetSign,
                          result          : _result,
                          passStreak      : _passStreak,
                          passRequired    : kPassFramesRequired,
                          stableFeedback  : _stableFeedback,
                          displayScore    : _displayScore,
                          showReference   : _showReference,
                          hasReference    : widget.referenceImageUrl != null,
                          onToggleReference: () =>
                              setState(() => _showReference = !_showReference),
                        )
                      : Container(
                          color: cardColor,
                          child: const Center(
                            child: Text('LOADING…',
                                style: TextStyle(
                                  color      : Color(0xFF9CA3AF),
                                  fontWeight : FontWeight.w900,
                                  letterSpacing: 1.0,
                                )),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FEEDBACK PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _SimplifiedFeedbackPanel extends StatelessWidget {
  final String                 targetSign;
  final SimplifiedGuidedResult result;
  final int     passStreak;
  final int     passRequired;
  final String  stableFeedback;
  final double  displayScore;
  final bool    showReference;
  final bool    hasReference;
  final VoidCallback onToggleReference;

  const _SimplifiedFeedbackPanel({
    required this.targetSign,
    required this.result,
    required this.passStreak,
    required this.passRequired,
    required this.stableFeedback,
    required this.displayScore,
    required this.showReference,
    required this.hasReference,
    required this.onToggleReference,
  });

  @override
  Widget build(BuildContext context) {
    // Show the target sign label — if it has a homonym, show both
    // so the user knows both forms are accepted before they even try
    final displayTarget = HomonymResolver.hasHomonym(targetSign)
        ? HomonymResolver.getDisplayLabel(targetSign)
        : targetSign.toUpperCase();

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.only(
          topLeft : Radius.circular(32),
          topRight: Radius.circular(32),
        ),
        border: Border(top: BorderSide(color: borderColor, width: 2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 48, height: 6,
              decoration: BoxDecoration(
                color: cardColor, borderRadius: BorderRadius.circular(3)),
            ),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Container(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // ── Header ──────────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Show both signs if homonym exists
                                  Text(
                                    displayTarget,
                                    style: const TextStyle(
                                      color      : Colors.white,
                                      fontSize   : 22,
                                      fontWeight : FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  // Small label clarifying why two signs shown
                                  if (HomonymResolver.hasHomonym(targetSign))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Either form accepted',
                                        style: TextStyle(
                                          color    : Colors.amber.shade400,
                                          fontSize : 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (hasReference)
                              GestureDetector(
                                onTap: onToggleReference,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: borderColor, width: 2),
                                    boxShadow: const [
                                      BoxShadow(
                                        color     : borderColor,
                                        blurRadius: 0,
                                        offset    : Offset(0, 4),
                                      )
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        showReference
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                        color: Colors.grey.shade400,
                                        size : 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        showReference
                                            ? 'HIDE REFERENCE'
                                            : 'SHOW REFERENCE',
                                        style: TextStyle(
                                          color      : Colors.grey.shade400,
                                          fontSize   : 11,
                                          fontWeight : FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // ── Progress bar ──────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          height: 3,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          // This alignment forces the child to scale outward from the center
                          alignment: Alignment.center, 
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Optional: Add a tiny bit of the confidence score to the width 
                              // so the bar "breathes" smoothly between frames
                              final double pulse = (displayScore > 0.5 && passStreak < passRequired) 
                                  ? (displayScore * 0.2) 
                                  : 0.0;
                                  
                              final double percent = 
                                  ((passStreak + pulse) / passRequired).clamp(0.0, 1.0);
                              
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                curve: Curves.easeInOut, 
                                height: 12,
                                width: constraints.maxWidth * percent,
                                decoration: BoxDecoration(
                                  // Change color to green if the progress is 50% or more
                                  color: percent >= 0.50
                                      ? Colors.green.shade400
                                      : Colors.amber.shade400,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Confidence ────────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 1. Remove 'const' from the Text widget
                            // 2. Check if passStreak is 0 to determine the text
                            Text(
                              passStreak == 0 ? 'Perform Sign' : 'Hold...',
                              style: const TextStyle(
                                  color     : Color(0xFF9CA3AF),
                                  fontSize  : 12,
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${(displayScore * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                color     : displayScore >= 0.70
                                    ? Colors.green.shade400
                                    : Colors.amber.shade400,
                                fontSize  : 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ── Feedback banner ───────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _FeedbackBanner(
                          message: stableFeedback.isEmpty
                              ? 'LOOKING GOOD!'
                              : stableFeedback,
                          isGood : result.passed,
                        ),
                      ),

                      const SizedBox(height: 5),

                      // ── Detected sign ─────────────────────────────────────
                      if (result.detectedSign != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color        : Colors.blue.shade500.withOpacity(0.15),
                              borderRadius : BorderRadius.circular(16),
                              border       : Border.all(
                                  color: Colors.blue.shade400, width: 2),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_rounded,
                                    color: Colors.blue.shade400, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Detected: ${result.detectedSign}'
                                    // Show hint if detected is homonym of target
                                    '${result.passedViaHomonym ? ' (same as ${targetSign})' : ''}',
                                    style: TextStyle(
                                      color     : Colors.blue.shade300,
                                      fontSize  : 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FEEDBACK BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _FeedbackBanner extends StatelessWidget {
  final String message;
  final bool   isGood;
  const _FeedbackBanner({required this.message, required this.isGood});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: isGood
          ? Colors.green.shade500.withOpacity(0.15)
          : Colors.amber.shade500.withOpacity(0.15),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isGood ? Colors.green.shade400 : Colors.amber.shade400,
        width: 2,
      ),
    ),
    child: Row(
      children: [
        Icon(
          isGood ? Icons.check_circle_rounded : Icons.info_rounded,
          color: isGood ? Colors.green.shade400 : Colors.amber.shade400,
          size : 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message.toUpperCase(),
            style: TextStyle(
              color      : isGood
                  ? Colors.green.shade300
                  : Colors.amber.shade300,
              fontSize   : 12,
              fontWeight : FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPLETION OVERLAY
// Updated to show homonym info if the pass was via an alias
// ─────────────────────────────────────────────────────────────────────────────
class _CompletionOverlay extends StatelessWidget {
  final String    signLabel;
  final bool      viaHomonym;
  final String?   detectedSign;
  final VoidCallback onNext;
  final VoidCallback onRetry;

  const _CompletionOverlay({
    required this.signLabel,
    required this.viaHomonym,
    this.detectedSign,
    required this.onNext,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: bgColor.withOpacity(0.9),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color       : cardColor,
            borderRadius: BorderRadius.circular(24),
            border      : Border.all(color: borderColor, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade500.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle_rounded,
                    color: Colors.green.shade400, size: 64),
              ),
              const SizedBox(height: 14),
              const Text('GREAT JOB!',
                  style: TextStyle(
                    color      : Colors.white,
                    fontSize   : 24,
                    fontWeight : FontWeight.w900,
                    letterSpacing: 1.0,
                  )),
              const SizedBox(height: 8),

              // Normal completion message
              if (!viaHomonym)
                Text(
                  'You performed "$signLabel" correctly',
                  style: const TextStyle(
                    color    : Color(0xFF9CA3AF),
                    fontSize : 14,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),

              // Homonym completion — show educational note
              if (viaHomonym && detectedSign != null)
                Column(
                  children: [
                    Text(
                      'You performed "$detectedSign" correctly',
                      style: const TextStyle(
                        color    : Color(0xFF9CA3AF),
                        fontSize : 14,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color       : Colors.amber.shade500.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border      : Border.all(
                            color: Colors.amber.shade700, width: 1),
                      ),
                      child: Text(
                        '"$detectedSign" and "$signLabel" share the '
                        'same handshape in BIM',
                        style: TextStyle(
                          color    : Colors.amber.shade300,
                          fontSize : 12,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: _buildButton(
                      text: 'TRY AGAIN',
                      color      : borderColor,
                      shadowColor: bgColor,
                      textColor  : Colors.white,
                      onPressed  : onRetry,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildButton(
                      text: 'DONE',
                      color      : Colors.green.shade500,
                      shadowColor: Colors.green.shade800,
                      textColor  : Colors.white,
                      onPressed  : onNext,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildButton({
    required String text,
    required Color color,
    required Color shadowColor,
    required Color textColor,
    required VoidCallback onPressed,
  }) => GestureDetector(
    onTap: onPressed,
    child: Container(
      width  : double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color       : color,
        borderRadius: BorderRadius.circular(16),
        boxShadow   : [
          BoxShadow(color: shadowColor, blurRadius: 0, offset: const Offset(0, 5)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(text,
          style: TextStyle(
            fontSize  : 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            color     : textColor,
          )),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PROCESSING DOT
// ─────────────────────────────────────────────────────────────────────────────
class _ProcessingDot extends StatefulWidget {
  const _ProcessingDot();
  @override
  State<_ProcessingDot> createState() => _ProcessingDotState();
}

class _ProcessingDotState extends State<_ProcessingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 600))
    ..repeat(reverse: true);

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: 12, height: 12,
      decoration: BoxDecoration(
        color: Colors.green.shade400,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.green.shade400.withOpacity(0.5),
            blurRadius: 8, spreadRadius: 2,
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LIGHTING BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _LightingBanner extends StatelessWidget {
  final double lightLevel;
  const _LightingBanner({required this.lightLevel});

  @override
  Widget build(BuildContext context) {
    if (lightLevel >= 0.25) return const SizedBox.shrink();
    return Container(
      width  : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color       : Colors.amber.shade500.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(color: Colors.amber.shade400, width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.wb_sunny_outlined,
              color: Colors.amber.shade400, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text('TOO DARK — MOVE TO A BRIGHTER AREA',
                style: TextStyle(
                  color      : Colors.amber.shade400,
                  fontSize   : 11,
                  fontWeight : FontWeight.w900,
                  letterSpacing: 0.5,
                )),
          ),
        ],
      ),
    );
  }
}