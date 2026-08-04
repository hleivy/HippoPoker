// lib/pages/lobby_page.dart - 大厅：房间列表 / 建房（含 AI 对手）/ 加入 / 设置
import 'dart:async';
import 'dart:math';
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
  final _roomNameCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _sbCtrl = TextEditingController(text: '10');
  final _bbCtrl = TextEditingController(text: '20');
  final _minBuyInCtrl = TextEditingController(text: '1000');
  final _maxBuyInCtrl = TextEditingController(text: '3999');
  final _buyInUnitCtrl = TextEditingController(text: '1000');
  final _anteCtrl = TextEditingController(text: '0');
  bool _hasAnte = false;
  bool _navigated = false;
  bool _creating = false; // 是否处于“创建房间”表单
  int _aiCount = 0; // AI 对手数量（单人测试用）
  final _actionTimeoutCtrl = TextEditingController(text: '60'); // 每轮行动时限(秒)
  final _extCountCtrl = TextEditingController(text: '2'); // 每轮可申请的延长次数
  final _extSecondsCtrl = TextEditingController(text: '60'); // 每次延长时间(秒)
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
      _c.nickname = n;
    }
  }

  Future<void> _saveNickname() async {
    final n = _nameCtrl.text.trim();
    if (n.isNotEmpty) {
      await _settings.saveNickname(n);
      _c.nickname = n;
    }
  }

  void _onChange() {
    // 仅当用户主动“加入”房间时才导航到牌桌；创建房间后仍停留在大厅
    if (_c.roomId != null && !_navigated && mounted && _c.lastCreatedRoomId == null) {
      _navigated = true;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TablePage(controller: _c)),
      );
    }
    if (_c.lastCreatedRoomId != null && mounted) {
      final id = _c.lastCreatedRoomId!;
      _c.lastCreatedRoomId = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('房间创建成功：$id，可在大厅加入'), duration: const Duration(seconds: 3)),
      );
      // 创建成功后返回大厅列表，方便用户选择进入或继续创建
      setState(() => _creating = false);
    }
    if (_c.errorMsg != null && mounted) {
      final msg = _c.errorMsg!;
      _c.clearError();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  int _i(TextEditingController c, int dflt) =>
      int.tryParse(c.text.trim()) ?? dflt;

  // 生成唯一房间名（创建表单留空时自动兜底，避免误用固定默认名）
  String _genRoomName() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    final suffix = List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return '河马桌-$suffix';
  }

  void _startCreate() {
    _roomNameCtrl.clear(); // 留空，提示用户自行命名
    setState(() => _creating = true);
  }

  void _create() {
    final sb = _i(_sbCtrl, 10);
    final bb = _i(_bbCtrl, sb * 2);
    final ante = _hasAnte ? (_i(_anteCtrl, sb).clamp(1, 999999)) : 0;
    final minBuyIn = _i(_minBuyInCtrl, 1000);
    final maxBuyIn = _i(_maxBuyInCtrl, 3999);
    final unit = _i(_buyInUnitCtrl, 1000).clamp(1, 999999);
    final nick = _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim();
    final roomName = _roomNameCtrl.text.trim().isEmpty ? _genRoomName() : _roomNameCtrl.text.trim();
    _saveNickname();
    _c.createRoom(
      roomName: roomName,
      name: nick,
      buyIn: minBuyIn,
      sb: sb,
      bb: bb,
      ante: ante,
      minBuyIn: minBuyIn,
      maxBuyIn: maxBuyIn,
      buyInUnit: unit,
      aiCount: _aiCount,
      actionTimeout: _i(_actionTimeoutCtrl, 60).clamp(5, 300),
      extensionCount: _i(_extCountCtrl, 2).clamp(0, 20),
      extensionSeconds: _i(_extSecondsCtrl, 60).clamp(0, 300),
    );
  }

  // 公共参数组件：创建与设置共用，保持风格一致、避免冗余
  Widget _buildParamFields({
    required TextEditingController sb,
    required TextEditingController bb,
    required TextEditingController min,
    required TextEditingController max,
    required TextEditingController unit,
    required TextEditingController to,
    required TextEditingController ec,
    required TextEditingController es,
    required TextEditingController ante,
    required bool hasAnte,
    required void Function(bool) onAnteChanged,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('牌桌参数', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          _numField('小盲', sb, enabled: enabled),
          const SizedBox(width: 8),
          _numField('大盲', bb, enabled: enabled),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _numField('买入下限', min, enabled: enabled),
          const SizedBox(width: 8),
          _numField('买入上限', max, enabled: enabled),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _numField('买入最小单位', unit, enabled: enabled),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('是否有前注 (ante)'),
          subtitle: const Text('开启后默认等于小盲', style: TextStyle(fontSize: 12, color: Colors.white54)),
          value: hasAnte,
          onChanged: enabled ? onAnteChanged : null,
        ),
        if (hasAnte) _numField('前注金额', ante, enabled: enabled),
        const SizedBox(height: 8),
        _numField('每轮行动时间(秒)', to, enabled: enabled),
        const SizedBox(height: 8),
        Row(children: [
          _numField('每轮延长次数', ec, enabled: enabled),
          const SizedBox(width: 8),
          _numField('每次延长时间(秒)', es, enabled: enabled),
        ]),
      ],
    );
  }

  // 房主在大厅直接设置房间参数（持久房间：不必进入房间即可管理）
  void _showRoomSettingsDialog(Map<String, dynamic> room) {
    final nameCtrl = TextEditingController(text: '${room['name'] ?? ''}');
    final sbCtrl = TextEditingController(text: '${(room['smallBlind'] as int?) ?? 10}');
    final bbCtrl = TextEditingController(text: '${(room['bigBlind'] as int?) ?? 20}');
    final minCtrl = TextEditingController(text: '${(room['minBuyIn'] as int?) ?? 1000}');
    final maxCtrl = TextEditingController(text: '${(room['maxBuyIn'] as int?) ?? 3999}');
    final unitCtrl = TextEditingController(text: '${(room['buyInUnit'] as int?) ?? 1000}');
    final toCtrl = TextEditingController(text: '${(room['actionTimeout'] as int?) ?? 60}');
    final ecCtrl = TextEditingController(text: '${(room['extensionCount'] as int?) ?? 2}');
    final esCtrl = TextEditingController(text: '${(room['extensionSeconds'] as int?) ?? 60}');
    final anteVal = (room['ante'] as int?) ?? 0;
    final anteCtrl = TextEditingController(text: '$anteVal');
    bool anteOn = anteVal > 0;
    String err = '';
    int _i(TextEditingController c, int d) => int.tryParse(c.text.trim()) ?? d;

    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('房间设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '房间名称', hintText: '给房间起个名字'),
                ),
                const SizedBox(height: 8),
                _buildParamFields(
                  sb: sbCtrl,
                  bb: bbCtrl,
                  min: minCtrl,
                  max: maxCtrl,
                  unit: unitCtrl,
                  to: toCtrl,
                  ec: ecCtrl,
                  es: esCtrl,
                  ante: anteCtrl,
                  hasAnte: anteOn,
                  onAnteChanged: (v) => setSt(() {
                    anteOn = v;
                    // 开启前注时，若当前值为空或 0，默认填入小盲
                    if (v && (anteCtrl.text.trim().isEmpty || anteCtrl.text.trim() == '0')) {
                      anteCtrl.text = sbCtrl.text.trim().isEmpty ? '10' : sbCtrl.text.trim();
                    }
                  }),
                ),
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
                  'roomId': room['id']?.toString() ?? '',
                  'name': nameCtrl.text.trim().isEmpty ? room['name'] : nameCtrl.text.trim(),
                  'smallBlind': _i(sbCtrl, 10),
                  'bigBlind': _i(bbCtrl, 20),
                  'minBuyIn': _i(minCtrl, 1000),
                  'maxBuyIn': _i(maxCtrl, 3999),
                  'buyInUnit': _i(unitCtrl, 1000),
                  'ante': anteOn ? _i(anteCtrl, 0).clamp(1, 999999) : 0,
                  'actionTimeout': _i(toCtrl, 60).clamp(5, 300),
                  'extensionCount': _i(ecCtrl, 2).clamp(0, 20),
                  'extensionSeconds': _i(esCtrl, 60).clamp(0, 300),
                };
                _c.updateRoom(params);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('房间设置已保存')));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
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
      builder: (dctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('加入 ${room['name'] ?? '房间'}'),
          content: DropdownButton<int>(
            value: sel,
            isExpanded: true,
            items: opts
                .map((o) => DropdownMenuItem(value: o, child: Text('初始买入：$o')))
                .toList(),
            onChanged: (val) {
              if (val != null) setSt(() => sel = val);
            },
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

  // 连接未就绪时的轻提示（按钮仍可点，动作会排队，连上后自动执行）
  Widget _connHint() {
    if (_c.connected) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          ),
          const SizedBox(width: 8),
          Text(
            _c.isConnecting ? '连接中…' : '未连接',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // 创建房间表单（含 AI 对手设置）
  Widget _buildCreateForm() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: ListView(
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
                decoration: const InputDecoration(
                    labelText: '房间名称', hintText: '留空将自动生成唯一名称')),
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
                    _buildParamFields(
                      sb: _sbCtrl,
                      bb: _bbCtrl,
                      min: _minBuyInCtrl,
                      max: _maxBuyInCtrl,
                      unit: _buyInUnitCtrl,
                      to: _actionTimeoutCtrl,
                      ec: _extCountCtrl,
                      es: _extSecondsCtrl,
                      ante: _anteCtrl,
                      hasAnte: _hasAnte,
                      onAnteChanged: (v) => setState(() {
                        _hasAnte = v;
                        if (v && (_anteCtrl.text.trim().isEmpty || _anteCtrl.text.trim() == '0')) {
                          final sb = _sbCtrl.text.trim();
                          _anteCtrl.text = sb.isEmpty ? '10' : sb;
                        }
                      }),
                    ),
                    const SizedBox(height: 12),
                    // AI 对手设置（单人测试用，不影响真实对局）
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
                      child: const Text('创建房间'),
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
        ),
      ),
    );
  }

  // 大厅：房间列表优先
  Widget _buildLobby() {
    final list = _c.roomList;
    final sv = _c.serverVersion;
    final statusText = sv != null
        ? '服务端 v$sv'
        : (_c.connected ? '服务端 已连接' : '服务端 连接中…');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: ListView(
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
                final isInThisRoom = _c.roomId == room['id']?.toString();
                final isHost = room['hostId']?.toString() == _c.playerId;
                return Card(
                  child: ListTile(
                    title: Text(room['name'] ?? '房间'),
                    subtitle: Text(sub.join('　'), style: const TextStyle(fontSize: 13)),
                    trailing: isInThisRoom
                        ? ElevatedButton(
                            onPressed: () {
                              _navigated = true;
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => TablePage(controller: _c)),
                              );
                            },
                            child: const Text('进入'),
                          )
                        : isHost
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => _showRoomSettingsDialog(room),
                                    child: const Text('设置'),
                                  ),
                                  const SizedBox(width: 4),
                                  ElevatedButton(
                                    onPressed: () {
                                      _navigated = true;
                                      Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => TablePage(controller: _c)),
                                      );
                                    },
                                    child: const Text('进入'),
                                  ),
                                ],
                              )
                            : ElevatedButton(
                                onPressed: () => _showJoinDialog(room),
                                child: const Text('加入'),
                              ),
                  ),
                );
              }).toList(),
            const SizedBox(height: 16),
            Center(
              child: Text(
                '内部测试版 v$kAppVersion · $statusText',
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
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
