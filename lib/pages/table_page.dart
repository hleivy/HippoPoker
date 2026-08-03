// lib/pages/table_page.dart —— 牌桌：GG 风格图形化（椭圆牌桌 + 座位环绕 + 本人置底 + 位置标签）
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../game_controller.dart';
import '../models/card_model.dart';
import '../widgets/poker_card.dart';
import 'lobby_page.dart';
import 'hand_history_page.dart';

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

  void _leave() {
    _cancelAutoTimer();
    _c.leaveRoom();
    _c.dispose();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LobbyPage(controller: GameController())),
      (_) => false,
    );
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
        title: Text(roomName),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _autoCall = !_autoCall;
              if (!_autoCall) _cancelAutoTimer();
            }),
            child: Text(_autoCall ? '自动跟注·开' : '自动跟注·关',
                style: TextStyle(color: _autoCall ? Colors.amber : Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => HandHistoryPage(controller: _c))),
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
          final isDealerFirst = dealerSeat < 0;

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
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: i < community.length
                        ? PokerCardView(card: community[i])
                        : PokerCardView(card: null, width: 40, height: 56),
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
              // 椭圆牌桌（绿绒）
              seats.add(Positioned(
                left: cx - rx,
                top: cy - ry,
                child: Container(
                  width: rx * 2,
                  height: ry * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0E5C3A),
                    border: Border.all(color: Colors.green.shade700, width: 6),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 12, spreadRadius: 2)
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
                seats.add(Positioned(
                  left: x,
                  top: y,
                  child: Transform.translate(
                    offset: const Offset(-62, -50),
                    child: _buildSeat(p, p['id'] == _c.playerId, pos),
                  ),
                ));
              }
              return Stack(children: seats);
            },
          );

          return Column(
            children: [
              // 状态条
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                color: Colors.black38,
                child: Column(
                  children: [
                    if (_c.canStartHand)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ElevatedButton(
                          onPressed: _c.startHand,
                          child: Text(isDealerFirst ? '房主发牌（首手）' : '庄家发牌'),
                        ),
                      )
                    else if (!inProgress)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('等待庄家开始下一手', style: TextStyle(color: Colors.white70)),
                      ),
                  ],
                ),
              ),
              // 思考超时警告（功能 4）
              if (_c.timeoutWarning)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.red.shade800,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '即将自动暂时离桌（剩余 ${_c.secondsLeft}s）',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_c.delayClicksLeft > 0)
                        ElevatedButton(
                          onPressed: _c.requestDelay,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                          child: Text('延时1分钟 (${_c.delayClicksLeft})'),
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
              // 我的管理操作（非行动时可见）
              if (me != null && !myTurn)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  color: Colors.black45,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (me['tempLeft'] == true)
                        ElevatedButton(
                          onPressed: _c.returnTable,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                          child: const Text('返回牌桌'),
                        )
                      else ...[
                        ElevatedButton(
                          onPressed: _c.tempLeave,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                          child: const Text('暂时离桌'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: (!inProgress) ? _showBuyCashout : null,
                          child: const Text('补充/赎回'),
                        ),
                      ]
                    ],
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
  Widget _buildSeat(Map<String, dynamic> p, bool isSelf, String pos) {
    final name = (p['name']?.toString() ?? '玩家');
    final chips = (p['chips'] as int?) ?? 0;
    final bet = (p['bet'] as int?) ?? 0;
    final folded = p['folded'] == true;
    final allIn = p['allIn'] == true;
    final isTurn = p['isTurn'] == true;
    final isDealer = p['isDealer'] == true;
    final cards = (p['cards'] as List? ?? [])
        .map((c) => PokerCard.fromJson(c as Map<String, dynamic>))
        .toList();
    final cardRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(2, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: i < cards.length
              ? PokerCardView(card: cards[i], width: 24, height: 34)
              : PokerCardView(card: null, width: 24, height: 34),
        );
      }),
    );

    return Container(
      width: 124,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: isTurn ? Colors.green.shade800 : Colors.black54,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isTurn ? Colors.amber : (isDealer ? Colors.amber.shade200 : Colors.green.shade900),
          width: isTurn ? 2.5 : 1.5,
        ),
      ),
      child: Opacity(
        opacity: folded ? 0.45 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (pos.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: pos == 'BTN' ? Colors.amber : Colors.blueGrey,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(pos, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                if (isSelf)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text('我', style: TextStyle(fontSize: 11, color: Colors.amber)),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            Text('筹码 $chips', style: const TextStyle(fontSize: 11, color: Colors.white70)),
            if (bet > 0)
              Text('下注 $bet', style: const TextStyle(fontSize: 11, color: Colors.orange)),
            const SizedBox(height: 3),
            cardRow,
            if (allIn)
              const Text('ALL IN', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
            if (folded)
              const Text('弃牌', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}
