// QR login example: renders the unikey QR in the terminal, polls to
// completion, then verifies the session (profile + a login-gated lossless
// song URL). Demonstrates the eapi @ interface channel that actually delivers
// MUSIC_U.
//
// Run: dart run example/qr_login.dart
import 'dart:io';

import 'package:ncm_api/ncm_api.dart';
import 'package:qr/qr.dart';

Future<void> main() async {
  final client = NcmClient();

  final unikey = await client.loginQrKey();
  _printQr(client.loginQrCodeUrl(unikey));
  print('\n用网易云音乐 App 扫码并确认登录…\n');

  var round = 0;
  while (round++ < 90) {
    await Future.delayed(const Duration(seconds: 2));
    final resp = await client.loginQrCheck(unikey);
    final code = resp.body['code'];
    stdout.write('[$round] code=$code ${resp.body['message'] ?? ''}\r');

    if (code == 803) {
      print('\n\n登录成功。');
      final status = await client.loginStatus();
      final profile = status['profile'] as Map<String, dynamic>?;
      if (profile == null) {
        print('会话校验失败：profile 为空');
        break;
      }
      print('用户: ${profile['nickname']} (uid=${profile['userId']})');

      final urls = await client.songUrl([347230], level: SongLevel.lossless);
      final first = urls.isEmpty ? null : urls.first;
      print('无损试听: level=${first?['level']} br=${first?['br']} '
          'url=${first?['url'] != null ? "OK" : "无"}');

      final pls = await client.userPlaylists((profile['userId'] as num).toInt());
      print('歌单数: ${pls.length}');
      break;
    }
    if (code == 800) {
      print('\n二维码已过期，请重跑。');
      break;
    }
  }
  client.close();
}

void _printQr(String data) {
  final qr =
      QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M);
  final img = QrImage(qr);
  final n = img.moduleCount;
  const quiet = 2;
  bool dark(int r, int col) =>
      r >= 0 && col >= 0 && r < n && col < n && img.isDark(r, col);
  final buf = StringBuffer();
  for (var r = -quiet; r < n + quiet; r += 2) {
    for (var col = -quiet; col < n + quiet; col++) {
      final top = dark(r, col), bot = dark(r + 1, col);
      buf.write(top && bot ? '\u2588' : top ? '\u2580' : bot ? '\u2584' : ' ');
    }
    buf.write('\n');
  }
  stdout.write(buf.toString());
}
