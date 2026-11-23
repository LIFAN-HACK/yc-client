import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/yc_team.dart';
import 'package:get/get.dart';

/// Home screen of the YC build.
///
/// Signed out, it is one sign-in form. Signed in, it is the team: every computer in a sidebar,
/// the selected one on a stage with a single primary action. There are no ids to exchange and
/// no passwords to type, so neither appears here.
class YcHome extends StatefulWidget {
  /// Permission and service prompts from the stock home page (screen recording, install, …).
  final Widget helpCards;

  const YcHome({Key? key, required this.helpCards}) : super(key: key);

  @override
  State<YcHome> createState() => _YcHomeState();
}

class _C {
  static const bg = Color(0xFF08090B);
  static const panel = Color(0xFF101216);
  static const raised = Color(0xFF171A20);
  static const line = Color(0xFF23272F);
  static const text = Color(0xFFF2F3F5);
  static const dim = Color(0xFF8D93A0);
  static const accent = Color(0xFFC9F85F);
  static const ink = Color(0xFF101A02);
  static const danger = Color(0xFFFF7A6B);
}

Color _hueOf(String id, {double s = 0.55, double l = 0.42}) {
  var sum = 0;
  for (final c in id.codeUnits) {
    sum = (sum * 31 + c) % 360;
  }
  return HSLColor.fromAHSL(1, sum.toDouble(), s, l).toColor();
}

IconData _osIcon(String os) {
  final v = os.toLowerCase();
  if (v.contains('android')) return Icons.phone_android_rounded;
  if (v.contains('mac')) return Icons.laptop_mac_rounded;
  return Icons.desktop_windows_rounded;
}

String _osLabel(String os) {
  final v = os.toLowerCase();
  if (v.contains('windows')) return 'Windows';
  if (v.contains('mac')) return 'macOS';
  if (v.contains('android')) return 'Android';
  if (v.contains('linux')) return 'Linux';
  return os.isEmpty ? '电脑' : os.split('/').first.trim();
}

class _YcHomeState extends State<YcHome> {
  List<YcDevice> _devices = [];
  String? _selected;
  String _myId = '';
  String? _error;
  bool _loaded = false;
  String _query = '';
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
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!gFFI.userModel.isLogin) {
      if (mounted && (_devices.isNotEmpty || _loaded)) {
        setState(() {
          _devices = [];
          _loaded = false;
          _selected = null;
        });
      }
      return;
    }
    try {
      final list = await YcTeam.devices();
      if (!mounted) return;
      setState(() {
        _devices = list;
        _loaded = true;
        _error = null;
        if (_selected == null || !list.any((d) => d.id == _selected)) {
          final others = list.where((d) => d.id != _myId).toList();
          final firstOnline = others.where((d) => d.online).toList();
          _selected = firstOnline.isNotEmpty
              ? firstOnline.first.id
              : (others.isNotEmpty ? others.first.id : null);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _error = '列表刷新失败，正在重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MyTheme.darkTheme,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: _C.text),
        child: Container(
          color: _C.bg,
          child: Obx(() => gFFI.userModel.userName.value.isEmpty
              ? _SignIn(helpCards: widget.helpCards)
              : _team(context)),
        ),
      ),
    );
  }

  Widget _team(BuildContext context) {
    final selected = _devices.where((d) => d.id == _selected).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 272, child: _sidebar(context)),
        Container(width: 1, color: _C.line),
        Expanded(
          child: selected.isEmpty
              ? _emptyStage()
              : _Stage(device: selected.first, helpCards: widget.helpCards),
        ),
      ],
    );
  }

  // ---------- sidebar ----------

  Widget _sidebar(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final others = _devices
        .where((d) => d.id != _myId)
        .where((d) =>
            q.isEmpty ||
            d.name.toLowerCase().contains(q) ||
            d.id.contains(q) ||
            d.group.toLowerCase().contains(q))
        .toList();
    final groups = <String, List<YcDevice>>{};
    for (final d in others) {
      groups.putIfAbsent(d.group.isEmpty ? '未分组' : d.group, () => []).add(d);
    }
    final rows = <Widget>[];
    groups.forEach((name, list) {
      final online = list.where((d) => d.online).length;
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
        child: Row(children: [
          Expanded(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5,
                    color: _C.dim,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600)),
          ),
          Text('$online / ${list.length}',
              style: const TextStyle(fontSize: 11, color: _C.dim)),
        ]),
      ));
      list.sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      for (final d in list) {
        rows.add(_DeviceRow(
          device: d,
          selected: d.id == _selected,
          onTap: () => setState(() => _selected = d.id),
          onOpen: () => _open(context, d),
        ));
      }
    });

    return Container(
      color: _C.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
            child: Row(children: [
              loadIcon(26),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('YC 远程',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              _IconBtn(
                  icon: Icons.refresh_rounded, tip: '刷新', onTap: _refresh),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 13, color: _C.text),
                cursorColor: _C.accent,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索电脑',
                  hintStyle: const TextStyle(color: _C.dim, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 17, color: _C.dim),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  filled: true,
                  fillColor: _C.raised,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _C.accent, width: 1)),
                ),
              ),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? _sidebarEmpty(q.isNotEmpty)
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: rows),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 11.5, color: _C.danger)),
            ),
          Container(height: 1, color: _C.line),
          _thisDevice(),
          Container(height: 1, color: _C.line),
          _account(),
        ],
      ),
    );
  }

  Widget _sidebarEmpty(bool searching) {
    final String msg;
    if (!_loaded) {
      msg = '正在读取团队电脑…';
    } else if (searching) {
      msg = '没有匹配的电脑';
    } else {
      msg = '还没有别的电脑。\n在另一台电脑上装好客户端并登录同一个账号，它就会出现在这里。';
    }
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Text(msg,
          style: const TextStyle(fontSize: 12.5, color: _C.dim, height: 1.6)),
    );
  }

  Widget _thisDevice() {
    final me = _devices.where((d) => d.id == _myId).toList();
    final ready = me.isNotEmpty && me.first.ready;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      child: Row(children: [
        Icon(Icons.computer_rounded,
            size: 18, color: ready ? _C.accent : _C.dim),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(me.isNotEmpty ? '本机 · ${me.first.name}' : '本机',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                  _myId.isEmpty
                      ? '正在获取设备码…'
                      : '${formatID(_myId)} · ${ready ? '可被团队连接' : '正在加入团队…'}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _C.dim)),
            ],
          ),
        ),
        _IconBtn(
          icon: Icons.copy_rounded,
          tip: '复制设备码',
          onTap: () {
            Clipboard.setData(ClipboardData(text: _myId));
            showToast('已复制');
          },
        ),
      ]),
    );
  }

  Widget _account() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 12),
      child: Row(children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: _C.raised, borderRadius: BorderRadius.circular(13)),
          child: Obx(() {
            final n = gFFI.userModel.displayNameOrUserName;
            return Text(n.isEmpty ? '?' : n.substring(0, 1).toUpperCase(),
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700));
          }),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Obx(() => Text(gFFI.userModel.displayNameOrUserName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5))),
        ),
        _IconBtn(
            icon: Icons.settings_outlined,
            tip: '设置',
            onTap: () => DesktopTabPage.onAddSetting()),
        _IconBtn(
            icon: Icons.logout_rounded,
            tip: '退出登录',
            onTap: () => gFFI.userModel.logOut()),
      ]),
    );
  }

  Widget _emptyStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.devices_other_rounded, size: 44, color: _C.dim),
              const SizedBox(height: 14),
              Text(_loaded ? '在左边选一台电脑' : '正在读取团队电脑…',
                  style: const TextStyle(fontSize: 15, color: _C.dim)),
            ]),
          ),
        ),
        _Footer(helpCards: widget.helpCards),
      ],
    );
  }

  void _open(BuildContext context, YcDevice d) {
    if (!d.online) {
      showToast('${d.name} 不在线');
      return;
    }
    connect(context, d.id);
  }
}

// ---------- pieces ----------

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.tip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: _C.raised,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 17, color: _C.dim),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool on;
  const _Dot(this.on);
  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: on ? _C.accent : const Color(0xFF3A3F49),
          shape: BoxShape.circle,
        ),
      );
}

class _DeviceRow extends StatelessWidget {
  final YcDevice device;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  const _DeviceRow(
      {required this.device,
      required this.selected,
      required this.onTap,
      required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final d = device;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? _C.raised : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onOpen,
          borderRadius: BorderRadius.circular(10),
          hoverColor: _C.raised.withOpacity(0.6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Opacity(
                opacity: d.online ? 1 : 0.45,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _hueOf(d.id),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_osIcon(d.os), size: 16, color: Colors.white),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(d.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: d.online ? _C.text : _C.dim)),
              ),
              const SizedBox(width: 8),
              _Dot(d.online),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final Widget child;
  const _Chip({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.28),
          borderRadius: BorderRadius.circular(20),
        ),
        child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 12, color: Colors.white),
            child: child),
      );
}

class _Stage extends StatelessWidget {
  final YcDevice device;
  final Widget helpCards;
  const _Stage({required this.device, required this.helpCards});

  @override
  Widget build(BuildContext context) {
    final d = device;
    final top = _hueOf(d.id, s: 0.5, l: d.online ? 0.34 : 0.2);
    final bottom = _hueOf(d.id, s: 0.45, l: 0.1);
    final sub = [
      formatID(d.id),
      if (d.group.isNotEmpty) d.group,
      if (d.owner.isNotEmpty) d.owner,
    ].join('  ·  ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [top, bottom],
                ),
              ),
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _Chip(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_osIcon(d.os), size: 13, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(_osLabel(d.os)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    _Chip(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _Dot(d.online),
                        const SizedBox(width: 7),
                        Text(d.online ? '在线' : '离线'),
                      ]),
                    ),
                  ]),
                  const Spacer(),
                  Text(d.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 34,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 13, color: Colors.white.withOpacity(0.72))),
                  const SizedBox(height: 26),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Primary(
                        label: d.online ? '进入桌面' : '电脑不在线',
                        enabled: d.online,
                        onTap: () => connect(context, d.id),
                      ),
                      _Ghost(
                        icon: Icons.folder_open_rounded,
                        label: '文件传输',
                        enabled: d.online,
                        onTap: () =>
                            connect(context, d.id, isFileTransfer: true),
                      ),
                      _Ghost(
                        icon: Icons.videocam_outlined,
                        label: '查看摄像头',
                        enabled: d.online,
                        onTap: () =>
                            connect(context, d.id, isViewCamera: true),
                      ),
                    ],
                  ),
                  if (d.online && !d.ready)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text('这台电脑还没完成加入，连接时可能会要求输入密码。',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.7))),
                    ),
                ],
              ),
            ),
          ),
        ),
        _Footer(helpCards: helpCards),
      ],
    );
  }
}

class _Primary extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _Primary(
      {required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? _C.accent : Colors.white.withOpacity(0.12),
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 8, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: enabled ? _C.ink : Colors.white.withOpacity(0.55))),
            const SizedBox(width: 16),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: enabled ? _C.ink : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 18,
                  color: enabled ? _C.accent : Colors.white.withOpacity(0.4)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Ghost extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _Ghost(
      {required this.icon,
      required this.label,
      required this.enabled,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withOpacity(enabled ? 0.92 : 0.4);
    return Material(
      color: Colors.black.withOpacity(0.26),
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 13.5, color: color)),
          ]),
        ),
      ),
    );
  }
}

/// Connection status of this device plus any pending system prompts.
class _Footer extends StatelessWidget {
  final Widget helpCards;
  const _Footer({required this.helpCards});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: helpCards),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 10),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _C.line))),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: const OnlineStatusWidget(),
        ),
      ],
    );
  }
}

// ---------- signed out ----------

class _SignIn extends StatefulWidget {
  final Widget helpCards;
  const _SignIn({required this.helpCards});

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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

  InputDecoration _field(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _C.dim, fontSize: 14),
        prefixIcon: Icon(icon, size: 18, color: _C.dim),
        filled: true,
        fillColor: _C.raised,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _C.accent, width: 1)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(alignment: Alignment.centerLeft, child: loadIcon(44)),
                    const SizedBox(height: 22),
                    const Text('登录团队账号',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('登录后，这台电脑会自动加入团队，可以控制团队里的其他电脑，也可以被它们控制。',
                        style: TextStyle(
                            fontSize: 13, color: _C.dim, height: 1.6)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _user,
                      autofocus: true,
                      enabled: !_busy,
                      cursorColor: _C.accent,
                      style: const TextStyle(fontSize: 14, color: _C.text),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _passFocus.requestFocus(),
                      decoration: _field('账号', Icons.person_outline_rounded),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _pass,
                      focusNode: _passFocus,
                      enabled: !_busy,
                      obscureText: true,
                      cursorColor: _C.accent,
                      style: const TextStyle(fontSize: 14, color: _C.text),
                      onSubmitted: (_) => _submit(),
                      decoration: _field('密码', Icons.lock_outline_rounded),
                    ),
                    SizedBox(
                      height: 30,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_error ?? '',
                            style: const TextStyle(
                                fontSize: 12.5, color: _C.danger)),
                      ),
                    ),
                    Material(
                      color: _busy ? _C.accent.withOpacity(0.6) : _C.accent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: _busy ? null : _submit,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          child: Text(_busy ? '正在登录…' : '登录',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _C.ink)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      const Expanded(
                        child: Text('没有账号？请找团队管理员开通。',
                            style: TextStyle(fontSize: 12, color: _C.dim)),
                      ),
                      _IconBtn(
                          icon: Icons.settings_outlined,
                          tip: '设置',
                          onTap: () => DesktopTabPage.onAddSetting()),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
        _Footer(helpCards: widget.helpCards),
      ],
    );
  }
}
