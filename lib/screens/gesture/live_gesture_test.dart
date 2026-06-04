// lib/screens/live_test.dart
// =====================================
// Live sign detection screen.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:signlingo/services/camera_feature_extraction.dart';
import 'package:signlingo/services/homonym_resolver.dart';
import 'package:signlingo/database/database_helper.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:signlingo/services/on_device_llm_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DARK THEME CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
const Color bgColor     = Color(0xFF131415);
const Color cardColor   = Color(0xFF1E2124);
const Color borderColor = Color(0xFF373A3F);
const Color duoTextGrey = Color(0xFF9CA3AF);
const Color colorOrange   = Colors.deepOrange;

/// Silence before sentence is finalised (seconds).
const int kSentenceTimeoutSeconds = 5;

/// How long the corrected sentence is shown before auto-clear (seconds).
const int kAutoClearSeconds = 3;

// ─────────────────────────────────────────────────────────────────────────────
// LIVE TEST
// ─────────────────────────────────────────────────────────────────────────────
class LiveTest extends StatefulWidget {
  const LiveTest({super.key});

  @override
  State<LiveTest> createState() => _LiveTestState();
}

class _LiveTestState extends State<LiveTest> {
  final ValueNotifier<String> predictedSignNotifier = ValueNotifier(' ');
  final ValueNotifier<double> confidenceNotifier    = ValueNotifier(0.0);
  final ValueNotifier<int>    bufferNotifier        = ValueNotifier(0);

  Map<String, String> signImages = {};

  // ── TTS ──────────────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool _disposed = false;
  int _speakSession = 0;
  int _ttsSession = 0;

  // ── Sentence state ────────────────────────────────────────────────────────
  List<String> _sentence          = [];
  String       _lastSign          = '';
  bool         _isResolving       = false;
  String       _resolvedSentence  = '';

  // ── Auto-correct toggle state ────────────────────────────────────────────
  bool _autoCorrectEnabled = false;
  bool _isConnectedToWifi = false;

  // ── Timers ────────────────────────────────────────────────────────────────
  Timer? _silenceTimer;
  Timer? _countdownTicker;
  Timer? _autoClearTimer;      // fires kAutoClearSeconds after correction
  int    _countdownSeconds = kSentenceTimeoutSeconds;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _tts.stop();
    });
    super.initState();
    _loadSignImages();
    _initTts();
    _checkWifiConnection();
    _startWifiMonitoring();
    printAvailableVoices();
    setAiVoice();
    predictedSignNotifier.addListener(_onSignChanged);
    _ttsSession++;
  }

  // ── TTS init ──────────────────────────────────────────────────────────────
  Future<void> _initTts() async {
    await _tts.setLanguage('ms-MY');
    await _tts.setSpeechRate(0.55);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    final langs = await _tts.getLanguages as List?;
    if (langs != null && !langs.contains('ms-MY')) {
      await _tts.setLanguage('en-US');
    }
  }

  // ── WiFi connectivity ─────────────────────────────────────────────────────
  Future<void> _checkWifiConnection() async {
    print('Connectivity result: ');
    final connectivityResult = await Connectivity().checkConnectivity();
     print('Connectivity result: $connectivityResult');
    final isWifi = connectivityResult == ConnectivityResult.wifi;
    setState(() {
      _isConnectedToWifi = isWifi;
      if (!isWifi) _autoCorrectEnabled = false;
    });
  }

  void _startWifiMonitoring() {
    Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) {
        final isWifi = result == ConnectivityResult.wifi;
        setState(() {
          _isConnectedToWifi = isWifi;
          if (!isWifi) {
            _autoCorrectEnabled = false;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('WiFi disconnected. Auto-correct disabled.', style: TextStyle(fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700)),
                backgroundColor: Colors.red.shade500,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('WiFi connected. You can enable auto-correct.', style: TextStyle(fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700)),
                backgroundColor: borderColor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        });
      }
    });
  }

  Future<void> _speak(String text) async {
    final session = ++_ttsSession;

    await _tts.stop();
    await Future.delayed(const Duration(milliseconds: 100));

    if (session != _ttsSession || _disposed) return;

    await _tts.speak(text);
  }
  // ── Sign change handler ───────────────────────────────────────────────────
  void _onSignChanged() {
    final sign = predictedSignNotifier.value.trim();
    if (sign.isEmpty || sign == _lastSign) return;
    _lastSign = sign;

    // If a corrected sentence is still visible, clear it before starting fresh
    if (_resolvedSentence.isNotEmpty) {
      _autoClearTimer?.cancel();
      setState(() => _resolvedSentence = '');
    }

    _playBeepSfx();
    _speak(sign);

    final Set<String>? homonym_group = HomonymResolver.getHomonymGroup(sign);

    final String displayText =
        homonym_group?.isNotEmpty == true
            ? homonym_group!.join('/')
            : sign;

    setState(() => _sentence.add(displayText));
    print('Sentence ${_sentence}');
    _resetSilenceTimer();
  }

  // ── Silence timer ─────────────────────────────────────────────────────────
  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _countdownTicker?.cancel();

    setState(() => _countdownSeconds = kSentenceTimeoutSeconds);

    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdownSeconds--);
    });

    _silenceTimer = Timer(
      Duration(seconds: kSentenceTimeoutSeconds),
      _finaliseSentence,
    );
  }

  // ── Finalise sentence ─────────────────────────────────────────────────────
  Future<void> _finaliseSentence() async {
    _silenceTimer?.cancel();
    _countdownTicker?.cancel();
    if (_sentence.isEmpty) return;

    // Check if auto-correct is enabled and WiFi is connected
    if (_autoCorrectEnabled && _isConnectedToWifi) {
      if (mounted) setState(() => _isResolving = true);

      print("finalisesentense with auto-correct");
      final corrected = await _correctSentence(List.from(_sentence));

      if (!mounted) return;
      setState(() {
        _resolvedSentence = corrected;
        _isResolving      = false;
        _lastSign         = '';
      });

      await _speak(corrected);
    } else {
      // Auto-correct disabled or no WiFi - just speak the raw sentence
      if (mounted) {
        final rawSentence = _sentence.join(' ');
        setState(() {
          _resolvedSentence = rawSentence;
          _lastSign = '';
        });
        await _speak(rawSentence);
      }
    }

    // ── Auto-clear after kAutoClearSeconds ───────────────────────────────
    _autoClearTimer?.cancel();
    _autoClearTimer = Timer(
      const Duration(seconds: kAutoClearSeconds),
      () { if (mounted) _clearSentence(); },
    );
  }

Future<String> _correctSentence(List<String> signs) async {
  if (OnDeviceLlmService.instance.isReady) {
    return OnDeviceLlmService.instance.correctBimSentence(signs);
  }
  // Fallback: offline letter-merge only
  return _mergeLetters(signs).join(' ');
}

// Simple offline letter merger (instant, no model needed)
List<String> _mergeLetters(List<String> signs) {
  final result = <String>[];
  final buffer = StringBuffer();
  for (final sign in signs) {
    if (sign.length == 1 && RegExp(r'[A-Za-z]').hasMatch(sign)) {
      buffer.write(sign.toUpperCase());
    } else {
      if (buffer.isNotEmpty) { result.add(buffer.toString()); buffer.clear(); }
      result.add(sign);
    }
  }
  if (buffer.isNotEmpty) result.add(buffer.toString());
  return result;
}

  void _playBeepSfx() {
    final player = AudioPlayer();
    player.onPlayerComplete.listen((_) => player.dispose());
    player.play(AssetSource('audio/beep.mp3'), volume: 100);
  }

  void _clearSentence() {
    _silenceTimer?.cancel();
    _countdownTicker?.cancel();
    _autoClearTimer?.cancel();
    setState(() {
      _sentence.clear();
      _lastSign         = '';
      _isResolving      = false;
      _resolvedSentence = '';
      _countdownSeconds = kSentenceTimeoutSeconds;
    });
    _tts.stop();
  }

  void _speakSentence() {
    final text = _resolvedSentence.isNotEmpty
        ? _resolvedSentence
        : _sentence.join(' ');
    if (text.isNotEmpty) _speak(text);
  }

  Future<void> _loadSignImages() async {
    final images = await DatabaseHelper.instance.getSignsImagePath();
    if (mounted) setState(() => signImages = images);
  }

  Future<void> printAvailableVoices() async {
  // Returns a list of dynamic (Maps) containing voice data
  List<dynamic> voices = await _tts.getVoices;
  
  for (var voice in voices) {
    print('Voice Name: ${voice['name']} | Locale: ${voice['locale']}');
  }
}

Future<void> setAiVoice() async {
  // Set the voice engine variant
  await _tts.setVoice({
    "name": "ms-my-x-msc-network",
    "locale": " ms-MY"
  });

  // AI assistants usually sound crisp with a slightly higher pitch (1.0 - 1.2)
  // and a moderate speech rate (0.4 - 0.5)
  await _tts.setPitch(0.5); 
  await _tts.setSpeechRate(0.45);

  await _tts.speak("Selamat Datang Ke SignLinggo");
}


  void _toggleAutoCorrect(bool value) {
    setState(() {
      _autoCorrectEnabled = value;
    });
    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value 
          ? 'Auto-correct enabled' 
          : 'Auto-correct disabled. Raw signs will be used.',
          style: const TextStyle(fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: value ? borderColor : colorOrange,
      ),
    );
  }

  @override
  void dispose() {
      _disposed = true;

    _silenceTimer?.cancel();
    _countdownTicker?.cancel();
    _autoClearTimer?.cancel();
    predictedSignNotifier.removeListener(_onSignChanged);
    predictedSignNotifier.dispose();
    confidenceNotifier.dispose();
    bufferNotifier.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq           = MediaQuery.of(context);
    final usableHeight = mq.size.height - mq.padding.top - mq.padding.bottom;
    final panelHeight  = usableHeight * 0.35;
    final cameraHeight = usableHeight * 0.65;

    final bool isCollecting =
        _sentence.isNotEmpty && !_isResolving && _resolvedSentence.isEmpty;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ── Camera + bottom panel ────────────────────────────────────────
          CameraFeatureExtraction(
            signNotifier      : predictedSignNotifier,
            confidenceNotifier: confidenceNotifier,
            bufferNotifier    : bufferNotifier,
            cameraHeight      : cameraHeight,
            showHandLandmarks : true,
            bottomWidget      : _BottomPanel(
              panelHeight       : panelHeight,
              signNotifier      : predictedSignNotifier,
              confidenceNotifier: confidenceNotifier,
              bufferNotifier    : bufferNotifier,
              signImages        : signImages,
              isResolving       : _isResolving,
              sentence          : _sentence,
              resolvedSentence  : _resolvedSentence,
              onClear           : _clearSentence,
              onSpeak           : _speakSentence,
            ),
          ),

          // ── TOP overlays (SafeArea column) ───────────────────────────────
          Positioned(
            top  : 0,
            left : 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Auto-correct toggle button (top-left)
                  Padding(
                    padding: const EdgeInsets.only(left: 140, top: 10),
                    child: _AutoCorrectToggle(
                      isEnabled: _autoCorrectEnabled,
                      isConnectedToWifi: _isConnectedToWifi,
                      onToggle: _toggleAutoCorrect,
                    ),
                  ),

                  // 2. Large sign label (top-right of camera)
                  // Padding(
                  //   padding: const EdgeInsets.fromLTRB(76, 12, 16, 0),
                  //   child: _SignCameraOverlay(
                  //     signNotifier     : predictedSignNotifier,
                  //     isCollecting     : isCollecting,
                  //     isResolving      : _isResolving,
                  //     resolvedSentence : _resolvedSentence,
                  //   ),
                  // ),

                  const SizedBox(height: 12),

                  // 3. Word-by-word collection chips (now below sign label)
                  if (_sentence.isNotEmpty || _isResolving || _resolvedSentence.isNotEmpty)
                    Opacity(
                      opacity: 0.5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _SentenceOverlay(
                          sentence        : _sentence,
                          resolvedSentence: _resolvedSentence,
                          isResolving     : _isResolving,
                          countdown       : isCollecting ? _countdownSeconds : -1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Back button ──────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, left: 16),
              child: GestureDetector(
                onTap: () async {
                await _tts.stop();
                if (context.mounted) Navigator.pop(context);
              },
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
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTO-CORRECT TOGGLE BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _AutoCorrectToggle extends StatelessWidget {
  final bool isEnabled ;
  final bool isConnectedToWifi;
  final Function(bool) onToggle;

  const _AutoCorrectToggle({
    required this.isEnabled,
    required this.isConnectedToWifi,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.3,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isConnectedToWifi 
              ? (isEnabled ? colorOrange : borderColor)
              : Colors.red.shade400,
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: bgColor,
              blurRadius: 0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isConnectedToWifi ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              size: 16,
              color: isConnectedToWifi 
                ? (isEnabled ? colorOrange : duoTextGrey)
                : Colors.red.shade400,
            ),
            const SizedBox(width: 8),
            Text(
              'AUTO-CORRECT',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                color: isConnectedToWifi 
                  ? (isEnabled ? Colors.white : duoTextGrey)
                  : Colors.red.shade300,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: isEnabled && isConnectedToWifi,
                onChanged: isConnectedToWifi ? onToggle : null,
                activeColor: Colors.white,
                activeTrackColor: borderColor,
                inactiveThumbColor: duoTextGrey,
                inactiveTrackColor: bgColor,
                trackOutlineColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? Colors.transparent : borderColor,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIGN CAMERA OVERLAY — large current-sign label
// ─────────────────────────────────────────────────────────────────────────────
// class _SignCameraOverlay extends StatelessWidget {
//   final ValueNotifier<String> signNotifier;
//   final bool                  isCollecting;
//   final bool                  isResolving;
//   final String                resolvedSentence;

//   const _SignCameraOverlay({
//     required this.signNotifier,
//     required this.isCollecting,
//     required this.isResolving,
//     required this.resolvedSentence,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return ValueListenableBuilder<String>(
//       valueListenable: signNotifier,
//       builder: (_, rawSign, __) {
//         final sign    = rawSign.trim();
//         final label   = sign.isEmpty
//             ? ''
//             : HomonymResolver.getDisplayLabel(sign).toUpperCase();

//         if (isResolving || resolvedSentence.isNotEmpty) return const SizedBox.shrink();
//         if (label.isEmpty) return const SizedBox.shrink();

//         final hasHomonym = HomonymResolver.hasHomonym(sign);
//         final themeColor = hasHomonym ? colorOrange : borderColor;

//         return AnimatedSwitcher(
//           duration: const Duration(milliseconds: 180),
//           transitionBuilder: (child, anim) => FadeTransition(
//             opacity: anim,
//             child: SlideTransition(
//               position: Tween<Offset>(
//                 begin: const Offset(0, -0.3),
//                 end  : Offset.zero,
//               ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
//               child: child,
//             ),
//           ),
//           child: Container(
//             key        : ValueKey(label),
//             padding    : const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
//             decoration : BoxDecoration(
//               color       : cardColor,
//               borderRadius: BorderRadius.circular(20),
//               border: Border.all(
//                 color: themeColor,
//                 width: 2,
//               ),
//               boxShadow: [
//                 BoxShadow(
//                   color : themeColor.withOpacity(0.5),
//                   blurRadius: 0,
//                   offset: const Offset(0, 5),
//                 ),
//               ],
//             ),
//             child: Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Container(
//                   width : 10, height: 10,
//                   decoration: BoxDecoration(
//                     shape: BoxShape.circle,
//                     color: isCollecting
//                         ? Colors.red.shade400
//                         : borderColor,
//                   ),
//                 ),
//                 const SizedBox(width: 12),
//                 Text(
//                   label,
//                   style: TextStyle(
//                     fontFamily: 'SF Pro Display',
//                     color     : themeColor,
//                     fontSize  : hasHomonym ? 8 : 10,
//                     fontWeight: FontWeight.w900,
//                     letterSpacing: 1.0,
//                   ),
//                 ),
//                 if (hasHomonym) ...[
//                   const SizedBox(width: 8),
//                   Icon(Icons.swap_horiz_rounded,
//                       color: colorOrange, size: 20),
//                 ],
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }
// }


// ─────────────────────────────────────────────────────────────────────────────
// SENTENCE OVERLAY — word chips while collecting + animated corrected result
// ─────────────────────────────────────────────────────────────────────────────
class _SentenceOverlay extends StatelessWidget {
  final List<String> sentence;
  final String       resolvedSentence;
  final bool         isResolving;
  final int          countdown; // -1 = hide

  const _SentenceOverlay({
    required this.sentence,
    required this.resolvedSentence,
    required this.isResolving,
    required this.countdown,
  });

  @override
  Widget build(BuildContext context) {
    Color borderCol;
    if (isResolving)                      borderCol = colorOrange;
    else if (resolvedSentence.isNotEmpty) borderCol = borderColor;
    else                                  borderCol = borderColor;

    Widget content;

    // ── Resolving spinner ─────────────────────────────────────────────────
    if (isResolving) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 3, color: colorOrange),
          ),
          const SizedBox(width: 12),
          const Text(
            'AI CORRECTING...',
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              color    : colorOrange,
              fontSize : 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ],
      );

    // ── Corrected sentence — animated per-word blocks ─────────────────────
    } else if (resolvedSentence.isNotEmpty) {
      content = _CorrectedSentenceBlocks(sentence: resolvedSentence);

    // ── Collecting — word chips + countdown ───────────────────────────────
    } else if (sentence.isEmpty) {
      content = const Text(
        'START SIGNING...',
        style: TextStyle(
          fontFamily: 'SF Pro Display',
          color    : duoTextGrey,
          fontSize : 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      );
    } else {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing   : 8,
              runSpacing: 8,
              children  : sentence.asMap().entries.map((e) {
                final isLatest = e.key == sentence.length - 1;
                return AnimatedContainer(
                  duration  : const Duration(milliseconds: 180),
                  padding   : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color       : isLatest
                        ? borderColor.withOpacity(0.15)
                        : bgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isLatest ? borderColor : borderColor,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    e.value.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      color     : isLatest ? borderColor : Colors.white,
                      fontSize  : 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (countdown >= 0) ...[
            const SizedBox(width: 12),
            _CountdownBadge(seconds: countdown),
          ],
        ],
      );
    }

    return Container(
      width     : double.infinity,
      padding   : const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color       : cardColor,
        borderRadius: BorderRadius.circular(20),
        border      : Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: borderCol.withOpacity(0.3), // Tinted shadow based on state
            blurRadius: 0,
            offset: const Offset(0, 5),
          )
        ]
      ),
      child: content,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CORRECTED SENTENCE BLOCKS — staggered pop-in animation per word
// ─────────────────────────────────────────────────────────────────────────────
class _CorrectedSentenceBlocks extends StatefulWidget {
  final String sentence;
  const _CorrectedSentenceBlocks({required this.sentence});

  @override
  State<_CorrectedSentenceBlocks> createState() =>
      _CorrectedSentenceBlocksState();
}

class _CorrectedSentenceBlocksState extends State<_CorrectedSentenceBlocks> {
  List<bool> _visible = [];

  @override
  void initState() {
    super.initState();
    _scheduleAnimations();
  }

  @override
  void didUpdateWidget(_CorrectedSentenceBlocks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sentence != widget.sentence) _scheduleAnimations();
  }

  void _scheduleAnimations() {
    final words = widget.sentence.split(' ').where((w) => w.isNotEmpty).toList();
    _visible = List.filled(words.length, false);

    for (int i = 0; i < words.length; i++) {
      Future.delayed(Duration(milliseconds: 80 * i), () {
        if (mounted) setState(() => _visible[i] = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.sentence
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        const Row(
          children: [
            Icon(Icons.auto_fix_high_rounded, color: borderColor, size: 16),
            SizedBox(width: 8),
            Text(
              'CORRECTED SENTENCE',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                color     : borderColor,
                fontSize  : 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Animated word blocks
        Wrap(
          spacing   : 8,
          runSpacing: 8,
          children  : words.asMap().entries.map((e) {
            final idx     = e.key;
            final word    = e.value;
            final visible = idx < _visible.length ? _visible[idx] : false;

            return AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity : visible ? 1.0 : 0.0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 250),
                offset  : visible ? Offset.zero : const Offset(0, 0.4),
                curve   : Curves.easeOutBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color       : borderColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border      : Border.all(
                        color: borderColor, width: 2),
                  ),
                  child: Text(
                    word.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      color     : Colors.white,
                      fontSize  : 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COUNTDOWN BADGE
// ─────────────────────────────────────────────────────────────────────────────
class _CountdownBadge extends StatelessWidget {
  final int seconds;
  const _CountdownBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final isUrgent = seconds <= 1;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isUrgent ? Colors.red.shade500.withOpacity(0.15) : bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUrgent ? Colors.red.shade400 : borderColor,
          width: 2,
        ),
      ),
      child: Text(
        '$seconds S',
        style: TextStyle(
          fontFamily: 'SF Pro Display',
          color     : isUrgent ? Colors.red.shade400 : duoTextGrey,
          fontSize  : 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _BottomPanel extends StatelessWidget {
  final double                panelHeight;
  final ValueNotifier<String> signNotifier;
  final ValueNotifier<double> confidenceNotifier;
  final ValueNotifier<int>    bufferNotifier;
  final Map<String, String>   signImages;
  final bool                  isResolving;
  final List<String>          sentence;
  final String                resolvedSentence;
  final VoidCallback          onClear;
  final VoidCallback          onSpeak;

  const _BottomPanel({
    required this.panelHeight,
    required this.signNotifier,
    required this.confidenceNotifier,
    required this.bufferNotifier,
    required this.signImages,
    required this.isResolving,
    required this.sentence,
    required this.resolvedSentence,
    required this.onClear,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: panelHeight,
      decoration: const BoxDecoration(
        color       : cardColor,
        borderRadius: BorderRadius.only(
          topLeft : Radius.circular(32),
          topRight: Radius.circular(32),
        ),
        border: Border(top: BorderSide(color: borderColor, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 48,
            height: 6,
            decoration: BoxDecoration(
              color: borderColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: ValueListenableBuilder<String>(
                valueListenable: signNotifier,
                builder: (_, rawSign, __) {
                  final trimmed      = rawSign.trim();
                  final isWaiting    = trimmed.isEmpty;
                  final displayLabel = isWaiting
                      ? '...'
                      : HomonymResolver.getDisplayLabel(trimmed);
                  final hasHomonym   =
                      !isWaiting && HomonymResolver.hasHomonym(trimmed);

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        displayLabel.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          color     : isWaiting
                              ? borderColor
                              : borderColor,
                          fontSize  : hasHomonym ? 28 : 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                        textAlign: TextAlign.center,
                        maxLines : 1,
                        overflow : TextOverflow.ellipsis,
                      ),

                      if (hasHomonym)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'THESE SIGNS SHARE THE SAME HANDSHAPE',
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              color     : colorOrange,
                              fontSize  : 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      const SizedBox(height: 12),

                      Opacity(
                        opacity: 0.60,
                        child: ValueListenableBuilder<int>(
                          valueListenable: bufferNotifier,
                          builder: (_, bufferSize, __) =>
                              _NeuronThinkingIndicator(
                            current: bufferSize,
                            max    : kRawBufferMax,
                          ),
                        ),
                      ),

                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION CHIP
// ─────────────────────────────────────────────────────────────────────────────
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  final Color    color;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color       : color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border      : Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 0,
              offset: const Offset(0, 4),
            )
          ]
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                color     : color,
                fontSize  : 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEURON THINKING INDICATOR 
// ─────────────────────────────────────────────────────────────────────────────
class _NeuronThinkingIndicator extends StatefulWidget {
  final int current;
  final int max;

  const _NeuronThinkingIndicator({required this.current, required this.max});

  @override
  State<_NeuronThinkingIndicator> createState() =>
      _NeuronThinkingIndicatorState();
}

class _NeuronThinkingIndicatorState extends State<_NeuronThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (widget.current / widget.max).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: SizedBox(
              width : 100,
              height: 100,
              child : CustomPaint(
                painter: _NeuronPainter(
                  progress : ratio,
                  animation: _pulseController,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NeuronPainter extends CustomPainter {
  final double             progress;
  final Animation<double> animation;

  _NeuronPainter({required this.progress, required this.animation})
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final double pulse       = animation.value;
    final double smoothPulse = math.sin(pulse * math.pi);

    final center = Offset(size.width / 2, size.height / 2);
    final scale  = size.width / 40.0;

    final Color primaryGrey = duoTextGrey; // Using duo grey
    final Color darkGrey    = borderColor;

    final Paint fillPaint   = Paint()..style = PaintingStyle.fill;
    final Paint strokePaint = Paint()
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale;

    final backgroundGlow = Paint()
      ..color      = darkGrey.withOpacity(0.05 * (0.5 + 0.5 * smoothPulse))
      ..style      = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 20.0 * scale);
    canvas.drawCircle(center, (25.0 + (8.0 * smoothPulse)) * scale, backgroundGlow);

    if (progress > 0) {
      final ringRadius = 15.0 * scale;

      final bgRingPaint = Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2.0 * scale
        ..strokeCap   = StrokeCap.round
        ..color       = primaryGrey.withOpacity(0.1);
      canvas.drawCircle(center, ringRadius, bgRingPaint);

      final ringPaint = Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2.0 * scale
        ..strokeCap   = StrokeCap.round
        ..color       = borderColor.withOpacity(0.5 + 0.5 * smoothPulse); // Green ring when active
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        ringPaint,
      );

      final endAngle = -math.pi / 2 + 2 * math.pi * progress;
      final endX     = center.dx + ringRadius * math.cos(endAngle);
      final endY     = center.dy + ringRadius * math.sin(endAngle);

      final dotPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(endX, endY), (2.5 + smoothPulse) * scale, dotPaint);

      final dotGlow = Paint()
        ..color      = borderColor.withOpacity(0.5)
        ..style      = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * scale);
      canvas.drawCircle(Offset(endX, endY), (4.0 + smoothPulse) * scale, dotGlow);
    }

    final baseRadius = 5.0 * scale;
    final radius     = baseRadius + (2.0 * smoothPulse * scale);

    final auraPaint = Paint()
      ..color      = primaryGrey.withOpacity(0.15 * smoothPulse)
      ..style      = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8.0 * scale);
    canvas.drawCircle(center, radius * 3.0, auraPaint);

    final mediumGlow = Paint()
      ..color      = primaryGrey.withOpacity(0.3 * smoothPulse)
      ..style      = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * scale);
    canvas.drawCircle(center, radius * 2.0, mediumGlow);

    fillPaint.color = primaryGrey.withOpacity(0.9 + 0.1 * smoothPulse);
    canvas.drawCircle(center, radius, fillPaint);

    strokePaint.color = Colors.white.withOpacity(0.6);
    canvas.drawCircle(center, radius * 0.5, strokePaint);

    final corePaint = Paint()
      ..color = Colors.white.withOpacity(0.8 * (1 - smoothPulse))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.25, corePaint);

    if (progress > 0) {
      const particleCount = 4;
      for (int p = 0; p < particleCount; p++) {
        final angle = (smoothPulse * 2 * math.pi) +
            (p * 2 * math.pi / particleCount);
        final orbitRadius = radius * 2.5;
        final particleX   = center.dx + orbitRadius * math.cos(angle);
        final particleY   = center.dy + orbitRadius * math.sin(angle);

        final particlePaint = Paint()
          ..color = primaryGrey.withOpacity(0.5 * (1 - smoothPulse * 0.5))
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(particleX, particleY), 1.5 * scale, particlePaint);
      }
    }

    if (progress > 0.2) {
      const particleCount = 8;
      for (int p = 0; p < particleCount; p++) {
        final particleProgress = (p / particleCount + smoothPulse) % 1.0;
        if (progress > particleProgress) {
          final angle    = p * 2 * math.pi / particleCount;
          final distance = (20.0 + 10.0 * particleProgress) * scale;
          final x        = center.dx + distance * math.cos(angle);
          final y        = center.dy + distance * math.sin(angle);

          final dustPaint = Paint()
            ..color = primaryGrey.withOpacity(0.15 * (1 - smoothPulse))
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(x, y), 1.0 * scale, dustPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NeuronPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.animation != animation;
}
