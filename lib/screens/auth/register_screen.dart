import 'package:flutter/material.dart';
import 'package:signlingo/services/auth_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import 'package:signlingo/services/auth_gate.dart';

// Duolingo Dark Theme Colors
const Color bgColor = Color(0xFF131415);
const Color cardColor = Color(0xFF1E2124);
const Color borderColor = Color(0xFF373A3F);
const Color duoTextGrey = Color(0xFF9CA3AF);

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  //Using Supabase Authentication
  final authService = AuthService();
  //Using Google Sign In
  final GoogleSignIn signIn = GoogleSignIn.instance;

  bool _isHandlingGoogleFlow = false;

  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;


  @override
  void initState() {
    super.initState();
    
    // Initialize Google Sign-In as soon as the page loads
    // Use 'import 'dart:async';' at the very top of your file for unawaited
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

        // Tries to sign in automatically if they've logged in before
        //signIn.attemptLightweightAuthentication();
      }),
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel(); // Kill the ghost listener!
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmpasswordController.dispose();
    super.dispose();
  }

  void _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) async {

    // Ignore event if this screen is not the active top screen
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

              suppressAuthRedirect.value = true; // freeze AuthGate on LoginPage


          final response = await authService.signInWithGoogleTokens(
            idToken: idToken,
            accessToken: accessToken ?? '',
          );

          if (!mounted) return;

          final supabaseUser = response.user;
          final isNewUser = supabaseUser?.createdAt != null &&
              DateTime.now().difference(DateTime.parse(supabaseUser!.createdAt)).inSeconds < 10;


            if (isNewUser) {
              await authService.signOut();
              await signIn.signOut(); // clear Google cache
              suppressAuthRedirect.value = false;

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Account successfully registered',
                      style: TextStyle(fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700)),
                  backgroundColor: Colors.greenAccent,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),);
              Navigator.pop(context);
            } else {
              await authService.signOut();
              await signIn.signOut();
              suppressAuthRedirect.value = false;

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('This Google account is already registered. Please sign in instead.',
                      style: TextStyle(fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700)),
                  backgroundColor: Colors.deepOrange.shade500,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            }
        }
      } catch (e) {
        debugPrint("Detailed Auth Error: $e");
      }
    }
  }

  void _handleAuthenticationError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Google Sign-In Error: $error', style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Controllers
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmpasswordController = TextEditingController();

  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  // Live Validation States
  bool hasNumber = false;
  bool hasSpecialChar = false;
  bool passwordsMatch = false;
  bool isMinLength = false;
  //add email checking 
  bool isEmailValid = false;

  // Logic to update requirements
  void _validateInput(String value) {
    setState(() {
      final password = _passwordController.text;
      final confirm = _confirmpasswordController.text;

      isMinLength = password.length >= 8;
      hasNumber = password.contains(RegExp(r'[0-9]'));
      hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
      passwordsMatch = password.isNotEmpty && password == confirm;
    });
  }

  void _validateEmailInput(String email){
    // to check email input format and new email(make sure email is not exsited)
    setState(() {
      final emailText = _emailController.text;
      RegExp emailExp = RegExp( r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$' );
      isEmailValid = emailExp.hasMatch(emailText);
    });
  }

  void register() async {
    //check all field are fiiled
    if (_usernameController.text.isEmpty || _emailController.text.isEmpty || _passwordController.text.isEmpty
        || _confirmpasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        _buildSnackBar('Please fill all fields', Colors.deepOrange.shade500),
      );
      return;
    }

    if (!hasNumber || !hasSpecialChar || !passwordsMatch || !isMinLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        _buildSnackBar('Please fulfill all the password requirements', Colors.deepOrange.shade500),
      );
      return;
    }

    if (!isEmailValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        _buildSnackBar('Email is not valid', Colors.deepOrange.shade500),
      );
      return;
    }

    try {
        final response = await authService.signUpWithEmailPassword(
          _emailController.text,
          _passwordController.text,
        );

        final user = response.user;

        if (user != null && user.identities != null && user.identities!.isEmpty) {
          // Signup failed
          ScaffoldMessenger.of(context).showSnackBar(
            _buildSnackBar('This email is already registered or invalid.', Colors.red.shade400),
          );
        } else {
          // Signup successful
          ScaffoldMessenger.of(context).showSnackBar(
            _buildSnackBar('Signup successful! Check your email.', Colors.green.shade500),
          );

          //pop this register page if registration is successful
            Navigator.pop(context);
        }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _buildSnackBar('Error: $e', Colors.red.shade400)
        );
        return;
      }
    }
  }

  SnackBar _buildSnackBar(String message, Color color) {
    return SnackBar(
      content: Text(message, style: const TextStyle(fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // UI for the requirement list items (Duo Style)
  Widget _requirementItem(String title, bool isReady) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            isReady ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: isReady ? Colors.green.shade400 : borderColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              color: isReady ? Colors.green.shade300 : duoTextGrey,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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
              const SizedBox(height: 10),
              // Logo and Header
              Center(
                child: Image.asset('assets/images/logo_latest.png', width: 120, height: 120),
              ),
              const SizedBox(height: 16),
              const Text(
                'CREATE ACCOUNT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: Colors.white,
                )
              ),
              const SizedBox(height: 32),
      
              // 1. Username Field
              _buildField(_usernameController, 'USERNAME', false),
              const SizedBox(height: 16),
      
              // 2. Email Field
              _buildEmailField(_emailController, 'EMAIL ADDRESS', false, (val) => _validateEmailInput(val)),
              const SizedBox(height: 16),
      
              // 3. Password Field
              _buildPasswordField(_passwordController, 'PASSWORD', _hidePassword, (val) => _validateInput(val), () {
                setState(() => _hidePassword = !_hidePassword);
              }),
              const SizedBox(height: 16),
      
              // 4. Confirm Password Field
              _buildPasswordField(_confirmpasswordController, 'CONFIRM PASSWORD', _hideConfirmPassword, (val) => _validateInput(val), () {
                setState(() => _hideConfirmPassword = !_hideConfirmPassword);
              }),
              const SizedBox(height: 24),
      
              // PASSWORD REQUIREMENTS UI SECTION (Duo Style Card)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "PASSWORD REQUIREMENTS",
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        color: Colors.deepOrange.shade400,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _requirementItem("At least 8 characters", isMinLength),
                    _requirementItem("Contains a number", hasNumber),
                    _requirementItem("Contains a special character", hasSpecialChar),
                    _requirementItem("Passwords match", passwordsMatch),
                  ],
                ),
              ),
      
              const SizedBox(height: 32),
      
              // Sign Up Button
              _buildDuoButton(
                text: 'SIGN UP',
                color: Colors.deepOrange.shade500,
                shadowColor: Colors.deepOrange.shade800,
                textColor: Colors.white,
                onTap: register,
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

              // Sign Up with Google (Duo Style Button)
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

              // If user already registered
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'ALREADY HAVE AN ACCOUNT?',
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
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      'LOG IN',
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

  // Reusable Field Builders (Duo Dark Style)
  Widget _buildField(TextEditingController controller, String hint, bool obscure) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700, fontSize: 16),
      decoration: InputDecoration(
        filled: true,
        fillColor: bgColor, // Inset feel
        hintText: hint,
        hintStyle: TextStyle(color: duoTextGrey.withOpacity(0.5), fontWeight: FontWeight.w800, letterSpacing: 1.0, fontSize: 14),
        contentPadding: const EdgeInsets.all(20),
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

  Widget _buildEmailField(TextEditingController controller, String hint, bool obscure, Function(String) onChanged) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.emailAddress,
      style: const TextStyle(color: Colors.white, fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700, fontSize: 16),
      onChanged: onChanged,
      decoration: InputDecoration(
        filled: true,
        fillColor: bgColor,
        hintText: hint,
        hintStyle: TextStyle(color: duoTextGrey.withOpacity(0.5), fontWeight: FontWeight.w800, letterSpacing: 1.0, fontSize: 14),
        contentPadding: const EdgeInsets.all(20),
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

  Widget _buildPasswordField(TextEditingController controller, String hint, bool obscure, Function(String) onChanged, VoidCallback toggle) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontFamily: 'SF Pro Display', fontWeight: FontWeight.w700, fontSize: 16),
      onChanged: onChanged,
      decoration: InputDecoration(
        filled: true,
        fillColor: bgColor,
        hintText: hint,
        hintStyle: TextStyle(color: duoTextGrey.withOpacity(0.5), fontWeight: FontWeight.w800, letterSpacing: 1.0, fontSize: 14),
        contentPadding: const EdgeInsets.all(20),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: duoTextGrey),
          onPressed: toggle,
        ),
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

  // Reusable Duo Button
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
              offset: const Offset(0, 5),
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