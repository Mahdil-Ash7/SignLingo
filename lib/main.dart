import 'package:flutter/material.dart';
import 'package:signlingo/services/auth_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/learning/sign_dictionary.dart';
import 'screens/home/home.dart';
import 'screens/gesture/test_sign_screen.dart';
import 'screens/translator/realtime_translator_screen.dart';
import 'screens/learning/quiz_screen.dart';
import 'screens/profile/setting.dart';
import 'services/navigation_service.dart';

void main() async {
  //supabase setup
  await Supabase.initialize(
    //setup supabase
    anonKey: 'sb_publishable_dWhGxQkFuC6MU70EIezuFw_XAfK7fRK',
    url: 'https://isnrfcreczpkmrraqcvr.supabase.co',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SignLingo',
      theme: ThemeData(
        colorScheme: ColorScheme.dark(),
        fontFamily: 'SF Pro Display',
  
      ),
      debugShowCheckedModeBanner: false,
      home: AuthGate(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  int selectedBottNavIndex = 0; //by default select home page

  @override
  void initState() {
    super.initState();
    // Listen for changes from other screens (like Home)
    navNotifier.addListener(() {
      setState(() {
        selectedBottNavIndex = navNotifier.value;
      });
    });
  }

  @override
  void dispose() {
    // Clean up the listener when the widget is destroyed
    navNotifier.removeListener(() {}); 
    super.dispose();
  }

final List<Widget> _pages = [
  const Home(), //index 0
  const SignDictionary(), 
  const TestSign(),
  const RTC(),
  const QuizPage(),
  const SettingPage()
];

  Widget _buildNavIcon(String path, int index) {

    
  bool isSelected = selectedBottNavIndex == index;
  
  return Opacity(
    opacity: isSelected ? 1.0 : 0.5, // Adjust 0.4 to make it more/less faded
    child: Container(
      margin: EdgeInsets.only(top : 15),
      child: Image.asset(
        path,
        width: index == 4 ? 51 : 45,
        height: index == 4 ? 51 : 45,
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      body: _pages[selectedBottNavIndex],

      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: navNotifier,
        builder: (context, index, child) {
          return SizedBox(
            height: 90,
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.black,
              selectedItemColor: Colors.white, // Ensure selected items are visible
              unselectedItemColor: Colors.grey, // Ensure unselected items are visible
              showSelectedLabels: false,   // hide selected labels
              showUnselectedLabels: false,
              selectedFontSize: 0,
              unselectedFontSize: 0,
            
              onTap:(newIndex) {
                setState(() {
                  selectedBottNavIndex = newIndex;

                });
              },
              currentIndex: selectedBottNavIndex,
              items: [
                BottomNavigationBarItem(icon: _buildNavIcon('assets/images/home.png', 0),label: '',),
                BottomNavigationBarItem(icon: _buildNavIcon('assets/images/learning_page.png', 1),label: '',),
                BottomNavigationBarItem(icon: _buildNavIcon('assets/images/gesture.png', 2),label: ''),
                BottomNavigationBarItem(icon: _buildNavIcon('assets/images/rtc.png', 3),label: ''),
                BottomNavigationBarItem(icon: _buildNavIcon('assets/images/quizz.png', 4),label: ''),
                BottomNavigationBarItem(icon: _buildNavIcon('assets/images/setting.png', 5),label: ''),
                  ],
            
                ),
          );
        }
      ),
    );
  }
}

