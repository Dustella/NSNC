import 'dart:convert';
import 'dart:typed_data';

import 'package:ncm_api/ncm_api.dart';
import 'package:test/test.dart';

/// Reference vectors captured from Node's `crypto` (node:crypto), which the
/// live Netease servers accept. These lock the Dart port to byte-exact parity.
void main() {
  group('NcmCrypto', () {
    test('eapi params match reference vector', () {
      final out = NcmCrypto.eapi('/api/song/enhance/player/url/v1', {
        'ids': '[123]',
        'level': 'standard',
        'encodeType': 'flac',
      });
      expect(
        out['params'],
        'FA90B329E9614F79E79598F37DC2EDB487F00D1BC4C9B24CD57E6C318B9073569338432CD7D98D1A3626E997A2C5312196EAA6061696E185EE1BA15409319F18CA4ED390B056D95E39BB15C62B7E0B280A41E6E5D6BF982EFB798708965E277DEFA406BA5AC103AC7A6BC684E91C79AC3D61A4E821F177EBDAFDA8E93C2D46BFA612555CEE857F4636B7FF5F9692BBD5',
      );
    });

    test('linuxapi eparams match reference vector', () {
      final out = NcmCrypto.linuxapi({
        'method': 'POST',
        'url': 'https://music.163.com/api/song/detail',
        'params': {'id': 347230},
      });
      expect(
        out['eparams'],
        'A0D9583F4C5FF68DE851D2893A49DE98FAFB24399F27B4F7E74C64B6FC49A965CFA972FA5EA3D6247CD6247C8198CB8724902E133AF06ABB1602F129E968462D2DA5B6EA8682DB312EF51A6E7C5159E3EA5ABC68CDDC5CBFE58AC28A319D73C1',
      );
    });

    test('eapiDecrypt round-trips a known ciphertext', () {
      final cipher = _hexToBytes(
        '2cb98c1cf1635abd26376cef59e2fbe1d9033ddac757e797c9096313cecd41f9',
      );
      final plain = utf8.decode(NcmCrypto.eapiDecrypt(cipher));
      expect(plain, '{"code":200,"msg":"ok"}');
    });

    test('weapi shape: params + encSecKey present and well-formed', () {
      final out = NcmCrypto.weapi({'type': 1, 'csrf_token': ''});
      expect(out.containsKey('params'), isTrue);
      expect(out.containsKey('encSecKey'), isTrue);
      // encSecKey is RSA over a 128-byte block -> 256 hex chars.
      expect(out['encSecKey']!.length, 256);
      expect(RegExp(r'^[0-9a-f]{256}$').hasMatch(out['encSecKey']!), isTrue);
      // params is valid base64.
      expect(() => base64.decode(out['params']!), returnsNormally);
    });
  });
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
