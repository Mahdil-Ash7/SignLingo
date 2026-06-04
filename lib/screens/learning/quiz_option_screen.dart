// lib/screens/quiz_option_screen.dart
// =====================================
// Quiz hub page. The "Sign & Get Verified" card launches QuizSessionScreen.
// Best score is loaded from SharedPreferences and shown live on the card.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signlingo/screens/learning/quiz/sign_and_verify.dart';
import 'package:video_player/video_player.dart';

const String kBestScoreKey = 'quiz_best_score'; // must match quiz_session_screen.dart

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double>   _scaleAnimation;
  late VideoPlayerController _videoController;
  int _bestScore = 0;

  //   Dark Theme Colors
  final Color bgColor = const Color(0xFF131415);
  final Color cardColor = const Color(0xFF1E2124);
  final Color borderColor = const Color(0xFF373A3F);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

      _videoController = VideoPlayerController.asset(
    'assets/videos/quiz_preview.mp4',
  )
    ..setLooping(true)
    ..setVolume(0) // mute
    ..initialize().then((_) {
      setState(() {});
      _videoController.play();
    });

    _loadBestScore();
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _bestScore = prefs.getInt(kBestScoreKey) ?? 0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade400.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.bolt_rounded,
                        color: Colors.amber.shade400,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        "Interactive BIM Learning",
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize  : 24,
                          height    : 1.2,
                          letterSpacing: -0.5,
                          fontWeight: FontWeight.w900, //   extra-bold
                          color     : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Text(
                  "Level up your skills by completing various challenges.",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),

              // ── Main Quiz Card ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: borderColor,
                      width: 2,
                    ),
                    //   3D extruded shadow
                    boxShadow: [
                      BoxShadow(
                        color      : borderColor,
                        blurRadius : 0,
                        offset     : const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card image
                      Container(
                        clipBehavior: Clip.hardEdge,
                        width       : double.infinity,
                        height      : 180,
                        decoration  : const BoxDecoration(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                          color       : Color(0xFF131415),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              'assets/images/login_bg.jpg',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: const Color(0xFF2C2C2C)),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin : Alignment.topCenter,
                                  end   : Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    cardColor.withOpacity(0.8),
                                    cardColor,
                                  ],
                                  stops: const [0.4, 0.8, 1.0],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Card content
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Sign & Verify",
                                  style: TextStyle(
                                    fontFamily: 'SF Pro Display',
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                    fontSize  : 24,
                                    color     : Colors.white,
                                  ),
                                ),
                                Container(
                                  padding   : const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color        : Colors.tealAccent.shade400.withOpacity(0.15),
                                    borderRadius : BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.tealAccent.shade400.withOpacity(0.3),
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    "NEW",
                                    style: TextStyle(
                                      color     : Colors.tealAccent.shade400,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                      fontSize  : 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Quick stats row
                            Row(
                              children: [
                                _MiniStat(
                                  icon : Icons.quiz_rounded,
                                  label: '10 Questions',
                                  color: Colors.tealAccent.shade400,
                                ),
                                const SizedBox(width: 16),
                                _MiniStat(
                                  icon : Icons.star_rounded,
                                  label: 'Max 150 pts',
                                  color: Colors.amber.shade400,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            Text(
                              "Answer randomly generated quiz questions by performing the correct sign! Earn XP for every correct answer.",
                              style: TextStyle(
                                color   : Colors.white.withOpacity(0.7),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height  : 1.4,
                              ),
                            ),
                            
                            const SizedBox(height: 28),

                            // Animated start button (Duo Style)
                            GestureDetector(
                              onTap: () => showSignVerifyOption(context),
                              child: ScaleTransition(
                                scale: _scaleAnimation,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 16),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: Colors.teal.shade400, // Vibrant flat color
                                    boxShadow: [
                                      BoxShadow(
                                        color      : Colors.teal.shade700, // Hard 3D bottom border
                                        blurRadius : 0,
                                        offset     : const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "PLAY",
                                        style: TextStyle(
                                          fontFamily: 'SF Pro Display',
                                          color     : Colors.white,
                                          letterSpacing: 1.0,
                                          fontSize  : 16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),
                            
                            // ── Best score strip ─────────────────────────────────────
                            if (_bestScore > 0)
                              Container(
                                width: double.infinity,
                                padding   : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color        : bgColor, // Inset dark background
                                  borderRadius : BorderRadius.circular(16),
                                  border       : Border.all(color: borderColor, width: 2),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.emoji_events_rounded, color: Colors.amber.shade400, size: 22),
                                    const SizedBox(width: 8),
                                    Text(
                                      'PERSONAL BEST:',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5), 
                                        fontSize: 12,
                                        letterSpacing: 0.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$_bestScore PTS',
                                      style: TextStyle(
                                        color     : Colors.amber.shade400,
                                        fontSize  : 14,
                                        letterSpacing: 0.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // Adjusted unused badge to match the style in case you need it later
  Widget _buildStatBadge(IconData icon, String label, Color color) {
    return Container(
      padding   : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color        : color.withOpacity(0.15),
        borderRadius : BorderRadius.circular(14),
        border       : Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color     : color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              fontSize  : 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MINI STAT CHIP
// ─────────────────────────────────────────────────────────────────────────────
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _MiniStat({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          color: color, 
          fontSize: 14, 
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}