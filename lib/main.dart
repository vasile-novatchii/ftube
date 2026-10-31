import 'package:flutter/material.dart';

void main() {
  runApp(const FtubeApp());
}

/// Root widget. Theme, localization and navigation arrive in P5.
class FtubeApp extends StatelessWidget {
  const FtubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ftube',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(colorSchemeSeed: Colors.red),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.red,
        brightness: Brightness.dark,
      ),
      home: const Scaffold(body: Center(child: Text('Ftube'))),
    );
  }
}
