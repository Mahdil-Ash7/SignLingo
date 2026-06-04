// lib/screens/learning/quiz/quiz_session_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart'; 
import 'package:signlingo/services/camera_feature_extraction.dart';
import 'package:signlingo/database/database_helper.dart';
import 'package:signlingo/screens/gesture/guided_gesture_category_option.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONFIG
// ─────────────────────────────────────────────────────────────────────────────
const int    kTotalQuestions    = 10;
const double kQuizConfThreshold = 0.65;
const String kBestScoreKey      = 'quiz_best_score';

const int kMaxTimePerQuestion = 20;
const int kMaxPoints = 10;
const int kMinPoints = 2;
const int kSkipPenalty = -3;
const int kHintPenalty = -5; // Penalty for using hint

//   Dark Theme Colors
const Color bgColor = Color(0xFF131415);
const Color cardColor = Color(0xFF1E2124);
const Color borderColor = Color(0xFF373A3F);

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────
class SignAndVerify {
  final String sign;
  SignAndVerify({required this.sign});
}

class SignAndVerifyResult {
  final bool correct;
  final int  secondsTaken;
  final int points;
  final bool isHintUsed;
  SignAndVerifyResult({required this.correct, required this.secondsTaken, required this.points, required this.isHintUsed});
}

// ─────────────────────────────────────────────────────────────────────────────
// SignAndVerify SESSION SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class SignAndVerifyScreen extends StatefulWidget {
  final int categoryId;
  const SignAndVerifyScreen({super.key, required this.categoryId});

  @override
  State<SignAndVerifyScreen> createState() => _QuizSessionScreenState();
}

class _QuizSessionScreenState extends State<SignAndVerifyScreen>
    with TickerProviderStateMixin {

  // ── State ────────────────────────────────────────────────────────────────
  late List<SignAndVerify> _questions;
  int  _currentIndex = 0;
  bool _answered     = false;
  bool _sessionDone  = false;
  bool _showCorrect  = false;
  bool _hintUsed     = false; // Hint state

  //sign images path
  Map<String, String> signImages = {};

  // ── Camera notifiers — fresh per question via ValueKey ───────────────────
  late ValueNotifier<String>  _signNotifier;
  late ValueNotifier<double>  _confidenceNotifier;
  final ValueNotifier<int> _bufferNotifier = ValueNotifier(0); 
  VoidCallback? _signListener;

  // ── Timer & Countdown ────────────────────────────────────────────────────
  late DateTime _questionStart;
  Timer?        _elapsedTimer;
  int           _elapsedSeconds = 0;
  
  bool _isCountingDown = true;
  int _countdownSeconds = 3;
  Timer? _countdownTimer;

  // ── Audio Players ────────────────────────────────────────────────────────
  late AudioPlayer _bgmPlayer;
  // NOTE: _sfxPlayer was removed in favor of fire-and-forget players

  // ── Score / results ───────────────────────────────────────────────────────
  final List<SignAndVerifyResult> _results      = [];
  int  _correctCount = 0;
  int  _sessionScore = 0;
  int  _bestScore    = 0;
  bool _isNewRecord  = false;
  int _lastEarnedPoints = 0;

  // ── Correct badge animation ───────────────────────────────────────────────
  late AnimationController _correctAnim;
  late Animation<double>   _correctScale;

  final _cameraKey = GlobalKey<CameraFeatureExtractionState>();

  // ── Progress dot states: null=pending, true=correct, false=skipped ────────
  final List<bool?> _dotStates = List.filled(kTotalQuestions, null);

@override
  void initState() {
    super.initState();
    _initQuiz();
  }

  Future<void> _initQuiz() async {
    await loadSignImages();   // wait until DB is ready

    _generateQuestions();     // now safe to use signImages

    await _loadBestScore();

    AudioPlayer.global.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        audioFocus: AndroidAudioFocus.none,
        usageType: AndroidUsageType.game,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
    ));

    _bgmPlayer = AudioPlayer();

    _correctAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _correctScale = CurvedAnimation(
      parent: _correctAnim,
      curve: Curves.elasticOut,
    );

    _signNotifier = ValueNotifier(' ');
    _confidenceNotifier = ValueNotifier(0.0);

    setState(() {
      _countdownSeconds = 3;
      _isCountingDown = true;
    });

    _startCountdown();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _countdownTimer?.cancel();
    _removeSignListener();
    _signNotifier.dispose();
    _confidenceNotifier.dispose();
    _correctAnim.dispose();
    _bgmPlayer.dispose();
    super.dispose();
  }
  //load sign images
    Future <void> loadSignImages() async {
    signImages = await DatabaseHelper.instance.getSignsImagePathByCategory(widget.categoryId);
    setState(() {});
  }
  // ─────────────────────────────────────────────────────────────────────────
  // AUDIO MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _playSfx(String path) async {
    // Create a temporary player for this specific sound
    final player = AudioPlayer();
    
    // Dispose of the player immediately after the sound finishes
    player.onPlayerComplete.listen((_) => player.dispose());
    
    await player.play(AssetSource(path), volume: 0.5);
  }

  Future<void> _startBgm() async {
    _bgmPlayer.setReleaseMode(ReleaseMode.loop);
    await _bgmPlayer.play(AssetSource('audio/bgm.mp3'));
    await _bgmPlayer.seek(const Duration(seconds: 19));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SETUP
  // ─────────────────────────────────────────────────────────────────────────
  void _generateQuestions() {
    print('Sign: ${signImages}');
    final all = signImages.keys.toList()..shuffle(Random());
    _questions = all
        .take(kTotalQuestions)
        .map((s) => SignAndVerify(sign: s))
        .toList();
  }

  int _calculateScore(int secondsTaken) {
    double ratio = secondsTaken / kMaxTimePerQuestion;
    int points = (kMaxPoints * (1 - ratio)).round();
    return points.clamp(kMinPoints, kMaxPoints);
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _bestScore = prefs.getInt(kBestScoreKey) ?? 0);
  }

  Future<void> _saveBestScore(int score) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kBestScoreKey, score);
  }

  void _removeSignListener() {
    if (_signListener != null) {
      try { _signNotifier.removeListener(_signListener!); } catch (_) {}
      try { _confidenceNotifier.removeListener(_signListener!); } catch (_) {}
      _signListener = null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QUESTION LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────
  void _startCountdown() {
    _playSfx('audio/tick.mp3');
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_countdownSeconds > 1) {
        setState(() => _countdownSeconds--);
        _playSfx('audio/tick.mp3');
      } else {
        timer.cancel();
        setState(() => _isCountingDown = false);
        _playSfx('audio/start.mp3');
        _startBgm();
        _startQuestion();
      }
    });
  }

  void _startQuestion() {
    _cameraKey.currentState?.resetInferenceSession();

    if (!mounted) return;
    setState(() {
      _answered       = false;
      _showCorrect    = false;
      _hintUsed       = false;
      _elapsedSeconds = 0;
    });
    _questionStart = DateTime.now();

    _removeSignListener();
    _signNotifier.value       = ' ';
    _confidenceNotifier.value = 0.0;

    _elapsedTimer?.cancel();
    
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_answered) {
        setState(() => _elapsedSeconds++);

        if (_elapsedSeconds >= kMaxTimePerQuestion) {
          _skipQuestion();
        }
      }
    });

    _signListener = _onSignNotifierChanged;
    _signNotifier.addListener(_signListener!);
    _confidenceNotifier.addListener(_signListener!);
  }

  void _onSignNotifierChanged() {
    _onSignDetected(_signNotifier.value, _confidenceNotifier.value);
  }

  void _onSignDetected(String detected, double confidence) {
    if (_answered || _sessionDone || !mounted || _isCountingDown) return;
    final target = _questions[_currentIndex].sign.trim().toLowerCase();
    if (detected.trim().toLowerCase() == target &&
        confidence >= kQuizConfThreshold) {
      _acceptAnswer();
    }
  }

  void _useHint() {
    if (_hintUsed || _answered || !mounted) return;
    
    _playSfx('audio/hint.mp3');
    setState(() {
      _hintUsed = true;
      _sessionScore += kHintPenalty; 
      _sessionScore = max(0, _sessionScore);
    });
  }

  void _acceptAnswer() {
    if (_answered || !mounted) return;

    _answered = true;
    _removeSignListener();
    _elapsedTimer?.cancel();
    _playSfx('audio/correct.mp3');

    final secs = DateTime.now().difference(_questionStart).inSeconds;
    final earnedPoints = _calculateScore(secs); 

    setState(() {
      _lastEarnedPoints = earnedPoints; 
      _showCorrect = true;
      _dotStates[_currentIndex] = true;
      _correctCount++;
      _sessionScore += earnedPoints; 

      _results.add(SignAndVerifyResult(
        correct: true,
        secondsTaken: secs,
        points: earnedPoints, 
        isHintUsed: _hintUsed
      ));
    });

    _correctAnim.forward(from: 0);

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _advance();
    });
  }

  void _skipQuestion() {
    if (_answered || !mounted) return;

    _answered = true;
    _removeSignListener();
    _elapsedTimer?.cancel();
    _playSfx('audio/skip.mp3');

    final secs = DateTime.now().difference(_questionStart).inSeconds;

    setState(() {
      _dotStates[_currentIndex] = false;
      _sessionScore += kSkipPenalty; 

      _results.add(SignAndVerifyResult(
        correct: false,
        secondsTaken: secs,
        points: kSkipPenalty, 
        isHintUsed: _hintUsed
      ));
    });

    _sessionScore = max(0, _sessionScore);
    _advance();
  }

  void _advance() {
    if (!mounted) return;
    final next = _currentIndex + 1;
    if (next >= kTotalQuestions) {
      _finishSession();
    } else {
      setState(() {
        _currentIndex = next;
        _showCorrect  = false;
      });
      _startQuestion();
    }
  }

  Future<void> _finishSession() async {
    _elapsedTimer?.cancel();
    await _bgmPlayer.stop(); // Stop BGM on finish
    
    bool newRecord = false;
    if (_sessionScore > _bestScore) {
      newRecord  = true;
      _bestScore = _sessionScore;
      await _saveBestScore(_sessionScore);
    }
    if (mounted) setState(() { _sessionDone = true; _isNewRecord = newRecord; });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LEAVE GUARD
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> _onWillPop() async {
    if (_sessionDone) return true;
    final leave = await showDialog<bool>(
      context           : context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderColor, width: 2),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber.shade400, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Leave Quiz?', 
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'SF Pro Display',
                fontWeight: FontWeight.w800,
              )
            ),
          ],
        ),
        content: Text(
          'Your progress will be lost.\n'
          'You\'ve answered ${_results.length} of $kTotalQuestions questions.',
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: _buildDuoButton(
                  text: 'LEAVE',
                  color: Colors.red.shade400,
                  shadowColor: Colors.red.shade700,
                  textColor: Colors.white,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildDuoButton(
                  text: 'KEEP GOING',
                  color: Colors.teal.shade400,
                  shadowColor: Colors.teal.shade700,
                  textColor: Colors.white,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    
    if (leave == true) {
      await _bgmPlayer.stop();
    }
    return leave ?? false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_sessionDone) return _buildResultsScreen();

    final mq      = MediaQuery.of(context);
    final usableH = mq.size.height - mq.padding.top - mq.padding.bottom;
    final cameraH = usableH * 0.58;
    final panelH  = usableH * 0.42;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Stack(
          children: [
            CameraFeatureExtraction(
              key: _cameraKey,
              signNotifier      : _signNotifier,
              confidenceNotifier: _confidenceNotifier,
              bufferNotifier: _bufferNotifier,
              cameraHeight      : cameraH,
              topLeftWidget     : _buildTopBar(),
              bottomWidget      : _buildQuizPanel(panelH),
            ),

            // ── Ghost Hint Overlay ───────────────────────────────────────
            if (_hintUsed && !_isCountingDown)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: panelH,
                child: IgnorePointer(
                  child: SizedBox.expand(
                    child: Opacity(
                      opacity: 0.3,
                      child: Image.asset(
                        signImages[_questions[_currentIndex].sign] ?? '', 
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),

            // ── Countdown Overlay ────────────────────────────────────────
            if (_isCountingDown)
              Positioned.fill(
                child: Container(
                  color: bgColor.withOpacity(0.9),
                  child: Center(
                    child: Text(
                      '$_countdownSeconds',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 120,
                        fontWeight: FontWeight.w900,
                        color: Colors.teal.shade400,
                        shadows: [
                          BoxShadow(
                            color: Colors.teal.shade900,
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ── Correct overlay ──────────────────────────────────────────
            if (_showCorrect)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black87,
                    child: Center(
                      child: ScaleTransition(
                        scale: _correctScale,
                        child: _CorrectOverlay(score: _lastEarnedPoints),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(
          children: [
            GestureDetector(
              onTap: () async {
                if (await _onWillPop()) Navigator.pop(context);
              },
              child: Container(
                padding   : const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color       : borderColor,
                  shape       : BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value          : _currentIndex / kTotalQuestions,
                  minHeight      : 14,
                  backgroundColor: borderColor,
                  valueColor     : AlwaysStoppedAnimation(Colors.teal.shade400),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding   : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color       : borderColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentIndex + 1}/$kTotalQuestions',
                style: const TextStyle(
                  fontFamily: 'SF Pro Display',
                  color     : Colors.white,
                  fontSize  : 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Quiz panel ─────────────────────────────────────────────────────────
  Widget _buildQuizPanel(double panelH) {
    final q = _questions[_currentIndex];
    return Container(
      height    : panelH,
      decoration: const BoxDecoration(
        color       : bgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin : const EdgeInsets.only(top: 12),
            width  : 40,
            height : 5,
            decoration: BoxDecoration(
              color       : borderColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Score + timer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatChip(
                  icon : Icons.star_rounded,
                  label: '$_sessionScore pts',
                  color: Colors.amber.shade400,
                ),
                _StatChip(
                  icon : Icons.timer_rounded,
                  label: '${_elapsedSeconds}s',
                  color: _elapsedSeconds > 15 
                  ? Colors.red.shade400 
                  : (_elapsedSeconds > 10 ? Colors.amber.shade400 : Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Sign prompt card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PERFORM THIS SIGN',
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    color        : Colors.white.withOpacity(0.5),
                    fontSize     : 14,
                    fontWeight   : FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width     : double.infinity,
                  padding   : const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 14),
                  decoration: BoxDecoration(
                    color       : cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border      : Border.all(color: borderColor, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: borderColor,
                        blurRadius: 0,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Text(
                    q.sign,
                    textAlign: TextAlign.center,
                    style    : const TextStyle(
                      fontFamily   : 'SF Pro Display',
                      color        : Colors.white,
                      fontSize     : 38,
                      fontWeight   : FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Hint and Skip buttons 
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              children: [
                Expanded(
                  child: _buildDuoButton(
                    text: 'HINT (-5)',
                    color: Colors.blue.shade400,
                    shadowColor: Colors.blue.shade700,
                    textColor: Colors.white,
                    onPressed: _answered || _hintUsed ? null : _useHint,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDuoButton(
                    text: 'SKIP',
                    color: Colors.red.shade400,
                    shadowColor: bgColor,
                    textColor: Colors.white,
                    onPressed: _answered ? null : _skipQuestion,
                  ),
                ),
              ],
            ),
          ),

          // Progress dots
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(kTotalQuestions, (i) {
                final state     = _dotStates[i];
                final isCurrent = i == _currentIndex;
                Color color;
                if (state == true)       color = Colors.teal.shade400;
                else if (state == false) color = Colors.red.shade400;
                else if (isCurrent)      color = Colors.white;
                else                     color = borderColor;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin  : const EdgeInsets.symmetric(horizontal: 4),
                  width   : isCurrent ? 24 : 10,
                  height  : 10,
                  decoration: BoxDecoration(
                    color       : color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESULTS SCREEN
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildResultsScreen() {
    final skipped = kTotalQuestions - _correctCount;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'LESSON COMPLETE',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 16),

              if (_isNewRecord)
                Container(
                  margin    : const EdgeInsets.only(bottom: 24),
                  padding   : const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color       : Colors.amber.shade400,
                    borderRadius: BorderRadius.circular(20),
                    border      : Border.all(color: Colors.transparent, width: 0),
                    boxShadow: [
                      BoxShadow(
                        color    : Colors.amber.shade700,
                        blurRadius: 0,
                        offset   : const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events_rounded,
                          color: Colors.amber.shade900, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'NEW PERSONAL RECORD!',
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          color     : Colors.amber.shade900,
                          fontSize  : 14,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),

              // Big score
              Text(
                '$_sessionScore',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  color     : Colors.teal.shade400,
                  fontSize  : 88,
                  fontWeight: FontWeight.w900,
                  height    : 1.0,
                  letterSpacing: -2.0,
                ),
              ),
              const Text(
                'TOTAL XP',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  color: Color(0xFF9CA3AF), 
                  fontSize: 18, 
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 40),

              // Correct / skipped
              Row(
                children: [
                  Expanded(child: _ResultCard(
                    icon : Icons.check_circle_rounded,
                    color: Colors.teal.shade400,
                    shadowColor: Colors.teal.shade700,
                    value: '$_correctCount',
                    label: 'CORRECT',
                  )),
                  const SizedBox(width: 16),
                  Expanded(child: _ResultCard(
                    icon : Icons.cancel_rounded,
                    color: Colors.red.shade400,
                    shadowColor: Colors.red.shade700,
                    value: '$skipped',
                    label: 'SKIPPED',
                  )),
                ],
              ),
              const SizedBox(height: 16),

              // Personal best
              Container(
                width     : double.infinity,
                padding   : const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color       : cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border      : Border.all(
                    color: _isNewRecord ? Colors.amber.shade400 : borderColor,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _isNewRecord ? Colors.amber.shade700 : borderColor,
                      blurRadius: 0,
                      offset: const Offset(0, 5),
                    )
                  ]
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Icon(Icons.emoji_events_rounded,
                          color: _isNewRecord ? Colors.amber.shade400 : Colors.grey,
                          size : 24),
                      const SizedBox(width: 12),
                      const Text('PERSONAL BEST',
                          style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF9CA3AF), 
                              letterSpacing: 0.5,
                              fontSize: 14)),
                    ]),
                    Text(
                      '$_bestScore XP',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        color     : _isNewRecord ? Colors.amber.shade400 : Colors.white,
                        fontSize  : 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Question review
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'LESSON REVIEW',
                  style: TextStyle(
                    fontFamily   : 'SF Pro Display',
                    color        : Colors.white.withOpacity(0.6),
                    fontSize     : 16,
                    fontWeight   : FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...List.generate(kTotalQuestions, (i) {
                final q         = _questions[i];
                final res       = i < _results.length ? _results[i] : null;
                final isCorrect = res?.correct ?? false;
                bool hintUsed = res?.isHintUsed ?? false;

                int point = res?.points ?? 0;

                if(hintUsed)
                  point = point - 5;

                return Container(
                  margin    : const EdgeInsets.only(bottom: 12),
                  padding   : const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color       : cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border      : Border.all(
                      width: 2,
                      color: isCorrect
                          ? Colors.teal.shade400.withOpacity(0.3)
                          : Colors.red.shade400.withOpacity(0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isCorrect
                          ? Colors.teal.shade400.withOpacity(0.1)
                          : Colors.red.shade400.withOpacity(0.1),
                        blurRadius: 0,
                        offset: const Offset(0, 4),
                      )
                    ]
                  ),
                  child: Row(children: [
                    Container(
                      width : 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isCorrect
                            ? Colors.teal.shade400.withOpacity(0.2)
                            : Colors.red.shade400.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isCorrect ? Icons.check_rounded : Icons.close_rounded,
                        color: isCorrect ? Colors.teal.shade400 : Colors.red.shade400,
                        size : 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        q.sign,
                        style: const TextStyle(
                          fontFamily: 'SF Pro Display',
                          color: Colors.white, 
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (res != null && isCorrect)
                      Row(children: [
                        Text('${res.secondsTaken}s',
                            style: const TextStyle(
                                color: Color(0xFF9CA3AF), 
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        const SizedBox(width: 12),

                        
                        Text(
                          '${res.points >= 0 ? '+' : ''}$point XP',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            color: Colors.amber.shade400,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      ])
                    else
                      Text(
                        '${res?.points ?? 0} XP',
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          color: Colors.red.shade400, 
                          fontWeight: FontWeight.w900,
                          fontSize: 15
                        ),
                      )
                  ]),
                );
              }),

              const SizedBox(height: 32),

              Row(children: [
                Expanded(
                  child: _buildDuoButton(
                    text: 'HOME',
                    color: borderColor,
                    shadowColor: bgColor,
                    textColor: Colors.white,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _buildDuoButton(
                    text: 'PLAY AGAIN',
                    color: Colors.teal.shade400,
                    shadowColor: Colors.teal.shade700,
                    textColor: Colors.white,
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => SignAndVerifyScreen(categoryId: widget.categoryId ,)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helper method for style buttons ──
  Widget _buildDuoButton({
    required String text,
    required Color color,
    required Color shadowColor,
    required Color textColor,
    required VoidCallback? onPressed,
  }) {
    // If the button is disabled, visually dull it down
    final bool isDisabled = onPressed == null;
    
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isDisabled ? color.withOpacity(0.4) : color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (!isDisabled)
              BoxShadow(
                color: shadowColor,
                blurRadius: 0,
                offset: const Offset(0, 5),
              ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
            color: isDisabled ? textColor.withOpacity(0.5) : textColor,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _StatChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            color     : color,
            fontSize  : 16,
            fontWeight: FontWeight.w900,
          )),
    ],
  );
}

class _CorrectOverlay extends StatelessWidget {
  final int score;
  const _CorrectOverlay({required this.score});

  @override
  Widget build(BuildContext context) => Container(
    padding   : const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
    decoration: BoxDecoration(
      color       : Colors.teal.shade400,
      borderRadius: BorderRadius.circular(32),
      boxShadow: [
        BoxShadow(
          color: Colors.teal.shade700,
          blurRadius: 0,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded,
            color: Colors.white, size: 72),
        const SizedBox(height: 16),
        const Text(
          'CORRECT!',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            color     : Colors.white,
            fontSize  : 28,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '+$score XP',
            style: const TextStyle(
              fontFamily: 'SF Pro Display',
              color     : Colors.white,
              fontSize  : 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ResultCard extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final Color    shadowColor;
  final String   value;
  final String   label;
  
  const _ResultCard({
    required this.icon,
    required this.color,
    required this.shadowColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding   : const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
    decoration: BoxDecoration(
      color       : cardColor,
      borderRadius: BorderRadius.circular(20),
      border      : Border.all(color: color, width: 2),
      boxShadow: [
        BoxShadow(
          color: shadowColor,
          blurRadius: 0,
          offset: const Offset(0, 5),
        )
      ]
    ),
    child: Column(children: [
      Icon(icon, color: color, size: 32),
      const SizedBox(height: 12),
      Text(value,
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            color     : color,
            fontSize  : 32,
            fontWeight: FontWeight.w900,
          )),
      const SizedBox(height: 4),
      Text(label,
          style: const TextStyle(
            fontFamily: 'SF Pro Display',
            color: Colors.white, 
            fontSize: 12,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w800,
          )),
    ]),
  );
}

Future<void> showSignVerifyOption(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent, // Makes the background invisible
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          
          // ─── DISCONNECTED HEADER ROW ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2124), // Matte Dark Grey
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF373A3F), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xFF373A3F), // 3D Bottom Shadow
                  blurRadius: 0,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 28),
                SizedBox(width: 12),
                Text(
                  'SIGN & VERIFY',
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12), // The disconnected gap

          // ─── DISCONNECTED BODY SECTION ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2124),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF373A3F), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xFF373A3F),
                  blurRadius: 0,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select a question category.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    color: Color(0xFF9CA3AF), // Muted grey text
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                //category option for sign and verify
                FutureBuilder<List<Map<String, dynamic>>>(  
                future: DatabaseHelper.instance.getSignCategories(), 
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Error: ${snapshot.error}'),
                    );
                  }

                  final signCategory = snapshot.data ?? [];

                  print('SignCategory: ${signCategory}');

                  return Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(10, 15, 10, 40),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: signCategory.length,
                      itemBuilder: (context, index) {
                        final item = signCategory[index];

                        return _buildCategoryCard(
                          context,
                          name: item['name'] ?? 'No Name',
                          imageUrl: item['image_path'],
                          categoryId: item['id'],
                          index: index,
                        );
                      },
                    ),
                  );

                },
              ),
          

                const SizedBox(height: 32),

                // Cancel Button (Duo Style)
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF373A3F), // Border grey background
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xFF131415), // Pitch black bottom shadow
                          blurRadius: 0,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'CANCEL',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildCategoryCard(  
  BuildContext context, {
  required String name,
  required String? imageUrl,
  required int categoryId,
  required int index,
}) {
  print ("ID: ${categoryId}");
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SignAndVerifyScreen(categoryId: categoryId,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.greenAccent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color.fromARGB(255, 65, 181, 125),
            width: 2,
          ),
          // Duolingo 3D hard shadow
          boxShadow: const [
            BoxShadow(
              color: Colors.greenAccent,
              blurRadius: 0,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background Image
              Hero(
                tag: 'category_${name}_$index',
                child: Image.asset(
                  imageUrl ?? '',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFF2C2C2C),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported_rounded,
                          size: 40,
                          color: Colors.greenAccent,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No Image',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Gradient Overlay (Darker for dark mode)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.6),
                      Colors.black.withOpacity(0.9),
                    ],
                    stops: const [0.3, 0.7, 1.0],
                  ),
                ),
              ),
              
              // Content
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w900, // Extra bold
                          fontFamily: 'SF Pro Display',
                          letterSpacing: -0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            
            ],
          ),
        ),
      ),
    );
  }
