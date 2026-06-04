// lib/screens/camera_feature_extraction.dart
// =====================================
// On-device BIM Sign Language detection.
//
// CONFIRMED DEVICE MEASUREMENTS:
//   previewSize       : 320×240  (landscape)
//   sensorOrientation : 270°
//   Effective portrait: 240×320  (after rotation swaps w/h)
//   kSensorCropHeight : 208      (= int(320 * 0.65))
//
// HOW TO RECALIBRATE:
//   1. Read debug log: "📷 previewSize = Size(W, H)"
//   2. effectivePortraitH = max(W, H)  ← longer side after rotation
//   3. kSensorCropHeight = int(effectivePortraitH * 0.65)
//   4. Update CAMERA_FRACTION in 00_data_collection.py if fraction changed
//   5. Retrain if value changed
//
// RESPONSIVENESS — NON-BLOCKING PLATFORM CHANNEL (Step 6):
//   The camera stream callback must return immediately on every frame.
//   If _processCameraImage is async and awaits the platform channel,
//   the stream callback is held open and the next frame cannot begin
//   until MediaPipe finishes — creating a growing backlog.
//
//   Fix: copy plane bytes synchronously in the callback, then call
//   _dispatchFrame() without await. The callback returns immediately
//   and the camera plugin can deliver the next frame right away.
//   _isProcessing guards against overlapping dispatches.
//
// LAYOUT MODES:
//   cameraHeight != null → ClipRect + SizedBox, panel below in Column
//   cameraHeight == null → Expanded, panel overlays via Positioned

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:signlingo/services/camera_service.dart';
import 'package:signlingo/services/on_device_inference.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:signlingo/main.dart';
import 'package:flutter/scheduler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SENSOR CROP CONFIG
// ─────────────────────────────────────────────────────────────────────────────
//const int kSensorCropHeight = 208;
// ADD this computed value, set once after camera initializes:
int? _computedCropHeight;
// Single source of truth for the fraction — defined once, used everywhere
const double kCameraFraction = 0.65;  // must match panel split in live_test.dart
const int kRawBufferMax     = 8;

// ─────────────────────────────────────────────────────────────────────────────
// CROP UTILITIES
// ─────────────────────────────────────────────────────────────────────────────
class _CropRect {
  final int left, top, width, height;
  const _CropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

// _computeCropRect uses the computed value instead of the hardcoded constant:
_CropRect _computeCropRect(int effectiveW, int effectiveH) {
  final cropH = (_computedCropHeight ?? effectiveH).clamp(1, effectiveH);
  return _CropRect(left: 0, top: 0, width: effectiveW, height: cropH);
}

(int, int) _effectiveDimensions(int w, int h, int rotDeg) =>
    (rotDeg == 90 || rotDeg == 270) ? (h, w) : (w, h);

int _sensorRotation(CameraDescription camera) => camera.sensorOrientation;

// ─────────────────────────────────────────────────────────────────────────────
// COPIED FRAME — plain data, safe to pass across async boundaries
// ─────────────────────────────────────────────────────────────────────────────
// CameraImage plane bytes are backed by a native buffer that the camera plugin
// recycles after the stream callback returns. We must copy them synchronously
// before returning from the callback. This struct holds the copied data.
class _FrameData {
  final Uint8List yPlane;
  final Uint8List uPlane;
  final Uint8List vPlane;
  final int       yRowStride;
  final int       uvRowStride;
  final int       uvPixelStride;
  final int       width;
  final int       height;
  final int       rotationDeg;
  final int       cropLeft;
  final int       cropTop;
  final int       cropWidth;
  final int       cropHeight;

  const _FrameData({
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.width,
    required this.height,
    required this.rotationDeg,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════
class CameraFeatureExtraction extends StatefulWidget {
  final ValueNotifier<String> signNotifier;
  final ValueNotifier<double> confidenceNotifier;
  final ValueNotifier<int>?   bufferNotifier; // <--- ADD THIS
  final Widget? bottomWidget;
  final Widget? topLeftWidget;
  final double? cameraHeight;
  final bool showHandLandmarks;

  const CameraFeatureExtraction({
    super.key,
    required this.signNotifier,
    required this.confidenceNotifier,
    required this.bufferNotifier,
    this.bottomWidget,
    this.topLeftWidget,
    this.cameraHeight,
    this.showHandLandmarks = false,
  });

  @override
  State<CameraFeatureExtraction> createState() =>
      CameraFeatureExtractionState();
}

class CameraFeatureExtractionState extends State<CameraFeatureExtraction> with RouteAware, SingleTickerProviderStateMixin {

  final OnDeviceKeypointService  _keypointService  = OnDeviceKeypointService();
  final OnDeviceInferenceService _inferenceService = OnDeviceInferenceService();

  final ValueNotifier<List<double>?> _keypointNotifier = ValueNotifier(null);
  // ticker to drive continuous repaints at vsync rate
  late final Ticker _landmarkTicker;
  // Latest keypoints, written from _dispatchFrame, read by the painter
  List<double>? _paintedKeypoints;

  bool _keypointsReady = false;
  bool _modelReady     = false;

  bool   _dualHandDetected = false;
  int    _bufferSize       = 0;
  String _motionState      = 'static';
  double _velocity         = 0.0;
  bool   _userVisible      = false;
  String _visibilityReason = '';
  String _lastSign         = '';
  List<double>? _lastRawKeypoints;


  //-------------- User Lighting Checking -------------------------------------
  double _lightLevel      = 1.0;   // 0.0–1.0, computed from Y plane
  bool   _lightingOk      = true;
  // Throttle lighting check — only re-sample every 500ms, not every frame
  DateTime _lastLightCheck = DateTime.fromMillisecondsSinceEpoch(0);

  //Increase brightness
  double? _originalBrightness;

      // ── LIGHTING CHECK ──────────────────────────────────────────────────────
    // Samples the Y (luminance) plane from the YUV420 frame.
    // YUV420 Y plane: 1 byte per pixel, 0=black 255=white.
    // We sample every Nth pixel for speed — no need to read all bytes.
    // Returns average brightness 0.0–1.0.
    static const double _kDarkThreshold  = 0.50;  // below this = too dark
    static const double _kBrightThreshold = 0.92; // above this = overexposed
    static const int    _kSampleStride   = 20;    // sample every 20th pixel

  // ── Responsiveness: non-blocking dispatch ─────────────────────────────────
  // _isProcessing guards against overlapping dispatches.
  // It is set to true synchronously in the stream callback (before any await)
  // and cleared in the finally block of _dispatchFrame.
  bool _isProcessing = false;

  _CropRect? _cropRect;
  int  _lastEffW     = 0;
  int  _lastEffH     = 0;
  int  _rotationDeg  = -1;
  bool _loggedSensor = false;

  // Throttle — controls how often we copy + dispatch a frame.
  // Evaluated synchronously in the stream callback, no async involved.
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _shouldProcessFrame() {
    final now = DateTime.now();
    if (now.difference(_lastSentAt).inMilliseconds < _throttleMs) return false;
    _lastSentAt = now;
    return true;
  }

  int get _throttleMs {
    if (_motionState == 'dynamic')  return 0; // time for perform sign divide by sequence length
    if (_motionState == 'settling') return 20;   // fastest during settling
    return 33;
  }

  void resetInferenceSession() {
    _inferenceService.resetSession();
    _lastSign = '';
    // Explicitly push empty string so quiz listener sees the reset
    widget.signNotifier.value = '';
    widget.confidenceNotifier.value = 0.0;
  }

  @override
  void initState() {
    super.initState();
    _initPipeline();
    _saveAndSetMaxBrightness();

    // Drive the landmark overlay at display vsync independently of inference
  //   _landmarkTicker = createTicker((_) {
  //   // Only trigger a repaint if we have data and the widget is mounted
  //   if (_paintedKeypoints != null && mounted) {
  //     _keypointNotifier.value = _paintedKeypoints; // same list ref = no alloc
  //   }
  // })..start();
  }

    @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }



    Future<void> _saveAndSetMaxBrightness() async {
    try {

    } catch (e) {
      print("Error setting brightness: $e");
    }
  }

  Future<void> _restoreBrightness() async {
    if (_originalBrightness != null) {
      try {
        //await ScreenBrightness().setScreenBrightness(_originalBrightness!);
      } catch (e) {
        print("Error restoring brightness: $e");
      }
    }
  }

  Future<void> _initPipeline() async {
    final kpReady = await _keypointService.checkAvailable();
    if (mounted) setState(() => _keypointsReady = kpReady);
    debugPrint('MediaPipe: ${kpReady ? "✅" : "❌"}');

    final modelReady = await _inferenceService.load();
    if (mounted) setState(() => _modelReady = modelReady);
    debugPrint('TFLite: ${modelReady ? "✅" : "❌"}');
  }

  _CropRect _getCropRect(int effW, int effH) {
    if (_cropRect == null || _lastEffW != effW || _lastEffH != effH) {
      _cropRect = _computeCropRect(effW, effH);
      _lastEffW = effW;
      _lastEffH = effH;
      debugPrint('Crop: $effW×$effH '
          '→ ${_cropRect!.width}×${_cropRect!.height} '
          '(kSensorCropHeight=$_computedCropHeight)');
    }
    return _cropRect!;
  }

    double _computeLuminance(Uint8List yPlane, int yRowStride,
        int imgWidth, int imgHeight) {
      int total = 0;
      int count = 0;
      // Sample the center 60% of the frame (avoid black borders on some devices)
      final rowStart = imgHeight ~/ 5;
      final rowEnd   = imgHeight - rowStart;
      final colStart = imgWidth  ~/ 5;
      final colEnd   = imgWidth  - colStart;

      for (int row = rowStart; row < rowEnd; row += _kSampleStride) {
        for (int col = colStart; col < colEnd; col += _kSampleStride) {
          final idx = row * yRowStride + col;
          if (idx < yPlane.length) {
            total += yPlane[idx] & 0xFF;
            count++;
          }
        }
      }
      return count > 0 ? (total / count) / 255.0 : 1.0;
    }

  // ─────────────────────────────────────────────────────────────────────────
  // STREAM CALLBACK — must return as fast as possible
  //
  // This is called on every camera frame by the camera plugin.
  // It must NOT be async-awaited for long operations.
  //
  // What we do here (all synchronous, takes < 1ms):
  //   1. Throttle check — bail early if too soon
  //   2. Guard check — bail if already processing
  //   3. Copy plane bytes from native buffer into Dart heap
  //   4. Set _isProcessing = true
  //   5. Call _dispatchFrame() WITHOUT await — returns immediately
  //   6. Return — camera plugin can deliver next frame now
  // ─────────────────────────────────────────────────────────────────────────
  void _processCameraImage(CameraImage image, CameraDescription camera) {
    // In _processCameraImage(), compute once on first frame:
if (_computedCropHeight == null) {
  final (effW, effH) = _effectiveDimensions(image.width, image.height, _rotationDeg);

  _computedCropHeight = (effH * kCameraFraction).toInt().clamp(1, effH);

  debugPrint('Computed kSensorCropHeight = $_computedCropHeight ''(effH=$effH × fraction=$kCameraFraction)');
}
    // ── Fast path checks (synchronous, no allocation) ─────────────────────
    if (!_keypointsReady || !_modelReady) return;
    if (!_shouldProcessFrame())           return;
    if (_isProcessing)                    return;

    // ── Sensor rotation (read once) ───────────────────────────────────────
    if (_rotationDeg == -1) {
      _rotationDeg = _sensorRotation(camera);
    }

    // ── Compute crop (cached after first frame) ───────────────────────────
    final (effW, effH) = _effectiveDimensions(
        image.width, image.height, _rotationDeg);
    final crop = _getCropRect(effW, effH);

    // ── Log once ──────────────────────────────────────────────────────────
    if (!_loggedSensor) {
      _loggedSensor = true;
      debugPrint('RAW sensor: ${image.width}×${image.height}  '
          'rotation=$_rotationDeg°  portrait: $effW×$effH  '
          'kSensorCropHeight=$_computedCropHeight');
    }

    // ── Lighting check (synchronous, cheap — samples Y plane directly) ─────
  final now = DateTime.now();
  if (now.difference(_lastLightCheck).inMilliseconds >= 500) {
    _lastLightCheck = now;
    // Read Y plane bytes directly — already available before copy
    final yBytes  = image.planes[0].bytes;
    final yStride = image.planes[0].bytesPerRow;
    final lum     = _computeLuminance(yBytes, yStride, image.width, image.height);

    if(kDebugMode){debugPrint('Lum : $lum \n');}
    
    if (lum != _lightLevel) {
      _lightLevel  = lum;
      _lightingOk  = lum >= _kDarkThreshold && lum <= _kBrightThreshold;
      // No setState here — update in the next dispatchFrame setState call
    }
  }

    // ── CRITICAL: copy plane bytes synchronously before returning ─────────
    // CameraImage.planes are backed by a native buffer. Once this callback
    // returns, the camera plugin may overwrite or recycle that buffer.
    // We must copy the bytes into Dart heap NOW, before any await.
    final planes = image.planes;
    final frame  = _FrameData(
      yPlane        : Uint8List.fromList(planes[0].bytes),
      uPlane        : Uint8List.fromList(planes[1].bytes),
      vPlane        : Uint8List.fromList(planes[2].bytes),
      yRowStride    : planes[0].bytesPerRow,
      uvRowStride   : planes[1].bytesPerRow,
      uvPixelStride : planes[1].bytesPerPixel ?? 1,
      width         : image.width,
      height        : image.height,
      rotationDeg   : _rotationDeg,
      cropLeft      : crop.left,
      cropTop       : crop.top,
      cropWidth     : crop.width,
      cropHeight    : crop.height,
    );

    // ── Mark as processing and fire async work — DO NOT await ─────────────
    // _dispatchFrame is async but we do not await it here.
    // This means _processCameraImage returns immediately and the camera
    // plugin can call it again on the next frame without waiting.
    _isProcessing = true;
    _dispatchFrame(frame);
    // ← returns here immediately, next camera frame can begin
  }


Future<void> _saveDebugImage(_FrameData frame, int counter) async {
  try {
    // 1. Get JPG bytes from Kotlin
final jpgBytes = await _keypointService.getDebugJpg(
  yPlane: frame.yPlane,
  uPlane: frame.uPlane,
  vPlane: frame.vPlane,
  yRowStride: frame.yRowStride,
  uvRowStride: frame.uvRowStride,
  uvPixelStride: frame.uvPixelStride,
  width: frame.width,
  height: frame.height,
);

    if (jpgBytes == null) return;

    // 2. Save to local storage
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/debug_frames/frame_$counter.jpg');
    
    // Ensure the folder exists
    await file.parent.create(recursive: true);
    await file.writeAsBytes(jpgBytes);

    debugPrint('[Debug Images] SUCCESS: Debug frame saved to ${file.path}');
  } catch (e) {
    debugPrint('[Debug Images] Error saving debug image: $e');
  }
}
  // ─────────────────────────────────────────────────────────────────────────
  // DISPATCH — runs async, decoupled from the stream callback
  //
  // All the slow work happens here:
  //   - Platform channel call to Kotlin/MediaPipe (typically 20–50ms)
  //   - TFLite inference (typically 5–15ms)
  //   - setState updates
  //
  // _isProcessing is cleared in finally so the next frame can dispatch
  // as soon as this one finishes — no gaps, no backlog.
  // ─────────────────────────────────────────────────────────────────────────
 // int _debugSaveCounter = 0;

  Future<void> _dispatchFrame(_FrameData frame) async {
    //_debugSaveCounter++;
  
  // Save one frame every 100 dispatches for comparison
  // if (_debugSaveCounter % 100 == 0  && kDebugMode) {
  //   _saveDebugImage(frame, _debugSaveCounter);
  //   debugPrint('Frame rot : ${frame.rotationDeg}');
  // }
    try {
      // Platform channel → Kotlin → MediaPipe → 204 keypoints
      final rawKp = await _keypointService.extractKeypoints(
        yPlane        : frame.yPlane,
        uPlane        : frame.uPlane,
        vPlane        : frame.vPlane,
        yRowStride    : frame.yRowStride,
        uvRowStride   : frame.uvRowStride,
        uvPixelStride : frame.uvPixelStride,
        width         : frame.width,
        height        : frame.height,
        rotationDeg   : frame.rotationDeg,
        cropLeft      : frame.cropLeft,
        cropTop       : frame.cropTop,
        cropWidth     : frame.cropWidth,
        cropHeight    : frame.cropHeight,
      );

      if (rawKp == null || !mounted) return;

      // TFLite inference — runs on Dart side, fast
      final result = _inferenceService.processFrame(rawKp);
      if (!mounted) return;


      // Update confidence FIRST so it is ready when signNotifier fires.
      // The quiz listener reads confidenceNotifier.value synchronously inside
      // _onSignNotifierChanged — if confidence is updated after the sign fires
      // it will always read 0.0 on the first detection of a new question.
      if (result.sign != null) {
        widget.confidenceNotifier.value = result.confidence;
      } else if (widget.confidenceNotifier.value != 0.0) {
        widget.confidenceNotifier.value = 0.0;
      }

    // ── CHECK FOR NEW SIGN & RESET BUFFER ──
          final newSign = result.sign ?? _lastSign;
          final bool signChanged = (newSign != _lastSign) && (result.sign != null);

          if (signChanged) {
            // 1. A new sign was detected! Update the text on screen.
            _lastSign = newSign;
            widget.signNotifier.value = _lastSign;

            // 2. Clear the AI's memory so it has to collect 16 fresh frames 
            //    before making its next prediction.
            //_inferenceService.resetSession();
            
            // 3. Instantly drop the UI badge back to 0.
            if (widget.bufferNotifier != null) {
              widget.bufferNotifier!.value = 0;
            }
          } else {
            // 4. No new sign? Just update the buffer normally as it fills up.
            if (widget.signNotifier.value != _lastSign) {
              widget.signNotifier.value = _lastSign;
            }
            if (widget.bufferNotifier != null) {
              widget.bufferNotifier!.value = result.bufferSize;
            }
          }

          _keypointNotifier.value = rawKp;
          _paintedKeypoints = rawKp;

        setState(() {
      _bufferSize       = result.bufferSize;
      _dualHandDetected = result.dualHandDetected;
      _motionState      = result.motionState;
      _velocity         = result.velocity;
      _userVisible      = result.userVisible;
      _visibilityReason = result.visibilityReason;
      _isProcessing     = false;  
    });

    } catch (e, stack) {
      debugPrint('[dispatch frame] _dispatchFrame error: $e\n$stack');
    }
      // Always clear — even on error — so next frame can be dispatched
      if (mounted) {
        setState(() => _isProcessing = false);
      } else {
        _isProcessing = false;
      }
  }

  @override
  void dispose() {
  _landmarkTicker.dispose();
  _keypointNotifier.dispose();
  routeObserver.unsubscribe(this);
  _inferenceService.dispose();
  super.dispose();

  }

    @override
  void didPop() {
    // called when page is popped (e.g., swipe back)
    _restoreBrightness();
  }

  @override
  void didPopNext() {
    // called if coming back from another page
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CAMERA LAYER
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildCameraLayer(bool isReady) {
    return Stack(
      fit: StackFit.expand,
      children: [

        CameraService(
          throttleMs   : 0,
          onImageStream: _processCameraImage,
        ),

      // if (widget.showHandLandmarks)
      //   Positioned.fill(
      //     child: RepaintBoundary(
      //       child: ValueListenableBuilder<List<double>?>(
      //         valueListenable: _keypointNotifier,
      //         builder: (_, kp, __) {
      //           if (kp == null) return const SizedBox.shrink();
      //           return CustomPaint(
      //             painter: _HandLandmarkPainter(kp),
      //           );
      //         },
      //       ),
      //     ),
      //   ),


        if (!isReady)
          Container(
            color: Colors.black.withOpacity(0.65),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white54),
                  const SizedBox(height: 16),
                  Text(
                    !_keypointsReady
                        ? 'Initializing MediaPipe…'
                        : 'Loading sign model…',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

        if (_isProcessing && isReady)
          const Positioned(
            bottom: 12, right: 12,
            child : _ProcessingDot(),
          ),

        if (widget.topLeftWidget != null)
          Positioned(
            top: 56, left: 12,
            child: widget.topLeftWidget!,
          ),

        if (widget.cameraHeight == null)
          if (widget.bottomWidget != null)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: widget.bottomWidget!,
            )
          else
            const Positioned(
              left: 0, right: 0, bottom: 12,
              child: Text(
                'Position your upper body inside the frame',
                style    : TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TOP OVERLAYS
  // ─────────────────────────────────────────────────────────────────────────
  List<Widget> _buildTopOverlays(bool isReady) => [

    Positioned(
      top: 0, left: 0, right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton(
              onPressed  : () => Navigator.pop(context),
              icon       : const Icon(Icons.arrow_back_ios, color: Colors.white),
              padding    : EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            // _Badge(
            //   label: _motionState == 'dynamic'  ? '〰️ Moving'
            //        : _motionState == 'settling' ? '🎯 Predict'
            //        : '⏸ Still',
            //   color: _motionState == 'dynamic'  ? Colors.blue
            //        : _motionState == 'settling' ? Colors.green
            //        : Colors.grey.shade700,
            // ),
            const Spacer(),
            //_BufferBadge(current: _bufferSize, max: kRawBufferMax),
          ],
        ),
      ),
    ),

    if (!isReady)
      Positioned(
        top: 56, left: 0, right: 0,
        child: _LoadingBanner(
          keypointsReady: _keypointsReady,
          modelReady    : _modelReady,
        ),
      ),

    if (isReady && !_userVisible &&
        _visibilityReason.isNotEmpty &&
        _visibilityReason != 'not started')
      // Positioned(
      //   top: 56, left: 0, right: 0,
      //   child: _VisibilityBanner(reason: _visibilityReason),
      // ),

      if (isReady && !_lightingOk)
      Positioned(
        top: _userVisible ? 56 : 50,  // stack below visibility banner if both show
        left: 0, right: 0,
        child: _LightingBanner(lightLevel: _lightLevel),
  ),
  ];

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isReady = _keypointsReady && _modelReady;

    // ── EXACT HEIGHT MODE ─────────────────────────────────────────────────
    if (widget.cameraHeight != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            mainAxisSize      : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRect(
                child: SizedBox(
                  height: widget.cameraHeight,
                  child : Stack(
                    fit     : StackFit.expand,
                    children: [
                      _buildCameraLayer(isReady),
                      ..._buildTopOverlays(isReady),
                    ],
                  ),
                ),
              ),
              if (widget.bottomWidget != null)
                widget.bottomWidget!
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Position your upper body inside the frame',
                    style    : TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // ── FULL SCREEN MODE ──────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(children: [
              Expanded(child: _buildCameraLayer(isReady)),
            ]),
            ..._buildTopOverlays(isReady),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color       : color.withOpacity(0.85),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: const TextStyle(color: Colors.white, fontSize: 12)),
  );
}

class _LoadingBanner extends StatelessWidget {
  final bool keypointsReady;
  final bool modelReady;
  const _LoadingBanner({required this.keypointsReady, required this.modelReady});

  @override
  Widget build(BuildContext context) {
    final steps = <String>[];
    if (!keypointsReady) steps.add('MediaPipe Tasks');
    if (!modelReady)     steps.add('Sign model');
    return Container(
      width  : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color  : Colors.blueGrey.shade900.withOpacity(0.90),
      child  : Row(
        children: [
          const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white60),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Loading: ${steps.join(", ")}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _VisibilityBanner extends StatelessWidget {
  final String reason;
  const _VisibilityBanner({required this.reason});

  @override
  Widget build(BuildContext context) => Container(
    width  : double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color  : Colors.amber.shade900.withOpacity(0.50),
    child  : Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Position yourself properly',
          style: TextStyle(
              color     : Colors.white,
              fontSize  : 20,
              fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          reason,
          style: const TextStyle(
              color          : Color(0xFFFCEF01),
              fontSize       : 15,
              backgroundColor: Colors.black),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _BufferBadge extends StatelessWidget {
  final int current;
  final int max;
  const _BufferBadge({required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    final ratio    = (current / max).clamp(0.0, 1.0);
    final ready    = current >= (max ~/ 2);
    final barColor = ready ? Colors.greenAccent : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      // decoration: BoxDecoration(
      //   color       : Colors.black54,
      //   borderRadius: BorderRadius.circular(20),
      //   border      : Border.all(color: Colors.white12, width: 1),
      // ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // const Text('Predicting...',
          //     style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 6),
          Container(
            width: 40, height: 6,
            decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(3)),
            child: FractionallySizedBox(
              alignment  : Alignment.centerLeft,
              widthFactor: ratio,
              child: Container(
                decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Text('$current/$max',
          //     style: TextStyle(
          //         color     : barColor,
          //         fontSize  : 11,
          //         fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

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
      width: 10, height: 10,
      decoration: const BoxDecoration(
          color: Colors.greenAccent, shape: BoxShape.circle),
    ),
  );
}


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
            child: Text('POOR LIGHTING — MOVE TO A BRIGHTER AREA',
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