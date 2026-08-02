// lib/game_controller.dart —— WebSocket 客户端 + 房间状态管理 + 9 项功能逻辑
//
// 服务器权威：只通过 JSON 消息收发动作，状态由后端推送（roomUpdate）。
// 复用小程序/后端同一套协议，并扩展以下消息与字段以支撑 9 项功能：
//   发：createRoom(含桌子参数) / joinRoom / leaveRoom / tempLeave / returnTable
//       / buyChips / cashOut / startHand / action / listRooms / chat
//   收：joined / roomUpdate(含 ante/min-max/unit、各人 totalBuyIn/winLoss/tempLeft、
//       handHistory) / roomList / error / notice / dailyReport / left
//
// 客户端本地负责：超时自动暂离计时器(含延时按钮)、手牌全过程本地日志持久化。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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

  Map<String, dynamic>? state;
  List<dynamic> roomList = [];

  // ---- 暂时离桌 / 思考超时 ----
  bool timeoutWarning = false; // 仅剩 10 秒即将自动暂离时为 true
  int delayClicks = 0; // 已使用的延时次数（最多 2）
  int secondsLeft = 0; // 当前窗口剩余秒数（用于倒计时显示）
  Map<String, dynamic>? dailyReport; // 最后一人离开时服务端下发的日报

  Timer? _tickTimer, _expireTimer, _warnTimer;
  DateTime? _deadline;
  int _lastHandNumber = 0;
  String? _lastResultNote;

  // ---- 连接 ----
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
        _cancelTimers();
        notifyListeners();
      },
      onError: (e) {
        connected = false;
        connecting = false;
        errorMsg = '连接错误：$e';
        _cancelTimers();
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
        _onRoomUpdate();
        break;
      case 'roomList':
        roomList = (msg['rooms'] as List?) ?? [];
        break;
      case 'error':
        errorMsg = msg['message'] as String?;
        break;
      case 'notice':
        final text = msg['text'] as String? ?? '';
        if (state != null && state!['log'] is List) {
          (state!['log'] as List).add(text);
        }
        break;
      case 'dailyReport':
        dailyReport = msg;
        break;
      case 'left':
        roomId = null;
        playerId = null;
        isHost = false;
        state = null;
        dailyReport = null;
        _cancelTimers();
        break;
    }
    notifyListeners();
  }

  void _onRoomUpdate() {
    if (state == null) return;
    // 手牌全过程本地日志
    final hn = (state!['handNumber'] as int?) ?? 0;
    if (hn != _lastHandNumber) {
      if (hn > 0) _appendHistory('第 $hn 手开始（盲注 ${smallBlind}/${bigBlind}）');
      _lastHandNumber = hn;
      _lastResultNote = null;
    }
    final lr = state!['lastResult'];
    final note = lr is Map ? (lr['note']?.toString() ?? '') : '';
    if (note.isNotEmpty && note != _lastResultNote) {
      _appendHistory('第 $hn 手结束：$note');
      _lastResultNote = note;
    }
    // 思考超时计时器：轮到我且未启动 -> 启动；不轮到我 -> 取消
    if (myTurn) {
      if (_expireTimer == null) _startTurnTimer();
    } else {
      _cancelTimers();
    }
  }

  // ---- 动作封装 ----
  void createRoom({
    required String name,
    required int buyIn,
    required int sb,
    required int bb,
    int ante = 0,
    int minBuyIn = 1000,
    int maxBuyIn = 3999,
    int buyInUnit = 1000,
  }) {
    _send({
      'type': 'createRoom',
      'name': name,
      'buyIn': buyIn,
      'smallBlind': sb,
      'bigBlind': bb,
      'ante': ante,
      'minBuyIn': minBuyIn,
      'maxBuyIn': maxBuyIn,
      'buyInUnit': buyInUnit,
    });
  }

  void joinRoom(String roomId, String name, int buyIn,
      {String password = '', int minBuyIn = 1000, int maxBuyIn = 3999, int buyInUnit = 1000}) {
    _send({
      'type': 'joinRoom',
      'roomId': roomId.toUpperCase(),
      'name': name,
      'buyIn': buyIn,
      'password': password,
      'minBuyIn': minBuyIn,
      'maxBuyIn': maxBuyIn,
      'buyInUnit': buyInUnit,
    });
  }

  void leaveRoom() => _send({'type': 'leaveRoom'});
  void listRooms() => _send({'type': 'listRooms'});
  void sync() => _send({'type': 'sync'});
  void startHand() => _send({'type': 'startHand'});
  void tempLeave() {
    _cancelTimers();
    _send({'type': 'tempLeave'});
  }

  void returnTable() => _send({'type': 'returnTable'});
  void buyChips(int amount) => _send({'type': 'buyChips', 'amount': amount});
  void cashOut(int amount) => _send({'type': 'cashOut', 'amount': amount});

  void action(String action, {int amount = 0}) {
    _cancelTimers();
    _appendHistory('我 $action${amount > 0 ? ' $amount' : ''}');
    _send({'type': 'action', 'action': action, 'amount': amount});
  }

  void clearError() {
    errorMsg = null;
    notifyListeners();
  }

  // ---- 当前视角便捷访问 ----
  Map<String, dynamic>? get me {
    if (state == null || playerId == null) return null;
    for (final p in state!['players'] as List) {
      if (p['id'] == playerId) return p as Map<String, dynamic>;
    }
    return null;
  }

  bool get myTurn {
    final m = me;
    return m != null && m['isTurn'] == true;
  }

  int get callNeed {
    final m = me;
    if (m == null) return 0;
    final currentBet = (state?['currentBet'] as int?) ?? 0;
    return (currentBet - (m['bet'] as int? ?? 0)).clamp(0, 1 << 30);
  }

  // 桌子设置
  int get ante => (state?['ante'] as int?) ?? 0;
  int get minBuyIn => (state?['minBuyIn'] as int?) ?? 1000;
  int get maxBuyIn => (state?['maxBuyIn'] as int?) ?? 3999;
  int get buyInUnit => (state?['buyInUnit'] as int?) ?? 1000;
  int get smallBlind => (state?['smallBlind'] as int?) ?? 0;
  int get bigBlind => (state?['bigBlind'] as int?) ?? 0;

  // 仅庄家（首手为房主）可开始一手牌
  bool get canStartHand {
    if (state == null) return false;
    if (state!['handInProgress'] == true) return false;
    final m = me;
    if (m == null) return false;
    final dealerSeat = (state!['dealerSeat'] as int?) ?? -1;
    if (dealerSeat < 0) return isHost;
    return m['isDealer'] == true;
  }

  List<dynamic> get handHistory => (state?['handHistory'] as List?) ?? [];

  // ---- 思考超时计时（功能 4）----
  int get delayClicksLeft => (2 - delayClicks).clamp(0, 2);

  void _startTurnTimer() {
    _cancelTimers();
    delayClicks = 0;
    timeoutWarning = false;
    secondsLeft = 60;
    _deadline = DateTime.now().add(const Duration(minutes: 1));
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _warnTimer = Timer(const Duration(seconds: 50), () {
      timeoutWarning = true;
      notifyListeners();
    });
    _expireTimer = Timer(const Duration(minutes: 1), _onExpire);
  }

  void _onTick() {
    final left = _deadline?.difference(DateTime.now()).inSeconds ?? 0;
    secondsLeft = left > 0 ? left : 0;
    if (secondsLeft <= 10) timeoutWarning = true;
    notifyListeners();
  }

  void _onExpire() {
    // 整段思考时间用尽仍未操作 -> 自动暂时离桌
    _cancelTimers();
    tempLeave();
  }

  /// 点击「延时 1 分钟」按钮：把本窗口延长 1 分钟（最多 2 次，共 3 分钟）
  void requestDelay() {
    if (delayClicks >= 2) return;
    delayClicks++;
    _cancelTimers();
    timeoutWarning = false;
    secondsLeft = 60;
    _deadline = DateTime.now().add(const Duration(minutes: 1));
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _warnTimer = Timer(const Duration(seconds: 50), () {
      timeoutWarning = true;
      notifyListeners();
    });
    _expireTimer = Timer(const Duration(minutes: 1), _onExpire);
    notifyListeners();
  }

  void _cancelTimers() {
    _tickTimer?.cancel();
    _expireTimer?.cancel();
    _warnTimer?.cancel();
    _tickTimer = null;
    _expireTimer = null;
    _warnTimer = null;
    timeoutWarning = false;
    secondsLeft = 0;
  }

  // ---- 手牌全过程本地日志持久化（功能 2）----
  Future<String> get _historyPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/hand_history.log';
  }

  Future<void> _appendHistory(String line) async {
    try {
      final f = File(await _historyPath);
      final ts = _now();
      await f.writeAsString('[$ts] $line\n', mode: FileMode.append);
    } catch (_) {
      // 忽略本地写入失败
    }
  }

  /// 读取本地手牌日志（供历史查看页使用）
  Future<List<String>> readHistory() async {
    try {
      final f = File(await _historyPath);
      if (!await f.exists()) return [];
      final content = await f.readAsString();
      return content.split('\n').where((e) => e.trim().isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  String _now() {
    final d = DateTime.now();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:'
        '${d.second.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _cancelTimers();
    _channel?.sink.close();
    super.dispose();
  }
}
