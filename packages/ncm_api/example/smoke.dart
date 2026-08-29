// Live smoke test for the NCM API client. Hits real servers with the
// anonymous/guest session. Run: dart run example/smoke.dart
import 'package:ncm_api/ncm_api.dart';

Future<void> main() async {
  final client = NcmClient();
  var pass = 0, fail = 0;

  Future<void> check(String name, Future<bool> Function() body) async {
    try {
      final ok = await body();
      print('${ok ? "PASS" : "FAIL"}  $name');
      ok ? pass++ : fail++;
    } catch (e) {
      print('FAIL  $name  ->  $e');
      fail++;
    }
  }

  await check('loginQrKey (weapi)', () async {
    final key = await client.loginQrKey();
    print('        unikey=$key');
    print('        qrUrl=${client.loginQrCodeUrl(key)}');
    return key.isNotEmpty;
  });

  await check('search song (eapi, plaintext fallback)', () async {
    final body = await client.search('周杰伦 稻香', limit: 3);
    final songs = body['result']?['songs'] as List? ?? const [];
    for (final s in songs.take(3)) {
      final ar = (s['ar'] as List?)?.map((a) => a['name']).join('/') ?? '';
      print('        ${s['name']} - $ar  (id=${s['id']})');
    }
    return songs.isNotEmpty;
  });

  await check('songDetail (weapi)', () async {
    final songs = await client.songDetail([347230, 25906124]);
    for (final s in songs) {
      final ar = (s['ar'] as List?)?.map((a) => a['name']).join('/') ?? '';
      print('        ${s['name']} - $ar');
    }
    return songs.length == 2;
  });

  await check('lyric (api)', () async {
    final body = await client.lyric(347230);
    final lrc = body['lrc']?['lyric'] as String? ?? '';
    print('        lrc head: ${lrc.split("\n").take(2).join(" | ")}');
    return lrc.isNotEmpty;
  });

  await check('playlistDetail (api)', () async {
    // 网易云官方"云音乐热歌榜" playlist id
    final body = await client.playlistDetail(3778678);
    final pl = body['playlist'] as Map?;
    final name = pl?['name'];
    final count = (pl?['trackIds'] as List?)?.length ?? 0;
    print('        playlist="$name" trackCount=$count');
    return pl != null && count > 0;
  });

  await check('songUrl (eapi, guest — expect graceful degrade)', () async {
    final urls = await client.songUrl([347230]);
    final first = urls.isEmpty ? null : urls.first;
    print('        url=${first?['url']} br=${first?['br']} '
        'level=${first?['level']} fee=${first?['fee']}');
    // Guest may get null url for member tracks; the call itself must succeed.
    return urls.isNotEmpty;
  });

  client.close();
  print('\n$pass passed, $fail failed');
}
