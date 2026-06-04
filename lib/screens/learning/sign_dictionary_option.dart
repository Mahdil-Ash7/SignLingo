import 'package:flutter/material.dart';
import 'package:signlingo/database/database_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signlingo/services/youtube_player_flutter.dart';

class DictionaryOption extends StatefulWidget {
  final int categoryId;

  const DictionaryOption({
    super.key,
    required this.categoryId,
  });

  @override
  State<DictionaryOption> createState() => _DictionaryOptionState();
}

class _DictionaryOptionState extends State<DictionaryOption> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> signs = [];

  //   dark mode design system colors
  final backgroundColor = const Color(0xFF131415);
  final cardColor = const Color(0xFF1E2124);
  final borderColor = const Color(0xFF373A3F);

  @override
  void initState() {
    super.initState();
    fetchSignList();
  }

  void fetchSignList() async {
    signs = await DatabaseHelper.instance.getSignsByCategory(widget.categoryId);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        titleSpacing: 2,
        leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded, // A chunkier, more playful arrow
              size: 22,
            ),
            color: Colors.white, // Muted grey, or use deepOrange!
            splashColor: Colors.transparent,
            highlightColor: Colors.white.withOpacity(0.05),
            onPressed: () => Navigator.pop(context),
          ),
        title: const Text(
          'Explore Signs',
          style: TextStyle(
            fontFamily: 'Fredoka', 
            fontWeight: FontWeight.w600, 
            fontSize: 24,
            letterSpacing: -0.5,
            color: Colors.white
          ),
        ),
        backgroundColor: backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Builder(
        builder: (context) {
          if (signs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.pan_tool_alt_rounded, color: Color(0xFF373A3F), size: 72),
                  SizedBox(height: 16),
                  Text(
                    'No gestures found.',
                    style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 16,
                      fontFamily: 'Quicksand',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(top: 12, bottom: 40),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                childAspectRatio: 0.75,
              ),
              itemCount: signs.length,
              itemBuilder: (context, index) {
                return _buildGestureCard(signs, index);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildGestureCard(List<Map<String,dynamic>> signs, int index) {

    Map<String, dynamic> item;
    item = signs[index];

    print('Item: ${item}');
    final label = (item['label'] ?? '').toString();
    final imageUrl = (item['asset_path'] ?? '').toString();
    

    return GestureDetector(
      onTap: () {
        showSignPopup(
          context,
          signs: signs,
          index: index,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: borderColor,
              blurRadius: 0,
              offset: const Offset(0, 5), // 3D pushable effect
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Container(
                    color: borderColor.withOpacity(0.5),
                    child: const Icon(
                      Icons.broken_image_rounded,
                      size: 32,
                      color: Color(0xFF9CA3AF),
                    ),
                  );
                },
              ),
              
              // Dark gradient for text contrast
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      backgroundColor.withOpacity(0.85),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
              
              Positioned(
                bottom: 10,
                left: 8,
                right: 8,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'Quicksand',
                    fontVariations: [FontVariation('wght', 800)],
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showSignPopup(
    BuildContext context, {
    required List<Map<String,dynamic>> signs,
    required int index
  }) {

    Map<String, dynamic> item;
    item = signs[index];

    final sign = (item['label'] ?? '').toString();
    final imageUrl = (item['asset_path'] ?? '').toString();
    final videoUrl = (item['yt_link'] ?? '').toString();

    final String? videoId = extractYoutubeId(videoUrl);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent, // Making transparent to use custom container
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: borderColor,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: borderColor,
                  blurRadius: 0,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sign.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 24,
                              fontFamily: 'Fredoka',
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        // GestureDetector(
                        //   onTap: () => Navigator.pop(this.context),
                        //   child: Container(
                        //     padding: const EdgeInsets.all(8),
                        //     decoration: BoxDecoration(
                        //       color: borderColor.withOpacity(0.5),
                        //       shape: BoxShape.circle,
                        //     ),
                        //     child: const Icon(
                        //       Icons.close_rounded, 
                        //       color: Color(0xFF9CA3AF),
                        //       size: 20,
                        //     ),
                        //   ),
                        // ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    
                    Row(
                      spacing: 2,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        
                        // Back Button
                        GestureDetector(
                          onTap: () => {
                            Navigator.pop(this.context),
                            showSignPopup(context, signs: signs, index: index - 1)
                          },
                          child: Container(
                            width: 40, height: 170,
                            child: Icon(Icons.arrow_back_ios_new_rounded, color: const Color.fromARGB(255, 64, 64, 64),),
                            decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.rectangle,
                            border: BoxBorder.all(color: Color(0xFF9CA3AF), width: 1),
                            borderRadius: BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16))
                            ),
                          ),
                        ),

                        // Image Section
                        Container(
                          decoration: BoxDecoration(
                            //borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor, width: 2),
                          ),
                          child: ClipRRect(
                            //borderRadius: BorderRadius.circular(14),
                            child: Image.asset(
                              imageUrl,
                              height: 170,
                              width: 180,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: MediaQuery.of(context).size.height * 0.15,
                                color: borderColor.withOpacity(0.3),
                                child: const Center(
                                  child: Icon(Icons.broken_image_rounded, color: Color(0xFF9CA3AF), size: 40),
                                ),
                              ),
                            ),
                          ),
                        ),
                      
                        // Forward Button
                        GestureDetector(
                          onTap:() => {
                            Navigator.pop(this.context),
                            showSignPopup(context, signs: signs, index: index + 1)
                          },
                          child: Container(
                            width: 40, height: 170,
                            child: Icon(Icons.arrow_forward_ios_rounded, color: const Color.fromARGB(255, 64, 64, 64),),
                            decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.rectangle,
                            border: BoxBorder.all(color: Color(0xFF9CA3AF), width: 1),
                            borderRadius: BorderRadius.only(topRight: Radius.circular(16), bottomRight: Radius.circular(16))
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Video Section
                    if (videoId != null && videoId.isNotEmpty)
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SignYoutubePlayer(videoId: videoId),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: borderColor.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: 2),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.videocam_off_rounded, color: Colors.deepOrange.shade400),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Video tutorial unavailable.',
                                style: TextStyle(
                                  color: Color(0xFFD1D5DB),
                                  fontFamily: 'Quicksand',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 20),
                    
                    // Gamified 3D Close Button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.shade400,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.deepOrange.shade700,
                              blurRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'GOT IT',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'Fredoka',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4), // Padding for the bottom shadow
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? extractYoutubeId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    if (uri.host.contains('youtu.be')) {
      if (uri.pathSegments.isNotEmpty) {
        final id = uri.pathSegments.first;
        if (id.length == 11) return id;
      }
      return null;
    }

    final v = uri.queryParameters['v'];
    if (v != null && v.length == 11) return v;

    if (uri.pathSegments.length >= 2 &&
        (uri.pathSegments[0] == 'embed' || uri.pathSegments[0] == 'shorts')) {
      final id = uri.pathSegments[1];
      if (id.length == 11) return id;
    }

    return null;
  }
}