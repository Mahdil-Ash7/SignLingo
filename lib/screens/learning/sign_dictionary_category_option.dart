import 'package:flutter/material.dart';
import 'package:signlingo/screens/learning/sign_dictionary_option.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signlingo/database/database_helper.dart';

class SignDictionary extends StatefulWidget {
  const SignDictionary({super.key});

  @override
  State<SignDictionary> createState() => _SignDictionaryState();
}

class _SignDictionaryState extends State<SignDictionary> {
  final supabase = Supabase.instance.client;
  bool _isGridView = true;

  List<Map<String, dynamic>> signCategory = [];
  bool isLoading = true;
  String? error;

  //   dark mode design system colors
  final backgroundColor = const Color(0xFF131415);
  final cardColor = const Color(0xFF1E2124);
  final borderColor = const Color(0xFF373A3F);

@override
void initState() {
  super.initState();
  fetchSignsCategory();
}

  Future<void> fetchSignsCategory() async {
    
    try{
    final result = await DatabaseHelper.instance.getSignCategories();
    setState(() {
      signCategory = result;
      print('signCategory: ${signCategory}');
      isLoading = false;
      error = null;
    });
   } catch(e){
      setState(() {
      error = e.toString();
      isLoading = false;
    });
   }

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        leadingWidth: 60,
        titleSpacing: 5,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Image.asset(
            'assets/images/logo_home.png',
            fit: BoxFit.contain,
          ),
        ),
        title: const Text(
          'Dictionary',
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          // Toggle view button styled to match the dark 3D theme
          Container(
            margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: borderColor,
                  blurRadius: 0,
                  offset: const Offset(0, 2), // Smaller shadow for the app bar button
                ),
              ],
            ),
            child: ToggleButtons(
              isSelected: [_isGridView, !_isGridView],
              onPressed: (index) {
                setState(() {
                  _isGridView = index == 0;
                });
              },
              borderRadius: BorderRadius.circular(10),
              selectedColor: Colors.deepOrange.shade400,
              color: const Color(0xFF9CA3AF),
              fillColor: Colors.deepOrange.withOpacity(0.15),
              constraints: const BoxConstraints(
                minHeight: 36,
                minWidth: 40,
              ),
              children: const [
                Icon(Icons.grid_view_rounded, size: 20),
                Icon(Icons.list_rounded, size: 20),
              ],
            ),
          ),
        ],
      ),
    body: Builder(
      builder: (context) {
        if (isLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.deepOrange.shade400,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Loading categories...',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontFamily: 'Quicksand',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        if (error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red.shade400,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Error loading categories',
                  style: TextStyle(
                    color: Color(0xFFD1D5DB),
                    fontFamily: 'Quicksand',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (signCategory.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  size: 64,
                  color: Color(0xFF373A3F),
                ),
                SizedBox(height: 16),
                Text(
                  'No categories found',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontFamily: 'Quicksand',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        return _isGridView
            ? _buildGridView(signCategory)
            : _buildListView(signCategory);
      },
    ),
    );
  }

  Widget _buildGridView(List<Map<String, dynamic>> categories) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 12, // Increased to account for the 6px hard shadow
        childAspectRatio: 0.85,
      ),
      physics: const BouncingScrollPhysics(),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final item = categories[index];
        print('item: ${item}');
        return _buildCategoryCard(
          name: item['name'] ?? 'No Name',
          imageUrl: item['image_path'],
          index: index,
          categoryId: item['id']
        );
      },
    );
  }

  Widget _buildListView(List<Map<String, dynamic>> categories) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      physics: const BouncingScrollPhysics(),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final item = categories[index];
        return _buildListItem(
          name: item['name'] ?? 'No Name',
          imageUrl: item['image_path'],
          index: index,
        );
      },
    );
  }

  Widget _buildCategoryCard({
    required String name,
    required String? imageUrl,
    required int index,
    required int categoryId
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => DictionaryOption(categoryId: categoryId)));
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: borderColor,
              blurRadius: 0,
              offset: const Offset(0, 4), // 3D pushable effect
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10), // Slightly less than container to fit inside border
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
                    color: borderColor.withOpacity(0.5),
                    child: const Icon(
                      Icons.image_not_supported,
                      size: 40,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ),
              
              // Gradient Overlay (Darkened for better text contrast in dark mode)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      backgroundColor.withOpacity(0.8),
                      backgroundColor.withOpacity(0.95),
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
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'Quicksand',
                          fontVariations: [FontVariation('wght', 800)],
                          letterSpacing: -0.5,
                          height: 1.1,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      //const SizedBox(height: 8),
                      // Container(
                      //   padding: const EdgeInsets.symmetric(
                      //     horizontal: 10,
                      //     vertical: 6,
                      //   ),
                      //   decoration: BoxDecoration(
                      //     color: Colors.teal.shade400,
                      //     borderRadius: BorderRadius.circular(12),
                      //   ),
                      //   child: const Row(
                      //     mainAxisSize: MainAxisSize.min,
                      //     children: [
                      //       Icon(
                      //         Icons.play_arrow_rounded,
                      //         size: 14,
                      //         color: Colors.white,
                      //       ),
                      //       SizedBox(width: 4),
                      //       Text(
                      //         'EXPLORE',
                      //         style: TextStyle(
                      //           color: Colors.white,
                      //           fontSize: 5,
                      //           fontFamily: 'Fredoka',
                      //           fontWeight: FontWeight.w600,
                      //           letterSpacing: 0.5,
                      //         ),
                      //       ),
                      //     ],
                      //   ),
                      // ),
                    
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

  Widget _buildListItem({
    required String name,
    required String? imageUrl,
    required int index,
  }) {
    return GestureDetector(
      onTap: () {
        print('Clicked category: $name');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20), // Increased margin for shadow
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
              offset: const Offset(0, 6), // 3D pushable effect
            ),
          ],
        ),
        child: Row(
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                bottomLeft: Radius.circular(22),
              ),
              child: SizedBox(
                width: 110,
                height: 110,
                child: Hero(
                  tag: 'category_list_${name}_$index',
                  child: Image.asset(
                    imageUrl ?? '',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: borderColor.withOpacity(0.5),
                      child: const Icon(
                        Icons.image_not_supported,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontFamily: 'Quicksand',
                        fontVariations: [FontVariation('wght', 800)],
                        letterSpacing: -0.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          size: 14,
                          color: Colors.deepOrange.shade400,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${(index + 1) * 8} signs',
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'Quicksand',
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Action Button
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.deepOrange.shade400.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Colors.deepOrange.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}