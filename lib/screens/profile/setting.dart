import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signlingo/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signlingo/screens/auth/login_screen.dart';


class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  final authService = AuthService();
  final supabase = Supabase.instance.client;
  
  File? _image;
  final ImagePicker _picker = ImagePicker();
  
  // User data controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  
  // Original values for change detection
  String _originalName = '';
  String _originalBio = '';
  String? _originalImageUrl;
  
  // Edit mode states
  bool _isEditingPersonalInfo = false;
  bool _hasChanges = false;
  bool _isSaving = false;
  
  // User data
  Map<String, dynamic> _userData = {};
  bool _isLoading = true;
  
  // Preferences
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  String _selectedLanguage = 'English';
  String _selectedDifficulty = 'Beginner';
  
  // Learning stats
  int _streak = 0;
  int _wordsLearned = 0;
  int _lessonsCompleted = 0;

  // Duolingo Dark Theme Colors
  final Color bgColor = const Color(0xFF131415);
  final Color cardColor = const Color(0xFF1E2124);
  final Color borderColor = const Color(0xFF373A3F);

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserPreferences();
    _loadLearningStats();
  }
  
 Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    
    try {
      final userId = supabase.auth.currentUser?.id;
      
      // FIX: If it's a guest, turn off loading and stop fetching data.
      if (userId == null) {
        setState(() => _isLoading = false);
        return; 
      }
      
      // Fetch user profile from Supabase
      final response = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      
      setState(() {
        _userData = response;
        _originalName = response['username'] ?? '';
        _originalBio = response['bio'] ?? '';
        _originalImageUrl = response['avatar_url'];
        
        _nameController.text = _originalName;
        _bioController.text = _originalBio;
        
        if (_originalImageUrl != null) {
          _loadImageFromUrl(_originalImageUrl!);
        }
        
        _isLoading = false; // Turn off loading for logged-in users
      });
    } catch (e) {
      print('Error loading user data: $e');
      setState(() => _isLoading = false); // Turn off loading on errors too
    }
  }
  Future<void> _loadImageFromUrl(String url) async {
    // Implement image loading from URL if needed
    // For now, we'll handle image uploads separately
  }
  
  Future<void> _loadUserPreferences() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      
      final response = await supabase
          .from('user_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      
      if (response != null) {
        setState(() {
          _notificationsEnabled = response['notifications_enabled'] ?? true;
          _darkModeEnabled = response['dark_mode_enabled'] ?? false;
          _selectedLanguage = response['language'] ?? 'English';
          _selectedDifficulty = response['difficulty'] ?? 'Beginner';
        });
      }
    } catch (e) {
      print('Error loading preferences: $e');
    }
  }
  
  Future<void> _loadLearningStats() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      
      final response = await supabase
          .from('user_stats')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      
      if (response != null) {
        setState(() {
          _streak = response['streak'] ?? 0;
          _wordsLearned = response['words_learned'] ?? 0;
          _lessonsCompleted = response['lessons_completed'] ?? 0;
        });
      }
    } catch (e) {
      print('Error loading stats: $e');
    }
  }
  
  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _checkForChanges();
      });
    }
  }
  
  Future<String?> _uploadImage(File image) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;
      
      final fileExt = image.path.split('.').last;
      final fileName = '$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'avatars/$fileName';
      
      await supabase.storage.from('user_avatars').upload(filePath, image);
      final imageUrl = supabase.storage.from('user_avatars').getPublicUrl(filePath);
      
      return imageUrl;
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }
  
  void _checkForChanges() {
    final hasNameChanged = _nameController.text != _originalName;
    final hasBioChanged = _bioController.text != _originalBio;
    final hasImageChanged = _image != null;
    
    setState(() {
      _hasChanges = hasNameChanged || hasBioChanged || hasImageChanged;
    });
  }
  
  void _startEditing() {
    setState(() {
      _isEditingPersonalInfo = true;
      _hasChanges = false;
    });
  }
  
  void _cancelEditing() {
    setState(() {
      _nameController.text = _originalName;
      _bioController.text = _originalBio;
      _image = null;
      _isEditingPersonalInfo = false;
      _hasChanges = false;
    });
  }
  
  Future<void> _savePersonalInfo() async {
    setState(() => _isSaving = true);
    
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      
      String? avatarUrl = _originalImageUrl;
      
      // Upload new image if selected
      if (_image != null) {
        final uploadedUrl = await _uploadImage(_image!);
        if (uploadedUrl != null) {
          avatarUrl = uploadedUrl;
        }
      }
      
      // Update user profile in Supabase
      final updates = {
        'full_name': _nameController.text,
        'bio': _bioController.text,
        'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await supabase
          .from('user_profiles')
          .upsert({
            'id': userId,
            ...updates,
          });
      
      // Update local original values
      setState(() {
        _originalName = _nameController.text;
        _originalBio = _bioController.text;
        _originalImageUrl = avatarUrl;
        _isEditingPersonalInfo = false;
        _hasChanges = false;
        _isSaving = false;
      });
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated successfully!', style: TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: Colors.green.shade500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving profile: $e', style: const TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
  
  Future<void> _savePreferences() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      
      await supabase
          .from('user_preferences')
          .upsert({
            'user_id': userId,
            'notifications_enabled': _notificationsEnabled,
            'dark_mode_enabled': _darkModeEnabled,
            'language': _selectedLanguage,
            'difficulty': _selectedDifficulty,
            'updated_at': DateTime.now().toIso8601String(),
          });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Preferences saved!', style: TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: Colors.green.shade500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      print('Error saving preferences: $e');
    }
  }

  void logout() async {
    await authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        titleSpacing: 5,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
        ),
        backgroundColor: bgColor,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: Image.asset('assets/images/setting.png', color: Colors.white),
        ),
        actions: [
          GestureDetector(
            onTap: () {
              final isGuest = supabase.auth.currentUser == null;
              if (isGuest) {
                // Route them to the login screen and WAIT for them to come back
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                ).then((_) {
                  // THIS CODE RUNS WHEN THE LOGIN PAGE CLOSES
                  // Force the UI to rebuild (changes "LOGIN" to "LOGOUT")
                  setState(() {}); 
                  
                  // If they successfully logged in, fetch their data!
                  if (supabase.auth.currentUser != null) {
                    _loadUserData();
                    _loadUserPreferences();
                    _loadLearningStats();
                  }
                });
              } else {
                logout();
                // Optionally refresh the page after logout too
                setState(() {}); 
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Text(
                supabase.auth.currentUser == null ? 'LOGIN' : 'LOGOUT', 
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  color: supabase.auth.currentUser == null ? Colors.tealAccent : Colors.red.shade400, 
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              )
            )
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildProfileHeader(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Column(
                      children: [
                        _buildLearningStatsSection(),
                        const SizedBox(height: 24),
                        _buildPersonalInfoSection(),
                        const SizedBox(height: 24),
                        _buildPreferencesSection(),
                        const SizedBox(height: 24),
                        _buildAccountSection(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  
  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      color: bgColor,
      child: Column(
        children: [
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _isEditingPersonalInfo ? _pickImage : null,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 4),
                    color: cardColor,
                    image: _image != null
                        ? DecorationImage(
                            image: FileImage(_image!),
                            fit: BoxFit.cover,
                          )
                        : (_originalImageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(_originalImageUrl!),
                                fit: BoxFit.cover,
                              )
                            : null),
                  ),
                  child: (_image == null && _originalImageUrl == null)
                      ? Icon(
                          Icons.person_rounded,
                          color: borderColor,
                          size: 80,
                        )
                      : null,
                ),
                if (_isEditingPersonalInfo)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade400,
                      shape: BoxShape.circle,
                      border: Border.all(color: bgColor, width: 4),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _nameController.text.isEmpty ? 'User Name' : _nameController.text,
            style: const TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
  
  Widget _buildPersonalInfoSection() {
    return _buildDuoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'PERSONAL INFO',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              if (!_isEditingPersonalInfo)
                GestureDetector(
                  onTap: _startEditing,
                  child: Text(
                    'EDIT',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      color: Colors.blue.shade400,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _buildInfoField(
            label: 'FULL NAME',
            value: _nameController.text,
            controller: _nameController,
            isEditing: _isEditingPersonalInfo,
            icon: Icons.person_rounded,
            onChanged: _checkForChanges,
          ),
          const SizedBox(height: 16),
          _buildInfoField(
            label: 'EMAIL',
            value: supabase.auth.currentUser?.email ?? '',
            isEditing: false,
            icon: Icons.email_rounded,
          ),
          if (_isEditingPersonalInfo) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildDuoButton(
                    text: 'CANCEL',
                    color: borderColor,
                    shadowColor: bgColor,
                    textColor: Colors.white,
                    onPressed: _cancelEditing,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _buildDuoButton(
                    text: 'SAVE',
                    color: _hasChanges ? Colors.green.shade400 : borderColor,
                    shadowColor: _hasChanges ? Colors.green.shade700 : bgColor,
                    textColor: Colors.white,
                    isLoading: _isSaving,
                    onPressed: _hasChanges && !_isSaving ? _savePersonalInfo : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildInfoField({
    required String label,
    required String value,
    TextEditingController? controller,
    required bool isEditing,
    required IconData icon,
    int maxLines = 1,
    VoidCallback? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF9CA3AF),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isEditing ? bgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEditing ? borderColor : Colors.transparent,
              width: 2,
            ),
          ),
          child: isEditing && controller != null
              ? TextField(
                  controller: controller,
                  maxLines: maxLines,
                  onChanged: (text) => onChanged?.call(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    prefixIcon: Icon(icon, color: Colors.grey.shade500),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                )
              : Row(
                  children: [
                    Icon(icon, color: Colors.grey.shade500, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        value.isEmpty ? 'Not set' : value,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
  
  Widget _buildPreferencesSection() {
    return _buildDuoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PREFERENCES',
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF9CA3AF),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 20),
          _buildToggleTile(
            title: 'Push Notifications',
            subtitle: 'Receive daily reminders',
            icon: Icons.notifications_rounded,
            iconColor: Colors.amber.shade400,
            value: _notificationsEnabled,
            onChanged: (value) {
              setState(() => _notificationsEnabled = value);
              _savePreferences();
            },
          ),
          // Padding(
          //   padding: const EdgeInsets.symmetric(vertical: 12),
          //   child: Divider(color: borderColor, thickness: 2, height: 2),
          // ),
          // _buildToggleTile(
          //   title: 'Dark Mode',
          //   subtitle: 'Switch to dark theme',
          //   icon: Icons.dark_mode_rounded,
          //   iconColor: Colors.deepPurple.shade400,
          //   value: _darkModeEnabled,
          //   onChanged: (value) {
          //     setState(() => _darkModeEnabled = value);
          //     _savePreferences();
          //   },
          // ),
          // Padding(
          //   padding: const EdgeInsets.symmetric(vertical: 12),
          //   child: Divider(color: borderColor, thickness: 2, height: 2),
          // ),
          // _buildDropdownTile(
          //   title: 'Language',
          //   subtitle: 'App display language',
          //   icon: Icons.language_rounded,
          //   iconColor: Colors.blue.shade400,
          //   value: _selectedLanguage,
          //   items: ['English', 'Malay'],
          //   onChanged: (value) {
          //     setState(() => _selectedLanguage = value);
          //     _savePreferences();
          //   },
          // ),
        ],
      ),
    );
  }
  
  Widget _buildLearningStatsSection() {
    return _buildDuoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STATISTICS',
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF9CA3AF),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 20),
          _buildStatTile(
            title: 'Day Streak',
            value: '$_streak',
            icon: Icons.local_fire_department_rounded,
            color: Colors.orange.shade500,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: borderColor, thickness: 2, height: 2),
          ),
          _buildStatTile(
            title: 'Words Learned',
            value: '$_wordsLearned',
            icon: Icons.school_rounded,
            color: Colors.blue.shade400,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: borderColor, thickness: 2, height: 2),
          ),
          _buildStatTile(
            title: 'Lessons Completed',
            value: '$_lessonsCompleted',
            icon: Icons.verified_rounded,
            color: Colors.green.shade400,
          ),
        ],
      ),
    );
  }
  
  Widget _buildAccountSection() {
    return _buildDuoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACCOUNT',
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF9CA3AF),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 20),
          _buildActionTile(
            title: 'Change Password',
            icon: Icons.lock_rounded,
            iconColor: Colors.grey.shade400,
            onTap: () {},
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: borderColor, thickness: 2, height: 2),
          ),
          _buildActionTile(
            title: 'Privacy Policy',
            icon: Icons.privacy_tip_rounded,
            iconColor: Colors.grey.shade400,
            onTap: () {},
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: borderColor, thickness: 2, height: 2),
          ),
          _buildActionTile(
            title: 'Terms of Service',
            icon: Icons.description_rounded,
            iconColor: Colors.grey.shade400,
            onTap: () {},
          ),
        ],
      ),
    );
  }
  
  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: Colors.teal.shade400,
          inactiveThumbColor: Colors.grey.shade400,
          inactiveTrackColor: bgColor,
          trackOutlineColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) 
                ? Colors.transparent 
                : borderColor,
          ),
        ),
      ],
    );
  }
  
  Widget _buildDropdownTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required String value,
    required List<String> items,
    required Function(String) onChanged,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: DropdownButton<String>(
            value: value,
            dropdownColor: cardColor,
            borderRadius: BorderRadius.circular(16),
            items: items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(
                  item,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
            underline: const SizedBox(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: color,
          ),
        ),
      ],
    );
  }
  
  Widget _buildActionTile({
    required String title,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded, color: borderColor, size: 18),
        ],
      ),
    );
  }

  // --- DUOLINGO STYLE COMPONENTS ---

  Widget _buildDuoCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: const [
          BoxShadow(
            color: const Color(0xFF373A3F),
            blurRadius: 0,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildDuoButton({
    required String text,
    required Color color,
    required Color shadowColor,
    required Color textColor,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    final bool disabled = onPressed == null && !isLoading;
    
    return GestureDetector(
      onTap: disabled ? null : onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: disabled ? const Color(0xFF373A3F) : color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: disabled ? bgColor : shadowColor,
              blurRadius: 0,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                text,
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: disabled ? Colors.grey.shade600 : textColor,
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }
}