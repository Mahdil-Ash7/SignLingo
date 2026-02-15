import 'package:flutter/material.dart';

class TestSign extends StatefulWidget {
  const TestSign({super.key});

  @override
  State<TestSign> createState() => _TestSignState();
}

class _TestSignState extends State<TestSign> {

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
        // Here we take the value from the MyTestSignPage object that was created by
        // the App.build method, and use it to set our appbar title.
        leadingWidth: 80,
        leading: Padding(
          padding: EdgeInsetsGeometry.all(10),
          child: Image.asset('assets/images/gesture.png'),
          ),
        titleSpacing: -10, // Reduces the gap significantly
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BIM Gesture Test'),
            Text('Test your BIM Skill', style:TextStyle(
              color: const Color.fromARGB(255, 200, 157, 0),
              fontStyle: FontStyle.italic,
              fontSize: 10
            ) )
          ],
        ),
      ),
    );
  }
}