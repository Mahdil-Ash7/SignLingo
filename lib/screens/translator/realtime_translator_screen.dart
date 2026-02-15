import 'package:flutter/material.dart';

class RTC extends StatefulWidget {
  const RTC({super.key});

  @override
  State<RTC> createState() => _RTCState();
}

class _RTCState extends State<RTC> {

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
          child: Image.asset('assets/images/rtc.png'),
          ),
        titleSpacing: -10, // Reduces the gap significantly
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Real Time Hand Sign Translation', style: TextStyle(fontSize: 20),),
            Text('Video Call', style: TextStyle(color: const Color.fromARGB(255, 182, 137, 0)
                                               ,fontStyle: FontStyle.italic,fontSize: 15),)
          ],
        ),
      ),
    );
  }
}