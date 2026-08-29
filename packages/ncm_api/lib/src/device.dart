import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as c;

/// Client OS profile — drives os/appver/osver/channel + User-Agent, matching
/// the values the current Netease clients send. A realistic, self-consistent
/// profile is what keeps login off the "device risk" path.
enum OsProfile { pc, android, iphone, osx, linux }

class _OsInfo {
  const _OsInfo({
    required this.os,
    required this.appver,
    required this.osver,
    required this.channel,
    required this.weapiUa,
    required this.apiUa,
  });
  final String os;
  final String appver;
  final String osver;
  final String channel;
  final String weapiUa;
  final String apiUa;
}

/// Stable device identity for one install.
///
/// Netease fingerprints the requesting client via a large cookie set
/// (deviceId, _ntes_nuid/_nnid, WNMCID, WEVNSM, osver, channel, appver …).
/// An empty/partial set + a stale anonymous token reads as an untrusted
/// device and trips risk control on login. This class synthesizes a complete,
/// self-consistent set and persists it via [toMap]/[fromMap] so the identity
/// is stable across launches (a device that changes fingerprint every request
/// is itself suspicious).
class Device {
  Device({
    required this.deviceId,
    required this.ntesNuid,
    required this.wnmcid,
    this.profile = OsProfile.pc,
  });

  /// 52 uppercase hex chars — the format the official client uses.
  final String deviceId;

  /// 32-byte random hex; seeds _ntes_nuid / _ntes_nnid.
  final String ntesNuid;

  /// `{6 lowercase}.{ms}.01.0`
  final String wnmcid;

  final OsProfile profile;

  static final Random _rng = Random.secure();

  /// Create a fresh identity (call once per install, then persist).
  factory Device.generate({OsProfile profile = OsProfile.pc}) {
    return Device(
      deviceId: _randomHexUpper(52),
      ntesNuid: _randomHexLower(32),
      wnmcid: '${_randomLowerAlpha(6)}.${DateTime.now().millisecondsSinceEpoch}.01.0',
      profile: profile,
    );
  }

  static const Map<OsProfile, _OsInfo> _osMap = {
    OsProfile.pc: _OsInfo(
      os: 'pc',
      appver: '3.1.17.204416',
      osver: 'Microsoft-Windows-10-Professional-build-19045-64bit',
      channel: 'netease',
      weapiUa:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0',
      apiUa:
          'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/3.1.29.205117',
    ),
    OsProfile.osx: _OsInfo(
      os: 'osx',
      appver: '3.1.10.5100',
      osver: '15.5',
      channel: 'netease',
      weapiUa:
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0',
      apiUa:
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/3.1.29.205117',
    ),
    OsProfile.android: _OsInfo(
      os: 'android',
      appver: '8.20.20.231215173437',
      osver: '14',
      channel: 'xiaomi',
      weapiUa:
          'Mozilla/5.0 (Linux; Android 14; 23013RK75C Build/UKQ1.230804.001) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      apiUa:
          'NeteaseMusic/9.1.65.240927161425(9001065);Dalvik/2.1.0 (Linux; U; Android 14; 23013RK75C Build/UKQ1.230804.001)',
    ),
    OsProfile.iphone: _OsInfo(
      os: 'iPhone OS',
      appver: '9.0.90',
      osver: '16.2',
      channel: 'distribution',
      weapiUa:
          'Mozilla/5.0 (iPhone; CPU iPhone OS 16_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Mobile/15E148 Safari/604.1',
      apiUa: 'NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)',
    ),
    OsProfile.linux: _OsInfo(
      os: 'linux',
      appver: '1.2.1.0428',
      osver: 'Deepin 20.9',
      channel: 'netease',
      weapiUa:
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      apiUa:
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36',
    ),
  };

  _OsInfo get _info => _osMap[profile]!;

  String get os => _info.os;
  String get appver => _info.appver;
  String get osver => _info.osver;
  String get channel => _info.channel;
  String get weapiUserAgent => _info.weapiUa;
  String get apiUserAgent => _info.apiUa;

  /// Fill the device-identity cookies into [cookies] without overwriting any
  /// value already present (server-set or session cookies win).
  void augmentCookies(Map<String, String> cookies) {
    final now = DateTime.now().millisecondsSinceEpoch;
    void put(String k, String v) => cookies.putIfAbsent(k, () => v);
    put('__remember_me', 'true');
    put('ntes_kaola_ad', '1');
    put('_ntes_nuid', ntesNuid);
    put('_ntes_nnid', '$ntesNuid,$now');
    put('WNMCID', wnmcid);
    put('WEVNSM', '1.0.0');
    put('osver', osver);
    put('deviceId', deviceId);
    put('os', os);
    put('channel', channel);
    put('appver', appver);
  }

  /// The `username` payload for `/api/register/anonimous`:
  /// `base64("deviceId md5b64(xor(deviceId, key))")`.
  String anonymousUsername() {
    final encoded = _cloudmusicEncodeId(deviceId);
    return base64.encode(utf8.encode('$deviceId $encoded'));
  }

  static const _idXorKey = '3go8&\$8*3*3h0k(2)2';

  static String _cloudmusicEncodeId(String id) {
    final key = _idXorKey;
    final xored = <int>[];
    for (var i = 0; i < id.length; i++) {
      xored.add(id.codeUnitAt(i) ^ key.codeUnitAt(i % key.length));
    }
    return base64.encode(c.md5.convert(xored).bytes);
  }

  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'ntesNuid': ntesNuid,
        'wnmcid': wnmcid,
        'profile': profile.name,
      };

  factory Device.fromMap(Map<String, dynamic> m) => Device(
        deviceId: m['deviceId'] as String,
        ntesNuid: m['ntesNuid'] as String,
        wnmcid: m['wnmcid'] as String,
        profile: OsProfile.values.firstWhere(
          (p) => p.name == m['profile'],
          orElse: () => OsProfile.pc,
        ),
      );

  static String _randomHexUpper(int len) {
    const hex = '0123456789ABCDEF';
    final sb = StringBuffer();
    for (var i = 0; i < len; i++) {
      sb.write(hex[_rng.nextInt(16)]);
    }
    return sb.toString();
  }

  static String _randomHexLower(int bytes) {
    final sb = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      sb.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String _randomLowerAlpha(int len) {
    const a = 'abcdefghijklmnopqrstuvwxyz';
    final sb = StringBuffer();
    for (var i = 0; i < len; i++) {
      sb.write(a[_rng.nextInt(a.length)]);
    }
    return sb.toString();
  }
}
