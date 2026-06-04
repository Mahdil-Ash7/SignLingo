import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signlingo/screens/gesture/guided_gesture_option.dart';
import 'package:signlingo/services/on_device_inference.dart';
import 'package:signlingo/services/guided_feedback_inference.dart';
import 'package:signlingo/database/database_helper.dart';

// Duolingo Dark Theme Colors
const Color bgColor = Color(0xFF131415);
const Color cardColor = Color(0xFF1E2124);
const Color borderColor = Color(0xFF373A3F);

class GuidedGestureCategoryOption extends StatefulWidget {
  const GuidedGestureCategoryOption({super.key});

  @override
  State<GuidedGestureCategoryOption> createState() => _GuidedGestureCategoryOptionState();
}

class _GuidedGestureCategoryOptionState extends State<GuidedGestureCategoryOption> {
  final supabase = Supabase.instance.client;
  final SignProfileService _profileService = SignProfileService();
  final OnDeviceKeypointService _keypointService = OnDeviceKeypointService();

  bool _servicesReady = false;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await Future.wait([
      _profileService.load(),
      _keypointService.checkAvailable(),
    ]);
    if (mounted) setState(() => _servicesReady = true);
  }

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
          'Guided Sign Evaluation',
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

          return GridView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 24,
              childAspectRatio: 0.85,
            ),
            itemCount: signCategory.length,
            itemBuilder: (context, index) {
              final item = signCategory[index];

              return _buildCategoryCard(
                name: item['name'] ?? 'No Name',
                imageUrl: item['image_path'],
                categoryId: item['id'],
                index: index,
              );
            },
          );
        },
      ),
          );
        }

  Widget _buildCategoryCard({
    required String name,
    required String? imageUrl,
    required int categoryId,
    required int index,
  }) {
    return GestureDetector(
      onTap: () {
        if (!_servicesReady) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GuidedGestureOption(
              categoryId: categoryId,
              profileService: _profileService,
              keypointService: _keypointService,
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900, // Extra bold
                          fontFamily: 'SF Pro Display',
                          letterSpacing: -0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade500, // Vibrant button color
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.shade800, // Hard shadow
                                  blurRadius: 0,
                                  offset: const Offset(0, 3),
                                )
                              ]
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
                                  _servicesReady ? 'EVALUATE' : 'LOADING',
                                  style: const TextStyle(
                                    fontFamily: 'SF Pro Display',
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              // Accent corner indicator (Duolingo style)
              if (_servicesReady)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Colors.white,
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