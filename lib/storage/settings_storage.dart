// 简单键值持久化平台分流（当前用于“上次昵称”记忆）。
// Web 编译时 dart.library.html 为真 -> 用 localStorage；
// 其他平台（Android 等）-> 用应用文档目录文件。
// 条件导入避免在跨平台编译时 dart:html 与 dart:io 互相冲突。
export 'settings_storage_io.dart' if (dart.library.html) 'settings_storage_web.dart';
