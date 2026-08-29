import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/export.dart' as pc;

/// Netease Cloud Music request encryption.
///
/// Implements the three classic schemes still in use on the live servers
/// (verified 2026-07): WEAPI (double AES-CBC + RSA key wrap), EAPI
/// (MD5 digest + AES-ECB), and LinuxAPI (AES-ECB). All AES is AES-128 with
/// PKCS7 padding, matching Node's `createCipheriv` defaults.
class NcmCrypto {
  NcmCrypto._();

  static final Uint8List _iv = _ascii('0102030405060708');
  static final Uint8List _presetKey = _ascii('0CoJUm6Qyw8W8jud');
  static final Uint8List _linuxapiKey = _ascii('rFgB&h#%2?^eDg:Q');
  static final Uint8List _eapiKey = _ascii('e82ckenh8dichen8');
  static const String _base62 =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// RSA public key (n, e) extracted from the PEM used by the Netease client.
  /// e = 65537. Encryption is raw modular exponentiation with NO padding,
  /// input left-padded with zeros to 128 bytes — identical to Node's
  /// `RSA_NO_PADDING`.
  static final BigInt _rsaModulus = BigInt.parse(
    '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725'
    '152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312'
    'ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424'
    'd813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7',
    radix: 16,
  );
  static final BigInt _rsaExponent = BigInt.from(65537);

  static final Random _rng = Random.secure();

  /// WEAPI: params = AES-CBC(secretKey, base64(AES-CBC(presetKey, json)))
  ///        encSecKey = RSA(reverse(secretKey))
  static Map<String, String> weapi(Object object) {
    final text = utf8.encode(jsonEncode(object));
    final secretKey = _randomSecretKey();

    final inner = base64.encode(_aesCbc(text, _presetKey, _iv));
    final params = base64.encode(_aesCbc(utf8.encode(inner), secretKey, _iv));

    final reversed = Uint8List.fromList(secretKey.reversed.toList());
    final encSecKey = _rsaEncrypt(reversed);

    return {'params': params, 'encSecKey': encSecKey};
  }

  /// EAPI: `params = HEX(AES-ECB(eapiKey, "URL-36cd479b6b5-JSON-36cd479b6b5-MD5"))`
  static Map<String, String> eapi(String url, Object object) {
    final text = object is String ? object : jsonEncode(object);
    final message = 'nobody${url}use${text}md5forencrypt';
    final digest = c.md5.convert(utf8.encode(message)).toString();
    final data = '$url-36cd479b6b5-$text-36cd479b6b5-$digest';
    final enc = _aesEcb(utf8.encode(data), _eapiKey);
    return {'params': _hex(enc).toUpperCase()};
  }

  /// LinuxAPI: eparams = HEX(AES-ECB(linuxapiKey, json))
  static Map<String, String> linuxapi(Object object) {
    final text = utf8.encode(jsonEncode(object));
    final enc = _aesEcb(text, _linuxapiKey);
    return {'eparams': _hex(enc).toUpperCase()};
  }

  /// Decrypt an EAPI response body (AES-ECB with eapiKey, PKCS7).
  static Uint8List eapiDecrypt(Uint8List cipher) =>
      _aesEcbDecrypt(cipher, _eapiKey);

  // --- primitives ---

  static Uint8List _aesCbc(List<int> data, Uint8List key, Uint8List iv) {
    final cipher = pc.PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        pc.PaddedBlockCipherParameters(
          pc.ParametersWithIV(pc.KeyParameter(key), iv),
          null,
        ),
      );
    return cipher.process(Uint8List.fromList(data));
  }

  static Uint8List _aesEcb(List<int> data, Uint8List key) {
    final cipher = pc.PaddedBlockCipher('AES/ECB/PKCS7')
      ..init(
        true,
        pc.PaddedBlockCipherParameters(pc.KeyParameter(key), null),
      );
    return cipher.process(Uint8List.fromList(data));
  }

  static Uint8List _aesEcbDecrypt(Uint8List data, Uint8List key) {
    final cipher = pc.PaddedBlockCipher('AES/ECB/PKCS7')
      ..init(
        false,
        pc.PaddedBlockCipherParameters(pc.KeyParameter(key), null),
      );
    return cipher.process(data);
  }

  /// RSA with NO padding: c = m^e mod n, where m is the 128-byte big-endian
  /// integer formed from `input` left-padded with zeros to 128 bytes.
  static String _rsaEncrypt(Uint8List input) {
    final padded = Uint8List(128);
    padded.setRange(128 - input.length, 128, input);
    final m = _bytesToBigInt(padded);
    final cipher = m.modPow(_rsaExponent, _rsaModulus);
    return _bigIntToHex(cipher, 256);
  }

  static Uint8List _randomSecretKey() {
    final key = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      key[i] = _base62.codeUnitAt(_rng.nextInt(62));
    }
    return key;
  }

  static Uint8List _ascii(String s) => Uint8List.fromList(ascii.encode(s));

  static String _hex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var r = BigInt.zero;
    for (final b in bytes) {
      r = (r << 8) | BigInt.from(b);
    }
    return r;
  }

  static String _bigIntToHex(BigInt value, int width) {
    var h = value.toRadixString(16);
    if (h.length < width) h = h.padLeft(width, '0');
    return h;
  }
}
