// lib/pages/table_page.dart —— 牌桌：椭圆牌桌 + 紧凑透明座位 + 顺时针位置 + 倒计时进度条
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../game_controller.dart';
import '../config.dart';
import '../ai_avatars.dart';
import '../models/card_model.dart';
import '../widgets/poker_card.dart';

class TablePage extends StatefulWidget {
  final GameController controller;
  const TablePage({super.key, required this.controller});

  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage> {
  late final GameController _c = widget.controller;
  int _raiseTarget = 0;
  String _betPreset = '1/2';
  bool _reportShown = false;
  bool _autoCall = false;
  Timer? _autoTimer;
  Timer? _bubbleTimer;

  static const _stageLabels = {
    'waiting': '等待开始',
    'preflop': '翻牌前',
    'flop': '翻牌',
    'turn': '转牌',
    'river': '河牌',
    'showdown': '摊牌',
    'ended': '本手结束',
  };

  @override
  void initState() {
    super.initState();
    // 进入牌桌立即向服务端请求一次最新状态，避免停留在“等待房间状态”
    if (_c.roomId != null) _c.sync();
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

  Future<void> _leave() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出房间？'),
        content: const Text('确定要离开当前牌桌吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('确定离开')),
        ],
      ),
    );
    if (confirm != true) return;
    _cancelAutoTimer();
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
                      color: ((s['winLoss'] as num? ?? 0) >= 0) ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('参与手牌：${s['handsPlayed']} 手'),
              Text('游戏时长：${_fmtDuration(s['gameSeconds'])}'),
              Text('累计思考：${_fmtDuration(s['thinkSeconds'])}'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('确定')),
          ],
        ),
      );
    }
    _c.leaveRoom();
    // 返回到位于栈底、与此牌桌共用同一 GameController 的大厅，避免重建连接导致“连接中”与状态丢失
    if (mounted) Navigator.of(context).pop();
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
                    subtitle: Text('总买入 ${m['totalBuyIn']} · 已赎回 ${m['cashedOut']} · 当前 ${m['chips']}'),
                    trailing: Text('${wl >= 0 ? '+' : ''}$wl',
                        style: TextStyle(color: wl >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
            ],
          ),
        );
      });
    }
  }

  // ---- 牌桌几何：顺时针排列，自己置底 ----
  Offset _seatPos(double cx, double cy, double rx, double ry, int n, int relIndex) {
    final angle = pi / 2 + relIndex * (2 * pi / (n > 0 ? n : 1));
    return Offset(cx + rx * cos(angle), cy + ry * sin(angle));
  }

  Offset _outerPos(double cx, double cy, double rx, double ry, int n, int relIndex, double factor) {
    final angle = pi / 2 + relIndex * (2 * pi / (n > 0 ? n : 1));
    return Offset(cx + rx * factor * cos(angle), cy + ry * factor * sin(angle));
  }

  String _posLabel(int rel, int n) {
    if (rel == 0) return 'BTN';
    if (rel == 1) return 'SB';
    if (rel == 2) return 'BB';
    if (n == 4 && rel == 3) return 'UTG';
    if (rel == 3) return 'UTG';
    if (n >= 6 && rel == 4) return 'UTG+1';
    if (n >= 7 && rel == 5) return 'MP';
    if (rel == n - 2) return 'CO';
    if (rel == n - 1) return 'HJ';
    return 'MP';
  }

  // ---- 筹码图标：自定义绘制高清筹码 ----
  Widget _buildChipStack(int chips, {double size = 15}) {
    if (chips <= 0) return const SizedBox.shrink();
    final tiers = [1, 100, 500, 2000, 10000, 50000, 250000];
    final colors = [
      const Color(0xFFE53935), // 红
      const Color(0xFF1E88E5), // 蓝
      const Color(0xFF43A047), // 绿
      const Color(0xFFFB8C00), // 橙
      const Color(0xFF8E24AA), // 紫
      const Color(0xFF000000), // 黑
    ];
    int count = 1;
    for (int i = 0; i < tiers.length; i++) {
      if (chips >= tiers[i]) count = (i + 1).clamp(1, 6);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: size,
          height: size + (count - 1) * size * 0.22,
          child: Stack(
            clipBehavior: Clip.none,
            children: List.generate(count, (i) {
              return Positioned(
                bottom: i * size * 0.22,
                child: CustomPaint(
                  size: Size(size, size),
                  painter: _ChipPainter(color: colors[i % colors.length]),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 4),
        Text(_fmtChips(chips), style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _fmtChips(int chips) {
    if (chips >= 10000) {
      return '${(chips / 1000).toStringAsFixed(chips % 1000 == 0 ? 0 : 1)}k';
    }
    return chips.toString();
  }

  // ---- 头像 ----
  Widget _buildAvatar(String displayName, {double radius = 22}) {
    final asset = aiAvatarFor(displayName);
    if (asset != null) {
      return CircleAvatar(radius: radius, backgroundColor: Colors.grey.shade800, backgroundImage: AssetImage(asset));
    }
    final base = displayName.replaceAll(' (AI)', '').trim();
    final initial = base.isNotEmpty ? base[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.blueGrey,
      child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  // ---- 行动气泡 ----
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
        decoration: BoxDecoration(color: color.withOpacity(0.92), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ---- 紧凑座位：无背景卡片，信息横向排布 ----
  Widget _buildSeat(Map<String, dynamic> p, bool isSelf, String pos, bool isDealer,
      {bool hideCards = false}) {
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

    final totalSec = (_c.actionTimeout > 0 ? _c.actionTimeout : 60);
    final progress = isTurn ? (_c.secondsLeft / totalSec).clamp(0.0, 1.0) : 0.0;

    Widget handWidget;
    if (hideCards) {
      handWidget = const SizedBox(width: 30);
    } else {
      handWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(2, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: i < cards.length
                ? PokerCardView(card: cards[i], width: 28, height: 40)
                : const CardBack(width: 28, height: 40),
          );
        }),
      );
    }

    final statusText = folded
        ? '已弃牌'
        : allIn
            ? 'ALL IN'
            : tempLeft || sittingOut
                ? '暂时离桌'
                : null;

    return SizedBox(
      width: 172,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 头像 + 进度条 + 气泡
          SizedBox(
            width: 52,
            height: 72,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (isTurn)
                  Positioned(
                    top: 0,
                    left: 4,
                    right: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress < 0.25 ? Colors.redAccent : Colors.amber,
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ),
                Positioned(
                  top: 10,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: isTurn
                          ? Border.all(color: Colors.amber, width: 2.5)
                          : isDealer
                              ? Border.all(color: Colors.amber.shade200, width: 1.5)
                              : null,
                      boxShadow: isTurn
                          ? [BoxShadow(color: Colors.amber.withOpacity(0.55), blurRadius: 10, spreadRadius: 1)]
                          : null,
                    ),
                    child: _buildAvatar(name, radius: 22),
                  ),
                ),
                if (_buildActionBubble(p) case final bubble?)
                  Positioned(top: -10, child: bubble),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // 名字 + 筹码 + 状态
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isSelf ? Colors.amber : Colors.white)),
                const SizedBox(height: 2),
                _buildChipStack(chips),
                if (statusText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(statusText,
                        style: TextStyle(
                            fontSize: 11,
                            color: folded ? Colors.white54 : (allIn ? Colors.redAccent : Colors.orange))),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // 手牌
          Opacity(opacity: folded ? 0.35 : 1, child: handWidget),
        ],
      ),
    );
  }

  // ---- 牌桌区域 ----
  Widget _buildTableArea(Map<String, dynamic> state, List<Map<String, dynamic>> players,
      Map<String, dynamic>? me, int mySeat, int n, int dealerSeat, bool inProgress) {
    final stage = state['stage'] as String? ?? '';
    final pot = state['pot'] as int? ?? 0;
    final community = (state['community'] as List? ?? [])
        .map((c) => PokerCard.fromJson(c as Map<String, dynamic>))
        .toList();
    final lastResult = state['lastResult'] as Map<String, dynamic>?;

    return LayoutBuilder(
      builder: (lctx, cons) {
        final w = cons.maxWidth;
        final h = cons.maxHeight;
        final cx = w / 2;
        final cy = h / 2;
        final rx = w * 0.36;
        final ry = h * 0.34;
        final items = <Widget>[];

        // 木边椭圆
        items.add(Positioned(
          left: cx - rx - 10,
          top: cy - ry - 10,
          child: Container(
            width: (rx + 10) * 2,
            height: (ry + 10) * 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ry + 10),
              color: const Color(0xFF6B4226),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 14, spreadRadius: 2)],
            ),
          ),
        ));
        // 绿绒台面
        items.add(Positioned(
          left: cx - rx,
          top: cy - ry,
          child: Container(
            width: rx * 2,
            height: ry * 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ry),
              gradient: const RadialGradient(
                colors: [Color(0xFF1B7A4B), Color(0xFF0B3D27)],
                center: Alignment.center,
                radius: 0.78,
              ),
              border: Border.all(color: const Color(0xFF6B8E23), width: 3),
            ),
          ),
        ));

        // 中央：底池 + 公共牌 + 阶段 + 本手结果
        items.add(Positioned(
          left: cx,
          top: cy,
          child: Transform.translate(
            offset: const Offset(-120, -58),
            child: SizedBox(
              width: 240,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                    child: Text('底池  $pot',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: i < community.length
                            ? PokerCardView(card: community[i], width: 46, height: 64)
                            : const CardBack(width: 46, height: 64),
                      );
                    }),
                  ),
                  const SizedBox(height: 5),
                  Text(_stageLabels[stage] ?? stage, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (lastResult != null && !inProgress)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.amber.shade800, borderRadius: BorderRadius.circular(6)),
                      child: Text(lastResult['note']?.toString() ?? '',
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
        ));

        // 各座位与外侧标签
        for (final p in players) {
          final seat = (p['seat'] as int?) ?? 0;
          final rel = n > 0 ? (((seat - mySeat) % n) + n) % n : 0;
          final pos = _posLabel(dealerSeat >= 0 && n > 0
              ? (((seat - dealerSeat) % n) + n) % n
              : -1, n);
          final isDealer = p['id'] == _c.dealerId;
          final isSelf = p['id'] == _c.playerId;
          final bet = (p['bet'] as int?) ?? 0;

          final posOffset = _seatPos(cx, cy, rx, ry, n, rel);

          // 已下注筹码（靠近底池）
          if (bet > 0) {
            final inner = _outerPos(cx, cy, rx, ry, n, rel, 0.62);
            items.add(Positioned(
              left: inner.dx,
              top: inner.dy,
              child: Transform.translate(
                offset: const Offset(-20, -10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200, width: 1),
                  ),
                  child: Text('$bet', style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                ),
              ),
            ));
          }

          // 外侧位置标签（BTN/SB/BB/... 与 D 合并）
          if (pos.isNotEmpty) {
            final out = _outerPos(cx, cy, rx, ry, n, rel, 1.16);
            items.add(Positioned(
              left: out.dx,
              top: out.dy,
              child: Transform.translate(
                offset: const Offset(-16, -10),
                child: Container(
                  width: 32,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: pos == 'BTN' ? Colors.amber : Colors.blueGrey.shade700,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white54, width: 0.5),
                  ),
                  child: Text(pos == 'BTN' ? 'D' : pos,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ));
          }

          // 座位信息本体
          items.add(Positioned(
            left: posOffset.dx,
            top: posOffset.dy,
            child: Transform.translate(
              offset: const Offset(-86, -36),
              child: _buildSeat(p, isSelf, pos, isDealer, hideCards: isSelf),
            ),
          ));
        }

        return Stack(children: items);
      },
    );
  }

  // ---- 顶部状态条 ----
  Widget _buildStatusBar(Map<String, dynamic> state, Map<String, dynamic>? me,
      List<Map<String, dynamic>> players, bool inProgress) {
    if (inProgress) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)),
          const SizedBox(width: 8),
          Text('第 ${state['handNumber'] ?? 0} 手进行中 · ${_stageLabels[state['stage']] ?? state['stage']}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
            const Icon(Icons.pause, color: Colors.amber, size: 16),
            const SizedBox(width: 6),
            Text('已暂停：$names 请求本手后暂停',
                style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        );
      }
      final t = _c.timeToNextHand;
      if (t > 0) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer, color: Colors.amber, size: 16),
            const SizedBox(width: 6),
            Text('本手结束 · ${t} 秒后自动发下一手牌', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        );
      }
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hourglass_empty, color: Colors.white54, size: 16),
          SizedBox(width: 6),
          Text('等待开始下一手…', style: TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  // ---- 操作按钮区 ----
  Widget _buildActionBar(bool myTurn, int callNeed, int minTarget, int maxTarget, int target,
      bool canRaise, int currentBet, int pot) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: Colors.black54,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => _c.action('fold'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 18)),
                  child: const Text('弃牌'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _c.action(callNeed == 0 ? 'check' : 'call', amount: callNeed),
                  child: Text(callNeed == 0 ? '过牌' : '跟注 $callNeed'),
                ),
                if (canRaise) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _betPreset,
                        isDense: true,
                        style: const TextStyle(fontSize: 13),
                        items: const [
                          DropdownMenuItem(value: '1/3', child: Text('1/3 底池')),
                          DropdownMenuItem(value: '1/2', child: Text('1/2 底池')),
                          DropdownMenuItem(value: '2/3', child: Text('2/3 底池')),
                          DropdownMenuItem(value: '满池', child: Text('满池')),
                          DropdownMenuItem(value: '全下', child: Text('全下')),
                          DropdownMenuItem(value: '自定义', child: Text('自定义')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _betPreset = v;
                            if (v == '全下') {
                              _raiseTarget = maxTarget;
                            } else if (v == '自定义') {
                              _raiseTarget = ((minTarget + maxTarget) ~/ 2).clamp(minTarget, maxTarget);
                            } else {
                              final f = {'1/3': 1 / 3, '1/2': 0.5, '2/3': 2 / 3, '满池': 1.0}[v]!;
                              _raiseTarget = ((currentBet + (pot * f).round()).clamp(minTarget, maxTarget)).toInt();
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _c.action('raise', amount: target),
                    child: Text('加注 $target'),
                  ),
                ],
              ],
            ),
            if (_betPreset == '自定义' && canRaise)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        min: minTarget.toDouble(),
                        max: maxTarget.toDouble(),
                        value: target.toDouble(),
                        divisions: (maxTarget - minTarget).clamp(1, 200),
                        label: target.toString(),
                        onChanged: (v) => setState(() => _raiseTarget = v.toInt()),
                      ),
                    ),
                    SizedBox(width: 54, child: Text('$target', textAlign: TextAlign.end)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- AppBar 折叠菜单：补充/赎回、离桌、历史、自动跟注 ----
  List<PopupMenuEntry<String>> _buildMenuItems(Map<String, dynamic>? me, bool inProgress) {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'buy', child: Text('补充 / 赎回筹码')),
      PopupMenuItem(
        value: me?['tempLeft'] == true ? 'return' : 'temp',
        child: Text(me?['tempLeft'] == true ? '回到牌桌' : '暂时离桌'),
      ),
      const PopupMenuItem(value: 'history', child: Text('历史手牌')),
      CheckedPopupMenuItem(
        value: 'auto',
        checked: _autoCall,
        child: const Text('自动跟注'),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'leave', child: Text('离开房间')),
    ];
    if (_c.amIHost) {
      items.insertAll(0, [
        const PopupMenuItem(value: 'editRoom', child: Text('修改房间')),
        const PopupMenuItem(value: 'deleteRoom', child: Text('删除房间')),
        const PopupMenuDivider(),
      ]);
    }
    return items;
  }

  // ---- 修改/删除房间对话框 ----
  void _showEditRoomDialog() {
    final s = _c.state ?? {};
    final sbCtrl = TextEditingController(text: '${(s['smallBlind'] as int?) ?? 10}');
    final bbCtrl = TextEditingController(text: '${(s['bigBlind'] as int?) ?? 20}');
    final minCtrl = TextEditingController(text: '${(s['minBuyIn'] as int?) ?? 1000}');
    final maxCtrl = TextEditingController(text: '${(s['maxBuyIn'] as int?) ?? 3999}');
    final unitCtrl = TextEditingController(text: '${(s['buyInUnit'] as int?) ?? 1000}');
    final toCtrl = TextEditingController(text: '${(s['actionTimeout'] as int?) ?? 60}');
    final ecCtrl = TextEditingController(text: '${(s['extensionCount'] as int?) ?? 2}');
    final esCtrl = TextEditingController(text: '${(s['extensionSeconds'] as int?) ?? 60}');
    final hasAnte = (s['ante'] as int? ?? 0) > 0;
    final anteCtrl = TextEditingController(text: '${((s['ante'] as int?) ?? 0)}');
    bool anteOn = hasAnte;
    String err = '';
    int _i(TextEditingController c, int d) => int.tryParse(c.text.trim()) ?? d;

    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('修改房间参数'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(child: TextField(controller: sbCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '小盲'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: bbCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '大盲'))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: minCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '买入下限'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: maxCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '买入上限'))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: unitCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '买入最小单位')),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('是否有前注 (ante)'),
                  value: anteOn,
                  onChanged: (v) => setSt(() {
                    anteOn = v;
                    if (v && anteCtrl.text.trim().isEmpty) anteCtrl.text = sbCtrl.text.trim();
                  }),
                ),
                if (anteOn)
                  TextField(controller: anteCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '前注金额')),
                const SizedBox(height: 8),
                TextField(controller: toCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '每轮行动时间(秒)')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: ecCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '每轮延长次数'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: esCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '每次延长时间(秒)'))),
                ]),
                if (err.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text(err, style: const TextStyle(color: Colors.red))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final params = <String, dynamic>{
                  'smallBlind': _i(sbCtrl, 10),
                  'bigBlind': _i(bbCtrl, 20),
                  'minBuyIn': _i(minCtrl, 1000),
                  'maxBuyIn': _i(maxCtrl, 3999),
                  'buyInUnit': _i(unitCtrl, 1000),
                  'ante': anteOn ? _i(anteCtrl, 0) : 0,
                  'actionTimeout': _i(toCtrl, 60).clamp(5, 300),
                  'extensionCount': _i(ecCtrl, 2).clamp(0, 20),
                  'extensionSeconds': _i(esCtrl, 60).clamp(0, 300),
                };
                _c.updateRoom(params);
                Navigator.of(ctx).pop();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteRoom() {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('删除房间'),
        content: const Text('确定要删除当前房间吗？所有未结束的手牌将终止，且房间无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.of(dctx).pop();
              _c.deleteRoom();
              Navigator.of(context).pop();
            },
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
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
                  children: const [Padding(padding: EdgeInsets.all(8), child: Text('补充')), Padding(padding: EdgeInsets.all(8), child: Text('赎回'))],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: '金额（最小单位 $unit 的整数倍）'),
              ),
              if (err != null)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(err!, style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 6),
              Text('当前筹码 $myChips · 上限 $maxBuy · 下限 $minBuy', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
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

  // ---- 历史手牌 ----
  Widget _cardViewFromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return const SizedBox.shrink();
    try {
      final c = PokerCard.fromJson(json);
      return PokerCardView(card: c, width: 28, height: 40);
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildMiniHand(List<dynamic>? cards) {
    if (cards == null || cards.length < 2) return const Text('--', style: TextStyle(color: Colors.white54));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [cards[0]].map(_cardViewFromJson).toList()
        ..add(const SizedBox(width: 2))
        ..addAll([cards[1]].map(_cardViewFromJson).toList()),
    );
  }

  Widget _buildHistoryRecord(Map<String, dynamic> h) {
    final handNo = (h['handNumber'] as int?) ?? 0;
    final pot = (h['pot'] as int?) ?? 0;
    final winners = (h['winners'] as List?) ?? [];
    List<dynamic>? myCards;
    if (_c.me != null) {
      final pc = (h['playerCards'] as List? ?? []).firstWhere(
        (pc) => pc is Map && pc['id'] == _c.playerId,
        orElse: () => null,
      );
      myCards = (pc is Map ? pc['cards'] : null) as List?;
    }
    final winText = winners.isNotEmpty
        ? winners.map((w) {
            final m = w as Map<String, dynamic>;
            return '${m['name']} +${m['amount']}';
          }).join('，')
        : '无（弃牌/未结算）';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: _buildMiniHand(myCards),
      title: Text('第 $handNo 手 · 底池 $pot', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      subtitle: Text('赢家：$winText', style: const TextStyle(fontSize: 12, color: Colors.amber)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: () => _showHandDetail(h),
    );
  }

  void _showHandDetail(Map<String, dynamic> h) {
    final community = (h['community'] as List? ?? []).map((c) => PokerCard.fromJson(c as Map<String, dynamic>)).toList();
    final actionLog = (h['actionLog'] as List? ?? []).cast<Map<String, dynamic>>();
    final playerCards = (h['playerCards'] as List? ?? []).cast<Map<String, dynamic>>();
    final winners = (h['winners'] as List? ?? []).cast<Map<String, dynamic>>();

    List<Widget> stageSection(String stage, List<PokerCard> cards, List<Map<String, dynamic>> actions) {
      return [
        Row(
          children: [
            Text(_stageLabels[stage] ?? stage, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 8),
            ...cards.map((c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: PokerCardView(card: c, width: 30, height: 42))),
          ],
        ),
        const SizedBox(height: 4),
        if (actions.isEmpty)
          const Text('无行动', style: TextStyle(fontSize: 12, color: Colors.white54))
        else
          ...actions.map((a) {
            final act = a['action'] as String? ?? '';
            final amt = (a['amount'] as int?) ?? 0;
            final nm = a['name']?.toString() ?? '玩家';
            String actText;
            switch (act) {
              case 'fold':
                actText = '弃牌';
                break;
              case 'check':
                actText = '过牌';
                break;
              case 'call':
                actText = '跟注 $amt';
                break;
              case 'raise':
                actText = '加注到 $amt';
                break;
              default:
                actText = '$act ${amt > 0 ? amt : ''}';
            }
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text('$nm：$actText', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            );
          }).toList(),
        const SizedBox(height: 12),
      ];
    }

    final preflop = actionLog.where((a) => a['stage'] == 'preflop').toList();
    final flop = actionLog.where((a) => a['stage'] == 'flop').toList();
    final turn = actionLog.where((a) => a['stage'] == 'turn').toList();
    final river = actionLog.where((a) => a['stage'] == 'river').toList();

    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('第 ${h['handNumber'] ?? 0} 手 详情'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('底池：${h['pot'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('赢家：${winners.map((w) => '${w['name']} +${w['amount']}').join('，')}',
                    style: const TextStyle(color: Colors.amber)),
                const Divider(color: Colors.white24),
                ...stageSection('preflop', [], preflop),
                ...stageSection('flop', community.take(3).toList(), flop),
                ...stageSection('turn', community.take(4).toList(), turn),
                ...stageSection('river', community.take(5).toList(), river),
                const Text('各人底牌', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                ...playerCards.map((pc) {
                  final name = pc['name']?.toString() ?? '玩家';
                  final cs = (pc['cards'] as List? ?? []);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 90, child: Text(name, style: const TextStyle(fontSize: 12))),
                        ...cs.map((c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: _cardViewFromJson(c))),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _showHistoryDialog() {
    final serverHist = _c.handHistory.whereType<Map<String, dynamic>>().toList();
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('历史手牌'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: serverHist.isEmpty
              ? const Center(child: Text('暂无历史手牌记录', style: TextStyle(color: Colors.white70)))
              : ListView(
                  children: serverHist.reversed.map(_buildHistoryRecord).toList(),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _maybeShowReport();
    final roomName = _c.state?['roomName']?.toString() ?? '牌桌';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _leave),
        title: Text(roomName),
        actions: [
          if (_c.handPaused)
            TextButton(
              onPressed: _c.resumeNextHand,
              child: const Text('继续下一手', style: TextStyle(color: Colors.amber)),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'buy':
                  _showBuyCashout();
                  break;
                case 'temp':
                  _c.tempLeave();
                  break;
                case 'return':
                  _c.returnTable();
                  break;
                case 'history':
                  _showHistoryDialog();
                  break;
                case 'auto':
                  setState(() {
                    _autoCall = !_autoCall;
                    if (!_autoCall) _cancelAutoTimer();
                  });
                  break;
                case 'editRoom':
                  _showEditRoomDialog();
                  break;
                case 'deleteRoom':
                  _confirmDeleteRoom();
                  break;
                case 'leave':
                  _leave();
                  break;
              }
            },
            itemBuilder: (ctx) => _buildMenuItems(_c.me, _c.state?['handInProgress'] == true),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) {
          final state = _c.state;
          if (_autoCall && _c.myTurn) _scheduleAutoCall(); else _cancelAutoTimer();
          if (state == null) return const Center(child: Text('等待房间状态…'));

          final stage = state['stage'] as String? ?? '';
          final inProgress = state['handInProgress'] == true;
          final players = (state['players'] as List? ?? [])
              .map((p) => p as Map<String, dynamic>)
              .toList();
          final me = _c.me;
          final mySeat = me?['seat'] as int? ?? -1;
          final n = players.length;
          final dealerSeat = (state['dealerSeat'] as int?) ?? -1;
          final myTurn = _c.myTurn;
          final callNeed = _c.callNeed;
          final currentBet = state['currentBet'] as int? ?? 0;
          final minRaise = state['minRaise'] as int? ?? 1;
          final myBet = me?['bet'] as int? ?? 0;
          final myChips = me?['chips'] as int? ?? 0;
          final maxTarget = myBet + myChips;
          final minTarget = currentBet + minRaise;
          final canRaise = maxTarget > minTarget;
          final pot = state['pot'] as int? ?? 0;
          final target = _raiseTarget.clamp(minTarget, maxTarget);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        color: Colors.black38,
                        child: _buildStatusBar(state, me, players, inProgress),
                      ),
                      if (inProgress && _c.turnSeat >= 0)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          color: _c.timeoutWarning ? Colors.red.shade800 : Colors.blueGrey.shade800,
                          child: Builder(builder: (ctx) {
                            final actor = players.firstWhere(
                              (p) => (p['seat'] as int? ?? -1) == _c.turnSeat,
                              orElse: () => <String, dynamic>{},
                            );
                            final name = actor['name']?.toString() ?? '玩家';
                            final isMe = actor['id'] == _c.playerId;
                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isMe
                                        ? '轮到你行动（剩余 ${_c.secondsLeft}s）'
                                        : '等待 $name 行动（剩余 ${_c.secondsLeft}s）',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                if (isMe && _c.myExtLeft > 0)
                                  TextButton.icon(
                                    onPressed: _c.requestExtension,
                                    icon: const Icon(Icons.hourglass_bottom, size: 16),
                                    label: Text('申请延时(${_c.myExtLeft})'),
                                    style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.blueGrey.shade600),
                                  ),
                              ],
                            );
                          }),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _buildTableArea(state, players, me, mySeat, n, dealerSeat, inProgress),
                        ),
                      ),
                      if (myTurn)
                        _buildActionBar(myTurn, callNeed, minTarget, maxTarget, target, canRaise, currentBet, pot),
                    ],
                  ),
                  // 版本号：左下角，不遮挡主要内容
                  Positioned(
                    left: 8,
                    bottom: myTurn ? 86 : 8,
                    child: Text(
                      '内部测试版 v$kAppVersion · 服务端 v${_c.serverVersion ?? '连接中…'}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
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
}

class _ChipPainter extends CustomPainter {
  final Color color;
  const _ChipPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    // 投影
    canvas.drawCircle(c.translate(1, 1), r - 1, Paint()..color = Colors.black38..style = PaintingStyle.fill);
    // 主体
    canvas.drawCircle(c, r - 1, Paint()..color = color..style = PaintingStyle.fill);
    // 外环白线
    canvas.drawCircle(c, r - 2, Paint()..color = Colors.white70..style = PaintingStyle.stroke..strokeWidth = 1.5);
    // 内环
    canvas.drawCircle(c, r * 0.55, Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 2);
    // 边缘条纹
    for (int i = 0; i < 8; i++) {
      final a = i * pi / 4;
      final p1 = c + Offset(cos(a) * r * 0.72, sin(a) * r * 0.72);
      final p2 = c + Offset(cos(a) * r * 0.88, sin(a) * r * 0.88);
      canvas.drawLine(p1, p2, Paint()..color = Colors.white.withOpacity(0.8)..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant _ChipPainter oldDelegate) => oldDelegate.color != color;
}
