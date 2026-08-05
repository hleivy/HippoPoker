// lib/main.dart —— 应用入口
import 'package:flutter/material.dart';
import 'pages/nickname_gate.dart';

void main() {
  // 全局错误兜底：release 模式下未捕获的渲染异常默认会白屏，这里改为展示可读错误信息
  ErrorWidget.builder = (details) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF0B3D2E),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            '界面渲染出错（已拦截白屏）：\n${details.exception}\n\n'
            '${details.stack.toString().split('\n').take(15).join('\n')}',
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ),
      ),
    );
  };
  FlutterError.onError = (details) {
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };
  runApp(const PokerApp());
}

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
      home: const NicknameGate(),
    );
  }
}
