import 'dart:html' as html;

/// Web 平台：手牌本地日志存于 localStorage（浏览器持久化，刷新/重开仍在）
class HandHistoryStorage {
  static const String _key = 'hippo_hand_history';

  Future<void> append(String line) async {
    final String cur = html.window.localStorage[_key] ?? '';
    html.window.localStorage[_key] = '$cur$line\n';
  }

  Future<List<String>> readAll() async {
    final String cur = html.window.localStorage[_key] ?? '';
    return cur.split('\n').where((String e) => e.trim().isNotEmpty).toList();
  }
}
