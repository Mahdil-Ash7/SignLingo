import 'package:flutter/material.dart';
import 'package:signlingo/screens/gesture/guided_gesture_category_option.dart';
import 'package:signlingo/screens/gesture/live_gesture_test.dart';

class TestSign extends StatefulWidget {
  const TestSign({super.key});

  @override
  State<TestSign> createState() => _TestSignState();
}

class _TestSignState extends State<TestSign> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  //   dark mode colors
  final Color bgColor = const Color(0xFF131415);
  final Color cardColor = const Color(0xFF1E2124);
  final Color borderColor = const Color(0xFF373A3F);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Widget optionCard({
    required IconData icon,
    required Color iconColor,
    required Color buttonShadowColor,
    required String title,
    required String desc,
    required VoidCallback onTap,
    int delay = 0,
  }) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Interval(0.2 + (delay * 0.1), 0.6 + (delay * 0.1),
              curve: Curves.easeOutCubic),
        )),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: borderColor,
                width: 2,
              ),
              //   3D hard shadow
              boxShadow: [
                BoxShadow(
                  color: borderColor,
                  blurRadius: 0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(24),
                highlightColor: Colors.white.withOpacity(0.05),
                splashColor: Colors.white.withOpacity(0.05),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      // Icon container 
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: iconColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          icon,
                          size: 32,
                          color: iconColor,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontFamily: 'SF Pro Display',
                                fontSize: 18,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              desc,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF9CA3AF),
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            //   3D Button inside the card
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: iconColor,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: buttonShadowColor,
                                    blurRadius: 0,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'TRY NOW!',
                                    style: TextStyle(
                                      fontFamily: 'SF Pro Display',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 24,
                        color: Colors.grey.shade600,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 80,
        titleSpacing: 0,
        backgroundColor: bgColor,
        foregroundColor: Colors.white,
        leadingWidth: 80,
        leading: Padding(
          padding: const EdgeInsets.all(15),
          child: Image.asset(
            'assets/images/logo_home.png',
            fit: BoxFit.contain,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BIM Gesture Evaluation',
              style: TextStyle(
                fontFamily: 'Fredoka',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
            Container(
              // decoration: BoxDecoration(
              //   color: Colors.deepOrange.withOpacity(0.2),
              //   borderRadius: BorderRadius.circular(12),
              //   border: Border.all(
              //     color: Colors.deepOrange.withOpacity(0.3),
              //   ),
              // ),
              child: Text(
                'Evaluate your BIM Skill',
                style: TextStyle(
                  color: Colors.deepOrange.shade300,
                  fontFamily: 'Quicksand',
                  fontSize: 11,
                  fontVariations: const [FontVariation('wght', 600)],
                ),
              ),
            ),
          ],
        ),

        // Duo-style flat hard bottom border instead of a blurry shadow
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            color: borderColor,
            height: 2,
          ),
        ),
        actions: [
          // Container(
          //   margin: const EdgeInsets.only(right: 16),
          //   child: IconButton(
          //     onPressed: () {
          //       // Info action
          //     },
          //     icon: const Icon(
          //       Icons.info_outline_rounded,
          //       color: Color(0xFF9CA3AF),
          //       size: 26,
          //     ),
          //   ),
          // ),
        ],
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // HERO SECTION
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.deepOrange.shade500, // Vibrant Hero Card
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.transparent, width: 0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepOrange.shade800,
                    blurRadius: 0,
                    offset: const Offset(0, 6), // 3D extrusion
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Evaluate your sign language!',
                          style: TextStyle(
                            fontFamily: 'Quicksand',
                            fontSize: 22,
                            fontVariations: const [FontVariation('wght',900)],
                            color: Colors.white,
                            letterSpacing: -0.5,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose your evaluation mode and start practicing',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '2 modes available',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Image.asset(
                        'assets/images/hand_landmark_icon_custom.png',
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 🔶 OPTION CARDS
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                [
                  optionCard(
                    icon: Icons.track_changes_rounded,
                    iconColor: Colors.green.shade400,
                    buttonShadowColor: Colors.green.shade700,
                    title: "Guided Evaluation",
                    desc: "Choose a specific sign and test if you perform it correctly.",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GuidedGestureCategoryOption(),
                        ),
                      );
                    },
                    delay: 1,
                  ),
                  const SizedBox(height: 20),
                  optionCard(
                    icon: Icons.front_hand_rounded,
                    iconColor: Colors.deepOrange.shade400,
                    buttonShadowColor: Colors.deepOrange.shade700,
                    title: "Live Recognition",
                    desc: "Perform any sign and let the system recognize it instantly.",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LiveTest(),
                        ),
                      );
                    },
                    delay: 0,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}