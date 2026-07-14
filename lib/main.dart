import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeepFocusApp());
}

class DeepFocusApp extends StatelessWidget {
  const DeepFocusApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = ThemeData(brightness: Brightness.dark).textTheme;
    final textTheme = GoogleFonts.soraTextTheme(baseTextTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    return MaterialApp(
      title: 'Deep Focus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C5CFC),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B0B12),
        textTheme: textTheme,
        splashFactory: InkRipple.splashFactory,
        highlightColor: Colors.transparent,
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        }),
      ),
      home: const HomeScreen(),
    );
  }
}
