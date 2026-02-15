import 'package:flutter/material.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {

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
          padding: EdgeInsetsGeometry.all(10),
          child: Image.asset('assets/images/quizz.png'),
          ),
        titleSpacing: -10, // Reduces the gap significantly
        title: Text('BIM Quiz Bank'),
      ),
    );
  }
}