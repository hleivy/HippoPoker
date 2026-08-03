// lib/pages/table_page.dart —— 牌桌：公共牌、玩家、底牌、下注动作 + 9 项功能 UI
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

  static const _stageLabels = {
    'preflop': '翻牌前',
    'flop': '翻牌',
    'turn': '转牌',
    'river': '河牌',
    'showdown': '摊牌',
    'ended': '本手结束',
  };

  void _leave() {
    _c.leaveRoom();
    _c.dispose();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LobbyPage(controller: GameController())),
      (_) => false,
    );
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

  @override
  Widget build(BuildContext context) {
    _maybeShowReport();
    return Scaffold(
      appBar: AppBar(
        title: Text('房间 ${_c.roomId ?? ''}'),
        actions: [
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
          final isDealerFirst = (state['dealerSeat'] as int? ?? -1) < 0;

          return Column(
            children: [
              // 状态条
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: Colors.black38,
                child: Column(
                  children: [
                    Text(_stageLabels[stage] ?? stage,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('底池：$pot　当前注额：$currentBet'
                        '${_c.ante > 0 ? '　前注：${_c.ante}' : ''}'),
                    if (_c.canStartHand)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ElevatedButton(
                          onPressed: _c.startHand,
                          child: Text(isDealerFirst ? '房主发牌（首手）' : '庄家发牌'),
                        ),
                      )
                    else if (!inProgress)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
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
              // 公共牌
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
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
              ),
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
              // 玩家列表
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: players.map((p) {
                    final cards = (p['cards'] as List? ?? [])
                        .map((c) => PokerCard.fromJson(c as Map<String, dynamic>))
                        .toList();
                    final isTurn = p['isTurn'] == true;
                    final tempLeft = p['tempLeft'] == true;
                    final totalBuyIn = p['totalBuyIn'] as int?;
                    final winLoss = p['winLoss'] as int?;
                    return Card(
                      color: isTurn ? Colors.green.shade900 : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: p['isDealer'] == true ? Colors.amber : Colors.grey,
                          child: Text(p['seat'].toString()),
                        ),
                        title: Text(p['name'] ?? '玩家'),
                        subtitle: Text(
                            '筹码 ${p['chips']}　本手下注 ${p['bet']}'
                            '${totalBuyIn != null ? '　总买入 $totalBuyIn' : ''}'
                            '${winLoss != null ? '　输赢 ${winLoss >= 0 ? '+' : ''}$winLoss' : ''}'
                            '${p['folded'] == true && !tempLeft ? ' · 已弃牌' : ''}'
                            '${tempLeft ? ' · 暂离' : ''}'
                            '${p['allIn'] == true ? ' · 全下' : ''}'
                            '${p['acted'] == true && p['folded'] != true && p['allIn'] != true && !tempLeft ? ' · 已行动' : ''}'),
                        trailing: SizedBox(
                          width: 96,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: cards
                                .map((c) => PokerCardView(card: c, width: 30, height: 42))
                                .toList(),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              // 我的底牌 + 我的管理操作
              if (me != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black45,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('我的手牌：', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          ...((me['cards'] as List? ?? [])
                                  .map((c) => PokerCardView(
                                      card: PokerCard.fromJson(c as Map<String, dynamic>)))
                                  .toList())
                              .cast<Widget>(),
                          if ((me['cards'] as List? ?? []).isEmpty)
                            const Text('（未发牌）', style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
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
                              onPressed: (!inProgress || myTurn) ? null : _showBuyCashout,
                              child: const Text('补充/赎回'),
                            ),
                          ]
                        ],
                      ),
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
}
