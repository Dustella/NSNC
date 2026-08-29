// Real-device playback smoke test. Runs on the native runner (Windows/…),
// so media_kit's mpv backend is fully linked. Resolves a guest-playable
// Netease URL live and asserts the player actually advances position.
//
// Run: flutter test integration_test/playback_test.dart -d windows
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:ncm_api/ncm_api.dart';
import 'package:nsnc/models/track.dart';
import 'package:nsnc/services/player_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  test('resolves a live URL and plays audio (position advances)', () async {
    final client = NcmClient();
    final player = PlayerService(client: client);

    // 稻香 / 周杰伦-style guest-playable track (id 347230 = 海阔天空/Beyond,
    // returned a playable guest URL in earlier live smoke tests).
    final details = await client.songDetail([347230]);
    expect(details, isNotEmpty, reason: 'songDetail should return the track');
    final track = Track.fromJson(details.first as Map<String, dynamic>);

    await player.setQueue([track]);

    // Wait until playback actually starts and the clock moves.
    var advanced = false;
    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      if (player.isPlaying && player.position > Duration.zero) {
        advanced = true;
        break;
      }
      if (player.lastError != null) {
        fail('player reported error: ${player.lastError}');
      }
    }

    expect(advanced, isTrue,
        reason: 'player should be playing with position > 0 within 10s');
    expect(player.current?.id, track.id);

    // Exercise pause/seek transport.
    await player.pause();
    await Future.delayed(const Duration(milliseconds: 300));
    expect(player.isPlaying, isFalse);

    await player.seek(const Duration(seconds: 30));
    await player.play();
    await Future.delayed(const Duration(milliseconds: 600));
    expect(player.position.inSeconds, greaterThanOrEqualTo(25));

    player.dispose();
    client.close();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
