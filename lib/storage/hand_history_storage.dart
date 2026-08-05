// 手牌本地日志持久化平台分流。
// Web 编译时 dart.library.html 为真 -> 用 localStorage 实现；
// 其他平台（Android 等，dart.library.io）-> 用文件实现。
// 用 conditional export 避免在跨平台编译时 dart:html 与 dart:io 互相冲突。
export 'hand_history_storage_io.dart' if (dart.library.html) 'hand_history_storage_web.dart';
