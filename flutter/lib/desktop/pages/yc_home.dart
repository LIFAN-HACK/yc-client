import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

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
  static const bg = Color(0xFF121014);
  static const side = Color(0xFF161316);
  static const panel = Color(0xFF1A1719);
  static const raised = Color(0xFF231F22);
  static const hover = Color(0xFF1D1A1C);
  static const line = Color(0xFF2A2629);
  static const line2 = Color(0xFF2E2A2D);
  static const text = Color(0xFFF5EFEA);
  static const sub = Color(0xFFB3A9A3);
  static const dim = Color(0xFF8C827C);
  static const accent = Color(0xFFF28C6B);
  static const ink = Color(0xFF1A1214);
  static const online = Color(0xFF5FD38D);
  static const danger = Color(0xFFFF8A8A);
  static const warn = Color(0xFFF5B74E);
  static const grad = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF7A27F), Color(0xFFEE7A5A)]);
  static const wallpaper = RadialGradient(
      center: Alignment(0.7, -1.0),
      radius: 1.35,
      stops: [
        0,
        0.32,
        0.66,
        1
      ],
      colors: [
        Color(0xFFF7A27F),
        Color(0xFFD9667A),
        Color(0xFF4A2A4F),
        Color(0xFF1A1719)
      ]);
  static const wallpaperOff = RadialGradient(
      center: Alignment(0.7, -1.0),
      radius: 1.35,
      stops: [0, 0.6, 1],
      colors: [Color(0xFF5A5155), Color(0xFF2D282B), Color(0xFF1A1719)]);
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

String _ago(int seconds) {
  final d = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(seconds * 1000));
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inDays < 1) return '${d.inHours} 小时前';
  if (d.inDays < 30) return '${d.inDays} 天前';
  return '很久以前';
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
  Set<String> _pinned = {};
  DateTime? _controlledSince;
  Timer? _timer;
  Timer? _statusTimer;
  Worker? _userWatch;

  @override
  void initState() {
    super.initState();
    _pinned = bind
        .mainGetLocalOption(key: 'yc-pinned')
        .split(',')
        .where((e) => e.isNotEmpty)
        .toSet();
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
      if (count is int) {
        if (count > 0) {
          _controlledSince ??= DateTime.now();
        } else {
          _controlledSince = null;
        }
        stateGlobal.videoConnCount.value = count;
      }
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
      // This computer first, then pinned ones, then online ones, then by name.
      list.sort((a, b) {
        final am = a.id == _myId ? 0 : 1, bm = b.id == _myId ? 0 : 1;
        if (am != bm) return am - bm;
        final ap = _pinned.contains(a.id) ? 0 : 1,
            bp = _pinned.contains(b.id) ? 0 : 1;
        if (ap != bp) return ap - bp;
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

  /// Opens the device's desktop. The session reads `yc-view-once` when it starts, so the
  /// choice between controlling and only watching is made here, not remembered per device.
  Future<void> _open(YcDevice d, {bool viewOnly = false}) async {
    if (d.id == _myId || !d.online) return;
    await bind.mainSetLocalOption(
        key: 'yc-view-once', value: viewOnly ? d.id : '');
    await bind.mainSetLocalOption(key: 'yc-restart-once', value: '');
    if (mounted) connect(context, d.id);
  }

  /// Restarting is a command of a live session, so this opens one and has it send the
  /// command as soon as it is connected.
  Future<void> _restart(YcDevice d) async {
    if (d.id == _myId || !d.online) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: MyTheme.darkTheme,
        child: AlertDialog(
          backgroundColor: _C.panel,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _C.line)),
          title: const Text('远程重启',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: _C.text)),
          content: SizedBox(
            width: 320,
            child: Text('确定要重启“${d.name}”吗？那台电脑上没保存的内容会丢失。重启完成后会自动重新连上。',
                style:
                    const TextStyle(fontSize: 13, color: _C.sub, height: 1.6)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消', style: TextStyle(color: _C.sub))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('重启',
                    style: TextStyle(
                        color: _C.danger, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await bind.mainSetLocalOption(key: 'yc-view-once', value: '');
    await bind.mainSetLocalOption(key: 'yc-restart-once', value: d.id);
    if (mounted) connect(context, d.id);
  }

  Future<void> _togglePin(YcDevice d) async {
    setState(() {
      if (!_pinned.remove(d.id)) _pinned.add(d.id);
    });
    await bind.mainSetLocalOption(key: 'yc-pinned', value: _pinned.join(','));
    await _refresh();
  }

  void _copyId(YcDevice d) {
    Clipboard.setData(ClipboardData(text: d.id));
    showToast('已复制设备码');
  }

  Future<void> _disconnectAll() async {
    await start_service(false);
    await Future.delayed(const Duration(milliseconds: 1500));
    await start_service(true);
    showToast('已断开');
  }

  Future<void> _rowMenu(YcDevice d, Offset at) async {
    final isMe = d.id == _myId;
    final canOpen = d.online && !isMe;
    final size = MediaQuery.of(context).size;
    PopupMenuItem<String> item(String v, String t,
            {bool on = true, Color? color}) =>
        PopupMenuItem(
            value: v,
            enabled: on,
            height: 36,
            child: Text(t,
                style: TextStyle(
                    fontSize: 13, color: on ? (color ?? _C.text) : _C.dim)));
    final v = await showMenu<String>(
      context: context,
      color: _C.raised,
      elevation: 8,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _C.line)),
      position: RelativeRect.fromLTRB(
          at.dx, at.dy, size.width - at.dx, size.height - at.dy),
      items: [
        if (!isMe) item('open', '进入桌面', on: canOpen),
        if (!isMe) item('view', '观看模式', on: canOpen),
        if (!isMe) item('file', '文件传输', on: canOpen),
        if (!isMe) const PopupMenuDivider(height: 8),
        item('rename', '重命名'),
        if (!isMe) item('pin', _pinned.contains(d.id) ? '取消置顶' : '置顶'),
        item('copy', '复制设备码'),
        if (!isMe) const PopupMenuDivider(height: 8),
        if (!isMe) item('restart', '远程重启', on: canOpen),
        if (!isMe) item('remove', '从账号移除', color: _C.danger),
      ],
    );
    if (!mounted || v == null) return;
    setState(() => _selected = d.id);
    if (v == 'open') _open(d);
    if (v == 'view') _open(d, viewOnly: true);
    if (v == 'file') connect(context, d.id, isFileTransfer: true);
    if (v == 'rename') _rename(d);
    if (v == 'pin') _togglePin(d);
    if (v == 'copy') _copyId(d);
    if (v == 'restart') _restart(d);
    if (v == 'remove') _remove(d);
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
                        pinned: _pinned.contains(d.id),
                        onOpen: () => _open(d),
                        onView: () => _open(d, viewOnly: true),
                        onPin: () => _togglePin(d),
                        onRestart: () => _restart(d),
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
              Image.asset('assets/mark_warm.png', width: 26, height: 26),
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
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('本机被控中',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _C.ink)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Flexible(
                          child: Text('$n 台设备 · ',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: _C.ink)),
                        ),
                        _Elapsed(since: _controlledSince ?? DateTime.now()),
                      ]),
                    ],
                  ),
                ),
                Material(
                  color: _C.ink,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: _disconnectAll,
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Text('断开',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _C.text)),
                    ),
                  ),
                ),
              ]),
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
                            pinned: _pinned.contains(d.id),
                            onTap: () => setState(() => _selected = d.id),
                            onOpen: () => _open(d),
                            onMenu: (at) => _rowMenu(d, at),
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
            if (stopped.value) 'resume': '恢复本机被控' else 'pause': '暂停本机被控',
            'logout': '退出登录',
          },
          onSelected: (v) {
            if (v == 'settings') DesktopTabPage.onAddSetting();
            if (v == 'resume') start_service(true);
            if (v == 'pause') start_service(false);
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
  final Color color;
  const _IconBtn(
      {required this.icon,
      required this.tip,
      required this.onTap,
      this.color = _C.sub});

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
          child: Icon(icon, size: 17, color: color),
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
  final Color iconColor;
  const _Menu(
      {required this.icon,
      required this.items,
      required this.onSelected,
      this.above = false,
      this.iconColor = _C.sub});

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
        icon: Icon(icon, size: 18, color: iconColor),
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
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final void Function(Offset) onMenu;
  const _DeviceRow(
      {required this.device,
      required this.isMe,
      required this.selected,
      required this.pinned,
      required this.onTap,
      required this.onOpen,
      required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final d = device;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? const Color(0xFF2A2427) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onOpen,
          onSecondaryTapDown: (e) => onMenu(e.globalPosition),
          borderRadius: BorderRadius.circular(12),
          hoverColor: selected ? const Color(0xFF2A2427) : _C.hover,
          child: SizedBox(
            height: 48,
            child: Row(children: [
              const SizedBox(width: 10),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: selected && d.online ? _C.grad : null,
                  color: selected && d.online
                      ? null
                      : (d.online
                          ? const Color(0xFF262124)
                          : const Color(0xFF1D1A1C)),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(_osIcon(d.os),
                    size: 15,
                    color: selected && d.online
                        ? _C.ink
                        : (d.online ? _C.text : _C.dim)),
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
              if (pinned && !isMe)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.push_pin_rounded, size: 12, color: _C.dim),
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
              if (d.online || isMe)
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      color: _C.online, shape: BoxShape.circle),
                )
              else if (d.lastSeen > 0)
                Text(_ago(d.lastSeen),
                    style: const TextStyle(fontSize: 11, color: _C.dim)),
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
  final bool pinned;
  final VoidCallback onOpen;
  final VoidCallback onView;
  final VoidCallback onPin;
  final VoidCallback onRestart;
  final VoidCallback onRename;
  final VoidCallback onRemove;
  const _DevicePage(
      {required this.device,
      required this.isMe,
      required this.pinned,
      required this.onOpen,
      required this.onView,
      required this.onPin,
      required this.onRestart,
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
    final String sub;
    if (isMe) {
      sub = d.ready ? '这是本机 · 同一账号的设备可以直接进入' : '正在把本机接入账号…';
    } else if (!d.online) {
      sub = d.lastSeen > 0
          ? '离线 · 最近在线 ${_lastSeen(d.lastSeen)}'
          : '离线 · 上线后即可进入';
    } else if (!d.ready) {
      sub = '尚未完成接入，进入时需要输入连接密码';
    } else {
      sub = '同一账号 · 免密进入';
    }
    final live = d.online || isMe;
    return LayoutBuilder(builder: (context, box) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(36, 30, 36, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 300,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: live ? _C.wallpaper : _C.wallpaperOff,
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x73000000),
                          blurRadius: 50,
                          offset: Offset(0, 24))
                    ],
                  ),
                  child: Stack(children: [
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.45, 1],
                            colors: [Color(0x00121014), Color(0xD1121014)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 18,
                      child: _GlassPill(children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: live ? _C.online : _C.dim,
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text('${live ? '在线' : '离线'} · ${_osLabel(d.os)}',
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: _C.text)),
                      ]),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        decoration: BoxDecoration(
                            color: const Color(0x8C121014),
                            borderRadius: BorderRadius.circular(9)),
                        child: _Menu(
                          icon: Icons.more_horiz_rounded,
                          iconColor: _C.text,
                          items: {
                            'rename': '重命名',
                            'copy': '复制设备码',
                            if (canOpen) 'camera': '查看摄像头',
                            if (!isMe) 'pin': pinned ? '取消置顶' : '置顶',
                            if (!isMe) 'remove': '从账号移除',
                          },
                          onSelected: (v) {
                            if (v == 'rename') onRename();
                            if (v == 'pin') onPin();
                            if (v == 'copy') _copy();
                            if (v == 'remove') onRemove();
                            if (v == 'camera') {
                              connect(context, d.id, isViewCamera: true);
                            }
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      left: 22,
                      right: 22,
                      bottom: 20,
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(children: [
                                    Flexible(
                                      child: Text(d.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.w800,
                                              color: _C.text)),
                                    ),
                                    const SizedBox(width: 4),
                                    _IconBtn(
                                        icon: Icons.edit_outlined,
                                        tip: '重命名',
                                        color: _C.text,
                                        onTap: onRename),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(sub,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          color: Color(0xFFD9CDC6))),
                                ],
                              ),
                            ),
                            if (!isMe) ...[
                              const SizedBox(width: 16),
                              _EnterBtn(
                                  label: d.online ? '进入桌面' : '设备离线',
                                  onTap: canOpen ? onOpen : null),
                            ],
                          ]),
                    ),
                  ]),
                ),
                if (!isMe) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    _ActionChip(
                        icon: Icons.folder_open_rounded,
                        label: '文件传输',
                        onTap: canOpen
                            ? () => connect(context, d.id, isFileTransfer: true)
                            : null),
                    const SizedBox(width: 10),
                    _ActionChip(
                        icon: Icons.visibility_outlined,
                        label: '观看模式',
                        onTap: canOpen ? onView : null),
                    const SizedBox(width: 10),
                    _ActionChip(
                        icon: Icons.terminal_rounded,
                        label: '终端',
                        onTap: canOpen
                            ? () => connect(context, d.id, isTerminal: true)
                            : null),
                    const SizedBox(width: 10),
                    _ActionChip(
                        icon: Icons.restart_alt_rounded,
                        label: '远程重启',
                        onTap: canOpen ? onRestart : null),
                  ]),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  _StatCard(
                      label: '设备码',
                      value: formatID(d.id),
                      onTap: _copy,
                      tip: '点击复制'),
                  const SizedBox(width: 10),
                  _StatCard(label: '系统', value: _osLabel(d.os)),
                  const SizedBox(width: 10),
                  _StatCard(
                      label: '登录账号', value: d.owner.isNotEmpty ? d.owner : '—'),
                ]),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _GlassPill extends StatelessWidget {
  final List<Widget> children;
  const _GlassPill({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: const Color(0x8C121014),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _EnterBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _EnterBtn({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Material(
      color: on ? _C.text : const Color(0x66121014),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: on ? _C.ink : _C.sub)),
              if (on) ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded,
                    size: 17, color: _C.ink),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ActionChip({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Expanded(
      child: Material(
        color: _C.panel,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _C.line2)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          hoverColor: _C.raised,
          child: SizedBox(
            height: 64,
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: on ? _C.accent : _C.dim),
              const SizedBox(height: 7),
              Text(label,
                  style:
                      TextStyle(fontSize: 12.5, color: on ? _C.text : _C.dim)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? tip;
  const _StatCard(
      {required this.label, required this.value, this.onTap, this.tip});

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: _C.panel,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _C.line2)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: _C.raised,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11.5, color: _C.dim)),
              const SizedBox(height: 6),
              Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _C.text)),
            ],
          ),
        ),
      ),
    );
    return Expanded(
        child: tip == null
            ? card
            : Tooltip(
                message: tip!,
                waitDuration: const Duration(milliseconds: 500),
                child: card));
  }
}

class _Elapsed extends StatefulWidget {
  final DateTime since;
  const _Elapsed({required this.since});

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = DateTime.now().difference(widget.since).inSeconds;
    String two(int v) => v.toString().padLeft(2, '0');
    return Text('${two(s ~/ 3600)}:${two(s ~/ 60 % 60)}:${two(s % 60)}',
        style: const TextStyle(
            fontSize: 11.5,
            color: _C.ink,
            fontFeatures: [FontFeature.tabularFigures()]));
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double width;
  final double height;
  const _PrimaryBtn(
      {required this.label, this.onTap, this.width = 168, this.height = 44});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Container(
      width: width,
      height: height,
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
        fillColor: const Color(0x0FFFFFFF),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: _border(const Color(0x14FFFFFF)),
        enabledBorder: _border(const Color(0x14FFFFFF)),
        disabledBorder: _border(const Color(0x14FFFFFF)),
        focusedBorder: _border(_C.accent),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.notice != null) _NoticeStrip(widget.notice!),
        Expanded(child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 760;
          return Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0xFFF3A48C)),
            Image.asset('assets/login_poster.jpg',
                fit: BoxFit.cover, alignment: const Alignment(-0.4, -0.1)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: [0.3, 0.62, 1],
                  colors: [
                    Color(0x00121014),
                    Color(0x59121014),
                    Color(0x99121014)
                  ],
                ),
              ),
            ),
            Positioned(
              left: 36,
              top: 40,
              child: Row(children: [
                Image.asset('assets/mark_white.png',
                    width: 28, height: 28, color: _posterInk),
                const SizedBox(width: 10),
                const Text('OpenDesk',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _posterInk)),
              ]),
            ),
            if (wide)
              const Positioned(
                left: 36,
                bottom: 40,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('每一台电脑，\n都在你手边。',
                          style: TextStyle(
                              fontSize: 30,
                              height: 1.3,
                              fontWeight: FontWeight.w800,
                              color: _posterInk)),
                      SizedBox(height: 10),
                      Text('登录即互联 · 免密进入 · 自己的服务器',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF6B3A2C))),
                    ]),
              ),
            Align(
              alignment: wide ? const Alignment(0.86, 0) : Alignment.center,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _card(),
              ),
            ),
          ]);
        })),
      ],
    );
  }

  static const _posterInk = Color(0xFF3A2018);

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 12, color: _C.sub)),
      );

  Widget _card() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: 340,
          padding: const EdgeInsets.fromLTRB(30, 34, 30, 26),
          decoration: BoxDecoration(
            color: const Color(0xCC161316),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x14FFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('欢迎回来',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _C.text)),
              const SizedBox(height: 8),
              const Text('登录同一账号的设备可以互相远程控制',
                  style: TextStyle(fontSize: 13, color: _C.sub)),
              const SizedBox(height: 26),
              _label('账号'),
              TextField(
                controller: _user,
                autofocus: true,
                enabled: !_busy,
                cursorColor: _C.accent,
                style: const TextStyle(fontSize: 14, color: _C.text),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _passFocus.requestFocus(),
                decoration: _field('请输入账号'),
              ),
              const SizedBox(height: 14),
              _label('密码'),
              TextField(
                controller: _pass,
                focusNode: _passFocus,
                enabled: !_busy,
                obscureText: true,
                cursorColor: _C.accent,
                style: const TextStyle(fontSize: 14, color: _C.text),
                onSubmitted: (_) => _submit(),
                decoration: _field('请输入密码'),
              ),
              SizedBox(
                height: 30,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error ?? '',
                      style: const TextStyle(fontSize: 12.5, color: _C.danger)),
                ),
              ),
              _PrimaryBtn(
                  label: _busy ? '正在登录…' : '登录',
                  width: double.infinity,
                  height: 48,
                  onTap: _busy ? null : _submit),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('没有账号？请联系管理员开通',
                    style: TextStyle(fontSize: 12, color: _C.dim)),
                const SizedBox(width: 4),
                _IconBtn(
                    icon: Icons.settings_outlined,
                    tip: '设置',
                    onTap: () => DesktopTabPage.onAddSetting()),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
