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
//
// 跨平台：WebSocketChannel.connect 同时支持 Web 与 Android；手牌本地日志通过
// storage/hand_history_storage.dart 的条件导入分流（Web=localStorage，其他=文件）。

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'config.dart';
import 'storage/hand_history_storage.dart';

class GameController extends ChangeNotifier {
  WebSocketChannel? _channel;
  final HandHistoryStorage _store = HandHistoryStorage();
  final List<Map<String, dynamic>> _queue = [];

  bool connected = false;
  bool connecting = false;
  bool _reconnecting = false;
  int _reconnectAttempts = 0;
  String? errorMsg;
  String? playerId;
  String? roomId;
  bool isHost = false;
  String? nickname; // 当前用户昵称，创建/加入房间时自动使用

  Map<String, dynamic>? state;
  List<dynamic> roomList = [];
  String? serverVersion; // 服务端版本号（roomUpdate/roomList 下发）
  String? lastCreatedRoomId; // 最近一次创建的房间 id（创建后不再自动进入）

  // ---- 当前行动者倒计时（服务端权威下发，全桌可见）----
  int turnRemaining = 0; // 当前行动者剩余行动秒数
  int turnSeat = -1; // 当前轮到的座位
  int actionTimeout = 60; // 房间设定的每轮行动时限(秒)

  // ---- 暂停 / 延长 ----
  bool handPaused = false; // 本手结束后暂停发牌，等待“继续下一手”
  int extensionCount = 2; // 每轮可申请的延长次数
  int extensionSeconds = 60; // 每次延长时间(秒)

  // ---- 退出结算 ----
  Map<String, dynamic>? summary; // requestSummary 返回的个人统计

  // ---- 暂时离桌 / 思考超时 ----
  bool timeoutWarning = false; // 仅剩 10 秒即将自动暂离时为 true
  int delayClicks = 0; // 已使用的延时次数（最多 2）
  int secondsLeft = 0; // 当前窗口剩余秒数（用于倒计时显示，本地平滑递减）
  Map<String, dynamic>? dailyReport; // 最后一人离开时服务端下发的日报
  Map<String, dynamic>? roomReport; // 大厅“战绩”请求返回的房间战绩

  Timer? _tickTimer, _expireTimer, _warnTimer;
  Timer? _retryTimer;
  bool _disposed = false;
  DateTime? _deadline;
  int _lastHandNumber = 0;
  String? _lastResultNote;

  // 断线重连缓存：连接断开时保留，重连成功后发 rejoinRoom 恢复原有座位
  String? _pendingRejoinRoomId;
  String? _pendingRejoinPlayerId;

  // 是否处于“正在连接/重连中”——用于 UI 显示“连接中”而非报错
  bool get isConnecting => connecting || _reconnecting;

  // ---- 连接 ----
  void connect() {
    if (_channel != null || connecting || _disposed) return;
    connecting = true;
    _reconnecting = false;
    notifyListeners();
    try {
      _channel = WebSocketChannel.connect(Uri.parse(SERVER_URL));
    } catch (e) {
      _onDrop();
      return;
    }
    _channel!.stream.listen(
      _onMessage,
      onDone: () => _onDrop(),
      onError: (_) => _onDrop(),
    );
    _channel!.ready.then((_) {
      connected = true;
      connecting = false;
      _reconnecting = false;
      _reconnectAttempts = 0;
      errorMsg = null;
      // 若之前断线时保留了房间/玩家ID，优先尝试恢复，避免 action 发到空连接报“尚未加入房间”
      if (_pendingRejoinRoomId != null && _pendingRejoinPlayerId != null) {
        final roomId = _pendingRejoinRoomId!;
        final pid = _pendingRejoinPlayerId!;
        _pendingRejoinRoomId = null;
        _pendingRejoinPlayerId = null;
        _send({'type': 'rejoinRoom', 'roomId': roomId, 'playerId': pid});
      }
      for (final m in _queue) _channel!.sink.add(jsonEncode(m));
      _queue.clear();
      notifyListeners();
    }).catchError((_, __) {
      _onDrop();
      return;
    });
  }

  // 连接断开/失败时统一处理：重连更快(1.5s)，首次失败不报警，连续失败才提示
  void _onDrop() {
    if (_disposed) return;
    // 保留重连所需信息后再清空当前连接
    if (roomId != null && playerId != null) {
      _pendingRejoinRoomId = roomId;
      _pendingRejoinPlayerId = playerId;
    }
    connected = false;
    connecting = false;
    _channel = null;
    _cancelTimers();
    _reconnectAttempts++;
    if (_reconnectAttempts >= 2) {
      errorMsg = '网络连接异常，正在自动重试…';
    } else {
      errorMsg = null; // 首次失败不打扰，直接重试
    }
    _reconnecting = true;
    notifyListeners();
    _scheduleReconnect();
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
      case 'created':
        lastCreatedRoomId = msg['roomId']?.toString();
        // 创建房间后不自动入座：大厅显示“加入”，用户主动点加入才真正入座。
        // 故此处不设置 roomId/playerId（server 也未把创建者加入房间）。
        break;
      case 'joined':
        playerId = msg['playerId'] as String?;
        roomId = msg['roomId'] as String?;
        isHost = msg['host'] == true;
        break;
      case 'roomUpdate':
        state = msg['state'] as Map<String, dynamic>?;
        serverVersion = (msg['serverVersion'] ?? state?['serverVersion'])?.toString();
        if (state != null) {
          turnRemaining = (state!['turnRemaining'] as int?) ?? 0;
          turnSeat = (state!['turnSeat'] as int?) ?? -1;
          actionTimeout = (state!['actionTimeout'] as int?) ?? 60;
          handPaused = (state!['handPaused'] as bool?) ?? false;
          extensionCount = (state!['extensionCount'] as int?) ?? 2;
          extensionSeconds = (state!['extensionSeconds'] as int?) ?? 60;
        }
        _onRoomUpdate();
        break;
      case 'roomList':
        roomList = (msg['rooms'] as List?) ?? [];
        serverVersion = msg['serverVersion']?.toString() ?? serverVersion;
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
      case 'summary':
        summary = msg;
        break;
      case 'dailyReport':
        dailyReport = msg;
        break;
      case 'roomReport':
        // 大厅“战绩”按钮返回的整房间战绩（不进入房间也可查看）
        roomReport = msg;
        break;
      case 'resetStatsOk':
        // 战绩重置成功，清空本地战绩缓存以便下次重新获取
        roomReport = null;
        break;
      case 'playerSummary':
        // 离场时服务端给本人发的个人战绩，结构与 dailyReport 一致，复用同一弹窗
        dailyReport = msg;
        break;
      case 'left':
        roomId = null;
        playerId = null;
        isHost = false;
        state = null;
        // 注意：不清空 dailyReport，离场统计需在返回大厅前展示
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
    // 行动倒计时（服务端权威）：显示当前行动者剩余秒，全桌可见。
    // 每次状态刷新时以服务端下发的 turnRemaining 重置，本地每秒平滑递减。
    if (turnRemaining > 0 && turnSeat >= 0) {
      secondsLeft = turnRemaining;
      timeoutWarning = secondsLeft <= 10;
      if (_tickTimer == null) {
        _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
      }
    } else {
      secondsLeft = 0;
      timeoutWarning = false;
      _tickTimer?.cancel();
      _tickTimer = null;
    }
  }

  // ---- 动作封装 ----
  void createRoom({
    required String roomName,
    required String name,
    required int buyIn,
    required int sb,
    required int bb,
    int ante = 0,
    int minBuyIn = 1000,
    int maxBuyIn = 3999,
    int buyInUnit = 1000,
    int aiCount = 0,
    List<String>? aiNames,
    int actionTimeout = 60,
    int extensionCount = 2,
    int extensionSeconds = 60,
  }) {
    final n = name.trim().isEmpty ? (nickname ?? '玩家') : name.trim();
    _send({
      'type': 'createRoom',
      'roomName': roomName,
      'name': n,
      'buyIn': buyIn,
      'smallBlind': sb,
      'bigBlind': bb,
      'ante': ante,
      'minBuyIn': minBuyIn,
      'maxBuyIn': maxBuyIn,
      'buyInUnit': buyInUnit,
      'aiCount': aiCount,
      'aiNames': aiNames ?? [],
      'actionTimeout': actionTimeout,
      'extensionCount': extensionCount,
      'extensionSeconds': extensionSeconds,
    });
  }

  void joinRoom(String roomId, String name, int buyIn,
      {String password = '', int minBuyIn = 1000, int maxBuyIn = 3999, int buyInUnit = 1000}) {
    final n = name.trim().isEmpty ? (nickname ?? '玩家') : name.trim();
    _send({
      'type': 'joinRoom',
      'roomId': roomId.toUpperCase(),
      'name': n,
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

  void pauseAfterHand() => _send({'type': 'pauseAfterHand', 'paused': true});
  void resumeAfterHand() => _send({'type': 'pauseAfterHand', 'paused': false});

  /// 继续下一手：清除暂停标记并让服务端开始发牌
  void resumeNextHand() => _send({'type': 'resumeNextHand'});

  /// 申请延长当前回合的思考时间（消耗一次延长次数）
  void requestExtension() => _send({'type': 'requestExtension'});

  /// 房主修改房间参数
  void updateRoom(Map<String, dynamic> params) => _send({'type': 'updateRoom', ...params});

  /// 房主删除当前房间
  void deleteRoom() => _send({'type': 'deleteRoom'});

  /// 管理员（知道管理密码）删除任意房间
  void adminDeleteRoom(String roomId, String password) =>
      _send({'type': 'adminDeleteRoom', 'roomId': roomId.toUpperCase(), 'password': password});

  /// 管理员（知道管理密码）修改任意房间参数
  void adminUpdateRoom(Map<String, dynamic> params) =>
      _send({'type': 'adminUpdateRoom', ...params});

  void requestRoomReport(String roomId) {
    roomReport = null;
    _send({'type': 'roomReport', 'roomId': roomId.toUpperCase()});
  }

  void adminResetStats(String roomId, String password) =>
      _send({'type': 'adminResetStats', 'roomId': roomId.toUpperCase(), 'password': password});

  void clearError() {
    errorMsg = null;
    notifyListeners();
  }

  /// 断线后自动重连（1.5 秒一次，比旧版 5 秒更快恢复）
  void _scheduleReconnect() {
    _retryTimer?.cancel();
    if (_disposed) return;
    _retryTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_disposed) return;
      connect();
    });
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

  // 我当前剩余的延长次数
  int get myExtLeft {
    final m = me;
    return (m?['extLeft'] as int?) ?? 0;
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

  // 当前应发牌者（庄家，或其下家链第一个人类），由服务端计算下发
  String get starterId => (state?['starterId'] as String?) ?? '';

  // 庄家 id
  String get dealerId => (state?['dealerId'] as String?) ?? '';

  // 房主 id
  String get hostId => (state?['hostId'] as String?) ?? '';

  // 当前用户是否为房主
  bool get amIHost => playerId != null && hostId == playerId;

  // 已请求“本手结束后暂停”的玩家 id 列表
  List<String> get pausedIds {
    final list = state?['pausedIds'];
    if (list is List) {
      return list.map((e) => e.toString()).toList();
    }
    return [];
  }

  // 距离自动开始下一手的秒数（0 表示未在倒计时）
  int get timeToNextHand => (state?['timeToNextHand'] as int?) ?? 0;

  // 当前是否“本手结束后暂停”（自动发牌已取消手动发牌按钮，保留 getter 兼容旧代码）
  bool get isPaused => pausedIds.contains(playerId);

  // 是否有人请求暂停
  bool get someonePaused => pausedIds.isNotEmpty;

  // 自动发牌时代不再需要手动按钮；保留兼容旧代码
  bool get canStartHand => false;

  List<dynamic> get handHistory => (state?['handHistory'] as List?) ?? [];

  // ---- 思考超时计时（功能 4）----
  int get delayClicksLeft => (2 - delayClicks).clamp(0, 2);

  void _startTurnTimer() {
    _cancelTimers();
    delayClicks = 0;
    timeoutWarning = false;
    // 以服务端下发的剩余秒数为准（服务端权威惩罚，前端仅展示倒计时）
    secondsLeft = turnRemaining > 0 ? turnRemaining : actionTimeout;
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    secondsLeft = secondsLeft > 0 ? secondsLeft - 1 : 0;
    if (secondsLeft <= 10) timeoutWarning = true;
    notifyListeners();
  }

  void _onExpire() {
    // 超时惩罚由服务端执行（check/fold + 暂时离桌），前端不再自动暂离
    timeoutWarning = true;
    notifyListeners();
  }

  /// 请求服务端返回个人结算（输赢/手牌数/游戏时间/思考时间）
  void requestSummary() => _send({'type': 'requestSummary'});

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

  // ---- 手牌全过程本地日志持久化（功能 2，跨平台）----
  Future<void> _appendHistory(String line) async {
    try {
      final ts = _now();
      await _store.append('[$ts] $line');
    } catch (_) {
      // 忽略本地写入失败
    }
  }

  /// 读取本地手牌日志（供历史查看页使用）
  Future<List<String>> readHistory() async {
    try {
      return await _store.readAll();
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
    _disposed = true;
    _retryTimer?.cancel();
    _cancelTimers();
    _channel?.sink.close();
    super.dispose();
  }
}
