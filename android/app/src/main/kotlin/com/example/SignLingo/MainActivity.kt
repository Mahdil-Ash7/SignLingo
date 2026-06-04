package com.example.SignLingo

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.util.Log
import android.util.Size
import androidx.annotation.NonNull
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Callable


class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG             = "SignLingoMP"
        private const val CHANNEL         = "com.signlingo/keypoints"
        private const val CAMERAX_CHANNEL = "com.signlingo/camerax"
        private const val FRAMES_CHANNEL  = "com.signlingo/frames"
        private const val VIDEO_CHANNEL   = "com.signlingo/video_frames"

        private const val HAND_FEATURES     = 126
        private const val FACE_FEATURES     = 60
        private const val POSE_FEATURES     = 6
        private const val FEATURE_SIZE      = 192

        private const val VIDEO_TARGET_FPS  = 12L
        private const val VIDEO_INTERVAL_MS = 1000L / VIDEO_TARGET_FPS
        private const val VIDEO_JPEG_QUALITY = 35

        private val SELECTED_FACE_IDX = intArrayOf(
            13, 14, 78, 308, 82, 312, 33, 133, 362, 263,
            70, 63, 105, 66, 107, 336, 296, 334, 293, 300
        )
        private val POSE_IDX = intArrayOf(11, 12)

        private const val HAND_MODEL = "hand_landmarker.task"
        private const val POSE_MODEL = "pose_landmarker_lite.task"
        private const val FACE_MODEL = "face_landmarker.task"
    }

    // ── MediaPipe ─────────────────────────────────────────────────────────
    private var handLandmarker: HandLandmarker? = null
    private var poseLandmarker: PoseLandmarker? = null
    private var faceLandmarker: FaceLandmarker? = null
    private var isInitialized = false

    // ── FIX 4: Reuse a single background thread instead of spawning a new
    //    Thread on every extractKeypoints call. Thread creation costs 5–15ms
    //    on Android. A persistent single-thread executor removes this overhead.
    //    Declared as an instance field (NOT in companion object) so it is tied
    //    to the Activity lifecycle and shut down properly in onDestroy().
    private val keypointExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var argbScratch: IntArray = IntArray(320 * 240)
    private val modelExecutors: Array<ExecutorService> = Array(3) { Executors.newSingleThreadExecutor() }

    // ── CameraX ───────────────────────────────────────────────────────────
    private var cameraProvider:   ProcessCameraProvider? = null
    private var analysisExecutor: ExecutorService?       = null
    private var cameraXActive     = false

    // ── EventChannel sinks ────────────────────────────────────────────────
    private var frameEventSink: EventChannel.EventSink? = null
    private var videoEventSink: EventChannel.EventSink? = null

    private var lastVideoFrameMs = 0L

    // ─────────────────────────────────────────────────────────────────────
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 1. Keypoint channel ───────────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "checkAvailable" -> {
                    if (!isInitialized) initMediaPipe(applicationContext)
                    result.success(isInitialized)
                }

                "extractKeypoints" -> {
                    if (!isInitialized) {
                        result.error("NOT_INIT", "MediaPipe not initialized", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val yPlane        = call.argument<ByteArray>("yPlane")!!
                        val uPlane        = call.argument<ByteArray>("uPlane")!!
                        val vPlane        = call.argument<ByteArray>("vPlane")!!
                        val yRowStride    = call.argument<Int>("yRowStride")!!
                        val uvRowStride   = call.argument<Int>("uvRowStride")!!
                        val uvPixelStride = call.argument<Int>("uvPixelStride")!!
                        val width         = call.argument<Int>("width")!!
                        val height        = call.argument<Int>("height")!!
                        val rotationDeg   = call.argument<Int>("rotationDeg")!!
                        val cropLeft      = call.argument<Int>("cropLeft")!!
                        val cropTop       = call.argument<Int>("cropTop")!!
                        val cropWidth     = call.argument<Int>("cropWidth")!!
                        val cropHeight    = call.argument<Int>("cropHeight")!!

                        //   Thread { ... }.start()   ← creates new thread every call
                        //
                        // AFTER: reuse keypointExecutor — no thread creation overhead
                        keypointExecutor.submit {
                            try {
                                val kp = extractKeypoints(
                                    yPlane, uPlane, vPlane,
                                    yRowStride, uvRowStride, uvPixelStride,
                                    width, height, rotationDeg,
                                    cropLeft, cropTop, cropWidth, cropHeight
                                )
                                runOnUiThread { result.success(kp) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("EXTRACT_FAIL", e.message, null)
                                }
                            }
                        }

                    } catch (e: Exception) {
                        result.error("BAD_ARGS", e.message, null)
                    }
                }

                // "saveDebugImage" -> {
                //     try {
                //         val yPlane        = call.argument<ByteArray>("yPlane")!!
                //         val uPlane        = call.argument<ByteArray>("uPlane")!!
                //         val vPlane        = call.argument<ByteArray>("vPlane")!!
                //         val yRowStride    = call.argument<Int>("yRowStride")!!
                //         val uvRowStride   = call.argument<Int>("uvRowStride")!!
                //         val uvPixelStride = call.argument<Int>("uvPixelStride")!!
                //         val width         = call.argument<Int>("width")!!
                //         val height        = call.argument<Int>("height")!!

                //         // saveDebugImage is debug-only and not performance-critical,
                //         // but use the same executor for consistency
                //         keypointExecutor.submit {
                //             try {
                //                 val bitmap = yuvToBitmap(
                //                     yPlane, uPlane, vPlane,
                //                     yRowStride, uvRowStride, uvPixelStride,
                //                     width, height
                //                 )
                //                 val matrix = Matrix().apply { postRotate(270f) }
                //                 val rotated = Bitmap.createBitmap(
                //                     bitmap, 0, 0,
                //                     bitmap.width, bitmap.height,
                //                     matrix, true
                //                 )
                //                 val out = ByteArrayOutputStream()
                //                 rotated.compress(Bitmap.CompressFormat.JPEG, 90, out)
                //                 val bytes = out.toByteArray()
                //                 bitmap.recycle()
                //                 if (rotated != bitmap) rotated.recycle()
                //                 runOnUiThread { result.success(bytes) }
                //             } catch (e: Exception) {
                //                 runOnUiThread {
                //                     result.error("SAVE_FAIL", e.message, null)
                //                 }
                //             }
                //         }

                //     } catch (e: Exception) {
                //         result.error("BAD_ARGS", e.message, null)
                //     }
                // }

                else -> result.notImplemented()
            }
        }

        // ── 2. CameraX control channel ────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CAMERAX_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCameraXCapture" -> {
                    try {
                        startCameraXPipeline()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "startCameraXCapture error: ${e.message}", e)
                        result.error("CAMERAX_FAIL", e.message, null)
                    }
                }
                "stopCameraXCapture" -> {
                    stopCameraXPipeline()
                    result.success(true)
                }
                "isActive" -> result.success(cameraXActive)
                else -> result.notImplemented()
            }
        }

        // ── 3. Sign detection frame EventChannel ──────────────────────────
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FRAMES_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                frameEventSink = events
                Log.d(TAG, "[CameraX] Sign frame channel opened")
            }
            override fun onCancel(arguments: Any?) {
                frameEventSink = null
                Log.d(TAG, "[CameraX] Sign frame channel closed")
            }
        })

        // ── 4. Video frame EventChannel ───────────────────────────────────
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VIDEO_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                videoEventSink = events
                Log.d(TAG, "[CameraX] Video frame channel opened")
            }
            override fun onCancel(arguments: Any?) {
                videoEventSink = null
                Log.d(TAG, "[CameraX] Video frame channel closed")
            }
        })

        initMediaPipe(applicationContext)
    }

    // ─────────────────────────────────────────────────────────────────────
    // CameraX PIPELINE
    // ─────────────────────────────────────────────────────────────────────
    @SuppressLint("UnsafeOptInUsageError")
    private fun startCameraXPipeline() {
        if (cameraXActive) {
            Log.d(TAG, "[CameraX] Already active")
            return
        }

        analysisExecutor = Executors.newSingleThreadExecutor()

        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            cameraProvider = future.get()

            val imageAnalysis = ImageAnalysis.Builder()
                .setTargetResolution(Size(320, 240))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                .build()

            imageAnalysis.setAnalyzer(analysisExecutor!!) { proxy ->
                onFrameFromCameraX(proxy)
            }

            val selector = CameraSelector.Builder()
                .requireLensFacing(CameraSelector.LENS_FACING_FRONT)
                .build()

            try {
                cameraProvider?.unbindAll()
                cameraProvider?.bindToLifecycle(
                    this as LifecycleOwner,
                    selector,
                    imageAnalysis
                )
                cameraXActive = true
                Log.d(TAG, "[CameraX] Started")
            } catch (e: Exception) {
                Log.e(TAG, "[CameraX] bindToLifecycle error: ${e.message}", e)
            }

        }, ContextCompat.getMainExecutor(this))
    }

    private fun stopCameraXPipeline() {
        cameraProvider?.unbindAll()
        analysisExecutor?.shutdown()
        analysisExecutor = null
        cameraXActive    = false
        lastVideoFrameMs = 0L
        Log.d(TAG, "[CameraX] Stopped")
    }

    // ─────────────────────────────────────────────────────────────────────
    // FRAME HANDLER
    // ─────────────────────────────────────────────────────────────────────
    private fun onFrameFromCameraX(imageProxy: ImageProxy) {
        try {
            val image  = imageProxy.image ?: return
            val width  = imageProxy.width
            val height = imageProxy.height
            val rotDeg = imageProxy.imageInfo.rotationDegrees

            val yBuffer       = image.planes[0].buffer
            val uBuffer       = image.planes[1].buffer
            val vBuffer       = image.planes[2].buffer
            val yStride       = image.planes[0].rowStride
            val uvStride      = image.planes[1].rowStride
            val uvPixelStride = image.planes[1].pixelStride

            val yBytes = ByteArray(yBuffer.remaining()).also { yBuffer.get(it) }
            val uBytes = ByteArray(uBuffer.remaining()).also { uBuffer.get(it) }
            val vBytes = ByteArray(vBuffer.remaining()).also { vBuffer.get(it) }

            // PATH 1: Sign detection frames
            val frameMap = mapOf(
                "yPlane"        to yBytes,
                "uPlane"        to uBytes,
                "vPlane"        to vBytes,
                "yRowStride"    to yStride,
                "uvRowStride"   to uvStride,
                "uvPixelStride" to uvPixelStride,
                "width"         to width,
                "height"        to height,
                "rotationDeg"   to rotDeg,
            )
            runOnUiThread { frameEventSink?.success(frameMap) }

            // PATH 2: Video preview (throttled)
            val nowMs = System.currentTimeMillis()
            if (nowMs - lastVideoFrameMs >= VIDEO_INTERVAL_MS) {
                lastVideoFrameMs = nowMs
                val jpegBytes = yuvToJpegForVideo(
                    yBytes, uBytes, vBytes,
                    yStride, uvStride, uvPixelStride,
                    width, height, rotDeg
                )
                if (jpegBytes != null) {
                    runOnUiThread { videoEventSink?.success(jpegBytes) }
                }
            }

        } finally {
            imageProxy.close()
        }
    }

    private fun yuvToJpegForVideo(
        yBytes: ByteArray, uBytes: ByteArray, vBytes: ByteArray,
        yStride: Int, uvStride: Int, uvPixelStride: Int,
        width: Int, height: Int, rotDeg: Int
    ): ByteArray? {
        return try {
            val bitmap = yuvToBitmapFast(
                yBytes, uBytes, vBytes,
                yStride, uvStride, uvPixelStride,
                width, height
            )
            val matrix = Matrix().apply {
                postRotate(rotDeg.toFloat())
                postScale(-1f, 1f, bitmap.width / 2f, bitmap.height / 2f)
            }
            val rotated = Bitmap.createBitmap(
                bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true
            )
            bitmap.recycle()
            val out = ByteArrayOutputStream()
            rotated.compress(Bitmap.CompressFormat.JPEG, VIDEO_JPEG_QUALITY, out)
            rotated.recycle()
            out.toByteArray()
        } catch (e: Exception) {
            Log.e(TAG, "[Video] yuvToJpeg error: ${e.message}")
            null
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // MEDIAPIPE INIT
    // ─────────────────────────────────────────────────────────────────────
    private fun initMediaPipe(context: Context) {
        try {
            val handOptions = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder().setModelAssetPath(HAND_MODEL).build()
                )
                .setRunningMode(RunningMode.IMAGE)
                .setNumHands(2)
                .build()
            handLandmarker = HandLandmarker.createFromOptions(context, handOptions)

            val poseOptions = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder().setModelAssetPath(POSE_MODEL).build()
                )
                .setRunningMode(RunningMode.IMAGE)
                .build()
            poseLandmarker = PoseLandmarker.createFromOptions(context, poseOptions)

            val faceOptions = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder().setModelAssetPath(FACE_MODEL).build()
                )
                .setRunningMode(RunningMode.IMAGE)
                .build()
            faceLandmarker = FaceLandmarker.createFromOptions(context, faceOptions)

            isInitialized = true
            Log.d(TAG, "MediaPipe initialized")
        } catch (e: Exception) {
            Log.e(TAG, "MediaPipe init failed: ${e.message}", e)
            isInitialized = false
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // KEYPOINT EXTRACTION
    // ─────────────────────────────────────────────────────────────────────
    private fun extractKeypoints(
        yPlane: ByteArray, uPlane: ByteArray, vPlane: ByteArray,
        yRowStride: Int, uvRowStride: Int, uvPixelStride: Int,
        frameWidth: Int, frameHeight: Int, rotationDeg: Int,
        cropLeft: Int, cropTop: Int, cropWidth: Int, cropHeight: Int
    ): FloatArray {
        val bitmap = yuvToBitmapFast(
            yPlane, uPlane, vPlane,
            yRowStride, uvRowStride, uvPixelStride,
            frameWidth, frameHeight
        )

        val matrix = Matrix()
        matrix.postRotate(rotationDeg.toFloat())
        val rotated = Bitmap.createBitmap(
            bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true
        )
        if (rotated != bitmap) bitmap.recycle()

        val mirrorMatrix = Matrix()
        mirrorMatrix.postScale(
            -1f, 1f,
            rotated.width / 2f,
            rotated.height / 2f
        )
        val finalBitmap = Bitmap.createBitmap(
            rotated, 0, 0, rotated.width, rotated.height, mirrorMatrix, true
        )
        if (finalBitmap != rotated) rotated.recycle()

        val mpImage    = BitmapImageBuilder(finalBitmap).build()

        val handFuture = modelExecutors[0].submit(Callable { handLandmarker?.detect(mpImage) })
        val poseFuture = modelExecutors[1].submit(Callable { poseLandmarker?.detect(mpImage) })
        val faceFuture = modelExecutors[2].submit(Callable { faceLandmarker?.detect(mpImage) })

        val handResult = handFuture.get()   // wall time ≈ max(hand,pose,face) not sum
        val poseResult = poseFuture.get()
        val faceResult = faceFuture.get()

        finalBitmap.recycle()

        val kp = FloatArray(FEATURE_SIZE)

        handResult?.let {
            for (hi in it.landmarks().indices) {
                val label = it.handednesses()[hi].firstOrNull()?.categoryName() ?: ""
                val base  = if (label == "Left") 0 else 63
                it.landmarks()[hi].forEachIndexed { i, lm ->
                    kp[base + i * 3]     = lm.x()
                    kp[base + i * 3 + 1] = lm.y()
                    kp[base + i * 3 + 2] = lm.z()
                }
            }
        }

        faceResult?.faceLandmarks()?.firstOrNull()?.let { face ->
            SELECTED_FACE_IDX.forEachIndexed { i, idx ->
                val lm = face[idx]
                kp[HAND_FEATURES + i * 3]     = lm.x()
                kp[HAND_FEATURES + i * 3 + 1] = lm.y()
                kp[HAND_FEATURES + i * 3 + 2] = lm.z()
            }
        }

        poseResult?.landmarks()?.firstOrNull()?.let { pose ->
            POSE_IDX.forEachIndexed { i, idx ->
                val lm  = pose[idx]
                val off = HAND_FEATURES + FACE_FEATURES + i * 3
                kp[off]     = lm.x()
                kp[off + 1] = lm.y()
                kp[off + 2] = lm.z()
            }
        }

        return kp
    }

    // ─────────────────────────────────────────────────────────────────────
    // YUV → BITMAP
    // ─────────────────────────────────────────────────────────────────────
    private fun yuvToBitmapFast(
        yPlane: ByteArray, uPlane: ByteArray, vPlane: ByteArray,
        yRowStride: Int, uvRowStride: Int, uvPixelStride: Int,
        width: Int, height: Int
    ): Bitmap {
        val needed = width * height
        if (argbScratch.size < needed) argbScratch = IntArray(needed)
        val argb = argbScratch

        for (row in 0 until height) {
            val yRowBase  = row * yRowStride
            val uvRowBase = (row ushr 1) * uvRowStride
            for (col in 0 until width) {
                val yIdx  = yRowBase + col
                val uvIdx = uvRowBase + (col ushr 1) * uvPixelStride

                val yVal = yPlane[yIdx].toInt() and 0xFF
                val uVal = (if (uvIdx < uPlane.size) uPlane[uvIdx].toInt() and 0xFF else 128) - 128
                val vVal = (if (uvIdx < vPlane.size) vPlane[uvIdx].toInt() and 0xFF else 128) - 128

                // Full-range BT.601 fixed-point ×1024
                val r = (yVal + (1436 * vVal shr 10)).coerceIn(0, 255)
                val g = (yVal - (352 * uVal shr 10) - (731 * vVal shr 10)).coerceIn(0, 255)
                val b = (yVal + (1815 * uVal shr 10)).coerceIn(0, 255)

                argb[row * width + col] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        return Bitmap.createBitmap(argb, width, height, Bitmap.Config.ARGB_8888)
    }

    // ─────────────────────────────────────────────────────────────────────
    // LIFECYCLE
    // ─────────────────────────────────────────────────────────────────────
    override fun onDestroy() {
        stopCameraXPipeline()
        keypointExecutor.shutdown()
        modelExecutors.forEach { it.shutdown() }
        handLandmarker?.close()
        poseLandmarker?.close()
        faceLandmarker?.close()
        super.onDestroy()
    }
}