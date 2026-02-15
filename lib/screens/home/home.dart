import 'package:flutter/material.dart';
import 'package:signlingo/screens/learning/sign_dictionary.dart';
import 'package:signlingo/services/navigation_service.dart';

class Home extends StatelessWidget {

  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        //backgroundColor: Theme.of(context).colorScheme,
        titleTextStyle: TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 25,
          fontWeight: FontWeight.w600,
        ),

        flexibleSpace: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                spreadRadius: 3,
                blurRadius: 3,
                blurStyle: BlurStyle.outer,
                offset: const Offset(0, 3), // changes position of shadow
              ),
            ],
          ),
        ),
        // Here we take the value from the MySignDictionaryPage object that was created by
        // the App.build method, and use it to set our appbar title.
        leadingWidth: 80,
        leading: Padding(
          padding: EdgeInsetsGeometry.all(8),
          child: Image.asset('assets/images/logo_latest.png'),
        ),
        titleSpacing: -10, // Reduces the gap significantly
        title: Text('SignLingo'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(40.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 20,),

                Text('Tonton Video Dan Belajar Bahasa Isyarat Malaysia',
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 20,
                  height: 0.8,
                  ),
                  ),

                SizedBox(height: 10,),
                GestureDetector(
                  onTap: () => navNotifier.value = 1,
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      borderRadius:BorderRadius.all(Radius.circular(20)) ,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepOrange.withOpacity(0.4),
                          blurRadius: 3,
                          spreadRadius: 0,
                          offset: const Offset(0, 5),
                          blurStyle: BlurStyle.normal)
                      ]
                    ),
                    child: Image.asset('assets/images/learning.png')),
                ),

                SizedBox(height: 50,),

                Text('Nilai Bahasa Isyarat Anda',
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 20,
                  height: 0.8,
                  ),
                  ),


                SizedBox(height: 10,),

                GestureDetector(
                  onTap: () => navNotifier.value = 2,
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      borderRadius:BorderRadius.all(Radius.circular(20)) ,
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(255, 0, 159, 112).withOpacity(0.4),
                          blurRadius: 3,
                          spreadRadius: 0,
                          offset: const Offset(0, 5),
                          blurStyle: BlurStyle.normal)
                      ]
                    ),
                    child: Image.asset('assets/images/gesture_test.png')),
                ),
                
              ],
            ),
          ),
        ),
      ),
    );
  }
}
