// lib/pages/lobby_page.dart —— 大厅：连接、建房、加入、房间列表
import 'package:flutter/material.dart';
import '../game_controller.dart';
import 'table_page.dart';

class LobbyPage extends StatefulWidget {
  final GameController controller;
  const LobbyPage({super.key, required this.controller});

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  late final GameController _c = widget.controller;
  final _nameCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _sbCtrl = TextEditingController(text: '1');
  final _bbCtrl = TextEditingController(text: '2');
  final _buyInCtrl = TextEditingController(text: '1000');
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = '玩家${(1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString()}';
    _c.connect();
    _c.listRooms();
    _c.addListener(_onChange);
  }

  void _onChange() {
    if (_c.roomId != null && !_navigated && mounted) {
      _navigated = true;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TablePage(controller: _c)),
      );
    }
    if (_c.errorMsg != null && mounted) {
      final msg = _c.errorMsg!;
      _c.clearError();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _create() {
    final buyIn = int.tryParse(_buyInCtrl.text) ?? 1000;
    final sb = int.tryParse(_sbCtrl.text) ?? 1;
    final bb = int.tryParse(_bbCtrl.text) ?? sb * 2;
    _c.createRoom(_nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim(),
        buyIn, sb, bb);
  }

  void _join() {
    final id = _roomCtrl.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入房间号')));
      return;
    }
    final buyIn = int.tryParse(_buyInCtrl.text) ?? 1000;
    _c.joinRoom(id, _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim(),
        buyIn,
        password: _pwdCtrl.text.trim());
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('德州扑克 · 大厅')),
      body: AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: '你的昵称'),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('创建房间',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: _sbCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: '小盲'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: _bbCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: '大盲'))),
                      ]),
                      TextField(
                          controller: _buyInCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '买入筹码')),
                      const SizedBox(height: 8),
                      ElevatedButton(
                          onPressed: _c.connected ? _create : null,
                          child: const Text('创建并进入房间')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('加入房间',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      TextField(
                          controller: _roomCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(labelText: '房间号')),
                      TextField(
                          controller: _pwdCtrl,
                          decoration: const InputDecoration(
                              labelText: '密码（无则留空）')),
                      const SizedBox(height: 8),
                      ElevatedButton(
                          onPressed: _c.connected ? _join : null,
                          child: const Text('加入房间')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('公开房间列表',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                      onPressed: _c.listRooms,
                      child: const Text('刷新')),
                ],
              ),
              ..._c.roomList.map((r) {
                final room = r as Map<String, dynamic>;
                return ListTile(
                  title: Text(room['name'] ?? '房间'),
                  subtitle: Text(
                      '房间号 ${room['id']} · ${room['players']}人 · 盲注 ${room['smallBlind']}/${room['bigBlind']}'
                      '${room['hasPassword'] == true ? ' · 有密码' : ''}'),
                  trailing: ElevatedButton(
                      onPressed: () {
                        _roomCtrl.text = room['id'] ?? '';
                        _join();
                      },
                      child: const Text('加入')),
                );
              }),
              const SizedBox(height: 16),
              if (!_c.connected)
                const Center(child: Text('连接中…', style: TextStyle(color: Colors.white70))),
            ],
          );
        },
      ),
    );
  }
}
