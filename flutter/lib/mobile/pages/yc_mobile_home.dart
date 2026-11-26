import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/mobile/pages/home_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/yc_team.dart';
import 'package:get/get.dart';

const _bg = Color(0xFF121014);
const _panel = Color(0xFF1A1719);
const _raised = Color(0xFF231F22);
const _line = Color(0xFF2E2A2D);
const _text = Color(0xFFF5EFEA);
const _sub = Color(0xFFB3A9A3);
const _dim = Color(0xFF8C827C);
const _ink = Color(0xFF1A1214);
const _online = Color(0xFF5FD38D);
const _danger = Color(0xFFFF8A8A);
const _accent = Color(0xFFF28C6B);
const _grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF7A27F), Color(0xFFEE7A5A)]);

/// The phone's first tab: sign in once, then the account's devices, one tap to enter.
class YcMobileHome extends StatefulWidget implements PageShape {
  YcMobileHome({Key? key}) : super(key: key);

  @override
  final icon = const Icon(Icons.devices_rounded);

  @override
  final title = '设备';

  @override
  final List<Widget> appBarActions = const [];

  @override
  State<YcMobileHome> createState() => _YcMobileHomeState();
}

class _YcMobileHomeState extends State<YcMobileHome> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  List<YcDevice> _devices = [];
  String _myId = '';
  bool _loaded = false;
  bool _failed = false;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  Worker? _userWatch;

  @override
  void initState() {
    super.initState();
    bind.mainGetMyId().then((v) {
      if (mounted) setState(() => _myId = v);
    });
    _userWatch = ever(gFFI.userModel.userName, (_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _userWatch?.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!gFFI.userModel.isLogin) {
      if (mounted && _devices.isNotEmpty) setState(() => _devices = []);
      return;
    }
    try {
      final list = await YcTeam.devices();
      if (!mounted) return;
      list.sort((a, b) {
        final am = a.id == _myId ? 0 : 1, bm = b.id == _myId ? 0 : 1;
        if (am != bm) return am - bm;
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() {
        _devices = list;
        _loaded = true;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _failed = true;
      });
    }
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final name = _user.text.trim();
    if (name.isEmpty || _pass.text.isEmpty) {
      setState(() => _error = '请输入账号和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await YcTeam.signIn(name, _pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _rename(YcDevice d) async {
    final ctl = TextEditingController(text: d.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        title:
            const Text('重命名设备', style: TextStyle(fontSize: 16, color: _text)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 60,
          style: const TextStyle(fontSize: 14, color: _text),
          decoration: const InputDecoration(
              hintText: '留空则恢复电脑自己的名字',
              hintStyle: TextStyle(fontSize: 13, color: _dim),
              counterText: ''),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消', style: TextStyle(color: _sub))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(ctl.text),
              child: const Text('保存', style: TextStyle(color: _text))),
        ],
      ),
    );
    if (name == null || name.trim() == d.name) return;
    final err = await YcTeam.rename(d.id, name.trim());
    showToast(err ?? '已改名');
    await _refresh();
  }

  void _sheet(YcDevice d) {
    final canOpen = d.online && d.id != _myId;
    Widget row(IconData icon, String label, VoidCallback? onTap) => ListTile(
          enabled: onTap != null,
          leading: Icon(icon, size: 20, color: onTap != null ? _text : _dim),
          title: Text(label,
              style: TextStyle(
                  fontSize: 14.5, color: onTap != null ? _text : _dim)),
          onTap: onTap == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  onTap();
                },
        );
    showModalBottomSheet(
      context: context,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(children: [
              Expanded(
                child: Text(d.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _text)),
              ),
            ]),
          ),
          row(Icons.desktop_windows_rounded, '进入桌面',
              canOpen ? () => connect(context, d.id) : null),
          row(
              Icons.folder_open_rounded,
              '文件传输',
              canOpen
                  ? () => connect(context, d.id, isFileTransfer: true)
                  : null),
          row(Icons.edit_outlined, '重命名', () => _rename(d)),
          row(Icons.copy_rounded, '复制设备码', () {
            Clipboard.setData(ClipboardData(text: d.id));
            showToast('已复制设备码');
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MyTheme.darkTheme,
      child: Container(
        color: _bg,
        child: Obx(() =>
            gFFI.userModel.userName.value.isEmpty ? _signInForm() : _list()),
      ),
    );
  }

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _dim, fontSize: 14),
        filled: true,
        fillColor: _raised,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _accent)),
      );

  Widget _signInForm() {
    return LayoutBuilder(builder: (context, box) {
      final posterH = (box.maxHeight * 0.42).clamp(200.0, 360.0);
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: posterH,
                child: Stack(fit: StackFit.expand, children: [
                  const ColoredBox(color: Color(0xFFF3A48C)),
                  Image.asset('assets/login_poster.jpg',
                      fit: BoxFit.cover, alignment: const Alignment(0, -0.2)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.55, 1],
                        colors: [Color(0x00121014), _bg],
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 24,
                    bottom: 18,
                    child: Text('每一台电脑，\n都在你手边。',
                        style: TextStyle(
                            fontSize: 24,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                            color: _text)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('欢迎回来',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: _text)),
                    const SizedBox(height: 6),
                    const Text('登录同一账号的设备可以互相远程控制',
                        style: TextStyle(fontSize: 13, color: _sub)),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _user,
                      enabled: !_busy,
                      cursorColor: _accent,
                      style: const TextStyle(fontSize: 14, color: _text),
                      textInputAction: TextInputAction.next,
                      decoration: _field('账号'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass,
                      enabled: !_busy,
                      obscureText: true,
                      cursorColor: _accent,
                      style: const TextStyle(fontSize: 14, color: _text),
                      onSubmitted: (_) => _signIn(),
                      decoration: _field('密码'),
                    ),
                    SizedBox(
                      height: 30,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_error ?? '',
                            style: const TextStyle(
                                fontSize: 12.5, color: _danger)),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: _busy ? null : _grad,
                          color: _busy ? _raised : null,
                          borderRadius: BorderRadius.circular(13)),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(13),
                          onTap: _busy ? null : _signIn,
                          child: SizedBox(
                            height: 50,
                            child: Center(
                              child: Text(_busy ? '正在登录…' : '登录',
                                  style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: _busy ? _dim : _ink)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('没有账号？请联系管理员开通',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: _dim)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _list() {
    final String? note;
    if (!_loaded) {
      note = '正在读取设备…';
    } else if (_failed && _devices.isEmpty) {
      note = '读取失败，正在重试…';
    } else if (_devices.isEmpty) {
      note = '还没有设备。在电脑上安装 OpenDesk 并登录这个账号，它就会出现在这里。';
    } else {
      note = null;
    }
    return RefreshIndicator(
      color: _text,
      backgroundColor: _raised,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 0, 10),
            child: Row(children: [
              Expanded(
                child: Text(
                    '我的设备${_devices.isEmpty ? '' : '  ${_devices.length}'}',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _dim)),
              ),
              Obx(() => Text(gFFI.userModel.displayNameOrUserName,
                  style: const TextStyle(fontSize: 12.5, color: _sub))),
              TextButton(
                  onPressed: () => gFFI.userModel.logOut(),
                  child: const Text('退出',
                      style: TextStyle(fontSize: 12.5, color: _sub))),
            ]),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 20, 6, 0),
              child: Text(note,
                  style:
                      const TextStyle(fontSize: 13, color: _dim, height: 1.6)),
            ),
          for (final d in _devices) _tile(d),
        ],
      ),
    );
  }

  Widget _tile(YcDevice d) {
    final isMe = d.id == _myId;
    final canOpen = d.online && !isMe;
    final os = d.os.toLowerCase();
    final icon = os.contains('android')
        ? Icons.phone_android_rounded
        : (os.contains('mac')
            ? Icons.laptop_mac_rounded
            : Icons.desktop_windows_rounded);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _panel,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: canOpen ? () => connect(context, d.id) : () => _sheet(d),
          onLongPress: () => _sheet(d),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    gradient: canOpen ? _grad : null,
                    color: canOpen
                        ? null
                        : Colors.white.withOpacity(d.online ? 0.08 : 0.04),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon,
                    size: 20,
                    color: canOpen ? _ink : (d.online ? _text : _dim)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: d.online ? _text : _dim)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: d.online ? _online : _dim,
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(isMe ? '本机' : (d.online ? '在线' : '离线'),
                          style: const TextStyle(fontSize: 12, color: _sub)),
                    ]),
                  ],
                ),
              ),
              IconButton(
                  onPressed: () => _sheet(d),
                  icon: const Icon(Icons.more_horiz_rounded,
                      size: 20, color: _sub)),
            ]),
          ),
        ),
      ),
    );
  }
}
