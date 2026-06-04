// lib/services/camera_service.dart
// ==================================
// Initializes the front camera and streams raw CameraImage frames.
//
// CONFIRMED DEVICE MEASUREMENTS:
//   previewSize      : 320×240  (landscape reported by controller)
//   aspectRatio      : 1.333    (always landscape: width/height)
//   sensorOrientation: 270°
//   Rendered output  : portrait (CameraPreview applies rotation internally)
//
// DISPLAY — why we don't use FittedBox:
//   CameraPreview applies sensorOrientation rotation internally.
//   The widget's reported size is still landscape (320×240) even though
//   the rendered pixels are portrait. FittedBox and AspectRatio see the
//   pre-rotation reported size and scale incorrectly, causing distortion.
//
//   The correct approach: give CameraPreview a SizedBox.expand parent
//   so it fills all available space, and wrap in ClipRect to prevent
//   any overflow bleeding into the panel below.
//   CameraPreview handles all rotation and scaling internally.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService extends StatefulWidget {
  final void Function(CameraImage image, CameraDescription camera) onImageStream;
  final int throttleMs;

  const CameraService({
    super.key,
    required this.onImageStream,
    this.throttleMs = 120,
  });

  @override
  State<CameraService> createState() => _CameraServiceState();
}

class _CameraServiceState extends State<CameraService> {
  CameraController? _controller;
  String?           _error;
  DateTime _lastProcessedTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    debugPrint('_initCamera() started');

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _error = 'Camera permission denied');
      return;
    }

    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
      debugPrint('[camera] Found ${cameras.length} cameras: '
          '${cameras.map((c) => c.lensDirection.name).toList()}');
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to list cameras: $e');
      return;
    }
    if (cameras.isEmpty) {
      if (mounted) setState(() => _error = 'No cameras found on device');
      return;
    }

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    // ResolutionPreset.low — delivers 320×240 on this device.
    // After sensorOrientation=270° rotation → portrait 240×320.
    final controller = CameraController(
      camera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    try {
      await controller.initialize();

      debugPrint('controller.initialize() done');
      debugPrint('[camera] aspectRatio      = ${controller.value.aspectRatio}');
      debugPrint('[camera] previewSize      = ${controller.value.previewSize}');
      debugPrint('[camera] isInitialized    = ${controller.value.isInitialized}');
      debugPrint('[camera] sensorOrientation = ${camera.sensorOrientation}°');

      await controller.startImageStream((image) {
        final now = DateTime.now();
        if (now.difference(_lastProcessedTime).inMilliseconds <
            widget.throttleMs) {
          return;
        }
        _lastProcessedTime = now;
        widget.onImageStream(image, camera);
      });

      debugPrint('[camera] startImageStream() started');

    } catch (e, stack) {
      debugPrint('[camera] Camera init failed: $e');
      debugPrint('   Stack: $stack');
      if (mounted) setState(() => _error = 'Camera init failed: $e');
      return;
    }

    if (!mounted) return;
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.red, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // CameraPreview handles rotation internally via sensorOrientation.
    // It fills whatever space it is given — no FittedBox or AspectRatio
    // needed. ClipRect ensures no overflow bleeds outside the container
    // (e.g. into the panel below in live_test / guided_mode_screen).
    return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover, // This forces proportional scaling (no stretch)
              child: SizedBox(
                // Forces the box to match the camera's natural portrait dimensions
                width: _controller!.value.previewSize!.height, 
                height: _controller!.value.previewSize!.width,
                child: CameraPreview(_controller!),
              ),
            ),
          ),
        );
  }
}