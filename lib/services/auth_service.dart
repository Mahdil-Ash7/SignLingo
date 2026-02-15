import 'package:supabase_flutter/supabase_flutter.dart';

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

  // --- SESSION HELPERS ---

  /// Returns the current active session, if any
  Session? get currentSession => _supabase.auth.currentSession;

  /// Returns the current user's email
  String? get currentUserEmail => _supabase.auth.currentUser?.email;

  /// Logs the user out of Supabase
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}