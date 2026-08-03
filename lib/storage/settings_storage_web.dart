import 'dart:html' as html;

/// Web 平台：昵称存于 localStorage（浏览器持久化，刷新/重开仍在）
class SettingsStorage {
  static const String _nickKey = 'hippo_nickname';

  Future<String?> loadNickname() async {
    final String? v = html.window.localStorage[_nickKey];
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  Future<void> saveNickname(String n) async {
    html.window.localStorage[_nickKey] = n.trim();
  }
}
