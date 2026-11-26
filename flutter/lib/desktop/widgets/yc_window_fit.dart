import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:window_size/window_size.dart' as window_size;

/// Local option that turns the window ratio lock off when set to 'N'.
const kYcFitWindow = 'yc-fit-window';

/// Keeps a session window at the remote screen's proportions, so the picture fills it with
/// no empty bands. The window plugin cannot lock a ratio while the user drags, so the
/// height is corrected once a resize has settled. Full screen and maximised windows are
/// left alone: there the screen decides the shape.
class YcWindowFit {
  final FFI ffi;
  Timer? _timer;
  Size? _canvas;
  String _done = '';
  String _display = '';

  YcWindowFit(this.ffi) {
    ffi.ffiModel.addListener(_onModel);
  }

  void dispose() {
    _timer?.cancel();
    ffi.ffiModel.removeListener(_onModel);
  }

  // The session model changes often; only a new remote screen size matters here.
  void _onModel() {
    final d =
        '${ffi.canvasModel.getDisplayWidth()}x${ffi.canvasModel.getDisplayHeight()}';
    if (d == _display) return;
    _display = d;
    _schedule();
  }

  void onCanvasSize(Size size) {
    if (_canvas == size) return;
    _canvas = size;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 450), _fit);
  }

  Future<void> _fit() async {
    final canvas = _canvas;
    if (canvas == null || !isDesktop || isWeb) return;
    if (bind.mainGetLocalOption(key: kYcFitWindow) == 'N') return;
    if (stateGlobal.fullscreen.value || stateGlobal.isMaximized.value) return;
    if (ffi.connType != ConnType.defaultConn) return;
    final rw = ffi.canvasModel.getDisplayWidth().toDouble();
    final rh = ffi.canvasModel.getDisplayHeight().toDouble();
    if (rw <= 0 || rh <= 0 || canvas.width <= 0 || canvas.height <= 0) return;
    final key =
        '${canvas.width.round()}x${canvas.height.round()}@${rw.round()}x${rh.round()}';
    if (key == _done) return;
    final viewStyle =
        await bind.sessionGetViewStyle(sessionId: ffi.sessionId) ?? '';
    if (viewStyle != kRemoteViewStyleAdaptive) return;
    final dh = canvas.width * rh / rw - canvas.height;
    if (dh.abs() < 2) {
      _done = key;
      return;
    }
    try {
      final screen = (await window_size.getWindowInfo()).screen;
      if (screen == null) return;
      // Windows frames are in physical pixels, Flutter sizes are logical.
      final scale = isWindows ? screen.scaleFactor : 1.0;
      final wc = WindowController.fromWindowId(stateGlobal.windowId);
      final f = await wc.getFrame();
      final area = screen.visibleFrame;
      var height = f.height + dh * scale;
      var width = f.width;
      if (height > area.height) {
        // Too tall for the screen: keep the height the screen allows and narrow instead.
        final over = height - area.height;
        height = area.height;
        width = f.width - over * rw / rh;
      }
      if (width < 360 || height < 240) return;
      var top = f.top;
      if (top + height > area.bottom) {
        top = math.max(area.top, area.bottom - height);
      }
      _done = key;
      await wc.setFrame(Rect.fromLTWH(f.left, top, width, height));
    } catch (e) {
      debugPrint('YcWindowFit: $e');
    }
  }
}
