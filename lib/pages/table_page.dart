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
  void dispose() {
    _cancelAutoTimer();
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

  // 历史手牌：牌桌页内弹框，不打断正常打牌（功能 7，不切页）
  void _showHistoryDialog() {
    final serverHist = _c.handHistory;
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('历史手牌'),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: FutureBuilder<List<String>>(
            future: _c.readHistory(),
            builder: (_, snap) {
              final local = snap.data ?? [];
              final items = <String>[];
              for (final h in serverHist) {
                if (h is Map) {
                  final line = h['line']?.toString() ?? h.toString();
                  if (line.isNotEmpty) items.add(line);
                } else if (h != null) {
                  items.add(h.toString());
                }
              }
              items.addAll(local);
              if (items.isEmpty) {
                return const Center(
                  child: Text('暂无历史手牌记录', style: TextStyle(color: Colors.white70)),
                );
              }
              return ListView(
                children: items.reversed
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(e, style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
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
          // 暂停 / 继续：仅在本手未结束时显示；暂停后下一手不会自动开始
          if (_c.state?['handInProgress'] != true)
            TextButton(
              onPressed: _c.isPaused ? _c.resumeAfterHand : _c.pauseAfterHand,
              child: Text(_c.isPaused ? '继续发牌' : '本手后暂停',
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
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: i < community.length
                        ? PokerCardView(card: community[i], width: 50, height: 70)
                        : PokerCardView(card: null, width: 50, height: 70),
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
                    color: const Color(0xFF0E5C3A),
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

          return Column(
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
                      ],
                    ),
                  );
                }),
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
          );
        },
      ),
    );
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
              : PokerCardView(card: null, width: 40, height: 56),
        );
      }),
    );

    return Container(
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
            Text('筹码 $chips', style: const TextStyle(fontSize: 13, color: Colors.white70)),
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
    );
  }
}
