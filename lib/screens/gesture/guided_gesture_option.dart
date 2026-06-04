import 'package:flutter/material.dart';
import 'package:signlingo/database/database_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signlingo/screens/gesture/guided_mode_screen.dart'; // Keeping your original import
import 'package:signlingo/services/on_device_inference.dart';
import 'package:signlingo/services/guided_feedback_inference.dart';
// Note: Ensure you import GuidedModeScreen if it's in a different file
// import 'package:signlingo/screens/guided_mode_screen.dart';

// Duolingo Dark Theme Colors
const Color bgColor = Color(0xFF131415);
const Color cardColor = Color(0xFF1E2124);
const Color borderColor = Color(0xFF373A3F);

class GuidedGestureOption extends StatefulWidget {
  final int categoryId;
  final SignProfileService profileService;
  final OnDeviceKeypointService keypointService;

  const GuidedGestureOption({
    super.key,
    required this.categoryId,
    required this.profileService,
    required this.keypointService,
  });

  @override
  State<GuidedGestureOption> createState() => _GuidedGestureOptionState();
}

class _GuidedGestureOptionState extends State<GuidedGestureOption> {
  final supabase = Supabase.instance.client;

  //late Future<List<Map<String, dynamic>>> _futureSigns;
  bool _servicesReady = false;

  @override
  void initState() {
    super.initState();
    _initServices();
    //_futureSigns = fetchSignList();
  }

  Future<void> _initServices() async {
    await Future.wait([
      widget.profileService.load(),
      widget.keypointService.checkAvailable(),
    ]);
    if (mounted) setState(() => _servicesReady = true);
  }

  // Future<List<Map<String, dynamic>>> fetchSignList() async {
  //   final data = await supabase
  //       .from('sign')
  //       .select('label, image_url')
  //       .eq('category_id', widget.categoryId)
  //       .order('label', ascending: true);

  //   debugPrint('Fetched Category id: ${widget.categoryId}');
  //   debugPrint('Fetched Data from Supabase: $data');

  //   return List<Map<String, dynamic>>.from(data);
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: bgColor,
        foregroundColor: Colors.white,
        leadingWidth: 60,
        titleSpacing: -5,
        leading: Padding(
          padding: const EdgeInsets.all(12),
          child: Image.asset(
            'assets/images/learning_page.png',
            fit: BoxFit.contain,
          ),
        ),
        title: const Text(
          'Practice Gestures',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 22,
            fontWeight: FontWeight.w900, // Extra bold Duo style
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
        // Duo-style flat hard bottom border
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            color: borderColor,
            height: 2,
          ),
        ),
        actions: [
          if (!_servicesReady)
            Container(
              margin: const EdgeInsets.only(right: 20),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                ),
              ),
            ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.getSignsByCategory(widget.categoryId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'LOADING GESTURES...',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/hand_landmark_icon_custom.png', 
                    color: Colors.grey.shade600, 
                    width: 80, 
                    height: 80,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'NO GESTURES FOUND.',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            );
          }

          final signs = snapshot.data!;

          print('signs: ${signs}');

          return GridView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 16, // Increased spacing for the 3D shadow
              childAspectRatio: 0.85,
            ),
            itemCount: signs.length,
            itemBuilder: (context, index) {
              final item = signs[index];
              return _buildGestureCard(item);
            },
          );
        },
      ),
    );
  }

  Widget _buildGestureCard(Map<String, dynamic> item) {
    print('item: ${item}');
    return GestureDetector(
      onTap: () {
        if (!_servicesReady) return;
        // Navigation remains untouched per your original code
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GuidedModeScreen(
              targetSign: item['label'],
              //profileService: widget.profileService,
              keypointService: widget.keypointService,
              referenceImageUrl: item['asset_path'],
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: borderColor,
            width: 2,
          ),
          // Duolingo 3D hard shadow
          boxShadow: const [
            BoxShadow(
              color: borderColor,
              blurRadius: 0,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background Image
              Image.asset(
                item['asset_path'] ?? '',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: const Color(0xFF2C2C2C),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image_rounded,
                          size: 40,
                          color: Colors.grey.shade600,
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
                  );
                },
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
                      Colors.black.withOpacity(0.95),
                    ],
                    stops: const [0.3, 0.7, 1.0],
                  ),
                ),
              ),

              // Bottom Label
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Text(
                  (item['label'] ?? '').toString().toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                ),
              ),

              // Top Right Practice Indicator (Duolingo style button/badge)
              Positioned(
                top: 12,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade500,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.shade800,
                        blurRadius: 0,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_arrow_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _servicesReady ? 'PRACTICE' : 'LOADING',
                        style: const TextStyle(
                          fontFamily: 'SF Pro Display',
                          color: Colors.white,
                          fontSize: 5,
                          fontWeight: FontWeight.w900,
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
      ),
    );
  }
}