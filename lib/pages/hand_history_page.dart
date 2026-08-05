// lib/pages/hand_history_page.dart —— 手牌历史查看（功能 2）
import 'package:flutter/material.dart';
import '../game_controller.dart';

class HandHistoryPage extends StatelessWidget {
  final GameController controller;
  const HandHistoryPage({super.key, required this.controller});

  static String _fmtServer(Map<String, dynamic> h) {
    final winners = (h['winners'] as List?) ?? [];
    final w =
        winners.map((w) => '${w['name'] ?? w['id']}:${w['amount']}').join('、');
    return '第 ${h['handNumber']} 手　底池 ${h['pot']}　胜者: ${w.isNotEmpty ? w : '—'}';
  }

  @override
  Widget build(BuildContext context) {
    final serverHist = controller.handHistory;
    return Scaffold(
      appBar: AppBar(title: const Text('手牌历史')),
      body: FutureBuilder<List<String>>(
        future: controller.readHistory(),
        builder: (ctx, snap) {
          final local = snap.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (serverHist.isNotEmpty) ...[
                const Text('服务端逐手记录',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
                ...serverHist.reversed.map((h) => Card(
                      child: ListTile(
                        title: Text(_fmtServer(h as Map<String, dynamic>)),
                        subtitle: Text('结束阶段: ${h['stage'] ?? ''}'),
                      ),
                    )),
                const Divider(height: 24),
              ],
              const Text('本机全过程日志（每次进入自动保存）',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
              if (local.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('暂无记录'),
                ),
              ...local.reversed.map((l) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(l, style: const TextStyle(fontSize: 13)),
                  )),
            ],
          );
        },
      ),
    );
  }
}
