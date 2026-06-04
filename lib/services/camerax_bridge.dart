// lib/services/camerax_bridge.dart
// =====================================
// Bridges the CameraX native pipeline into sign detection + video preview.
//
// OPTION 4 ARCHITECTURE:
//   CameraX owns the camera exclusively when signing is ON.
//   WebRTC uses audio-only (video: false) to avoid camera conflict.
//
//   Two EventChannels from Kotlin:
//     com.signlingo/frames       → YUV maps every frame → sign detection
//     com.signlingo/video_frames → JPEG bytes throttled → local PiP + remote video
//
//   The JPEG bytes from video_frames are:
//     1. Shown locally in the PiP tile via Image.memory
//     2. Sent to the remote peer via WebRTC DataChannel (label: 'video')
//     3. Remote peer displays received JPEG via Image.memory(gaplessPlayback: true)

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signlingo/services/on_device_inference.dart';

class CameraXBridge {

  // ── Channels ──────────────────────────────────────────────────────────
  static const _methodChannel     = MethodChannel('com.signlingo/camerax');
  static const _signEventChannel  = EventChannel('com.signlingo/frames');
  static const _videoEventChannel = EventChannel('com.signlingo/video_frames');

  // ── Pipeline services ─────────────────────────────────────────────────
  final OnDeviceKeypointService  _keypointService  = OnDeviceKeypointService();
  final OnDeviceInferenceService _inferenceService = OnDeviceInferenceService();

  // ── Output notifiers wired to VideoCallScreen ─────────────────────────
  final ValueNotifier<String> signNotifier       = ValueNotifier('');
  final ValueNotifier<double> confidenceNotifier = ValueNotifier(0.0);

  // ── Video frame callback — screen uses this to update PiP and DataChannel
  void Function(Uint8List jpegBytes)? onVideoFrame;

  // ── Internal state ────────────────────────────────────────────────────
  StreamSubscription? _signFrameSub;
  StreamSubscription? _videoFrameSub;
  bool _isProcessing = false;
  bool _modelReady   = false;
  bool _kpReady      = false;
  bool _active       = false;

  // Crop config — must match CameraFeatureExtraction
  static const double _kCameraFraction = 0.65;
  int? _computedCropH;

  String _lastSign = '';

  // ─────────────────────────────────────────────────────────────────────
  // START
  // ─────────────────────────────────────────────────────────────────────
  Future<bool> start() async {
    if (_active) return true;

    _kpReady    = await _keypointService.checkAvailable();
    _modelReady = await _inferenceService.load();

    if (!_kpReady || !_modelReady) {
      debugPrint('[CameraXBridge] Pipeline not ready — kp=$_kpReady model=$_modelReady');
      return false;
    }

    // Tell Kotlin to start CameraX ImageAnalysis
    final started = await _methodChannel.invokeMethod<bool>('startCameraXCapture') ?? false;
    if (!started) {
      debugPrint('[CameraXBridge] Kotlin failed to start CameraX');
      return false;
    }

    // ── Subscribe to sign detection frames ────────────────────────────
    _signFrameSub = _signEventChannel.receiveBroadcastStream().listen(
      _onSignFrame,
      onError: (e) => debugPrint('[CameraXBridge] sign frame error: $e'),
    );

    // ── Subscribe to video preview frames ─────────────────────────────
    _videoFrameSub = _videoEventChannel.receiveBroadcastStream().listen(
      _onVideoFrame,
      onError: (e) => debugPrint('[CameraXBridge] video frame error: $e'),
    );

    _active = true;
    debugPrint('[CameraXBridge] Started — sign + video channels active');
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────
  // STOP
  // ─────────────────────────────────────────────────────────────────────
  Future<void> stop() async {
    if (!_active) return;
    _active = false;

    await _signFrameSub?.cancel();
    await _videoFrameSub?.cancel();
    _signFrameSub  = null;
    _videoFrameSub = null;

    await _methodChannel.invokeMethod('stopCameraXCapture');

    _inferenceService.resetSession();
    signNotifier.value       = '';
    confidenceNotifier.value = 0.0;
    _lastSign      = '';
    _computedCropH = null;

    debugPrint('[CameraXBridge] Stopped');
  }

  // ─────────────────────────────────────────────────────────────────────
  // SIGN FRAME HANDLER
  // Receives YUV maps from Kotlin, runs extractKeypoints + processFrame,
  // updates signNotifier and confidenceNotifier.
  // ─────────────────────────────────────────────────────────────────────
  Future<void> _onSignFrame(dynamic event) async {
    if (!_active || _isProcessing) return;

    final map    = Map<String, dynamic>.from(event as Map);
    final width  = map['width']       as int;
    final height = map['height']      as int;
    final rotDeg = map['rotationDeg'] as int;

    // Effective portrait dimensions after rotation
    final effH = (rotDeg == 90 || rotDeg == 270) ? width  : height;
    final effW = (rotDeg == 90 || rotDeg == 270) ? height : width;

    _computedCropH ??= (effH * _kCameraFraction).toInt().clamp(1, effH);

    _isProcessing = true;
    try {
      // Safe cast — Kotlin ByteArray arrives as either Uint8List or List<int>
      List<int> toList(dynamic v) =>
          v is Uint8List ? v : List<int>.from(v as List);

      final rawKp = await _keypointService.extractKeypoints(
        yPlane        : toList(map['yPlane']),
        uPlane        : toList(map['uPlane']),
        vPlane        : toList(map['vPlane']),
        yRowStride    : map['yRowStride']    as int,
        uvRowStride   : map['uvRowStride']   as int,
        uvPixelStride : map['uvPixelStride'] as int,
        width         : width,
        height        : height,
        rotationDeg   : rotDeg,
        cropLeft      : 0,
        cropTop       : 0,
        cropWidth     : effW,
        cropHeight    : _computedCropH!,
      );

      if (rawKp == null) return;

      final result = _inferenceService.processFrame(rawKp);

      // Update confidence first — listener reads it synchronously
      if (result.sign != null) {
        confidenceNotifier.value = result.confidence;
      } else if (confidenceNotifier.value != 0.0) {
        confidenceNotifier.value = 0.0;
      }

      // Only fire signNotifier when value actually changes
      final newSign = result.sign ?? _lastSign;
      if (newSign != _lastSign) _lastSign = newSign;
      if (signNotifier.value != _lastSign) signNotifier.value = _lastSign;

    } catch (e) {
      debugPrint('[CameraXBridge] sign frame error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // VIDEO FRAME HANDLER
  // Receives JPEG bytes from Kotlin (already rotated + mirrored).
  // Calls onVideoFrame so VideoCallScreen can:
  //   1. Update the local PiP tile with Image.memory
  //   2. Send bytes to remote peer via WebRTC DataChannel
  // ─────────────────────────────────────────────────────────────────────
  void _onVideoFrame(dynamic event) {
    if (!_active) return;

    Uint8List bytes;
    if (event is Uint8List) {
      bytes = event;
    } else if (event is List) {
      bytes = Uint8List.fromList(event.cast<int>());
    } else {
      return;
    }

    onVideoFrame?.call(bytes);
  }

  // ─────────────────────────────────────────────────────────────────────
  // DISPOSE
  // ─────────────────────────────────────────────────────────────────────
  void dispose() {
    _active = false;
    _signFrameSub?.cancel();
    _videoFrameSub?.cancel();
    // Fire-and-forget during dispose — engine may already be shutting down
    _methodChannel.invokeMethod('stopCameraXCapture').catchError((_) {});
    _inferenceService.dispose();
    signNotifier.dispose();
    confidenceNotifier.dispose();
  }
}