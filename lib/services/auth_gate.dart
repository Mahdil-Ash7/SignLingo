/*
AUTH GATE - This will countinuosly listen for auth state changes
 */

import 'package:flutter/material.dart';
import 'package:signlingo/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signlingo/screens/auth/login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    
    return StreamBuilder(
      stream: Supabase.instance.client.auth.onAuthStateChange, 
      builder: (context, snapshot){

        //loading
        if (snapshot.connectionState == ConnectionState.waiting){
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(),),
          );
        }

        //check if there is a valid session
        final session = snapshot.hasData ? snapshot.data!.session : null;

        if(session != null) {
          return MyHomePage(title: ('SignLingo'));
        }else {
          return LoginPage();
        }
      });
  }
}