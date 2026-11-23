import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';

import '../common/hbbs/hbbs.dart';
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

  /// Signs in with a team account and enrolls this device. Returns null on success, otherwise
  /// a message to show next to the form.
  static Future<String?> signIn(String username, String password) async {
    try {
      final resp = await gFFI.userModel.login(LoginRequest(
          username: username,
          password: password,
          id: await bind.mainGetMyId(),
          uuid: await bind.mainGetUuid(),
          autoLogin: true,
          type: HttpType.kAuthReqTypeAccount));
      final token = resp.access_token;
      if (resp.type != HttpType.kAuthResTypeToken || token == null) {
        return '这个账号需要额外验证，请联系管理员';
      }
      await bind.mainSetLocalOption(key: 'access_token', value: token);
      await bind.mainSetLocalOption(
          key: 'user_info', value: jsonEncode(resp.user ?? {}));
      await enroll();
      return null;
    } on RequestException catch (e) {
      return e.cause.isEmpty ? '登录失败（${e.statusCode}）' : translate(e.cause);
    } catch (e) {
      debugPrint('yc: sign-in failed: $e');
      return '连不上服务器，请检查网络后重试';
    }
  }

  /// The team's computers. Throws when the list cannot be fetched.
  static Future<List<YcDevice>> devices() async {
    final api = await bind.mainGetApiServer();
    final resp = await http
        .get(Uri.parse('$api/api/yc/devices'), headers: getHttpHeaders())
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw RequestException(resp.statusCode, 'HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    final list = decoded is Map ? decoded['devices'] : null;
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((m) => YcDevice.fromJson(Map<String, dynamic>.from(m)))
        .toList();
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

/// One computer of the team, as the account service reports it.
class YcDevice {
  final String id;
  final String name;
  final String os;
  final String group;
  final String owner;
  final bool online;

  /// The device has escrowed its connection secret, so connecting needs no password.
  final bool ready;

  const YcDevice({
    required this.id,
    required this.name,
    required this.os,
    required this.group,
    required this.owner,
    required this.online,
    required this.ready,
  });

  factory YcDevice.fromJson(Map<String, dynamic> j) => YcDevice(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? j['id'] ?? ''}',
        os: '${j['os'] ?? ''}',
        group: '${j['group'] ?? ''}',
        owner: '${j['owner'] ?? ''}',
        online: j['online'] == true,
        ready: j['ready'] == true,
      );
}
