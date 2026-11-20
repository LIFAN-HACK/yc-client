import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';

import '../utils/http_service.dart' as http;
import 'platform_model.dart';

/// Team sign-in for the YC build.
///
/// Signing in is all it takes for a device to join the team: the client gives itself a random
/// connection secret and escrows it with the team's own account service. Other signed-in
/// members get that secret from the service when they connect, so nobody types or even sees a
/// device password. Signing out rotates the secret locally, which locks everyone out again.
class YcTeam {
  static const _kEnrolled = 'yc-enrolled';
  static const _alphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

  static String _randomSecret() {
    final rng = Random.secure();
    return List.generate(32, (_) => _alphabet[rng.nextInt(_alphabet.length)])
        .join();
  }

  /// iOS and the web client can only control other devices, so they have nothing to enroll.
  static bool get _canBeControlled => !isWeb && !isIOS;

  static bool get _signedIn =>
      bind.mainGetLocalOption(key: 'access_token').isNotEmpty;

  static Future<Map<String, dynamic>?> _post(
      String path, Map<String, dynamic> body) async {
    final api = await bind.mainGetApiServer();
    if (api.isEmpty) return null;
    final headers = getHttpHeaders();
    headers['Content-Type'] = 'application/json';
    final resp = await http
        .post(Uri.parse('$api$path'), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      debugPrint('yc: $path failed with HTTP ${resp.statusCode}');
      return null;
    }
    final decoded = jsonDecode(resp.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Gives this device a fresh connection secret and registers it with the account service.
  static Future<void> enroll() async {
    if (!_canBeControlled || !_signedIn) return;
    try {
      final secret = _randomSecret();
      final ok =
          await bind.mainSetPermanentPasswordWithResult(password: secret);
      if (!ok) {
        debugPrint('yc: could not set the connection secret on this device');
        return;
      }
      await bind.mainSetOption(
          key: kOptionVerificationMethod, value: 'use-permanent-password');
      await bind.mainSetOption(key: kOptionApproveMode, value: 'password');
      final res = await _post('/api/yc/enroll',
          {'id': await bind.mainGetMyId(), 'secret': secret});
      await bind.mainSetLocalOption(
          key: _kEnrolled, value: res == null ? '' : 'Y');
    } catch (e) {
      debugPrint('yc: enroll failed: $e');
    }
  }

  static Future<void> ensureEnrolled() async {
    if (bind.mainGetLocalOption(key: _kEnrolled) != 'Y') await enroll();
  }

  /// Returns the connection secret of team device [id], or null when [id] is not a team device
  /// (the normal password prompt then applies).
  static Future<String?> secretFor(String id) async {
    if (!_signedIn) return null;
    try {
      // Strip "@server" / "?key=" decorations; the service only knows plain ids.
      final plain = id.split('@').first.split('?').first.replaceAll('/r', '');
      final res = await _post('/api/yc/connect', {'id': plain});
      final secret = res?['secret'];
      return secret is String && secret.isNotEmpty ? secret : null;
    } catch (e) {
      debugPrint('yc: could not fetch the connection secret: $e');
      return null;
    }
  }

  /// Called on sign-out: rotate the local secret so the escrowed one stops working.
  static Future<void> leave() async {
    if (!_canBeControlled) return;
    if (bind.mainGetLocalOption(key: _kEnrolled) != 'Y') return;
    try {
      await bind.mainSetPermanentPasswordWithResult(password: _randomSecret());
      await bind.mainSetLocalOption(key: _kEnrolled, value: '');
    } catch (e) {
      debugPrint('yc: leave failed: $e');
    }
  }
}
