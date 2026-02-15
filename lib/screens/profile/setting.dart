import 'dart:io'; // Import for File
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // Import Image Picker
import 'package:signlingo/services/auth_service.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  final authService = AuthService();
  
  // 1. Variable to hold the selected image
  File? _image;
  final ImagePicker _picker = ImagePicker();

  // 2. Function to pick image
  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  void logout() async {
    await authService.signOut();
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
          child: Image.asset('assets/images/setting.png'),
        ),
        titleSpacing: -10,
        title: const Text('Profile Setting'),
        actions: [
          IconButton(onPressed: logout, icon: const Icon(Icons.logout))
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 7),
              width: double.infinity,
              height: 200,
              decoration: const BoxDecoration(
                color: Color.fromARGB(255, 6, 6, 6),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      // 3. Wrap in GestureDetector to trigger upload
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Colors.orange, Colors.red],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[300], // Background color
                                // 4. Display the picked image here
                                image: _image != null
                                    ? DecorationImage(
                                        image: FileImage(_image!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              // 5. Show an icon if no image is selected
                              child: _image == null
                                  ? const Icon(Icons.camera_alt, color: Colors.white, size: 40)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 15.0),
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.orange, Colors.red],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
                      child: const Text(
                        'User Name', // Changed from Gradient Text
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}