import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:signlingo/screens/auth/register_screen.dart';
import 'package:signlingo/services/auth_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  final GoogleSignIn signIn = GoogleSignIn.instance;


  void login() async {
    try {
      await authService.signInWithEmailPassword(_emailController.text, _passwordController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign In Successful!'),
            backgroundColor: Color.fromARGB(255, 212, 107, 1),
            duration: Duration(seconds: 2),
          ),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine the height of the image (40% of screen height)
    double imageAreaHeight = MediaQuery.of(context).size.height * 0.40;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Stack(
        children: [
          // 1. BOTTOM IMAGE LAYER
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: imageAreaHeight,
              width: double.infinity,
              child: Image.asset(
                'assets/images/mascot_hi.png', // Your image path
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
                  stops: const [0.0, 0.4], // Blends quickly at the top edge
                ),
              ),
            ),
          ),

          // 3. UI LAYER
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  
                  // Logo & Text
                  Transform.translate(
                    offset: const Offset(0, -50),
                    child: Image.asset('assets/images/full_logo_no_shadow.png', width: 300, height: 300)),

                  Transform.translate(
                    offset: const Offset(0, -150), // Move text UP by 40 pixels
                    child: Text(
                      'Hello Again!',
                      style: GoogleFonts.bebasNeue(fontSize: 52, color: const Color.fromARGB(255, 0, 141, 98)),
                    ),
                  ),

                  Transform.translate(
                    offset: const Offset(0, -150),
                    child: Text(
                      'Welcome back!',
                      style: TextStyle(fontSize: 20, color: Colors.grey[700]),
                    ),
                  ),
                  
                  const SizedBox(height: 30),

                  // Email Field
                  Transform.translate(
                    offset: const Offset(0, -150),
                    child: _buildInputField(_emailController, 'Email', Icons.email_outlined, false)),

                  const SizedBox(height: 15),

                  // Password Field
                  Transform.translate(
                    offset: const Offset(0, -150),
                    child: _buildInputField(
                      _passwordController, 
                      'Password', 
                      Icons.lock_outline, 
                      _hidePassword,
                      suffix: IconButton(
                        icon: Icon(_hidePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        color: Colors.grey,
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Sign In Button
                  Transform.translate(
                    offset: const Offset(0, -150),
                    child: _buildSignInButton()),

                  const SizedBox(height: 20),

                  // Register Link
                  Transform.translate(
                    offset: const Offset(0, -150),
                    child: _buildRegisterLink()),
                  

                Transform.translate(
                  offset: const Offset(0, -120),
                  child: Text('Or Sign In with',
                  style: TextStyle(color: Colors.black),),
                ),

                SizedBox(height: 5,),

                //Sign Up with google
                Transform.translate(
                offset: const Offset(0, -120),
                  child: GestureDetector(
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
                ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Helpers ---
  Widget _buildInputField(TextEditingController controller, String hint, IconData icon, bool obscure, {Widget? suffix}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9), // Slightly transparent to look modern
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: TextField(
          controller: controller,
          obscureText: obscure,
          style: TextStyle(color: Colors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey),
            border: InputBorder.none,
            icon: Icon(icon, color: Colors.grey),
            suffixIcon: suffix,
          ),
        ),
      ),
    );
  }

  Widget _buildSignInButton() {
    return GestureDetector(
      onTap: login,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Container(
          height: 55,
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 212, 107, 1),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ]
          ),
          child: const Center(
            child: Text('Sign In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Not Registered Yet?', style: TextStyle(color: Colors.black)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterPage())),
          child: const Text(
            'Register Now',
            style: TextStyle(color: Color.fromARGB(255, 0, 141, 98), fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
  

  
}