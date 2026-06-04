//app bar and footer
import 'package:flutter/material.dart';
import 'package:signlingo/services/video_call_lobby.dart';
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
        toolbarHeight: 80,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFF131415),
        titleTextStyle: TextStyle(
        fontFamily: 'Fredoka',
        fontSize: 25,
        fontWeight: FontWeight.w800,
        ),
        
        shape: const Border(
          bottom: BorderSide(
            color: const Color(0xFF373A3F),
            width: 2,
          ),
        ),

        
        flexibleSpace: Container(
        decoration: BoxDecoration(
        boxShadow: [
        // BoxShadow(
        //   spreadRadius: 1,
        //   blurRadius: 3,
        //   blurStyle: BlurStyle.outer,
        //   offset: const Offset(0, 1), // changes position of shadow
        //   ),
           ],
          ),
        ),
        // Here we take the value from the MySignDictionaryPage object that was created by
        // the App.build method, and use it to set our appbar title.
        leadingWidth: 60,
        leading: Padding(
          padding: EdgeInsetsGeometry.all(10),
          child: Image.asset('assets/images/logo_home.png'),
          ),
        titleSpacing: 0, // Reduces the gap significantly
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Real Time Hand Sign', style: TextStyle(fontSize: 20, color: const Color.fromARGB(255, 255, 255, 255), letterSpacing: -0.5, ),),
            Text('Video Call', style: TextStyle(color: Colors.deepOrange.shade300
                                               ,fontSize: 12, fontFamily: "Quicksand"),)
          ],
        ),
      ),
      body: VideoCallLobby(),
    );
  }
}