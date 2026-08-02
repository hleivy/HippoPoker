// lib/game_controller.dart —— WebSocket 客户端 + 房间状态管理
//
// 服务器权威：只通过 JSON 消息收发动作，状态由后端推送（roomUpdate）。
// 复用小程序/后端同一套协议：
//   发：createRoom / joinRoom / leaveRoom / sync / startHand / action / listRooms / chat
//   收：joined / roomUpdate / roomList / error / notice / left

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'config.dart';

class GameController extends ChangeNotifier {
  IOWebSocketChannel? _channel;
  final List<Map<String, dynamic>> _queue = [];

  bool connected = false;
  bool connecting = false;
  String? errorMsg;
  String? playerId;
  String? roomId;
  bool isHost = false;

  Map<String, dynamic>? state; // 最近一次 roomUpdate 的状态
  List<dynamic> roomList = [];

  /// 连接后端。重复调用安全。
  void connect() {
    if (_channel != null || connecting) return;
    connecting = true;
    notifyListeners();
    _channel = IOWebSocketChannel.connect(Uri.parse(SERVER_URL));
    _channel!.stream.listen(
      _onMessage,
      onDone: () {
        connected = false;
        connecting = false;
        notifyListeners();
      },
      onError: (e) {
        connected = false;
        connecting = false;
        errorMsg = '连接错误：$e';
        notifyListeners();
      },
    );
    _channel!.ready.then((_) {
      connected = true;
      connecting = false;
      for (final m in _queue) _channel!.sink.add(jsonEncode(m));
      _queue.clear();
      notifyListeners();
    }).catchError((e) {
      connecting = false;
      errorMsg = '连接失败：$e';
      notifyListeners();
    });
  }

  void _send(Map<String, dynamic> msg) {
    if (connected && _channel != null) {
      _channel!.sink.add(jsonEncode(msg));
    } else {
      _queue.add(msg);
    }
  }

  void _onMessage(dynamic data) {
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'joined':
        playerId = msg['playerId'] as String?;
        roomId = msg['roomId'] as String?;
        isHost = msg['host'] == true;
        break;
      case 'roomUpdate':
        state = msg['state'] as Map<String, dynamic>?;
        break;
      case 'roomList':
        roomList = (msg['rooms'] as List?) ?? [];
        break;
      case 'error':
        errorMsg = msg['message'] as String?;
        break;
      case 'notice':
        // 简单记录到 log（若已有 state.log 则追加）
        final text = msg['text'] as String? ?? '';
        if (state != null && state!['log'] is List) {
          (state!['log'] as List).add(text);
        }
        break;
      case 'left':
        roomId = null;
        playerId = null;
        isHost = false;
        state = null;
        break;
    }
    notifyListeners();
  }

  // ---- 动作封装 ----
  void createRoom(String name, int buyIn, int sb, int bb) {
    _send({
      'type': 'createRoom',
      'name': name,
      'buyIn': buyIn,
      'smallBlind': sb,
      'bigBlind': bb,
    });
  }

  void joinRoom(String roomId, String name, int buyIn, {String password = ''}) {
    _send({
      'type': 'joinRoom',
      'roomId': roomId.toUpperCase(),
      'name': name,
      'buyIn': buyIn,
      'password': password,
    });
  }

  void leaveRoom() => _send({'type': 'leaveRoom'});
  void listRooms() => _send({'type': 'listRooms'});
  void sync() => _send({'type': 'sync'});
  void startHand() => _send({'type': 'startHand'});

  void action(String action, {int amount = 0}) {
    _send({'type': 'action', 'action': action, 'amount': amount});
  }

  void clearError() {
    errorMsg = null;
    notifyListeners();
  }

  /// 当前视角下「我」的玩家数据（含我的底牌）。
  Map<String, dynamic>? get me {
    if (state == null || playerId == null) return null;
    for (final p in state!['players'] as List) {
      if (p['id'] == playerId) return p as Map<String, dynamic>;
    }
    return null;
  }

  /// 是否轮到我行动。
  bool get myTurn {
    final m = me;
    return m != null && m['isTurn'] == true;
  }

  /// 跟注需要补的金额。
  int get callNeed {
    final m = me;
    if (m == null) return 0;
    final currentBet = (state?['currentBet'] as int?) ?? 0;
    return (currentBet - (m['bet'] as int? ?? 0)).clamp(0, 1 << 30);
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }
}
