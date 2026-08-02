// lib/pages/table_page.dart —— 牌桌：公共牌、玩家、底牌、下注动作
import 'package:flutter/material.dart';
import '../game_controller.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('房间 ${_c.roomId ?? ''}'),
        actions: [
          TextButton(onPressed: _leave, child: const Text('离开', style: TextStyle(color: Colors.white))),
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
                    Text('底池：$pot　当前注额：$currentBet'),
                    if (_c.isHost && !inProgress)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ElevatedButton(
                          onPressed: _c.startHand,
                          child: const Text('开始下一手'),
                        ),
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
                            '${p['folded'] == true ? ' · 已弃牌' : ''}'
                            '${p['allIn'] == true ? ' · 全下' : ''}'
                            '${p['acted'] == true && p['folded'] != true && p['allIn'] != true ? ' · 已行动' : ''}'),
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
              // 我的底牌
              if (me != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black45,
                  child: Row(
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
