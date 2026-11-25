import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/yc_team.dart';
import 'package:window_manager/window_manager.dart';

const _panel = Color(0xFF1A1719);
const _raised = Color(0xFF262124);
const _line = Color(0xFF2E2A2D);
const _text = Color(0xFFF5EFEA);
const _sub = Color(0xFFB3A9A3);
const _online = Color(0xFF5FD38D);
const _danger = Color(0xFFFF8A8A);

const double _cardHeight = 76;
const double _gap = 8;
const double _pad = 10;
const double _width = 340;

/// When each connection was first seen, so a card keeps its timer across rebuilds.
final Map<int, DateTime> _since = {};

/// Names the account gives its devices, looked up once per process.
Map<String, String>? _names;
Future<void>? _loadingNames;

/// The controlled side's view of who is connected: one small card per connection in the
/// corner of the screen, in place of the stock window of permission buttons. A team member
/// is already trusted by the account, so there is nothing to approve or switch here.
class YcCmCards extends StatefulWidget {
  final List<Client> clients;
  const YcCmCards({Key? key, required this.clients}) : super(key: key);

  /// True when every connection is one the card can show: none waits for approval.
  static bool canShow(List<Client> clients) =>
      clients.isNotEmpty &&
      clients.every((c) => c.authorized || c.disconnected);

  @override
  State<YcCmCards> createState() => _YcCmCardsState();
}

class _YcCmCardsState extends State<YcCmCards> {
  Timer? _tick;
  Size? _applied;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadingNames ??= _loadNames();
    _loadingNames!.then((_) {
      if (mounted) setState(() {});
    });
  }

  static Future<void> _loadNames() async {
    try {
      final list = await YcTeam.devices();
      _names = {for (final d in list) d.id: d.name};
    } catch (_) {
      _names = {};
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    // The stock layout needs its own size back if it takes over again.
    windowManager.setSizeAlignment(
        kConnectionManagerWindowSizeClosedChat, Alignment.topRight);
    super.dispose();
  }

  void _fitWindow(int count) {
    final size =
        Size(_width, _pad * 2 + count * _cardHeight + (count - 1) * _gap);
    if (_applied == size) return;
    _applied = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      windowManager.setSizeAlignment(size, Alignment.bottomRight);
    });
  }

  @override
  Widget build(BuildContext context) {
    final clients = widget.clients;
    _fitWindow(clients.length);
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => windowManager.startDragging(),
        child: Container(
          color: const Color(0xFF121014),
          padding: const EdgeInsets.all(_pad),
          child: Column(children: [
            for (var i = 0; i < clients.length; i++) ...[
              if (i > 0) const SizedBox(height: _gap),
              _card(clients[i]),
            ],
          ]),
        ),
      ),
    );
  }

  String _elapsed(Client c) {
    final start = _since.putIfAbsent(c.id, () => DateTime.now());
    final s = DateTime.now().difference(start).inSeconds;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(s ~/ 3600)}:${two(s ~/ 60 % 60)}:${two(s % 60)}';
  }

  Widget _card(Client c) {
    final name = (_names?[c.peerId] ?? '').isNotEmpty
        ? _names![c.peerId]!
        : (c.name.isNotEmpty ? c.name : c.peerId);
    final String doing;
    if (c.disconnected) {
      doing = '已断开';
    } else if (c.isFileTransfer) {
      doing = '正在传输文件';
    } else if (c.isTerminal) {
      doing = '正在使用终端';
    } else if (c.isViewCamera) {
      doing = '正在查看摄像头';
    } else if (!c.keyboard) {
      doing = '正在观看本机';
    } else {
      doing = '正在控制本机';
    }
    return Container(
      height: _cardHeight,
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: c.disconnected ? _sub : _online, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$name $doing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _text)),
              const SizedBox(height: 4),
              Text(c.disconnected ? '连接已结束' : '同一账号的设备 · ${_elapsed(c)}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: _sub,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: _raised,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => c.disconnected ? _remove(c) : _disconnect(c),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(c.disconnected ? '关闭' : '断开',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.disconnected ? _sub : _danger)),
            ),
          ),
        ),
      ]),
    );
  }

  void _disconnect(Client c) {
    bind.cmCloseConnection(connId: c.id);
  }

  Future<void> _remove(Client c) async {
    _since.remove(c.id);
    await bind.cmRemoveDisconnectedConnection(connId: c.id);
    if (await bind.cmGetClientsLength() == 0) {
      windowManager.close();
    }
  }
}
