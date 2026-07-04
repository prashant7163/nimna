import 'package:flutter/material.dart';

void main() {
  runApp(const NimnaApp());
}

/// Session 1 scaffold — the real app shell (navigation, encrypted storage,
/// design tokens from designs/system/tokens.json) arrives in Session 7.
class NimnaApp extends StatelessWidget {
  const NimnaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'nimna',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0B0C),
      ),
      home: const Scaffold(
        body: Center(
          child: Text('nimna', style: TextStyle(color: Color(0xFFE8E6E1))),
        ),
      ),
    );
  }
}
