// lib/pages/lobby_page.dart —— 大厅：房间列表 / 建房（含 AI 对手）/ 加入
import 'dart:async';
import 'package:flutter/material.dart';
import '../game_controller.dart';
import '../config.dart';
import '../storage/settings_storage.dart';
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
  final _roomNameCtrl = TextEditingController(text: '财富西环线上扑克室');
  final _roomCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _sbCtrl = TextEditingController(text: '10');
  final _bbCtrl = TextEditingController(text: '20');
  int _buyInSelected = 1000;
  final _minBuyInCtrl = TextEditingController(text: '1000');
  final _maxBuyInCtrl = TextEditingController(text: '3999');
  final _buyInUnitCtrl = TextEditingController(text: '1000');
  final _anteCtrl = TextEditingController(text: '0');
  bool _hasAnte = false;
  bool _navigated = false;
  bool _creating = false; // 是否处于“创建房间”表单
  int _aiCount = 0; // AI 对手数量（单人测试用）
  Timer? _listTimer;
  final SettingsStorage _settings = SettingsStorage();

  @override
  void initState() {
    super.initState();
    _loadNickname();
    _c.connect();
    _c.listRooms();
    _c.addListener(_onChange);
    // 每 3 秒自动刷新房间列表（不依赖手动刷新）
    _listTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_navigated && mounted) _c.listRooms();
    });
  }

  // 记住上次使用的昵称（Web=localStorage，Android=文档文件），避免每次重填
  Future<void> _loadNickname() async {
    final n = await _settings.loadNickname();
    if (mounted && n != null && n.isNotEmpty) {
      _nameCtrl.text = n;
    }
  }

  Future<void> _saveNickname() async {
    final n = _nameCtrl.text.trim();
    if (n.isNotEmpty) await _settings.saveNickname(n);
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

  // 默认房间名：基础名若已被占用，则自动加 2/3… 后缀（房间名不可重复）
  String _defaultRoomName() {
    const base = '财富西环线上扑克室';
    final names = _c.roomList.map((r) {
      final n = r is Map ? r['name'] : null;
      return n is String ? n.trim().toLowerCase() : '';
    }).toList();
    if (!names.contains(base.toLowerCase())) return base;
    int i = 2;
    while (names.contains('$base$i'.toLowerCase())) i++;
    return '$base$i';
  }

  // 买入选项：下限到上限、按最小单位取整数倍（如 1000–3999/500 => 1000,1500,…,3500）
  List<int> _buyInOptions() {
    final min = _i(_minBuyInCtrl, 1000);
    final max = _i(_maxBuyInCtrl, 3999);
    final unit = _i(_buyInUnitCtrl, 1000).clamp(1, 999999);
    final opts = <int>[];
    int v = min;
    while (v <= max) {
      opts.add(v);
      v += unit;
    }
    if (opts.isEmpty) opts.add(min);
    return opts;
  }

  void _startCreate() {
    _roomNameCtrl.text = _defaultRoomName();
    setState(() => _creating = true);
  }

  void _create() {
    final buyIn = _buyInSelected;
    final sb = _i(_sbCtrl, 10);
    final bb = _i(_bbCtrl, sb * 2);
    final ante = _hasAnte ? _i(_anteCtrl, sb) : 0;
    final minBuyIn = _i(_minBuyInCtrl, 1000);
    final maxBuyIn = _i(_maxBuyInCtrl, 3999);
    final unit = _i(_buyInUnitCtrl, 1000).clamp(1, 999999);
    final nick = _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim();
    final roomName = _roomNameCtrl.text.trim().isEmpty
        ? '财富西环线上扑克室'
        : _roomNameCtrl.text.trim();
    _saveNickname();
    _c.createRoom(
      roomName: roomName,
      name: nick,
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

  // 加入房间：弹出对话框让玩家从下限/上限/单位生成的有限选项中选择初始买入
  void _showJoinDialog(Map<String, dynamic> room) {
    final min = (room['minBuyIn'] as int?) ?? 1000;
    final max = (room['maxBuyIn'] as int?) ?? 3999;
    final unit = (room['buyInUnit'] as int?) ?? 1000;
    final opts = <int>[];
    int v = min;
    while (v <= max) {
      opts.add(v);
      v += unit;
    }
    if (opts.isEmpty) opts.add(min);
    int sel = opts.first;
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('加入 ${room['name'] ?? '房间'}'),
        content: DropdownButton<int>(
          value: sel,
          isExpanded: true,
          items: opts
              .map((o) => DropdownMenuItem(value: o, child: Text('初始买入：$o')))
              .toList(),
          onChanged: (v) => sel = v ?? sel,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dctx).pop();
              final nick =
                  _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim();
              _saveNickname();
              _c.joinRoom(room['id']?.toString() ?? '', nick, sel,
                  password: _pwdCtrl.text.trim());
            },
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _listTimer?.cancel();
    _roomNameCtrl.dispose();
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
        TextField(
            controller: _roomNameCtrl,
            decoration: const InputDecoration(labelText: '房间名称')),
        const SizedBox(height: 12),
        TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: '你的昵称', hintText: '留空将记住上次使用的昵称')),
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
                DropdownButton<int>(
                  value: _buyInOptions().contains(_buyInSelected)
                      ? _buyInSelected
                      : _buyInOptions().first,
                  isExpanded: true,
                  items: _buyInOptions()
                      .map((v) => DropdownMenuItem(value: v, child: Text('我的初始买入：$v')))
                      .toList(),
                  onChanged: (v) => setState(() => _buyInSelected = v ?? _buyInSelected),
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
        TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: '你的昵称', hintText: '留空将记住上次使用的昵称')),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('公开房间', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            TextButton(onPressed: _c.listRooms, child: const Text('刷新')),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _startCreate(),
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
                    onPressed: () => _startCreate(),
                    child: const Text('创建房间'),
                  ),
                ],
              ),
            ),
          )
        else
          ...list.map((r) {
            final room = r as Map<String, dynamic>;
            final members = (room['members'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            final sub = <String>[
              '盲注 ${room['smallBlind']}/${room['bigBlind']}',
              if ((room['ante'] ?? 0) > 0) '前注 ${room['ante']}',
              '买入 ${room['minBuyIn']}–${room['maxBuyIn']}',
              '${room['players']}人'
                  '${room['botCount'] != null && room['botCount'] > 0 ? ' · AI×${room['botCount']}' : ''}',
              if (members.isNotEmpty) '成员：${members.join('、')}',
              if (room['hasPassword'] == true) '有密码',
            ];
            return Card(
              child: ListTile(
                title: Text(room['name'] ?? '房间'),
                subtitle: Text(sub.join('　'), style: const TextStyle(fontSize: 13)),
                trailing: ElevatedButton(
                  onPressed: () => _showJoinDialog(room),
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
