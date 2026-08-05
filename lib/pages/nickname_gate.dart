// lib/pages/nickname_gate.dart —— 首次进入强制设置昵称（必填），之后记住不再提示
import 'package:flutter/material.dart';
import '../game_controller.dart';
import '../storage/settings_storage.dart';
import '../config.dart';
import 'lobby_page.dart';

class NicknameGate extends StatefulWidget {
  const NicknameGate({super.key});

  @override
  State<NicknameGate> createState() => _NicknameGateState();
}

class _NicknameGateState extends State<NicknameGate> {
  final SettingsStorage _settings = SettingsStorage();
  final TextEditingController _ctrl = TextEditingController();
  bool _ready = false;
  bool _loading = true;
  GameController? _preparedController;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
    _init();
  }

  Future<void> _init() async {
    final n = await _settings.loadNickname();
    if (mounted) {
      if (n != null && n.trim().isNotEmpty) {
        // 昵称已设置：提前创建并连接 GameController，进大厅时直接复用，减少“连接中”等待
        final c = GameController();
        c.nickname = n;
        c.connect();
        c.listRooms();
        _preparedController = c;
        setState(() {
          _ready = true;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _enter() async {
    final n = _ctrl.text.trim();
    if (n.isEmpty) return;
    await _settings.saveNickname(n);
    if (mounted) {
      // 首次设置昵称时也提前启动连接
      final c = GameController();
      c.nickname = n;
      c.connect();
      c.listRooms();
      _preparedController = c;
      setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_ready) {
      return LobbyPage(controller: _preparedController ?? GameController());
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: Image.asset('images/app_icon.png', width: 320, height: 320),
              ),
              const SizedBox(height: 20),
              const Text('欢迎来到河马扑克',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('首次进入，请先设置你的昵称（必填）',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 20),
              TextField(
                controller: _ctrl,
                autofocus: true,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: '昵称',
                  hintText: '例如：小明',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _enter(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _ctrl.text.trim().isEmpty ? null : _enter,
                  child: const Text('进入大厅'),
                ),
              ),
              const SizedBox(height: 10),
              const Text('设置后下次进入将自动沿用，可在大厅页面修改。',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 16),
              Text('内部测试版 v$kAppVersion',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
