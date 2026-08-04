// lib/pages/table_page.dart —— 牌桌：GG 风格图形化（椭圆牌桌 + 座位环绕 + 本人置底 + 位置标签）
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../game_controller.dart';
import '../config.dart';
import '../models/card_model.dart';
import '../widgets/poker_card.dart';
import 'lobby_page.dart';

class TablePage extends StatefulWidget {
  final GameController controller;
  const TablePage({super.key, required this.controller});

  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage> {
  late final GameController _c = widget.controller;
  int _raiseTarget = 0;
  bool _reportShown = false;
  bool _autoCall = false; // 测试用：轮到我时自动过牌/跟注
  Timer? _autoTimer;
  Timer? _bubbleTimer; // 行动气泡淡出定时器（每 400ms 刷新一次）

  // 是否存在“近期行动”，用于决定是否保持气泡定时器运行
  bool _hasFreshActions(List<Map<String, dynamic>> players) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in players) {
      final la = p['lastAction'];
      if (la is Map && (la['at'] as int? ?? 0) > 0) {
        if (now - (la['at'] as int) < 4200) return true;
      }
    }
    return false;
  }

  static const _stageLabels = {
    'waiting': '等待开始',
    'preflop': '翻牌前',
    'flop': '翻牌',
    'turn': '转牌',
    'river': '河牌',
    'showdown': '摊牌',
    'ended': '本手结束',
  };

  void _leave() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出房间？'),
        content: const Text('确定要离开当前牌桌吗？离开后将结算你的输赢、手牌数、游戏时间与思考时间。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定离开'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    _cancelAutoTimer();
    // 请求服务端返回个人结算
    _c.requestSummary();
    await Future.delayed(const Duration(milliseconds: 500));
    final s = _c.summary;
    if (s != null && mounted) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('本局结算（${s['name'] ?? ''}）'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('净输赢：${_fmt(s['winLoss'])}',
                  style: TextStyle(
                      color: ((s['winLoss'] as num? ?? 0) >= 0)
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('参与手牌：${s['handsPlayed']} 手'),
              Text('游戏时长：${_fmtDuration(s['gameSeconds'])}'),
              Text('累计思考：${_fmtDuration(s['thinkSeconds'])}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
    // 真正离开并回到大厅
    _c.leaveRoom();
    _c.dispose();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LobbyPage(controller: GameController())),
      (_) => false,
    );
  }

  String _fmt(dynamic v) {
    final n = (v as num?)?.toInt() ?? 0;
    return '${n >= 0 ? '+' : ''}$n';
  }

  String _fmtDuration(dynamic secs) {
    final s = (secs as num?)?.toInt() ?? 0;
    final m = s ~/ 60;
    final r = s % 60;
    return m > 0 ? '$m 分 $r 秒' : '$r 秒';
  }

  // 测试用：轮到我且未行动时，延迟一小段自动过牌/跟注，便于单人 vs AI 看完一手牌
  void _scheduleAutoCall() {
    if (!_autoCall || _autoTimer != null || !_c.myTurn) return;
    _autoTimer = Timer(const Duration(milliseconds: 1200), () {
      _autoTimer = null;
      if (!mounted || !_autoCall || !_c.myTurn) return;
      final callNeed = _c.callNeed;
      _c.action(callNeed == 0 ? 'check' : 'call', amount: callNeed);
    });
  }

  void _cancelAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  @override
  void initState() {
    super.initState();
    // 行动气泡淡出：定期触发重建，仅在有近期行动时运行
    _bubbleTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      final st = _c.state;
      if (st == null) return;
      final players = (st['players'] as List? ?? [])
          .map((p) => p as Map<String, dynamic>)
          .toList();
      if (_hasFreshActions(players)) setState(() {});
    });
  }

  @override
  void dispose() {
    _cancelAutoTimer();
    _bubbleTimer?.cancel();
    super.dispose();
  }

  void _maybeShowReport() {
    if (_c.dailyReport != null && !_reportShown && mounted) {
      _reportShown = true;
      final report = _c.dailyReport!;
      final players = (report['players'] as List?) ?? [];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('当日输赢报告（${report['date'] ?? ''}）'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: players.map((p) {
                  final m = p as Map<String, dynamic>;
                  final wl = (m['winLoss'] as num?)?.toInt() ?? 0;
                  return ListTile(
                    title: Text(m['name']?.toString() ?? '玩家'),
                    subtitle: Text(
                        '总买入 ${m['totalBuyIn']} · 已赎回 ${m['cashedOut']} · 当前 ${m['chips']}'),
                    trailing: Text('${wl >= 0 ? '+' : ''}$wl',
                        style: TextStyle(
                            color: wl >= 0 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold)),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              )
            ],
          ),
        );
      });
    }
  }

  // 单条手牌历史记录（含赢家与思考时间统计）
  Widget _buildHistoryRecord(Map<String, dynamic> h) {
    final handNo = (h['handNumber'] as int?) ?? 0;
    final pot = (h['pot'] as int?) ?? 0;
    final winners = (h['winners'] as List?) ?? [];
    final log = (h['actionThinkLog'] as List?) ?? [];
    // 按玩家聚合思考时间（ms）
    final Map<String, int> thinkByName = {};
    for (final e in log) {
      if (e is! Map) continue;
      final name = (e['name']?.toString()) ?? '?';
      final ms = (e['thinkMs'] as int?) ?? 0;
      thinkByName[name] = (thinkByName[name] ?? 0) + ms;
    }
    final thinkSorted = thinkByName.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final winText = winners.isNotEmpty
        ? winners
            .map((w) {
              final m = w as Map<String, dynamic>;
              return '${m['name']} +${m['amount']}';
            })
            .join('，')
        : '无（弃牌/未结算）';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade900, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('第 $handNo 手 · 底池 $pot',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 3),
          Text('赢家：$winText', style: const TextStyle(fontSize: 12, color: Colors.amber)),
          if (thinkSorted.isNotEmpty)
            Text(
              '思考：${thinkSorted.map((e) => '${e.key} ${(e.value / 1000).toStringAsFixed(1)}s').join('，')}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
        ],
      ),
    );
  }

  // 历史手牌：牌桌页内弹框，不打断正常打牌（功能 7，不切页）
  void _showHistoryDialog() {
    final serverHist = _c.handHistory.whereType<Map<String, dynamic>>().toList();
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('历史手牌'),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: FutureBuilder<List<String>>(
            future: _c.readHistory(),
            builder: (_, snap) {
              final local = snap.data ?? [];
              if (serverHist.isEmpty && local.isEmpty) {
                return const Center(
                  child: Text('暂无历史手牌记录', style: TextStyle(color: Colors.white70)),
                );
              }
              final records = serverHist.reversed.toList();
              return ListView(
                children: [
                  ...records.map(_buildHistoryRecord),
                  if (local.isNotEmpty) ...[
                    const Divider(color: Colors.white30),
                    const Text('本机操作日志', style: TextStyle(fontSize: 12, color: Colors.white54)),
                    ...local.reversed.map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(e, style: const TextStyle(fontSize: 12, color: Colors.white60)),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('关闭'),
          )
        ],
      ),
    );
  }

  void _showBuyCashout() {
    final unit = _c.buyInUnit;
    final maxBuy = _c.maxBuyIn;
    final minBuy = _c.minBuyIn;
    final myChips = (_c.me?['chips'] as int?) ?? 0;
    final isBuy = ValueNotifier<bool>(true);
    final amtCtrl = TextEditingController(text: unit.toString());
    String? err;

    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('补充 / 赎回筹码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: isBuy,
                builder: (_, buy, __) => ToggleButtons(
                  isSelected: [buy, !buy],
                  onPressed: (i) => setSt(() => isBuy.value = i == 0),
                  children: const [Padding(padding: EdgeInsets.all(8), child: Text('补充')),
                    Padding(padding: EdgeInsets.all(8), child: Text('赎回'))],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '金额（最小单位 $unit 的整数倍）',
                ),
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(err!, style: const TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 6),
              Text('当前筹码 $myChips · 上限 $maxBuy · 下限 $minBuy',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final amt = int.tryParse(amtCtrl.text.trim()) ?? 0;
                if (amt <= 0) {
                  setSt(() => err = '金额必须大于 0');
                  return;
                }
                if (unit > 0 && amt % unit != 0) {
                  setSt(() => err = '必须是 $unit 的整数倍');
                  return;
                }
                if (isBuy.value) {
                  if (myChips + amt > maxBuy) {
                    setSt(() => err = '补充后超过买入上限 $maxBuy');
                    return;
                  }
                  _c.buyChips(amt);
                } else {
                  if (myChips - amt < minBuy) {
                    setSt(() => err = '赎回后低于买入下限 $minBuy');
                    return;
                  }
                  _c.cashOut(amt);
                }
                Navigator.of(ctx).pop();
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  // 自动发牌状态条：倒计时 / 已暂停 / 正在游戏中
  Widget _buildStatusBar(Map<String, dynamic> state, Map<String, dynamic>? me,
      List<Map<String, dynamic>> players, bool inProgress) {
    if (inProgress) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)),
          const SizedBox(width: 8),
          Text('第 ${state['handNumber'] ?? 0} 手进行中 · ${_stageLabels[state['stage']] ?? state['stage']}',
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      );
    }
    final stage = state['stage'] as String? ?? '';
    if (stage == 'ended' || stage == 'showdown' || stage == 'waiting') {
      if (_c.someonePaused) {
        final names = _c.pausedIds
            .map((id) => players.firstWhere((p) => p['id'] == id, orElse: () => {})['name']?.toString() ?? '玩家')
            .where((n) => n.isNotEmpty)
            .join('、');
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pause, color: Colors.amber, size: 18),
            const SizedBox(width: 6),
            Text('已暂停：$names 请求本手后暂停',
                style: const TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        );
      }
      final t = _c.timeToNextHand;
      if (t > 0) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer, color: Colors.amber, size: 18),
            const SizedBox(width: 6),
            Text('本手结束 · ${t} 秒后自动发下一手牌',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        );
      }
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hourglass_empty, color: Colors.white54, size: 18),
          SizedBox(width: 6),
          Text('等待开始下一手…', style: TextStyle(color: Colors.white54, fontSize: 14)),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  // 根据相对庄家的座位序号计算位置标签（BTN/SB/BB/UTG/MP/CO）
  String _posLabel(int rel, int n) {
    if (rel == 0) return 'BTN';
    if (rel == 1) return 'SB';
    if (rel == 2) return 'BB';
    if (n >= 5 && rel == n - 1) return 'CO';
    if (n == 4 && rel == 3) return 'UTG';
    if (rel == 3) return 'UTG';
    if (rel == n - 2) return 'MP';
    return 'MP';
  }

  @override
  Widget build(BuildContext context) {
    _maybeShowReport();
    final roomName = _c.state?['roomName']?.toString() ?? '牌桌';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _leave,
        ),
        title: Text(roomName),
        actions: [
          // 暂停 / 取消暂停：请求“本手结束后暂停发牌”（由底部“继续下一手”恢复）
          if (_c.state?['handInProgress'] != true)
            TextButton(
              onPressed: _c.isPaused ? _c.resumeAfterHand : _c.pauseAfterHand,
              child: Text(_c.isPaused ? '取消暂停' : '本手后暂停',
                  style: TextStyle(color: _c.isPaused ? Colors.amber : Colors.white)),
            ),
          TextButton(
            onPressed: () => setState(() {
              _autoCall = !_autoCall;
              if (!_autoCall) _cancelAutoTimer();
            }),
            child: Text(_autoCall ? '自动跟注·开' : '自动跟注·关',
                style: TextStyle(color: _autoCall ? Colors.amber : Colors.white)),
          ),
          TextButton(
            onPressed: _showHistoryDialog,
            child: const Text('历史', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: _leave,
            child: const Text('离开', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) {
          final state = _c.state;
          if (_autoCall && _c.myTurn) _scheduleAutoCall(); else _cancelAutoTimer();
          if (state == null) {
            return const Center(child: Text('等待房间状态…'));
          }
          final stage = state['stage'] as String? ?? '';
          final pot = state['pot'] as int? ?? 0;
          final community = (state['community'] as List? ?? [])
              .map((c) => PokerCard.fromJson(c as Map<String, dynamic>))
              .toList();
          final inProgress = state['handInProgress'] == true;
          final players = (state['players'] as List? ?? [])
              .map((p) => p as Map<String, dynamic>)
              .toList();
          final me = _c.me;
          final myTurn = _c.myTurn;
          final callNeed = _c.callNeed;
          final currentBet = state['currentBet'] as int? ?? 0;
          final minRaise = state['minRaise'] as int? ?? 1;
          final myBet = me?['bet'] as int? ?? 0;
          final myChips = me?['chips'] as int? ?? 0;
          final maxTarget = myBet + myChips;
          final minTarget = currentBet + minRaise;
          final canRaise = maxTarget > minTarget;
          final target = _raiseTarget.clamp(minTarget, maxTarget);
          final lastResult = state['lastResult'] as Map<String, dynamic>?;
              final dealerSeat = (state['dealerSeat'] as int? ?? -1);
          final mySeat = me?['seat'] as int? ?? -1;
          final n = players.length;

          // 居中区：底池 + 公共牌
          Widget centerArea = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('底池  $pot',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 6),
              _buildChipStack(pot, size: 18),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: i < community.length
                        ? PokerCardView(card: community[i], width: 50, height: 70)
                        : CardBack(width: 50, height: 70),
                  );
                }),
              ),
              const SizedBox(height: 6),
              Text(_stageLabels[stage] ?? stage,
                  style: const TextStyle(color: Colors.white70)),
            ],
          );

          // 牌桌图形区
          Widget tableArea = LayoutBuilder(
            builder: (lctx, cons) {
              final w = cons.maxWidth;
              final h = cons.maxHeight;
              final cx = w / 2;
              final cy = h / 2;
              final rx = w * 0.40;
              final ry = h * 0.37;
              final seats = <Widget>[];
              // 赌场椭圆牌桌：木边 + 绿绒椭圆台面
              seats.add(Positioned(
                left: cx - rx - 12,
                top: cy - ry - 12,
                child: Container(
                  width: (rx + 12) * 2,
                  height: (ry + 12) * 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ry + 12),
                    color: const Color(0x8B5E3C), // 木质外圈
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 16, spreadRadius: 3)
                    ],
                  ),
                ),
              ));
              seats.add(Positioned(
                left: cx - rx,
                top: cy - ry,
                child: Container(
                  width: rx * 2,
                  height: ry * 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ry), // 椭圆（胶囊形，经典牌桌轮廓）
                    gradient: const RadialGradient(
                      colors: [Color(0xFF1B7A4B), Color(0xFF0B3D27)], // 中心亮、边缘暗的绿绒台面
                      center: Alignment.center,
                      radius: 0.75,
                    ),
                    border: Border.all(color: const Color(0x6B8E23), width: 4),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 10, spreadRadius: 2)
                    ],
                  ),
                ),
              ));
              // 中央底池与公共牌
              seats.add(Positioned(
                left: cx,
                top: cy,
                child: Transform.translate(
                  offset: const Offset(-110, -62),
                  child: SizedBox(width: 220, child: centerArea),
                ),
              ));
              // 各座位
              for (final p in players) {
                final seat = (p['seat'] as int?) ?? 0;
                final rScreen = n > 0 ? (((seat - mySeat) % n) + n) % n : 0;
                final angle = pi / 2 - rScreen * (2 * pi / (n > 0 ? n : 1));
                final x = cx + rx * cos(angle);
                final y = cy + ry * sin(angle);
                final relPos = dealerSeat >= 0 && n > 0
                    ? (((seat - dealerSeat) % n) + n) % n
                    : -1;
                final pos = relPos >= 0 ? _posLabel(relPos, n) : '';
                final isDealer = p['id'] == _c.dealerId;
                final bet = (p['bet'] as int?) ?? 0;
                // 下注筹码放在座位内侧（更靠近底池）
                if (bet > 0) {
                  final innerX = cx + (rx * 0.55) * cos(angle);
                  final innerY = cy + (ry * 0.55) * sin(angle);
                  seats.add(Positioned(
                    left: innerX,
                    top: innerY,
                    child: Transform.translate(
                      offset: const Offset(-24, -12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade200, width: 1),
                        ),
                        child: Text('$bet', style: const TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ));
                }
                seats.add(Positioned(
                  left: x,
                  top: y,
                  child: Transform.translate(
                    offset: const Offset(-78, -52),
                    child: _buildSeat(p, p['id'] == _c.playerId, pos, isDealer),
                  ),
                ));
              }
              return Stack(children: seats);
            },
          );

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 1000),
              child: Column(
                children: [
              // 状态条：自动发牌提示 / 暂停提示 / 倒计时
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                color: Colors.black38,
                child: _buildStatusBar(state, me, players, inProgress),
              ),
              // 行动倒计时（全桌可见）：显示当前行动者与剩余秒数
              if (inProgress && _c.turnSeat >= 0)
                Builder(builder: (ctx) {
                  final actor = players.firstWhere(
                    (p) => (p['seat'] as int? ?? -1) == _c.turnSeat,
                    orElse: () => <String, dynamic>{},
                  );
                  final name = actor['name']?.toString() ?? '玩家';
                  final isMe = actor['id'] == _c.playerId;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: _c.timeoutWarning ? Colors.red.shade800 : Colors.blueGrey.shade800,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            isMe
                                ? '轮到你行动（剩余 ${_c.secondsLeft}s）'
                                : '等待 $name 行动（剩余 ${_c.secondsLeft}s）',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (isMe && _c.myExtLeft > 0)
                          TextButton.icon(
                            onPressed: _c.requestExtension,
                            icon: const Icon(Icons.hourglass_bottom, size: 16),
                            label: Text('申请延长(${_c.myExtLeft})'),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.blueGrey.shade600),
                          ),
                      ],
                    ),
                  );
                }),
              // 暂停发牌后：醒目的“继续下一手”按钮
              if (_c.handPaused)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pause_circle_filled, color: Colors.white),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('已暂停发牌，等待继续',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      ElevatedButton.icon(
                        onPressed: _c.resumeNextHand,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('继续下一手'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber, foregroundColor: Colors.black),
                      ),
                    ],
                  ),
                ),
              // 牌桌图形
              Expanded(child: tableArea),
              // 本手结果
              if (lastResult != null && !inProgress)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade800,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(lastResult['note']?.toString() ?? '',
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                ),
              // 我的管理操作：离桌/回桌、补充赎回（始终可见，参考 GG 底部信息条）
              if (me != null)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  color: Colors.black45,
                  child: SafeArea(
                    top: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 左侧：补充/赎回
                        ElevatedButton.icon(
                          onPressed: (!inProgress || me['tempLeft'] == true) ? _showBuyCashout : null,
                          icon: const Icon(Icons.account_balance_wallet, size: 16),
                          label: const Text('补充 / 赎回'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                        ),
                        // 右侧：离桌 / 回桌（更显眼）
                        if (me['tempLeft'] == true)
                          ElevatedButton.icon(
                            onPressed: _c.returnTable,
                            icon: const Icon(Icons.login, size: 18),
                            label: const Text('回到牌桌'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: _c.tempLeave,
                            icon: const Icon(Icons.logout, size: 18),
                            label: const Text('暂时离桌'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade700,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              // 每页版本号
              Center(
                child: Text(
                  '内部测试版 v$kAppVersion · 服务端 v${_c.serverVersion ?? '连接中…'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              // 动作条
              if (myTurn)
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.black54,
                  child: Column(
                    children: [
                      if (canRaise)
                        Row(
                          children: [
                            const Text('加注到：'),
                            Expanded(
                              child: Slider(
                                min: minTarget.toDouble(),
                                max: maxTarget.toDouble(),
                                value: target.toDouble(),
                                divisions: (maxTarget - minTarget).clamp(1, 1000),
                                label: target.toString(),
                                onChanged: (v) => setState(() => _raiseTarget = v.toInt()),
                              ),
                            ),
                            Text('$target'),
                          ],
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: () => _c.action('fold'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('弃牌'),
                          ),
                          ElevatedButton(
                            onPressed: () => _c.action(callNeed == 0 ? 'check' : 'call',
                                amount: callNeed),
                            child: Text(callNeed == 0 ? '过牌' : '跟注 $callNeed'),
                          ),
                          if (canRaise)
                            ElevatedButton(
                              onPressed: () => _c.action('raise', amount: target),
                              child: const Text('加注'),
                            ),
                          if (canRaise)
                            ElevatedButton(
                              onPressed: () => _c.action('raise', amount: maxTarget),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                              child: const Text('全下'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
        },
      ),
    );
  }

  // 行动文字气泡：根据 lastAction 生成“弃牌/过牌/跟注/加注”提示（带淡出）
  Widget? _buildActionBubble(Map<String, dynamic> p) {
    final la = p['lastAction'];
    if (la is! Map) return null;
    final at = (la['at'] as int? ?? 0);
    if (at <= 0) return null;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    if (age < 0 || age > 4200) return null;
    final action = (la['action'] as String?) ?? '';
    final amount = (la['amount'] as int?) ?? 0;
    final timeout = la['timeout'] == true;
    late String text;
    late Color color;
    switch (action) {
      case 'fold':
        text = '弃牌';
        color = Colors.red;
        break;
      case 'check':
        text = '过牌';
        color = Colors.blueGrey;
        break;
      case 'call':
        text = '跟注 $amount';
        color = Colors.lightGreen;
        break;
      case 'raise':
        text = '加注到 $amount';
        color = Colors.orange;
        break;
      default:
        return null;
    }
    if (timeout) text = '⏱ $text';
    final opacity = (1 - age / 4200).clamp(0.0, 1.0);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1))
          ],
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // 筹码堆积图标：纵向堆叠的圆盘表示筹码量级（1~maxDiscs 个），右侧显示数值
  Widget _buildChipStack(int chips, {double size = 16, int maxDiscs = 8}) {
    final discColors = [
      const Color(0xFFE53935),
      const Color(0xFF1E88E5),
      const Color(0xFF43A047),
      const Color(0xFFFB8C00),
      const Color(0xFF8E24AA),
    ];
    final tier = chips <= 0 ? 0 : (log(chips) / ln10 * 2).clamp(1, maxDiscs).ceil();
    final discs = <Widget>[];
    for (int i = 0; i < tier; i++) {
      discs.add(Positioned(
        bottom: i * (size * 0.30),
        child: Container(
          width: size,
          height: size * 0.42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: discColors[i % discColors.length],
            border: Border.all(color: Colors.white70, width: 1.2),
          ),
          child: Center(child: Container(width: size * 0.5, height: 2, color: Colors.white54)),
        ),
      ));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: size,
          height: tier > 0 ? size * 0.42 + (tier - 1) * (size * 0.30) + 2 : size * 0.42,
          child: Stack(children: discs),
        ),
        const SizedBox(width: 6),
        Text(_fmtChips(chips),
            style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _fmtChips(int chips) {
    if (chips >= 10000) {
      return '${(chips / 1000).toStringAsFixed(chips % 1000 == 0 ? 0 : 1)}k';
    }
    return chips.toString();
  }

  // 单个座位卡片（围绕牌桌显示）
  Widget _buildSeat(Map<String, dynamic> p, bool isSelf, String pos, bool isDealer) {
    final name = (p['name']?.toString() ?? '玩家');
    final chips = (p['chips'] as int?) ?? 0;
    final folded = p['folded'] == true;
    final allIn = p['allIn'] == true;
    final isTurn = p['isTurn'] == true;
    final tempLeft = p['tempLeft'] == true;
    final sittingOut = p['sittingOut'] == true;
    final cards = (p['cards'] as List? ?? [])
        .map((c) => PokerCard.fromJson(c as Map<String, dynamic>))
        .toList();
    final cardRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(2, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: i < cards.length
              ? PokerCardView(card: cards[i], width: 40, height: 56)
              : CardBack(width: 40, height: 56),
        );
      }),
    );

    final bubble = _buildActionBubble(p);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          width: 156,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: tempLeft || sittingOut
                ? Colors.black38
                : (isTurn ? Colors.green.shade800 : Colors.black54),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isTurn ? Colors.amber : (isDealer ? Colors.amber.shade200 : Colors.green.shade900),
              width: isTurn ? 3 : 2,
            ),
            // 当前行动者高亮发光
            boxShadow: isTurn
                ? [BoxShadow(color: Colors.amber.withValues(alpha: 0.7), blurRadius: 16, spreadRadius: 2)]
                : null,
          ),
          child: Opacity(
            opacity: folded ? 0.45 : (tempLeft || sittingOut ? 0.55 : 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isDealer)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Text('D', style: TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    if (pos.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: pos == 'BTN' ? Colors.amber : Colors.blueGrey,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(pos, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    if (isSelf)
                      const Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: Text('我', style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                // 筹码堆积图标（替代纯数字显示）
                _buildChipStack(chips),
                const SizedBox(height: 4),
                cardRow,
                if (tempLeft || sittingOut)
                  const Text('暂时离桌', style: TextStyle(fontSize: 12, color: Colors.white54)),
                if (allIn)
                  const Text('ALL IN', style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold)),
                if (folded)
                  const Text('弃牌', style: TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
          ),
        ),
        if (bubble != null)
          Positioned(
            top: -16,
            left: 0,
            right: 0,
            child: Center(child: bubble),
          ),
      ],
    );
  }
}
