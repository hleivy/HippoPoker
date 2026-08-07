// lib/pages/lobby_page.dart - 大厅：房间列表 / 建房（含 AI 对手）/ 加入 / 设置
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../game_controller.dart';
import '../config.dart';
import '../ai_avatars.dart';
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
  final _pwdCtrl = TextEditingController();
  bool _inTable = false; // 当前是否已推入牌桌页（返回大厅后置回 false，保证可再次进入）
  bool _creating = false; // 是否处于“创建房间”表单
  bool _editingNick = false; // 大厅昵称是否处于编辑态（默认只读，点“编辑”才可改）
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
      if (!_inTable && mounted) _c.listRooms();
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

  // 进入牌桌：用 _inTable 标记防止重复推栈，返回大厅后复位，保证每次都能稳定进入
  void _enterTable() {
    if (_inTable || !mounted) return;
    _inTable = true;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TablePage(controller: _c)))
        .then((_) {
      _inTable = false; // 从牌桌返回（离开房间）后允许再次进入
    });
  }

  void _onChange() {
    // 创建房间成功的提示：与进入逻辑解耦，先清标记避免拦截后续的自动进入
    if (_c.lastCreatedRoomId != null && mounted) {
      final id = _c.lastCreatedRoomId!;
      _c.lastCreatedRoomId = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('房间创建成功：$id，可在大厅加入'), duration: const Duration(seconds: 3)),
      );
      // 创建成功后返回大厅列表，方便用户选择进入或继续创建
      setState(() => _creating = false);
    }
    // 已进入房间且当前不在牌桌页 → 自动进入牌桌（不依赖只置真不复位的标志，返回大厅后复位）
    if (_c.roomId != null && !_inTable && mounted) {
      _enterTable();
    }
    if (_c.errorMsg != null && mounted) {
      final msg = _c.errorMsg!;
      _c.clearError();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // 生成唯一房间名（创建表单留空时自动兜底，避免误用固定默认名）
  String _genRoomName() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    final suffix = List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return '河马桌-$suffix';
  }

  void _startCreate() {
    setState(() => _creating = true);
  }

  // 用统一房间表单的结果创建房间（名称留空时自动生成唯一名）
  void _doCreate(_RoomFormResult res) {
    _saveNickname();
    final nick = (_c.nickname ?? '').trim().isEmpty ? '玩家' : _c.nickname!.trim();
    final roomName = res.name.trim().isEmpty ? _genRoomName() : res.name.trim();
    _c.createRoom(
      roomName: roomName,
      name: nick,
      buyIn: res.min,
      sb: res.sb,
      bb: res.bb,
      ante: res.hasAnte ? res.ante.clamp(1, 999999) : 0,
      minBuyIn: res.min,
      maxBuyIn: res.max,
      buyInUnit: res.unit.clamp(1, 999999),
      aiCount: res.aiCount,
      aiNames: res.aiNames,
      actionTimeout: res.actionTimeout.clamp(5, 300),
      extensionCount: res.extensionCount.clamp(0, 20),
      extensionSeconds: res.extensionSeconds.clamp(0, 300),
    );
  }

  // 在大厅直接设置房间参数（持久房间：不必进入房间即可管理）
  // [adminPassword] 非空时使用管理员通道（无需是该房间房主）
  // 与“创建房间”共用同一个 _RoomForm，保证参数项与 AI 选项始终一致。
  void _showRoomSettingsDialog(Map<String, dynamic> room, {String? adminPassword}) {
    final seed = _RoomFormSeed(
      name: '${room['name'] ?? ''}',
      sb: (room['smallBlind'] as int?) ?? 10,
      bb: (room['bigBlind'] as int?) ?? 20,
      min: (room['minBuyIn'] as int?) ?? 1000,
      max: (room['maxBuyIn'] as int?) ?? 3999,
      unit: (room['buyInUnit'] as int?) ?? 1000,
      ante: (room['ante'] as int?) ?? 0,
      actionTimeout: (room['actionTimeout'] as int?) ?? 60,
      extensionCount: (room['extensionCount'] as int?) ?? 2,
      extensionSeconds: (room['extensionSeconds'] as int?) ?? 60,
      aiCount: (room['aiCount'] as int?) ?? (room['botCount'] as int?) ?? 0,
      aiNames: (room['botNames'] as List? ?? []).map((e) => e.toString()).toList(),
    );
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('房间设置'),
        content: SingleChildScrollView(
          child: _RoomForm(
            seed: seed,
            submitLabel: '保存',
            showAiNote: false,
            onSubmit: (res) {
              final params = <String, dynamic>{
                'roomId': room['id']?.toString() ?? '',
                'name': res.name.trim().isEmpty ? room['name'] : res.name.trim(),
                'smallBlind': res.sb,
                'bigBlind': res.bb,
                'minBuyIn': res.min,
                'maxBuyIn': res.max,
                'buyInUnit': res.unit,
                'ante': res.hasAnte ? res.ante.clamp(1, 999999) : 0,
                'actionTimeout': res.actionTimeout.clamp(5, 300),
                'extensionCount': res.extensionCount.clamp(0, 20),
                'extensionSeconds': res.extensionSeconds.clamp(0, 300),
                'aiCount': res.aiCount,
                'aiNames': res.aiNames,
              };
              if (adminPassword != null && adminPassword.isNotEmpty) {
                _c.adminUpdateRoom({...params, 'password': adminPassword});
              } else {
                _c.updateRoom(params);
              }
              Navigator.of(dctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('房间设置已保存')));
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('取消')),
        ],
      ),
    );
  }

  // 加入房间：弹出对话框让玩家从下限/上限/单位生成的有限选项中选择初始买入
  void _showJoinDialog(Map<String, dynamic> room) {
    final min = (room['minBuyIn'] as int?) ?? 1000;
    final max = (room['maxBuyIn'] as int?) ?? 3999;
    final unit = (room['buyInUnit'] as int?) ?? 1000;
    final hasPwd = room['hasPassword'] == true;
    final opts = <int>[];
    int v = min;
    while (v <= max) {
      opts.add(v);
      v += unit;
    }
    if (opts.isEmpty) opts.add(min);
    int sel = opts.first;
    final pwdCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('加入 ${room['name'] ?? '房间'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                value: sel,
                isExpanded: true,
                items: opts
                    .map((o) => DropdownMenuItem(value: o, child: Text('初始买入：$o')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setSt(() => sel = val);
                },
              ),
              // 带密码的房间：必须输入密码才能加入（密码由服务端校验）
              if (hasPwd)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    controller: pwdCtrl,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '房间密码',
                      hintText: '请输入房间密码',
                    ),
                  ),
                ),
            ],
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
                    (_c.nickname ?? '').trim().isEmpty ? '玩家' : _c.nickname!.trim();
                _saveNickname();
                _c.joinRoom(room['id']?.toString() ?? '', nick, sel,
                    password: hasPwd ? pwdCtrl.text.trim() : '');
              },
              child: const Text('加入'),
            ),
          ],
        ),
      ),
    );
  }

  // 管理密码输入（密码不应在界面上以任何形式预设/显示，交由服务端校验）
  Future<String?> _verifyAdminPassword() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('房间管理'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '管理密码', hintText: '请输入管理密码'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    return res;
  }

  // 房间管理：输入密码后可删除任意房间（密码由服务端校验）
  void _showRoomManagementDialog() async {
    final pw = await _verifyAdminPassword();
    if (pw == null) return; // 取消
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('房间管理'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: _c.roomList.map((r) {
                final room = r as Map<String, dynamic>;
                return ListTile(
                  title: Text(room['name'] ?? '房间'),
                  subtitle: Text('${room['players']}人 · 盲注 ${room['smallBlind']}/${room['bigBlind']}'),
                  trailing: TextButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: ctx,
                        builder: (_) => AlertDialog(
                          title: const Text('删除房间'),
                          content: Text('确定删除「${room['name'] ?? '房间'}」吗？'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(_).pop(false), child: const Text('取消')),
                            TextButton(onPressed: () => Navigator.of(_).pop(true), child: const Text('删除', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        // 删除成功后停留在房间管理页面（刷新列表），不关闭整个管理弹窗
                        _c.adminDeleteRoom(room['id']?.toString() ?? '', pw);
                        _c.listRooms();
                        Future.delayed(const Duration(milliseconds: 400), () {
                          if (mounted) setSt(() {});
                        });
                      }
                    },
                    child: const Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭')),
          ],
        ),
      ),
    );
  }

  // 大厅“战绩”：查看某房间所有人的输赢，并支持管理员密码重置统计
  void _showRoomStatsDialog(Map<String, dynamic> room) {
    final roomId = room['id']?.toString() ?? '';
    final roomName = room['name']?.toString() ?? '房间';
    _c.requestRoomReport(roomId);
    showDialog(
      context: context,
      builder: (ctx) => AnimatedBuilder(
        animation: _c,
        builder: (ctx, child) {
          final report = _c.roomReport;
          final players = (report?['players'] as List?) ?? [];
          final handCount = (report?['handCount'] as int?) ?? 0;
          final durationMs = (report?['durationMs'] as int?) ?? 0;
          final startedAt = (report?['startedAt'] as int?) ?? 0;
          final startedText = startedAt > 0
              ? DateTime.fromMillisecondsSinceEpoch(startedAt).toLocal().toString().substring(0, 16).replaceFirst('T', ' ')
              : '';
          final durationSec = (durationMs / 1000).round();
          final durM = durationSec ~/ 60;
          final durS = durationSec % 60;
          final durText = durM > 0 ? '$durM 分 $durS 秒' : '$durS 秒';
          return AlertDialog(
            title: Text('房间战绩 · $roomName'),
            content: SizedBox(
              width: double.maxFinite,
              child: report == null
                  ? const Center(child: CircularProgressIndicator())
                  : players.isEmpty
                      ? const Center(child: Text('暂无战绩数据'))
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            Text('手牌数：$handCount${startedText.isNotEmpty ? '　开始时间：$startedText' : ''}'),
                            Text('已进行时长：$durText'),
                            const Divider(color: Colors.white24),
                            ...players.map((p) {
                              final m = p as Map<String, dynamic>;
                              final wl = (m['winLoss'] as num?)?.toInt() ?? 0;
                              final remain = ((m['chips'] as num?)?.toInt() ?? 0) + ((m['cashedOut'] as num?)?.toInt() ?? 0);
                              return ListTile(
                                title: Text(m['name']?.toString() ?? '玩家'),
                                subtitle: Text('总买入 ${m['totalBuyIn']} · 剩余 ${remain}'),
                                trailing: Text('净输赢 ${wl >= 0 ? '+' : ''}$wl',
                                    style: TextStyle(color: wl >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                              );
                            }).toList(),
                          ],
                        ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final pw = await _verifyAdminPassword();
                  if (pw != null && mounted) {
                    _c.adminResetStats(roomId, pw);
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('重置请求已发送，战绩将清零归档')),
                    );
                  }
                },
                child: const Text('重置', style: TextStyle(color: Colors.orange)),
              ),
              TextButton(
                onPressed: () {
                  _c.roomReport = null;
                  Navigator.of(ctx).pop();
                },
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _listTimer?.cancel();
    _c.removeListener(_onChange);
    super.dispose();
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

  // 创建房间表单：与“房间设置”共用同一个 _RoomForm，保证参数项与 AI 选项完全一致
  Widget _buildCreateForm() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset('images/app_icon.png', width: 160, height: 160),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _RoomForm(
                  seed: const _RoomFormSeed(),
                  submitLabel: '创建房间',
                  showAiNote: true,
                  footer: _connHint(),
                  onSubmit: (res) => _doCreate(res),
                ),
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
                borderRadius: BorderRadius.circular(28),
                child: Image.asset('images/app_icon.png', width: 160, height: 160),
              ),
            ),
            const SizedBox(height: 10),
            // 昵称：默认只读，点击“编辑”才进入可改状态（避免误触修改）
            Row(
              children: [
                Expanded(
                  child: _editingNick
                      ? TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                              labelText: '你的昵称', hintText: '留空将记住上次使用的昵称'),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _nameCtrl.text.trim().isEmpty ? '未设置昵称（将使用“玩家”）' : _nameCtrl.text.trim(),
                            style: const TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                if (_editingNick) ...[
                  TextButton(onPressed: () {
                    _saveNickname();
                    setState(() => _editingNick = false);
                  }, child: const Text('保存')),
                  TextButton(onPressed: () {
                    _loadNickname(); // 放弃修改，恢复已保存昵称
                    setState(() => _editingNick = false);
                  }, child: const Text('取消')),
                ] else
                  TextButton.icon(
                    onPressed: () => setState(() => _editingNick = true),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('编辑'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('公开房间', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                TextButton(onPressed: _c.listRooms, child: const Text('刷新')),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _showRoomManagementDialog,
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('房间管理'),
                ),
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
                return Card(
                  child: ListTile(
                    title: Text(room['name'] ?? '房间'),
                    subtitle: Text(sub.join('　'), style: const TextStyle(fontSize: 13)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () async {
                            final pw = await _verifyAdminPassword();
                            if (pw != null && mounted) _showRoomSettingsDialog(room, adminPassword: pw);
                          },
                          child: const Text('设置'),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: () => _showRoomStatsDialog(room),
                          child: const Text('战绩'),
                        ),
                        const SizedBox(width: 4),
                        if (isInThisRoom)
                          ElevatedButton(
                            onPressed: _enterTable,
                            child: const Text('进入'),
                          )
                        else
                          ElevatedButton(
                            onPressed: () => _showJoinDialog(room),
                            child: const Text('加入'),
                          ),
                      ],
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

// ---- 统一的房间参数表单（创建房间 / 房间设置 共用同一段代码、同一个页面组件） ----
// 这样以后调整房间参数（含 AI 对手数量）时，创建与设置始终保持一致，不会再次出现两边不一致的问题。

class _RoomFormSeed {
  final String name;
  final int sb;
  final int bb;
  final int min;
  final int max;
  final int unit;
  final int ante;
  final int actionTimeout;
  final int extensionCount;
  final int extensionSeconds;
  final int aiCount;
  final List<String> aiNames;
  const _RoomFormSeed({
    this.name = '',
    this.sb = 10,
    this.bb = 20,
    this.min = 1000,
    this.max = 3999,
    this.unit = 1000,
    this.ante = 0,
    this.actionTimeout = 60,
    this.extensionCount = 2,
    this.extensionSeconds = 60,
    this.aiCount = 0,
    this.aiNames = const [],
  });
}

class _RoomFormResult {
  final String name;
  final int sb;
  final int bb;
  final int min;
  final int max;
  final int unit;
  final int ante;
  final bool hasAnte;
  final int actionTimeout;
  final int extensionCount;
  final int extensionSeconds;
  final int aiCount;
  final List<String> aiNames;
  const _RoomFormResult({
    required this.name,
    required this.sb,
    required this.bb,
    required this.min,
    required this.max,
    required this.unit,
    required this.ante,
    required this.hasAnte,
    required this.actionTimeout,
    required this.extensionCount,
    required this.extensionSeconds,
    required this.aiCount,
    required this.aiNames,
  });
}

class _RoomForm extends StatefulWidget {
  final _RoomFormSeed seed;
  final String submitLabel;
  final bool showAiNote;
  final Widget? footer;
  final void Function(_RoomFormResult) onSubmit;
  const _RoomForm({
    super.key,
    required this.seed,
    required this.submitLabel,
    this.showAiNote = true,
    this.footer,
    required this.onSubmit,
  });

  @override
  State<_RoomForm> createState() => _RoomFormState();
}

class _RoomFormState extends State<_RoomForm> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _sbCtrl;
  late final TextEditingController _bbCtrl;
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _anteCtrl;
  late final TextEditingController _toCtrl;
  late final TextEditingController _ecCtrl;
  late final TextEditingController _esCtrl;
  late bool _hasAnte;
  late int _aiCount; // 0..8 或 -1 表示自定义
  late final Set<String> _aiNames;

  @override
  void initState() {
    super.initState();
    final s = widget.seed;
    _nameCtrl = TextEditingController(text: s.name);
    _sbCtrl = TextEditingController(text: '${s.sb}');
    _bbCtrl = TextEditingController(text: '${s.bb}');
    _minCtrl = TextEditingController(text: '${s.min}');
    _maxCtrl = TextEditingController(text: '${s.max}');
    _unitCtrl = TextEditingController(text: '${s.unit}');
    _anteCtrl = TextEditingController(text: '${s.ante}');
    _toCtrl = TextEditingController(text: '${s.actionTimeout}');
    _ecCtrl = TextEditingController(text: '${s.extensionCount}');
    _esCtrl = TextEditingController(text: '${s.extensionSeconds}');
    _hasAnte = s.ante > 0;
    _aiCount = s.aiCount;
    _aiNames = Set<String>.from(s.aiNames);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sbCtrl.dispose();
    _bbCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _unitCtrl.dispose();
    _anteCtrl.dispose();
    _toCtrl.dispose();
    _ecCtrl.dispose();
    _esCtrl.dispose();
    super.dispose();
  }

  int _i(TextEditingController c, int dflt) =>
      int.tryParse(c.text.trim()) ?? dflt;

  Widget _numField(String label, TextEditingController ctrl) {
    return Expanded(
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  void _submit() {
    final sb = _i(_sbCtrl, 10);
    final bb = _i(_bbCtrl, sb * 2);
    final isCustom = _aiCount == -1;
    final chosenNames = isCustom ? _aiNames.toList() : <String>[];
    widget.onSubmit(_RoomFormResult(
      name: _nameCtrl.text.trim(),
      sb: sb,
      bb: bb,
      min: _i(_minCtrl, 1000),
      max: _i(_maxCtrl, 3999),
      unit: _i(_unitCtrl, 1000),
      ante: _i(_anteCtrl, 0),
      hasAnte: _hasAnte,
      actionTimeout: _i(_toCtrl, 60),
      extensionCount: _i(_ecCtrl, 2),
      extensionSeconds: _i(_esCtrl, 60),
      aiCount: isCustom ? chosenNames.length : _aiCount,
      aiNames: chosenNames,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: '房间名称', hintText: '给房间起个名字'),
        ),
        const SizedBox(height: 12),
        const Text('牌桌参数', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          _numField('小盲', _sbCtrl),
          const SizedBox(width: 8),
          _numField('大盲', _bbCtrl),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _numField('买入下限', _minCtrl),
          const SizedBox(width: 8),
          _numField('买入上限', _maxCtrl),
        ]),
        const SizedBox(height: 8),
        Row(children: [_numField('买入最小单位', _unitCtrl)]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('是否有前注 (ante)'),
          subtitle: const Text('开启后默认等于小盲', style: TextStyle(fontSize: 12, color: Colors.white54)),
          value: _hasAnte,
          onChanged: (v) => setState(() {
            _hasAnte = v;
            if (v && (_anteCtrl.text.trim().isEmpty || _anteCtrl.text.trim() == '0')) {
              _anteCtrl.text = _sbCtrl.text.trim().isEmpty ? '10' : _sbCtrl.text.trim();
            }
          }),
        ),
        if (_hasAnte)
          Row(children: [_numField('前注金额', _anteCtrl)]),
        const SizedBox(height: 8),
        Row(children: [_numField('每轮行动时间(秒)', _toCtrl)]),
        const SizedBox(height: 8),
        Row(children: [
          _numField('每轮延长次数', _ecCtrl),
          const SizedBox(width: 8),
          _numField('每次延长时间(秒)', _esCtrl),
        ]),
        const SizedBox(height: 12),
        const Text('AI 对手选择（单人测试发牌打牌流程用）', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        DropdownButton<int>(
          value: _aiCount,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: 0, child: Text('无（真人局）')),
            ...List.generate(8, (i) => DropdownMenuItem(
              value: i + 1,
              child: Text('随机挑选 ${i + 1} 个 AI 牌手'),
            )),
            const DropdownMenuItem(value: -1, child: Text('自定义选择…')),
          ],
          onChanged: (v) => setState(() => _aiCount = v ?? 0),
        ),
        if (_aiCount == -1) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade800,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('已选 ${_aiNames.length}/8 个 AI 牌手', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: kAiNames.map((name) {
                    final selected = _aiNames.contains(name);
                    return FilterChip(
                      label: Text(name, style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          if (_aiNames.length < 8) _aiNames.add(name);
                        } else {
                          _aiNames.remove(name);
                        }
                      }),
                      selectedColor: Colors.amber.shade700,
                      checkmarkColor: Colors.white,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
        if (widget.showAiNote)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade800,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'AI 牌手由服务端自动坐入并发牌/下注，便于单人完整测试一手牌。'
                '若创建/设置后看不到 AI，说明服务端尚未部署含 AI 的版本（需上传新版 server-deploy.zip）。',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _submit, child: Text(widget.submitLabel)),
        if (widget.footer != null) ...[
          const SizedBox(height: 8),
          widget.footer!,
        ],
      ],
    );
  }
}
