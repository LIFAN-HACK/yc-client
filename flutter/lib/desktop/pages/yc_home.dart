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

/// Home screen of the YC build.
///
/// Signed out, it is one sign-in form. Signed in, it is the account's devices: all of them in
/// a sidebar, the selected one in the main area with a single primary action. There are no
/// ids to exchange and no passwords to type, so neither appears here.
class YcHome extends StatefulWidget {
  final YcNotice? notice;

  const YcHome({Key? key, this.notice}) : super(key: key);

  @override
  State<YcHome> createState() => _YcHomeState();
}

class _C {
  static const bg = Color(0xFFFFFFFF);
  static const side = Color(0xFFF5F6F8);
  static const card = Color(0xFFF7F8FA);
  static const hover = Color(0xFFECEEF2);
  static const line = Color(0xFFE9EBEF);
  static const text = Color(0xFF1D2129);
  static const sub = Color(0xFF4E5969);
  static const dim = Color(0xFF8A919F);
  static const accent = MyTheme.accent;
  static const off = Color(0xFFC4C9D2);
  static const danger = Color(0xFFE5484D);
  static const warnBg = Color(0xFFFFF6E8);
  static const warn = Color(0xFFB25E00);
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

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MyTheme.lightTheme,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 248, child: _sidebar(context)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.notice != null) _NoticeStrip(widget.notice!),
              Expanded(
                child: selected.isEmpty
                    ? _empty()
                    : _DevicePage(
                        device: selected.first,
                        isMe: selected.first.id == _myId),
              ),
              const _StatusBar(),
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
            padding: const EdgeInsets.fromLTRB(18, 18, 12, 14),
            child: Row(children: [
              loadIcon(26),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('YC 远程',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 34,
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
                      const BoxConstraints(minWidth: 36, minHeight: 34),
                  filled: true,
                  fillColor: _C.bg,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  border: _searchBorder(_C.line),
                  enabledBorder: _searchBorder(_C.line),
                  focusedBorder: _searchBorder(_C.accent),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 10, 6),
            child: Row(children: [
              Expanded(
                child: Text(
                    '我的设备${_devices.isEmpty ? '' : '  ${_devices.length}'}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _C.dim)),
              ),
              _IconBtn(
                  icon: Icons.refresh_rounded, tip: '刷新', onTap: _refresh),
            ]),
          ),
          Expanded(
            child: shown.isEmpty
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
                          if (d.id != _myId && d.online) connect(context, d.id);
                        },
                      );
                    }),
          ),
          Container(height: 1, color: _C.line),
          _account(),
        ],
      ),
    );
  }

  OutlineInputBorder _searchBorder(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
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
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Text(msg, style: const TextStyle(fontSize: 12.5, color: _C.dim)),
    );
  }

  Widget _account() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration:
              const BoxDecoration(color: _C.accent, shape: BoxShape.circle),
          child: Obx(() {
            final n = gFFI.userModel.displayNameOrUserName;
            return Text(n.isEmpty ? '?' : n.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white));
          }),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Obx(() => Text(gFFI.userModel.displayNameOrUserName,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ),
        PopupMenuButton<String>(
          tooltip: '菜单',
          padding: EdgeInsets.zero,
          color: _C.bg,
          elevation: 6,
          offset: const Offset(0, -96),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: _C.line)),
          icon: const Icon(Icons.menu_rounded, size: 18, color: _C.sub),
          onSelected: (v) {
            if (v == 'settings') DesktopTabPage.onAddSetting();
            if (v == 'logout') gFFI.userModel.logOut();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'settings',
                height: 38,
                child: Text('设置',
                    style: TextStyle(fontSize: 13, color: _C.text))),
            PopupMenuItem(
                value: 'logout',
                height: 38,
                child: Text('退出登录',
                    style: TextStyle(fontSize: 13, color: _C.text))),
          ],
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
      body = '在另一台电脑上安装 YC 远程并登录这个账号，它就会出现在左边。';
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.devices_rounded, size: 48, color: _C.off),
          const SizedBox(height: 16),
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: _C.dim, height: 1.6)),
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
        borderRadius: BorderRadius.circular(6),
        hoverColor: _C.hover,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: _C.dim),
        ),
      ),
    );
  }
}

class _OsTile extends StatelessWidget {
  final String os;
  final bool online;
  final double size;
  const _OsTile({required this.os, required this.online, this.size = 34});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: online ? _C.accent : _C.off,
          borderRadius: BorderRadius.circular(size * 0.24),
        ),
        child: Icon(_osIcon(os), size: size * 0.52, color: Colors.white),
      );
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
        color: selected ? _C.bg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onOpen,
          borderRadius: BorderRadius.circular(8),
          hoverColor: selected ? _C.bg : _C.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              _OsTile(os: d.os, online: d.online),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: d.online ? _C.text : _C.dim)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: d.online ? _C.accent : _C.off,
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                          '${d.online ? '在线' : '离线'}${isMe ? ' · 本机' : ''}',
                          style:
                              const TextStyle(fontSize: 11.5, color: _C.dim)),
                    ]),
                  ],
                ),
              ),
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
  const _DevicePage({required this.device, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final d = device;
    final canOpen = d.online && !isMe;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 30, 32, 24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                    color: _C.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _C.line)),
                child: Row(children: [
                  _OsTile(os: d.os, online: d.online, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                            [
                              _osLabel(d.os),
                              d.online ? '在线' : '离线',
                              if (isMe) '本机',
                            ].join('  ·  '),
                            style:
                                const TextStyle(fontSize: 13, color: _C.sub)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (!isMe)
                    _PrimaryBtn(
                      label: d.online ? '进入桌面' : '设备离线',
                      onTap: canOpen ? () => connect(context, d.id) : null,
                    ),
                ]),
              ),
              if (isMe) ...[
                const SizedBox(height: 14),
                Text(
                    d.ready
                        ? '这台电脑已就绪，登录同一账号的其他设备可以直接进入它的桌面。'
                        : '正在把这台电脑接入账号，稍等片刻…',
                    style: const TextStyle(
                        fontSize: 13, color: _C.sub, height: 1.6)),
              ] else ...[
                if (d.online && !d.ready) ...[
                  const SizedBox(height: 14),
                  const Text('这台电脑还没完成接入，进入时需要输入它的连接密码。',
                      style: TextStyle(fontSize: 13, color: _C.warn)),
                ],
                const SizedBox(height: 26),
                const Text('快捷功能',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _C.sub)),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _QuickTile(
                      icon: Icons.folder_open_rounded,
                      label: '文件传输',
                      onTap: canOpen
                          ? () => connect(context, d.id, isFileTransfer: true)
                          : null),
                  _QuickTile(
                      icon: Icons.terminal_rounded,
                      label: '终端',
                      onTap: canOpen
                          ? () => connect(context, d.id, isTerminal: true)
                          : null),
                  _QuickTile(
                      icon: Icons.videocam_outlined,
                      label: '摄像头',
                      onTap: canOpen
                          ? () => connect(context, d.id, isViewCamera: true)
                          : null),
                ]),
              ],
              const SizedBox(height: 26),
              const Text('设备信息',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _C.sub)),
              const SizedBox(height: 4),
              _InfoRow(
                  label: '设备码',
                  value: formatID(d.id),
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: d.id));
                    showToast('已复制');
                  }),
              _InfoRow(label: '系统', value: _osLabel(d.os)),
              if (d.owner.isNotEmpty) _InfoRow(label: '登录账号', value: d.owner),
              if (d.group.isNotEmpty) _InfoRow(label: '分组', value: d.group),
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
  const _PrimaryBtn({required this.label, this.onTap, this.width = 132});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Material(
      color: on ? _C.accent : _C.hover,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.black.withOpacity(0.06),
        child: Container(
          width: width,
          height: 40,
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: on ? Colors.white : _C.dim)),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _QuickTile({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Material(
      color: _C.card,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _C.line)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: _C.hover,
        child: SizedBox(
          width: 132,
          height: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: on ? _C.accent : _C.off),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(fontSize: 13, color: on ? _C.text : _C.dim)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;
  const _InfoRow({required this.label, required this.value, this.onCopy});

  @override
  Widget build(BuildContext context) => Container(
        height: 42,
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _C.line))),
        child: Row(children: [
          SizedBox(
            width: 88,
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
        color: _C.warnBg,
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
              color: _C.bg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: const BorderSide(color: Color(0xFFF3D9B1))),
              child: InkWell(
                onTap: notice.onAction,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Text(notice.action,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _C.warn)),
                ),
              ),
            ),
          ],
        ]),
      );
}

/// Whether this computer is reachable, in one quiet line.
class _StatusBar extends StatefulWidget {
  const _StatusBar();

  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {
  Timer? _timer;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _timer = periodic_immediate(const Duration(seconds: 1), _poll);
    bind.mainGetVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
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
  Widget build(BuildContext context) {
    final stopped = Get.isRegistered<RxBool>(tag: 'stop-service')
        ? Get.find<RxBool>(tag: 'stop-service')
        : false.obs;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _C.line))),
      child: Obx(() {
        final Color color;
        final String text;
        if (stopped.value) {
          color = _C.off;
          text = '本机已暂停被控';
        } else {
          switch (stateGlobal.svcStatus.value) {
            case SvcStatus.ready:
              color = _C.accent;
              text = '已连接';
              break;
            case SvcStatus.connecting:
              color = const Color(0xFFF5A623);
              text = '正在连接…';
              break;
            default:
              color = _C.danger;
              text = '未连接，请检查网络';
          }
        }
        return Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 12, color: _C.sub)),
          if (stopped.value) ...[
            const SizedBox(width: 10),
            InkWell(
              onTap: () => start_service(true),
              child: const Text('恢复',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _C.accent)),
            ),
          ],
          const Spacer(),
          if (_version.isNotEmpty)
            Text('版本 $_version',
                style: const TextStyle(fontSize: 12, color: _C.dim)),
        ]);
      }),
    );
  }
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
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c, width: 1));

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _C.dim, fontSize: 14),
        filled: true,
        fillColor: _C.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: _border(_C.line),
        enabledBorder: _border(_C.line),
        disabledBorder: _border(_C.line),
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
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(child: loadIcon(56)),
                    const SizedBox(height: 18),
                    const Text('登录 YC 远程',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('登录同一账号的设备可以互相远程控制',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: _C.dim)),
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
                    const Text('没有账号？请联系管理员开通',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: _C.dim)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const _StatusBar(),
      ],
    );
  }
}
