import 'package:flutter/material.dart';
import 'package:signlingo/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signlingo/screens/auth/login_screen.dart';

// Global flag
final ValueNotifier<bool> suppressAuthRedirect = ValueNotifier(false);

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: suppressAuthRedirect,
      builder: (context, isSuppressed, _) {
        return StreamBuilder(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            
            // 1. Show loading screen while checking auth state
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // 2. Freeze navigation during Google register flow to prevent bugs
            if (isSuppressed) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // 3. EVERYONE gets into the app by default now!
            // Notice we completely removed the "if (session != null)" check.
            return const MyHomePage(title: 'SignLingo');
            
          },
        );
      },
    );
  }
}