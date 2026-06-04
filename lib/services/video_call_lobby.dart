// lib/screens/video_call_lobby.dart
// =====================================
// Entry point for video calls.
// Users either create a new room (getting a room ID to share)
// or join an existing room by entering the ID they received.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signlingo/screens/translator/video_call_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math';

class VideoCallLobby extends StatefulWidget {
  const VideoCallLobby({super.key});

  @override
  State<VideoCallLobby> createState() => _VideoCallLobbyState();
}

class _VideoCallLobbyState extends State<VideoCallLobby> {
  final _joinController = TextEditingController();
  bool _isCreating = false;
  bool _isJoining = false;
  String? _createdRoomId;

  //   Dark Theme Colors
  final Color bgColor = const Color(0xFF131415);
  final Color cardColor = const Color(0xFF1E2124);
  final Color borderColor = const Color(0xFF373A3F);

  @override
  void dispose() {
    _joinController.dispose();
    super.dispose();
  }

  // Generate a short, shareable room ID
  String _generateRoomId() {
    final rand = Random();
    return (100000 + rand.nextInt(900000)).toString();
  }

  Future<void> _createRoom() async {
    if (_isCreating) return;
    setState(() => _isCreating = true);
    // Just generate the ID — no DB insert needed
    // Realtime channels work by channel name alone, no table required
    final roomId = _generateRoomId();
    if (mounted) {
      setState(() {
        _createdRoomId = roomId;
        _isCreating = false;
      });
    }
  }

  Future<void> _startAsHost() async {
    if (_createdRoomId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          roomId: _createdRoomId!,
          isCaller: true,
        ),
      ),
    );
  }

  Future<void> _joinRoom() async {
    final roomId = _joinController.text.trim();
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Enter a room code first',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: Colors.deepOrange.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            roomId: roomId,
            isCaller: false,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

               // HOW TO
              _buildDuoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.question_mark_outlined,
                          weight: 50,
                          color: Colors.amber.shade400,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'HOW TO?',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFD1D5DB),
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildTipRow(
                      'Create a room → share the code with your contact',
                      Icons.qr_code_scanner_rounded,
                    ),
                    const SizedBox(height: 10),
                    _buildTipRow(
                      'Join using their 6-digit code to connect',
                      Icons.people_alt_rounded,
                    ),
                    const SizedBox(height: 10),
                    _buildTipRow(
                      'Toggle signing mode to translate signs to text',
                      Icons.back_hand_rounded,
                    ),
                    const SizedBox(height: 10),
                    _buildTipRow(
                      'Subtitles appear in real-time on both screens',
                      Icons.closed_caption_rounded,
                    ),
                  ],
                ),
              ),
              

              // CREATE ROOM SECTION
              if (_createdRoomId == null) ...[
                _buildDuoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.shade500.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.add_call,
                              color: Colors.deepOrange.shade400,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Text(
                            'Start a new call',
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildDuoButton(
                        text: 'CREATE ROOM',
                        color: Colors.deepOrange.shade500,
                        shadowColor: Colors.deepOrange.shade800,
                        textColor: Colors.white,
                        isLoading: _isCreating,
                        onPressed: _isCreating ? null : _createRoom,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                _buildDuoCard(
                  glowBorder: Colors.deepOrange.shade600,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () => Share.share(
                            'Join my SignLingo call:\nhttps://signlingo.app/join/$_createdRoomId'),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.shade500.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.share_rounded,
                            color: Colors.deepOrange.shade400,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Share this code',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF9CA3AF),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            _createdRoomId!,
                            style: TextStyle(
                              color: Colors.deepOrange.shade400,
                              fontSize: 46,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 6,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: _createdRoomId!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Copied to clipboard',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: const Color(0xFF373A3F),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.copy_rounded,
                              color: Colors.grey.shade500,
                              size: 24,
                            ),
                            splashRadius: 24,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDuoButton(
                              text: 'CANCEL',
                              color: const Color(0xFF373A3F), // Dark grey
                              shadowColor: const Color(0xFF131415), // Black shadow
                              textColor: Colors.white,
                              onPressed: () =>
                                  setState(() => _createdRoomId = null),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: _buildDuoButton(
                              text: 'START CALL',
                              color: Colors.deepOrange.shade500,
                              shadowColor: Colors.deepOrange.shade800,
                              textColor: Colors.white,
                              onPressed: _startAsHost,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // JOIN ROOM SECTION
              _buildDuoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade500.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.call_merge_rounded,
                            color: Colors.teal.shade400,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'Join a call',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _joinController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 10,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '000000',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 32,
                          letterSpacing: 10,
                          fontWeight: FontWeight.w900,
                        ),
                        counterText: '',
                        filled: true,
                        fillColor: bgColor, // Deep dark inset background
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 20),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: borderColor, width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                              color: Colors.teal.shade400, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildDuoButton(
                      text: 'JOIN CALL',
                      color: Colors.teal.shade500,
                      shadowColor: Colors.teal.shade800,
                      textColor: Colors.white,
                      isLoading: _isJoining,
                      onPressed: _isJoining ? null : _joinRoom,
                    ),
                  ],
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  // ---   STYLE COMPONENTS ---

  // Main Card Container with hard 3D border
  Widget _buildDuoCard({required Widget child, Color? glowBorder}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: glowBorder ?? borderColor,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: glowBorder ?? borderColor,
            blurRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  // 3D Pressable Button Structure
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
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: disabled ? const Color(0xFF373A3F) : color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: disabled ? const Color(0xFF1E2124) : shadowColor,
              blurRadius: 0,
              offset: const Offset(0, 5), // Extruded shadow
            ),
          ],
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                text,
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: disabled ? Colors.grey.shade500 : textColor,
                ),
              ),
      ),
    );
  }

  // Row for Tips
  Widget _buildTipRow(String text, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: Colors.amber.shade400,
          size: 20,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF9CA3AF), // Muted grey
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}