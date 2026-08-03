import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 非 Web 平台（Android 等）：昵称存于应用文档目录文件
class SettingsStorage {
  static const String _fileName = 'nickname.txt';

  Future<String?> loadNickname() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$_fileName');
    if (!await f.exists()) return null;
    final c = await f.readAsString();
    final s = c.trim();
    return s.isEmpty ? null : s;
  }

  Future<void> saveNickname(String n) async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$_fileName');
    await f.writeAsString(n.trim());
  }
}
