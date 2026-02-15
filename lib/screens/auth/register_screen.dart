import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:signlingo/services/auth_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';

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
  

      @override
    void initState() {
      super.initState();
      
      
      // Initialize Google Sign-In as soon as the page loads
      // Use 'import 'dart:async';' at the very top of your file for unawaited
      unawaited(
        signIn.initialize(
          serverClientId: '309130886582-qhbuidf8v7nmpij3secdm98jmf8bcfj9.apps.googleusercontent.com', 
        ).then((_) {
          signIn.authenticationEvents
              .listen(_handleAuthenticationEvent)
              .onError(_handleAuthenticationError);

          // Tries to sign in automatically if they've logged in before
          //signIn.attemptLightweightAuthentication();
        }),
      );
    }

    void _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) async {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        try {
          final user = event.user;
          
          // 1. Get basic authentication (ID Token)
          final googleAuth = await user?.authentication;
          final String? idToken = googleAuth?.idToken;

          // 2. THE ALTERNATIVE LOGIC: Request the Access Token explicitly
          // We use authorizationClient to ensure we have the 'email' scope
          final authorization = await user?.authorizationClient.authorizationForScopes(['email']);
          final String? accessToken = authorization?.accessToken;

          if (idToken != null) {
            // 3. Pass both to your merged AuthService
            await authService.signInWithGoogleTokens(
              idToken: idToken,
              accessToken: accessToken ?? '', 
            );

            if (mounted) {
              //Navigator.pushReplacementNamed(context, Home());
                    //pop this register page
              Navigator.pop(context);
            }
          }
        } catch (e) {
          debugPrint("Detailed Auth Error: $e");
        }
      }
    }

void _handleAuthenticationError(Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Google Sign-In Error: $error')),
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

  void register() async {
    if (!hasNumber || !hasSpecialChar || !passwordsMatch || !isMinLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fulfill all requirements')),
      );
      return;
    }

    try {
      await authService.signUpWithEmailPassword(_emailController.text, _passwordController.text);

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration Successful!'),
            backgroundColor: Color.fromARGB(255, 159, 141, 0),
            duration: Duration(seconds: 3), 
          ),
        );

      //pop this register page
      Navigator.pop(context);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error:$e')));
      }
    }
  }

  // UI for the requirement list items
  Widget _requirementItem(String title, bool isReady) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            isReady ? Icons.check_circle : Icons.circle_outlined,
            color: isReady ? Colors.green : Colors.grey[400],
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: isReady ? Colors.green[700] : Colors.grey[600],
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    // Determine the height of the image (40% of screen height)
    double imageAreaHeight = MediaQuery.of(context).size.height * 0.30;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Stack(
        children: 
        [

          // 1. BOTTOM IMAGE LAYER
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: imageAreaHeight,
              width: double.infinity,
              child: Image.asset(
                'assets/images/login_bg2.jpg', 
                fit: BoxFit.cover,
              ),
            ),
          ),

          // 2. GRADIENT BLEND LAYER (Blends form into the image)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: imageAreaHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.grey[200]!, // Solid color at the top of the image
                    Colors.grey[200]!.withOpacity(0.0), // Fades out to show image
                  ],
                  stops: const [0.3, 0.9], // Blends quickly at the top edge
                ),
              ),
            ),
          ),

          SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Image.asset('assets/images/logo_latest.png', width: 150, height: 150),
                Text('Register To SignLingo', style: GoogleFonts.bebasNeue(fontSize: 42,color: Colors.black)),
        
                const SizedBox(height: 0),
        
                // 1. Username Field
                _buildField(_usernameController, 'Username', false),
                const SizedBox(height: 5),
        
                // 2. Email Field
                _buildField(_emailController, 'Email', false),
                const SizedBox(height: 5),
        
                // 3. Password Field
                _buildPasswordField(_passwordController, 'Password', _hidePassword, (val) => _validateInput(val), () {
                  setState(() => _hidePassword = !_hidePassword);
                }),
                const SizedBox(height: 5),
        
                // 4. Confirm Password Field
                _buildPasswordField(_confirmpasswordController, 'Confirm Password', _hideConfirmPassword, (val) => _validateInput(val), () {
                  setState(() => _hideConfirmPassword = !_hideConfirmPassword);
                }),
        
                const SizedBox(height: 5),
        
                // PASSWORD REQUIREMENTS UI SECTION
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _requirementItem("At least 8 characters", isMinLength),
                      _requirementItem("Contains a number", hasNumber),
                      _requirementItem("Contains a special character", hasSpecialChar),
                      _requirementItem("Passwords match", passwordsMatch),
                    ],
                  ),
                ),
        
                const SizedBox(height: 15),
        
                // Sign Up Button
                GestureDetector(
                  onTap: register,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 223, 97, 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text('Sign Up', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ),

                const SizedBox(height: 15,),
                //If user already register

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 10,
                  children: [
                    Text('Already Registered?',style: TextStyle(color: Colors.black),),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text('Sign In',style: TextStyle(color: Colors.black,
                                                      fontWeight: FontWeight.bold),),
                    )
                  ],
                ),

                SizedBox(height: 20,),

                Text('Or Sign Up with',
                style: TextStyle(color: Colors.black),),

                SizedBox(height: 5,),

                //Sign Up with google
                GestureDetector(
                onTap: () async {
                    try {
                      // This launches the Android account picker overlay
                      await signIn.authenticate();
                    } catch (e) {
                      print("User cancelled or error occurred: $e");
                    }
                  },
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.all(Radius.circular(15)),
                      boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1),
                          offset: Offset( 0, 1),
                          blurRadius: 1,
                          spreadRadius: 0)
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Image.asset('assets/images/google.webp'),
                    ),
                  ),
                ),

              ],
            ),
          ),
        ),
        ],
      ),
    );
  }

  // Reusable Field Builders
  Widget _buildField(TextEditingController controller, String hint, bool obscure) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white)),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(color: Colors.black),
        decoration: InputDecoration(hintText: hint, border: InputBorder.none,hintStyle: TextStyle(color: Colors.grey)),
      ),
    );
  }

  Widget _buildPasswordField(TextEditingController controller, String hint, bool obscure, Function(String) onChanged, VoidCallback toggle) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white)),
      padding: const EdgeInsets.only(left: 15),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              style: TextStyle(color: Colors.black),
              onChanged: onChanged, // Updates UI as user type
              decoration: InputDecoration(hintText: hint, border: InputBorder.none,hintStyle: TextStyle(color: Colors.grey),),
            ),
          ),
          IconButton(
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
            onPressed: toggle,
          ),
        ],
      ),
    );
  }
}