import 'dart:developer';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:signlingo/screens/auth/login_screen.dart';
class AuthService {
  final _supabase = Supabase.instance.client;

  // --- EMAIL & PASSWORD ---

  /// Registers a new user with Email and Password
  Future<AuthResponse> signUpWithEmailPassword(String email, String password) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
    );
  }

  /// Signs in an existing user with Email and Password
  Future<AuthResponse> signInWithEmailPassword(String email, String password) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // --- GOOGLE SIGN-IN (ANDROID NATIVE) ---

  /// Exchanges Google Tokens for a Supabase Session
  /// This creates a persistent session in your app.
  Future<AuthResponse> signInWithGoogleTokens({
    required String idToken,
    required String accessToken,
  }) async {
    return await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  //-- validate user email confirmation
  bool isEmailConfirmed ()
  {
    final user = _supabase.auth.currentUser;

    if (user != null) {
      if (user.emailConfirmedAt != null) {
        log("Email is verified ");
        return true;
      } else {
        log("Email not verified ");
        return false;
      }
    }

    return false;
  }


  // --- SESSION HELPERS ---

final ValueNotifier<bool> suppressAuthRedirect = ValueNotifier(false);

  /// Returns the current active session, if any
  Session? get currentSession => _supabase.auth.currentSession;

  /// Returns the current user's email
  String? get currentUserEmail => _supabase.auth.currentUser?.email;

  /// Logs the user out of Supabase
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}

void requireLogin(BuildContext context, VoidCallback onLoggedIn) {
  final session = Supabase.instance.client.auth.currentSession;
  
  if (session != null) {
    // User is logged in, execute the action!
    onLoggedIn();
  } else {
    // User is a guest. Show a message and push them to the Login Page.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('You must be logged in to use this feature.'),
        backgroundColor: Colors.deepOrange.shade500,
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }
}