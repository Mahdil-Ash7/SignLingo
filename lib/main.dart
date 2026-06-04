import 'package:flutter/material.dart';
import 'package:signlingo/services/auth_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/learning/sign_dictionary_category_option.dart';
import 'screens/home/home.dart';
import 'screens/gesture/test_sign_screen.dart';
import 'screens/translator/realtime_translator_screen.dart';
import 'screens/learning/quiz_option_screen.dart';
import 'screens/profile/setting.dart';
import 'services/navigation_service.dart';
import 'package:flutter/services.dart';
import 'package:signlingo/database/database_helper.dart';
import 'package:signlingo/services/on_device_llm_service.dart';
import 'dart:async';

//Global Route Observer
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();


void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    print('==== APP STARTED ====');

    unawaited(OnDeviceLlmService.instance.init());

    SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  //supabase setup
  await Supabase.initialize(
    //setup supabase
    anonKey: 'sb_publishable_dWhGxQkFuC6MU70EIezuFw_XAfK7fRK',
    url: 'https://isnrfcreczpkmrraqcvr.supabase.co',
  );

  //sqlite
  await DatabaseHelper.instance.database;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    
    return MaterialApp(
      navigatorObservers: [routeObserver],
      title: 'SignLingo',
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: Colors.orange,
          secondary: Colors.orange.shade700,
          surface: Colors.white,
          background: Colors.white,
        ),
        fontFamily: 'SF Pro Display',
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black87),
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            fontFamily: 'Fredoka',
          ),
        ),
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
  const SettingPage(),
];

  Widget _buildNavIcon(String path, int index) {

  bool isSelected = selectedBottNavIndex == index;
  
  // Check if we're on the quiz page (index 4)
  bool isQuizPage = selectedBottNavIndex == 4;
  
  return Padding(
    padding: const EdgeInsets.only(top: 8.0),
    child: Opacity(
      opacity: isSelected ? 1.0 : 0.6,
      child: Container(
        child: Image.asset(
          path,
          width: index == 4 ? 41 : 35,
          height: index == 4 ? 41 : 35,
          // For quiz icon: if selected AND on quiz page, make it orange
          // For other icons: keep the original behavior
          color: (isSelected && isQuizPage && index == 4) 
              ? Colors.deepOrange.shade400
              : (isSelected && index != 4) 
                  ? Colors.deepOrange.shade400
                  : Colors.grey.shade600,
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.white, // Set scaffold background to white

      body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,

      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(animation),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      
          child: Container(
            key: ValueKey(selectedBottNavIndex),
            child: _pages[selectedBottNavIndex],
          ),
        ),

      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: navNotifier,
        builder: (context, index, child) {
          // Check if we're on quiz page
          bool isQuizPage = selectedBottNavIndex == 4;
          
          return Container(
            decoration: BoxDecoration(
              // Change bottom navigation bar color to black when on quiz page
              color: isQuizPage ? Color(0xFF131415) : Colors.white,
              border: Border(top: BorderSide(width: 2, color: Color(0xFF373A3F)))
            ),
            child: SizedBox(
              height: 80,
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                // Set background color based on quiz page
                backgroundColor: Color(0xFF131415),
                selectedItemColor: Colors.deepOrange.shade700,
                unselectedItemColor: Color(0xFF373A3F),
                showSelectedLabels: false,   // hide selected labels
                showUnselectedLabels: false,
                selectedFontSize: 0,
                unselectedFontSize: 0,
                elevation: 0, // Remove default elevation since we have custom shadow
              
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
                  // if(owner)
                  //   BottomNavigationBarItem(icon: _buildNavIcon('assets/images/setting.png', 6),label: ''),
                ],
              ),
            ),
          );
        }
      ),
    );
  }
}