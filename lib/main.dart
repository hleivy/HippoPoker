// lib/main.dart —— 应用入口
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'pages/nickname_gate.dart';

void main() {
  // 绑定必须在设置全局错误处理器前初始化（确保 PlatformDispatcher 可用）
  WidgetsFlutterBinding.ensureInitialized();

  // 全局错误兜底：保证牌桌长期稳定——任何未捕获异常都不击穿整页（不出现绿/红崩溃屏）。
  // 1) 渲染期异常：框架会调用 ErrorWidget.builder 仅替换出错的那一小块子树（见下），而非整页。
  // 2) 异步/回调异常（如图片解码失败、定时器回调异常）：默认会弹崩溃屏，这里改为仅记录并吞掉。
  FlutterError.onError = (details) {
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('uncaught async error: $error\n$stack');
    return true; // 已处理，不再向上抛出导致整页崩溃
  };

  // 仅替换出错子树为可读提示，不破坏其余界面；状态刷新后该区域会自动恢复。
  ErrorWidget.builder = (details) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.all(8),
        color: const Color(0xFF0B3D2E),
        child: const Text(
          '该区域暂时显示异常，已自动隔离，不影响其他操作（会随状态刷新自动恢复）。',
          style: TextStyle(color: Colors.orange, fontSize: 12),
        ),
      ),
    );
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
