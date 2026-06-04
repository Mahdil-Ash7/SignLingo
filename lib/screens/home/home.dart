import 'package:flutter/material.dart';
import 'package:signlingo/services/navigation_service.dart';

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    // dark mode background (Off-black)
    const backgroundColor = Color(0xFF131415);
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 8.0,
        shadowColor: Colors.black,
        surfaceTintColor: Colors.black87,

        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: Colors.white,
        ),
        leadingWidth: 80,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset('assets/images/logo_home.png'),
        ),
        titleSpacing: -10,
        title: Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: const Text('SignLingo',style: TextStyle(fontWeight: FontWeight.w500),),
        ),
      ),
     
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Header Section
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: const Text(
                    'Learn & Practice\nBahasa Isyarat Malaysia!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Quicksand',
                      fontVariations: const [FontVariation('wght', 800)],
                      fontSize: 24,
                      height: 1.2,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Learning Card
                _buildFeatureCard(
                  context: context,
                  title: 'Learn Signs',
                  subtitle: 'Watch videos and learn Malaysian Sign Language',
                  description: 'Browse through our comprehensive dictionary of signs with video tutorials',
                  imageAsset: 'assets/images/learning.png',
                  // Using first color for face, last color for 3D shadow
                  gradientColors: [Colors.deepOrange.shade400, Colors.deepOrange.shade700],
                  icon: Icons.play_circle_fill_rounded,
                  iconColor: Colors.deepOrange.shade400,
                  onTap: () => navNotifier.value = 1,
                ),
                
                const SizedBox(height: 28),
                
                // Practice Card
                _buildFeatureCard(
                  context: context,
                  title: 'Practice Signs',
                  subtitle: 'Evaluate your signing skills',
                  description: 'Use AI-powered gesture recognition to evaluate your signing',
                  imageAsset: 'assets/images/gesture_test.png',
                  // Using first color for face, last color for 3D shadow
                  gradientColors: [Colors.teal.shade400, Colors.teal.shade700],
                  icon: Icons.assessment_rounded,
                  iconColor: Colors.teal.shade400,
                  onTap: () => navNotifier.value = 2,
                ),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String description,
    required String imageAsset,
    required List<Color> gradientColors,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    // Dark matte card color typical of Duo dark mode
    const cardColor = Color(0xFF1E2124);
    // Hard border color for the 3D effect
    const borderColor = Color(0xFF373A3F);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: borderColor,
          width: 2,
        ),
        //   signature hard bottom shadow (blurRadius: 0)
        boxShadow: const [
          BoxShadow(
            color: borderColor,
            blurRadius: 0,
            offset: Offset(0, 6),
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
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row (Icon + Text)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        icon,
                        color: iconColor,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontFamily: 'Quicksand',
                              fontVariations: const [FontVariation('wght', 900)],
                              fontSize: 22,
                              letterSpacing: -0.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 0),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 0.9,
                              fontFamily: 'Quicksand',
                              fontVariations: const [FontVariation('wght', 600)],
                              color: Color(0xFF9CA3AF), // Lighter grey
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Description
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFFD1D5DB),
                    height: 1.4,
                    fontFamily: 'Quicksand',
                    wordSpacing: -2,
                    fontVariations: const [FontVariation('wght', 400)],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Image & Action Button Stack
                Stack(
                  children: [
                    // Image Container
                    Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: borderColor,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          imageAsset,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    
                    //   3D Floating Action Button
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20, 
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: gradientColors.first, // Bright face color
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.transparent,
                            width: 0,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'GET STARTED',
                              style: TextStyle(
                                fontFamily: 'Fredoka',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}