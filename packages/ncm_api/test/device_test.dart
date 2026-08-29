import 'package:ncm_api/ncm_api.dart';
import 'package:test/test.dart';

void main() {
  group('Device', () {
    test('anonymousUsername matches the reference algorithm', () {
      // Same fixed deviceId used to capture the Node reference vector.
      final d = Device(
        deviceId: 'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF0011223344556677',
        ntesNuid: '00' * 32,
        wnmcid: 'abcdef.1700000000000.01.0',
      );
      expect(
        d.anonymousUsername(),
        'QUFCQkNDRERFRUZGMDAxMTIyMzM0NDU1NjY3Nzg4OTlBQUJCQ0NEREVFRkYwMDExMjIzMzQ0NTU2Njc3IDdTTVJUSGMxVVdKNXFwMjZTSEhFSlE9PQ==',
      );
    });

    test('generate produces a 52-char uppercase hex deviceId', () {
      final d = Device.generate();
      expect(d.deviceId.length, 52);
      expect(RegExp(r'^[0-9A-F]{52}$').hasMatch(d.deviceId), isTrue);
    });

    test('augmentCookies fills the full fingerprint without overwriting', () {
      final d = Device.generate(profile: OsProfile.pc);
      final cookies = <String, String>{'deviceId': 'PRESET', 'MUSIC_U': 'x'};
      d.augmentCookies(cookies);

      // Existing values win.
      expect(cookies['deviceId'], 'PRESET');
      // Full set is present.
      for (final k in [
        '__remember_me',
        'ntes_kaola_ad',
        '_ntes_nuid',
        '_ntes_nnid',
        'WNMCID',
        'WEVNSM',
        'osver',
        'os',
        'channel',
        'appver',
      ]) {
        expect(cookies.containsKey(k), isTrue, reason: 'missing $k');
      }
      expect(cookies['os'], 'pc');
      expect(cookies['channel'], 'netease');
    });

    test('round-trips through toMap/fromMap', () {
      final d = Device.generate(profile: OsProfile.android);
      final r = Device.fromMap(d.toMap());
      expect(r.deviceId, d.deviceId);
      expect(r.ntesNuid, d.ntesNuid);
      expect(r.wnmcid, d.wnmcid);
      expect(r.profile, OsProfile.android);
    });
  });
}
