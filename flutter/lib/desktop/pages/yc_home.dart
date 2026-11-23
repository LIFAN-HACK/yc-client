import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/models/yc_team.dart';
import 'package:get/get.dart';

/// Something this computer needs from its user before it can be controlled (a system
/// permission, an install step), shown as one strip above the device.
class YcNotice {
  final String text;
  final String action;
  final VoidCallback? onAction;
  const YcNotice(this.text, {this.action = '', this.onAction});
}

/// Home screen of OpenDesk.
///
/// Signed out, it is one sign-in form. Signed in, it is the account's devices: all of them in
/// a sidebar, the selected one in the main area with a single primary action. There are no
/// ids to exchange and no passwords to type, so neither is asked for here.
class YcHome extends StatefulWidget {
  final YcNotice? notice;

  const YcHome({Key? key, this.notice}) : super(key: key);

  @override
  State<YcHome> createState() => _YcHomeState();
}

class _C {
  static const bg = Color(0xFF0B0C10);
  static const side = Color(0xFF0F1116);
  static const panel = Color(0xFF14161C);
  static const raised = Color(0xFF1B1E26);
  static const hover = Color(0xFF171A21);
  static const line = Color(0xFF22252E);
  static const text = Color(0xFFECEEF3);
  static const sub = Color(0xFFA4A9B6);
  static const dim = Color(0xFF6D7382);
  static const accent = Color(0xFFECEEF3);
  static const ink = Color(0xFF0B0D10);
  static const online = Color(0xFF3DDC84);
  static const danger = Color(0xFFFF6B6B);
  static const warn = Color(0xFFF5B74E);
  static const grad = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFFFFF), Color(0xFFD9DCE4)]);
}

String _lastSeen(int seconds) {
  final t = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  final now = DateTime.now();
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return '今天 $hm';
  }
  return '${t.month} 月 ${t.day} 日 $hm';
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
  bool _loaded = false;
  bool _failed = false;
  String _query = '';
  bool _collapsed = false;
  Timer? _timer;
  Timer? _statusTimer;
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
    _statusTimer = periodic_immediate(const Duration(seconds: 1), _pollStatus);
  }

  Future<void> _pollStatus() async {
    try {
      final status =
          jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
      final n = status['status_num'];
      stateGlobal.svcStatus.value = n == 0
          ? SvcStatus.connecting
          : (n == 1 ? SvcStatus.ready : SvcStatus.notReady);
      final count = status['video_conn_count'];
      if (count is int) stateGlobal.videoConnCount.value = count;
    } catch (_) {}
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
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
      // This computer first, then online ones, then by name.
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
        if (_selected == null || !list.any((d) => d.id == _selected)) {
          final others = list.where((d) => d.id != _myId).toList();
          _selected = others.isNotEmpty
              ? others.first.id
              : (list.isNotEmpty ? list.first.id : null);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _failed = true;
      });
    }
  }

  Future<void> _rename(YcDevice d) async {
    final ctl = TextEditingController(text: d.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => Theme(
        data: MyTheme.darkTheme,
        child: AlertDialog(
          backgroundColor: _C.panel,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _C.line)),
          title: const Text('重命名设备',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: _C.text)),
          content: SizedBox(
            width: 320,
            child: TextField(
              controller: ctl,
              autofocus: true,
              maxLength: 60,
              cursorColor: _C.accent,
              style: const TextStyle(fontSize: 14, color: _C.text),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
              decoration: InputDecoration(
                hintText: '留空则恢复电脑自己的名字',
                hintStyle: const TextStyle(fontSize: 13, color: _C.dim),
                counterText: '',
                filled: true,
                fillColor: _C.raised,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消', style: TextStyle(color: _C.sub))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(ctl.text),
                child: const Text('保存',
                    style: TextStyle(
                        color: _C.accent, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
    if (name == null || name.trim() == d.name) return;
    final err = await YcTeam.rename(d.id, name.trim());
    showToast(err ?? '已改名');
    await _refresh();
  }

  Future<void> _remove(YcDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: MyTheme.darkTheme,
        child: AlertDialog(
          backgroundColor: _C.panel,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _C.line)),
          title: const Text('从账号移除',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: _C.text)),
          content: SizedBox(
            width: 320,
            child: Text('“${d.name}”将从设备列表消失，那台电脑上的 OpenDesk 需要重新登录才能再加入。',
                style:
                    const TextStyle(fontSize: 13, color: _C.sub, height: 1.6)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消', style: TextStyle(color: _C.sub))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('移除',
                    style: TextStyle(
                        color: _C.danger, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final err = await YcTeam.remove(d.id);
    showToast(err ?? '已移除');
    await _refresh();
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
              ? _SignIn(notice: widget.notice)
              : _signedIn(context)),
        ),
      ),
    );
  }

  Widget _signedIn(BuildContext context) {
    final selected = _devices.where((d) => d.id == _selected).toList();
    final d = selected.isEmpty ? null : selected.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 256, child: _sidebar(context)),
        Container(width: 1, color: _C.line),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.notice != null) _NoticeStrip(widget.notice!),
              Expanded(
                child: d == null
                    ? _empty()
                    : _DevicePage(
                        device: d,
                        isMe: d.id == _myId,
                        onRename: () => _rename(d),
                        onRemove: () => _remove(d)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- sidebar ----------

  Widget _sidebar(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? _devices
        : _devices
            .where((d) =>
                d.name.toLowerCase().contains(q) ||
                d.id.contains(q.replaceAll(' ', '')))
            .toList();
    return Container(
      color: _C.side,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 10, 14),
            child: Row(children: [
              Image.asset('assets/mark_white.png', width: 26, height: 26),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('OpenDesk',
                    style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2)),
              ),
              _IconBtn(icon: Icons.refresh_rounded, tip: '刷新', onTap: _refresh),
            ]),
          ),
          Obx(() {
            final n = stateGlobal.videoConnCount.value;
            if (n <= 0) return const SizedBox();
            return Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                  gradient: _C.grad, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('本机被控中',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _C.ink)),
                  const SizedBox(height: 4),
                  Text('当前有 $n 台设备正在控制此电脑',
                      style: const TextStyle(fontSize: 11.5, color: _C.ink)),
                ],
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                cursorColor: _C.accent,
                style: const TextStyle(fontSize: 13, color: _C.text),
                decoration: InputDecoration(
                  hintText: '搜索设备',
                  hintStyle: const TextStyle(fontSize: 13, color: _C.dim),
                  prefixIcon:
                      const Icon(Icons.search_rounded, size: 17, color: _C.dim),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 38, minHeight: 36),
                  filled: true,
                  fillColor: _C.raised,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: _searchBorder(Colors.transparent),
                  enabledBorder: _searchBorder(Colors.transparent),
                  focusedBorder: _searchBorder(_C.accent),
                ),
              ),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 8),
              child: Row(children: [
                Expanded(
                  child: Text(
                      '我的设备${_devices.isEmpty ? '' : '  ${_devices.length}'}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: _C.dim)),
                ),
                Icon(
                    _collapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 16,
                    color: _C.dim),
              ]),
            ),
          ),
          Expanded(
            child: _collapsed
                ? const SizedBox()
                : (shown.isEmpty
                    ? _sidebarEmpty(q.isNotEmpty)
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final d = shown[i];
                          return _DeviceRow(
                            device: d,
                            isMe: d.id == _myId,
                            selected: d.id == _selected,
                            onTap: () => setState(() => _selected = d.id),
                            onOpen: () {
                              if (d.id != _myId && d.online) {
                                connect(context, d.id);
                              }
                            },
                          );
                        })),
          ),
          Container(height: 1, color: _C.line),
          _account(),
        ],
      ),
    );
  }

  OutlineInputBorder _searchBorder(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c, width: 1));

  Widget _sidebarEmpty(bool searching) {
    final String msg;
    if (!_loaded) {
      msg = '正在读取设备…';
    } else if (_failed) {
      msg = '读取失败，正在重试…';
    } else if (searching) {
      msg = '没有匹配的设备';
    } else {
      msg = '还没有设备';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Text(msg, style: const TextStyle(fontSize: 12.5, color: _C.dim)),
    );
  }

  Widget _account() {
    final stopped = Get.isRegistered<RxBool>(tag: 'stop-service')
        ? Get.find<RxBool>(tag: 'stop-service')
        : false.obs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration:
              const BoxDecoration(gradient: _C.grad, shape: BoxShape.circle),
          child: Obx(() {
            final n = gFFI.userModel.displayNameOrUserName;
            return Text(n.isEmpty ? '?' : n.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: _C.ink));
          }),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(() => Text(gFFI.userModel.displayNameOrUserName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600))),
              const SizedBox(height: 2),
              Obx(() {
                final Color c;
                final String t;
                if (stopped.value) {
                  c = _C.dim;
                  t = '本机已暂停被控';
                } else if (stateGlobal.svcStatus.value == SvcStatus.ready) {
                  c = _C.online;
                  t = '服务已连接';
                } else if (stateGlobal.svcStatus.value ==
                    SvcStatus.connecting) {
                  c = _C.warn;
                  t = '正在连接服务…';
                } else {
                  c = _C.danger;
                  t = '服务未连接';
                }
                return Row(children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: c, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(t,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: _C.dim)),
                  ),
                ]);
              }),
            ],
          ),
        ),
        _Menu(
          icon: Icons.more_horiz_rounded,
          above: true,
          items: {
            'settings': '设置',
            if (stopped.value) 'resume': '恢复本机被控',
            'logout': '退出登录',
          },
          onSelected: (v) {
            if (v == 'settings') DesktopTabPage.onAddSetting();
            if (v == 'resume') start_service(true);
            if (v == 'logout') gFFI.userModel.logOut();
          },
        ),
      ]),
    );
  }

  Widget _empty() {
    final String title, body;
    if (!_loaded) {
      title = '正在读取设备…';
      body = '';
    } else {
      title = '还没有设备';
      body = '在另一台电脑上安装 OpenDesk 并登录这个账号，它就会出现在左边。';
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.devices_rounded, size: 48, color: _C.dim),
          const SizedBox(height: 16),
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, color: _C.dim, height: 1.6)),
          ],
        ]),
      ),
    );
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
          child: Icon(icon, size: 17, color: _C.sub),
        ),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  final IconData icon;
  final Map<String, String> items;
  final void Function(String) onSelected;
  final bool above;
  const _Menu(
      {required this.icon,
      required this.items,
      required this.onSelected,
      this.above = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<String>(
        tooltip: '',
        padding: EdgeInsets.zero,
        color: _C.raised,
        elevation: 8,
        offset: Offset(0, above ? -(items.length * 40.0 + 12) : 36),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: _C.line)),
        icon: Icon(icon, size: 18, color: _C.sub),
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final e in items.entries)
            PopupMenuItem(
                value: e.key,
                height: 40,
                child: Text(e.value,
                    style: const TextStyle(fontSize: 13, color: _C.text))),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final YcDevice device;
  final bool isMe;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  const _DeviceRow(
      {required this.device,
      required this.isMe,
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
          hoverColor: selected ? _C.raised : _C.hover,
          child: SizedBox(
            height: 46,
            child: Row(children: [
              const SizedBox(width: 10),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: d.online
                      ? _C.accent.withOpacity(0.12)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_osIcon(d.os),
                    size: 15, color: d.online ? _C.accent : _C.dim),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(d.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: d.online ? _C.text : _C.dim)),
              ),
              if (isMe)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(5)),
                  child: const Text('本机',
                      style: TextStyle(fontSize: 10.5, color: _C.sub)),
                ),
              const SizedBox(width: 8),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: d.online ? _C.online : const Color(0xFF353944),
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DevicePage extends StatelessWidget {
  final YcDevice device;
  final bool isMe;
  final VoidCallback onRename;
  final VoidCallback onRemove;
  const _DevicePage(
      {required this.device,
      required this.isMe,
      required this.onRename,
      required this.onRemove});

  void _copy() {
    Clipboard.setData(ClipboardData(text: device.id));
    showToast('已复制设备码');
  }

  @override
  Widget build(BuildContext context) {
    final d = device;
    final canOpen = d.online && !isMe;
    final String hint;
    if (isMe) {
      hint = d.ready ? '这是本机。登录同一账号的其他设备可以直接进入它的桌面。' : '正在把本机接入账号…';
    } else if (!d.online) {
      hint = d.lastSeen > 0
          ? '上线后即可进入 · 最近在线：${_lastSeen(d.lastSeen)}'
          : '设备离线，上线后即可进入。';
    } else if (!d.ready) {
      hint = '该设备尚未完成接入，进入时需要输入它的连接密码。';
    } else {
      hint = '';
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 26, 32, 28),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      color: (d.online ? _C.online : _C.dim).withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: d.online ? _C.online : _C.dim,
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(d.online ? '在线' : '离线',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: d.online ? _C.online : _C.sub)),
                  ]),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(d.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 4),
                _IconBtn(
                    icon: Icons.edit_outlined, tip: '重命名', onTap: onRename),
                const Spacer(),
                _Menu(
                  icon: Icons.more_horiz_rounded,
                  items: {
                    'rename': '重命名',
                    'copy': '复制设备码',
                    if (!isMe) 'remove': '从账号移除',
                  },
                  onSelected: (v) {
                    if (v == 'rename') onRename();
                    if (v == 'copy') _copy();
                    if (v == 'remove') onRemove();
                  },
                ),
              ]),
              const SizedBox(height: 20),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                    color: _C.panel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _C.line)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 230,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -1.2),
                          radius: 1.3,
                          colors: [
                            (d.online ? _C.accent : _C.dim).withOpacity(0.10),
                            _C.panel,
                          ],
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_osIcon(d.os),
                              size: 44, color: d.online ? _C.text : _C.dim),
                          const SizedBox(height: 20),
                          if (!isMe)
                            _PrimaryBtn(
                                label: d.online ? '进入桌面' : '设备离线',
                                onTap: canOpen
                                    ? () => connect(context, d.id)
                                    : null),
                          if (hint.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(
                                  top: isMe ? 0 : 12, left: 24, right: 24),
                              child: Text(hint,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 12.5, color: _C.sub)),
                            ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: _C.line),
                    SizedBox(
                      height: 54,
                      child: Row(children: [
                        _BarAction(
                            icon: Icons.folder_open_rounded,
                            label: '文件传输',
                            onTap: canOpen
                                ? () =>
                                    connect(context, d.id, isFileTransfer: true)
                                : null),
                        const _BarDivider(),
                        _BarAction(
                            icon: Icons.terminal_rounded,
                            label: '终端',
                            onTap: canOpen
                                ? () => connect(context, d.id, isTerminal: true)
                                : null),
                        const _BarDivider(),
                        _BarAction(
                            icon: Icons.videocam_outlined,
                            label: '摄像头',
                            onTap: canOpen
                                ? () =>
                                    connect(context, d.id, isViewCamera: true)
                                : null),
                      ]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                    color: _C.panel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _C.line)),
                child: Column(children: [
                  _InfoRow(label: '设备码', value: formatID(d.id), onCopy: _copy),
                  _InfoRow(label: '系统', value: _osLabel(d.os)),
                  if (d.owner.isNotEmpty)
                    _InfoRow(label: '登录账号', value: d.owner),
                  _InfoRow(
                      label: '免密进入',
                      value: d.ready ? '已开启' : '未就绪',
                      last: true),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double width;
  const _PrimaryBtn({required this.label, this.onTap, this.width = 168});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Container(
      width: width,
      height: 44,
      decoration: BoxDecoration(
          gradient: on ? _C.grad : null,
          color: on ? null : _C.raised,
          borderRadius: BorderRadius.circular(12)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.black.withOpacity(0.08),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: on ? _C.ink : _C.dim)),
          ),
        ),
      ),
    );
  }
}

class _BarDivider extends StatelessWidget {
  const _BarDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 18, color: _C.line);
}

class _BarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _BarAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = onTap != null ? _C.text : _C.dim;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        hoverColor: _C.raised,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: onTap != null ? _C.accent : _C.dim),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13.5, color: c)),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;
  final bool last;
  const _InfoRow(
      {required this.label,
      required this.value,
      this.onCopy,
      this.last = false});

  @override
  Widget build(BuildContext context) => Container(
        height: 46,
        decoration: BoxDecoration(
            border:
                last ? null : const Border(bottom: BorderSide(color: _C.line))),
        child: Row(children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: _C.dim)),
          ),
          Expanded(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: _C.text)),
          ),
          if (onCopy != null)
            _IconBtn(icon: Icons.copy_rounded, tip: '复制', onTap: onCopy!),
        ]),
      );
}

class _NoticeStrip extends StatelessWidget {
  final YcNotice notice;
  const _NoticeStrip(this.notice);

  @override
  Widget build(BuildContext context) => Container(
        color: _C.warn.withOpacity(0.10),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: _C.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(notice.text,
                style: const TextStyle(
                    fontSize: 12.5, color: _C.warn, height: 1.4)),
          ),
          if (notice.onAction != null && notice.action.isNotEmpty) ...[
            const SizedBox(width: 12),
            Material(
              color: _C.warn.withOpacity(0.16),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: notice.onAction,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(notice.action,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _C.warn)),
                ),
              ),
            ),
          ],
        ]),
      );
}

// ---------- signed out ----------

class _SignIn extends StatefulWidget {
  final YcNotice? notice;
  const _SignIn({this.notice});

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

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: 1));

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _C.dim, fontSize: 14),
        filled: true,
        fillColor: _C.raised,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: _border(Colors.transparent),
        enabledBorder: _border(Colors.transparent),
        disabledBorder: _border(Colors.transparent),
        focusedBorder: _border(_C.accent),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.notice != null) _NoticeStrip(widget.notice!),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 330),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                        child: Image.asset('assets/mark_white.png',
                            width: 64, height: 64)),
                    const SizedBox(height: 20),
                    const Text('登录 OpenDesk',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('登录同一账号的设备可以互相远程控制',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: _C.sub)),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _user,
                      autofocus: true,
                      enabled: !_busy,
                      cursorColor: _C.accent,
                      style: const TextStyle(fontSize: 14, color: _C.text),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _passFocus.requestFocus(),
                      decoration: _field('账号'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass,
                      focusNode: _passFocus,
                      enabled: !_busy,
                      obscureText: true,
                      cursorColor: _C.accent,
                      style: const TextStyle(fontSize: 14, color: _C.text),
                      onSubmitted: (_) => _submit(),
                      decoration: _field('密码'),
                    ),
                    SizedBox(
                      height: 32,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_error ?? '',
                            style: const TextStyle(
                                fontSize: 12.5, color: _C.danger)),
                      ),
                    ),
                    _PrimaryBtn(
                        label: _busy ? '正在登录…' : '登录',
                        width: double.infinity,
                        onTap: _busy ? null : _submit),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('没有账号？请联系管理员开通',
                          style: TextStyle(fontSize: 12, color: _C.dim)),
                      const SizedBox(width: 6),
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
      ],
    );
  }
}
