// lib/pages/lobby_page.dart —— 大厅：连接、建房、加入、房间列表
import 'package:flutter/material.dart';
import '../game_controller.dart';
import '../config.dart';
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
  final _sbCtrl = TextEditingController(text: '10');
  final _bbCtrl = TextEditingController(text: '20');
  final _buyInCtrl = TextEditingController(text: '1000');
  final _minBuyInCtrl = TextEditingController(text: '1000');
  final _maxBuyInCtrl = TextEditingController(text: '3999');
  final _buyInUnitCtrl = TextEditingController(text: '1000');
  final _anteCtrl = TextEditingController(text: '0');
  bool _hasAnte = false;
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

  int _i(TextEditingController c, int dflt) =>
      int.tryParse(c.text.trim()) ?? dflt;

  void _create() {
    final buyIn = _i(_buyInCtrl, 1000);
    final sb = _i(_sbCtrl, 10);
    final bb = _i(_bbCtrl, sb * 2);
    final ante = _hasAnte ? _i(_anteCtrl, sb) : 0;
    final minBuyIn = _i(_minBuyInCtrl, 1000);
    final maxBuyIn = _i(_maxBuyInCtrl, 3999);
    final unit = _i(_buyInUnitCtrl, 1000).clamp(1, 999999);
    _c.createRoom(
      name: _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim(),
      buyIn: buyIn,
      sb: sb,
      bb: bb,
      ante: ante,
      minBuyIn: minBuyIn,
      maxBuyIn: maxBuyIn,
      buyInUnit: unit,
    );
  }

  void _join() {
    final id = _roomCtrl.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入房间号')));
      return;
    }
    final buyIn = _i(_buyInCtrl, 1000);
    _c.joinRoom(id,
        _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim(), buyIn,
        password: _pwdCtrl.text.trim());
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    super.dispose();
  }

  Widget _numField(String label, TextEditingController ctrl, {bool enabled = true}) {
    return Expanded(
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('河马扑克 · 大厅')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 96,
                height: 96,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 昵称输入框放在 AnimatedBuilder 之外，避免连接状态刷新打断中文输入法合成
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
                  const Text('创建房间（牌桌参数）',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _numField('小盲', _sbCtrl),
                    const SizedBox(width: 8),
                    _numField('大盲', _bbCtrl),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _numField('买入下限', _minBuyInCtrl),
                    const SizedBox(width: 8),
                    _numField('买入上限', _maxBuyInCtrl),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _numField('买入最小单位', _buyInUnitCtrl),
                    const SizedBox(width: 8),
                    _numField('初始买入', _buyInCtrl),
                  ]),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('是否有前注 (ante)'),
                    value: _hasAnte,
                    onChanged: (v) => setState(() {
                      _hasAnte = v;
                      // 开启 ante 时，默认前注金额 = 小盲
                      if (v &&
                          (_anteCtrl.text.trim().isEmpty ||
                              _anteCtrl.text.trim() == '0')) {
                        final sb = _sbCtrl.text.trim();
                        _anteCtrl.text = sb.isEmpty ? '10' : sb;
                      }
                    }),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_hasAnte) _numField('前注金额', _anteCtrl),
                  const SizedBox(height: 8),
                  AnimatedBuilder(
                    animation: _c,
                    builder: (ctx, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton(
                            onPressed: _c.connected ? _create : null,
                            child: const Text('创建并进入房间')),
                        if (!_c.connected)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _c.connecting
                                  ? '连接中…'
                                  : '未连接到服务器，无法创建（正在自动重试）',
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
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
                  AnimatedBuilder(
                    animation: _c,
                    builder: (ctx, _) => ElevatedButton(
                        onPressed: _c.connected ? _join : null,
                        child: const Text('加入房间')),
                  ),
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
                  onPressed: _c.listRooms, child: const Text('刷新')),
            ],
          ),
          AnimatedBuilder(
            animation: _c,
            builder: (ctx, _) => Column(
              children: _c.roomList.map((r) {
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
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Center(
              child: Text('内部测试版 v$kAppVersion',
                  style: const TextStyle(color: Colors.white54))),
        ],
      ),
    );
  }
}
