import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A small picture of each remote screen, kept on this computer only, so the home page can
/// show what a device looked like last time instead of a plain card (UU shows the remote
/// wallpaper there). Taken a few seconds into a session and then every half minute.
class YcSnapshot {
  static const _width = 640.0;
  static final Map<String, (DateTime, Future<Uint8List?>)> _cache = {};

  static Future<File> _file(String id) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'yc_thumbs'));
    await dir.create(recursive: true);
    final safe = id.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_');
    return File(p.join(dir.path, '$safe.png'));
  }

  /// Starts taking snapshots of [id]'s screen for as long as the returned timer runs.
  static Timer track(FFI ffi, String id) {
    Future<void> take() async {
      final img = ffi.imageModel.image;
      if (img == null || img.width <= 0 || img.height <= 0) return;
      ui.Image? copy;
      try {
        copy = img.clone();
        await _save(id, copy);
      } catch (_) {
        // A frame that is replaced mid-copy is simply skipped.
      } finally {
        copy?.dispose();
      }
    }

    var first = true;
    return Timer.periodic(const Duration(seconds: 5), (t) {
      if (first || t.tick % 6 == 0) {
        first = false;
        take();
      }
    });
  }

  static Future<void> _save(String id, ui.Image img) async {
    final scale = _width / img.width;
    final h = (img.height * scale).round();
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(0, 0, _width, h.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium);
    final out = await rec.endRecording().toImage(_width.toInt(), h);
    try {
      final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final f = await _file(id);
      await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    } finally {
      out.dispose();
    }
  }

  /// The last snapshot of [id], re-read at most every half minute.
  static Future<Uint8List?> load(String id) {
    final hit = _cache[id];
    if (hit != null && DateTime.now().difference(hit.$1).inSeconds < 30) {
      return hit.$2;
    }
    final f = () async {
      try {
        final file = await _file(id);
        return await file.exists() ? await file.readAsBytes() : null;
      } catch (_) {
        return null;
      }
    }();
    _cache[id] = (DateTime.now(), f);
    return f;
  }
}
