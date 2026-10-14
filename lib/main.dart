import 'package:flutter/material.dart';
import 'views/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AudioSplitterApp());
}

class AudioSplitterApp extends StatelessWidget {
  const AudioSplitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Splitter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          surface: Color(0xFF1E293B),
        ),
        fontFamily: '.AppleSystemUIFont',
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}
