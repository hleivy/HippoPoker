// lib/pages/lobby_page.dart —— 大厅：房间列表 / 建房（含 AI 对手）/ 加入
import 'dart:async';
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
  bool _creating = false; // 是否处于“创建房间”表单
  int _aiCount = 0; // AI 对手数量（单人测试用）
  Timer? _listTimer;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = '玩家${(1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString()}';
    _c.connect();
    _c.listRooms();
    _c.addListener(_onChange);
    // 每 3 秒自动刷新房间列表（不依赖手动刷新）
    _listTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_navigated && mounted) _c.listRooms();
    });
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
      aiCount: _aiCount,
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
    _listTimer?.cancel();
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

  // 连接未就绪时的提示（按钮仍可点，动作会排队，连上后自动执行）
  Widget _connHint() {
    if (_c.connected) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        _c.isConnecting ? '正在连接服务器，操作将在连接后自动执行…' : '未连接到服务器',
        style: const TextStyle(color: Colors.white70),
        textAlign: TextAlign.center,
      ),
    );
  }

  // 创建房间表单（含 AI 对手设置）
  Widget _buildCreateForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset('assets/images/app_icon.png', width: 84, height: 84),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: '你的昵称')),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('牌桌参数', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  contentPadding: EdgeInsets.zero,
                  value: _hasAnte,
                  onChanged: (v) => setState(() {
                    _hasAnte = v;
                    if (v && (_anteCtrl.text.trim().isEmpty || _anteCtrl.text.trim() == '0')) {
                      final sb = _sbCtrl.text.trim();
                      _anteCtrl.text = sb.isEmpty ? '10' : sb;
                    }
                  }),
                ),
                if (_hasAnte) _numField('前注金额', _anteCtrl),
                const SizedBox(height: 12),
                // AI 对手设置
                const Text('AI 对手数量（单人测试发牌打牌流程用）',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButton<int>(
                  value: _aiCount,
                  isExpanded: true,
                  items: List.generate(9, (i) => DropdownMenuItem(
                    value: i,
                    child: Text(i == 0 ? '无（真人局）' : '$i 个 AI 牌手'),
                  )),
                  onChanged: (v) => setState(() => _aiCount = v ?? 0),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _create,
                  child: const Text('创建并进入房间'),
                ),
                _connHint(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_aiCount > 0)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade800,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'AI 牌手由服务端自动坐入并发牌/下注，便于单人完整测试一手牌。'
              '若创建后看不到 AI，说明服务端尚未部署含 AI 的版本（需上传新版 server-deploy.zip）。',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
      ],
    );
  }

  // 大厅：房间列表优先
  Widget _buildLobby() {
    final list = _c.roomList;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset('assets/images/app_icon.png', width: 84, height: 84),
          ),
        ),
        const SizedBox(height: 10),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: '你的昵称')),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('公开房间', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            TextButton(onPressed: _c.listRooms, child: const Text('刷新')),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => setState(() => _creating = true),
              icon: const Icon(Icons.add),
              label: const Text('创建'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Card(
            color: Colors.blueGrey.shade800,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.meeting_room, size: 42, color: Colors.white70),
                  const SizedBox(height: 10),
                  const Text('还没有房间', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('创建一个房间，或等待别人创建后在此加入。',
                      style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: () => setState(() => _creating = true),
                    child: const Text('创建房间'),
                  ),
                ],
              ),
            ),
          )
        else
          ...list.map((r) {
            final room = r as Map<String, dynamic>;
            return Card(
              child: ListTile(
                title: Text(room['name'] ?? '房间'),
                subtitle: Text(
                    '房间号 ${room['id']} · ${room['players']}人 · 盲注 ${room['smallBlind']}/${room['bigBlind']}'
                    '${room['hasPassword'] == true ? ' · 有密码' : ''}'),
                trailing: ElevatedButton(
                  onPressed: () {
                    _roomCtrl.text = room['id'] ?? '';
                    _join();
                  },
                  child: const Text('加入'),
                ),
              ),
            );
          }).toList(),
        const SizedBox(height: 16),
        Center(
          child: Text('内部测试版 v$kAppVersion', style: const TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('河马扑克 · 大厅'),
        leading: _creating
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _creating = false),
              )
            : null,
      ),
      body: AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) => _creating ? _buildCreateForm() : _buildLobby(),
      ),
    );
  }
}
