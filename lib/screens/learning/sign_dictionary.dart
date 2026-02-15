import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignDictionary extends StatefulWidget {
  const SignDictionary({super.key});

  @override
  State<SignDictionary> createState() => _SignDictionaryState();
}

class _SignDictionaryState extends State<SignDictionary> {
  final supabase = Supabase.instance.client;

  // This is your original fetch function
  Future<List<Map<String, dynamic>>> fetchSigns() async {
    final data = await Supabase.instance.client
        .from('category') // Your table name
        .select('name, image_url');
    
    // Debug print as requested
    debugPrint('Fetched Data from Supabase: $data');
    return List<Map<String, dynamic>>.from(data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleTextStyle: const TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 25,
          fontWeight: FontWeight.w600,
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                spreadRadius: 3,
                blurRadius: 3,
                blurStyle: BlurStyle.outer,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
        leadingWidth: 80,
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: Image.asset('assets/images/learning_page.png'),
        ),
        titleSpacing: -10,
        title: const Text('BIM Learning Dictionary'),
      ),
      
      
      // --- NEW BODY SECTION START ---
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchSigns(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No categories found.'));
          }

          final categories = snapshot.data!;

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // Two columns like the reference image
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.0, // adjust this for card height
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final item = categories[index];
              return GestureDetector(
                onTap: () {
                  print('Clicked');
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.grey[900], // Background while loading
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // The Background Image
                      Image.network(
                        item['image_url'] ?? '',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.broken_image, size: 30),
                      ),
                      // Dark gradient overlay to make text readable
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                          ),
                        ),
                      ),
                      // The Name Overlay
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Text(
                          item['name'] ?? 'No Name',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      // --- NEW BODY SECTION END ---
    );
  }
}