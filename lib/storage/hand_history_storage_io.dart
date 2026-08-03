import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 非 Web 平台（Android 等）：手牌本地日志存于应用文档目录文件
class HandHistoryStorage {
  static const String _fileName = 'hand_history.log';

  Future<void> append(String line) async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$_fileName');
    await f.writeAsString('$line\n', mode: FileMode.append);
  }

  Future<List<String>> readAll() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$_fileName');
    if (!await f.exists()) return <String>[];
    final content = await f.readAsString();
    return content.split('\n').where((String e) => e.trim().isNotEmpty).toList();
  }
}
