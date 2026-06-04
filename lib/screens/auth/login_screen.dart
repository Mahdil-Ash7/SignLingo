import 'package:flutter/material.dart';
import 'package:signlingo/screens/auth/register_screen.dart';
import 'package:signlingo/services/auth_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';

// Duolingo Dark Theme Colors
const Color bgColor = Color(0xFF131415);
const Color cardColor = Color(0xFF1E2124);
const Color borderColor = Color(0xFF373A3F);
const Color duoTextGrey = Color(0xFF9CA3AF);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();
    unawaited(
      signIn.initialize(
        serverClientId: '309130886582-qhbuidf8v7nmpij3secdm98jmf8bcfj9.apps.googleusercontent.com',
      ).then((_) {
        _authSubscription = signIn.authenticationEvents
              .listen(_handleAuthenticationEvent);

        _authSubscription?.onError(_handleAuthenticationError);

        signIn.authenticationEvents
            .listen(_handleAuthenticationEvent)
            .onError(_handleAuthenticationError);
      }),
    );
  }

  @override
  void dispose() {
      _authSubscription?.cancel(); // Kill the listener when leaving the page!
      _emailController.dispose();
      _passwordController.dispose();
      super.dispose();
    }

  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;

  final GoogleSignIn signIn = GoogleSignIn.instance;

  void login() async {
    try {
      await authService.signInWithEmailPassword(
          _emailController.text, _passwordController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Sign In Successful!',
              style: TextStyle(fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700),
            ),
            backgroundColor: Colors.green.shade500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );

        // Dismiss the login screen to reveal the screen underneath
        if (Navigator.canPop(context)) {
          Navigator.pop(context); 
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: const TextStyle(fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700),
            ),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) async {

    // Ignore event if we are currently on the Register page
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return; 
    }

    if (event is GoogleSignInAuthenticationEventSignIn) {
      try {
        final user = event.user;
        final googleAuth = user.authentication;
        final String? idToken = googleAuth?.idToken;

        final authorization = await user.authorizationClient.authorizationForScopes(['email']);
        final String? accessToken = authorization?.accessToken;

        if (idToken != null) {
          await authService.signInWithGoogleTokens(
            idToken: idToken,
            accessToken: accessToken ?? '',
          );
          if (mounted && Navigator.canPop(context)) {
             Navigator.pop(context); // Dismiss login screen
          }
          // AuthGate will automatically navigate to home on session creation
        }
      } catch (e) {
        debugPrint("Google Sign-In Error: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sign-in failed: $e',
                  style: const TextStyle(fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700)),
              backgroundColor: Colors.red.shade400,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    }
  }

  void _handleAuthenticationError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google Error: $error',
              style: const TextStyle(fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700)),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // Logo & Text
              Center(
                child: Image.asset('assets/images/logo_latest.png', width: 140, height: 140),
              ),
              const SizedBox(height: 16),
              const Text(
                'HELLO AGAIN!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Welcome back to SignLingo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: duoTextGrey,
                ),
              ),

              const SizedBox(height: 40),

              // Email Field
              _buildInputField(
                controller: _emailController,
                hint: 'EMAIL ADDRESS',
                icon: Icons.email_rounded,
                obscure: false,
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 16),

              // Password Field
              _buildInputField(
                controller: _passwordController,
                hint: 'PASSWORD',
                icon: Icons.lock_rounded,
                obscure: _hidePassword,
                suffix: IconButton(
                  icon: Icon(
                    _hidePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: duoTextGrey,
                  ),
                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                ),
              ),

              const SizedBox(height: 32),

              // Sign In Button
              _buildDuoButton(
                text: 'LOG IN',
                color: Colors.deepOrange.shade500,
                shadowColor: Colors.deepOrange.shade800,
                textColor: Colors.white,
                onTap: login,
              ),

              const SizedBox(height: 32),

              // OR Divider
              Row(
                children: [
                  Expanded(child: Divider(color: borderColor, thickness: 2)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        color: duoTextGrey,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: borderColor, thickness: 2)),
                ],
              ),

              const SizedBox(height: 24),

              // Sign In with Google
              GestureDetector(
                onTap: () async {
                  try {
                    await signIn.authenticate();
                  } catch (e) {
                    print("User cancelled or error occurred: $e");
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: borderColor,
                        blurRadius: 0,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/images/google.png', height: 24),
                      const SizedBox(width: 12),
                      const Text(
                        'CONTINUE WITH GOOGLE',
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Register Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'NOT REGISTERED YET?',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      color: duoTextGrey,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterPage())),
                    child: Text(
                      'SIGN UP',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        color: Colors.blue.shade400,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // --- Duo Dark Style Helpers ---

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool obscure,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: Colors.white,
        fontFamily: 'SF Pro Display',
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: bgColor, // Inset feel inside the black background
        hintText: hint,
        hintStyle: TextStyle(
          color: duoTextGrey.withOpacity(0.5),
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          fontSize: 14,
        ),
        contentPadding: const EdgeInsets.all(20),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 8, right: 8),
          child: Icon(icon, color: duoTextGrey),
        ),
        suffixIcon: suffix,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.deepOrange.shade400, width: 2),
        ),
      ),
    );
  }

  Widget _buildDuoButton({
    required String text,
    required Color color,
    required Color shadowColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 0,
              offset: const Offset(0, 5), // Extruded shadow
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
            color: textColor,
          ),
        ),
      ),
    );
  }
}