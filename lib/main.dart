// lib/main.dart —— 应用入口
import 'package:flutter/material.dart';
import 'game_controller.dart';
import 'pages/lobby_page.dart';

void main() => runApp(const PokerApp());

class PokerApp extends StatelessWidget {
  const PokerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '河马扑克',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.green,
        scaffoldBackgroundColor: const Color(0xFF0B3D2E),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: LobbyPage(controller: GameController()),
    );
  }
}
