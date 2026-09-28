import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:nsnc/models/track.dart';
import 'package:nsnc/services/library_services.dart';
import 'package:nsnc/services/player_service.dart';

/// Mimics [PlayerService]'s queue semantics, including the synchronous
/// listener notification on every state change.
class _FakePlayback extends ChangeNotifier implements FmPlayback {
  _FakePlayback({List<Track> queue = const [], this.isShuffle = false})
    : _queue = [...queue],
      _index = queue.isEmpty ? -1 : 0;

  List<Track> _queue;
  int _index;
  bool _reachedEnd = false;

  @override
  bool isShuffle;

  @override
  List<Track> get tracks => List.unmodifiable(_queue);
  @override
  Track? get current => _index >= 0 ? _queue[_index] : null;
  @override
  int get currentIndex => _index;
  @override
  Duration get position => Duration.zero;
  @override
  bool get reachedEnd => _reachedEnd;

  @override
  void toggleShuffle() {
    isShuffle = !isShuffle;
    notifyListeners(); // publishes the OLD queue, like the real player
  }

  @override
  Future<void> setQueue(List<Track> tracks, {int startAt = 0}) async {
    _queue = [...tracks];
    _index = startAt;
    _reachedEnd = false;
    notifyListeners();
  }

  @override
  void enqueueAll(Iterable<Track> tracks) {
    _queue.addAll(tracks);
    notifyListeners();
  }

  @override
  Future<void> playAt(int queueIndex) async {
    _index = queueIndex;
    _reachedEnd = false;
    notifyListeners();
  }

  @override
  Future<void> next({bool userInitiated = true}) async {
    if (_index + 1 < _queue.length) {
      _index++;
    } else if (!userInitiated) {
      _reachedEnd = true; // auto-advance stops at the end, repeat off
    }
    notifyListeners();
  }
}

Track _track(int id) => Track.fromJson({'id': id, 'name': 't$id'});

Map<String, Object> _fm(List<int> ids) => {
  'code': 200,
  'data': [
    for (final id in ids) {'id': id, 'name': 't$id'},
  ],
};

NcmClient _clientServing(List<Future<Map<String, Object>> Function()> batches) {
  var call = 0;
  return NcmClient(
    httpClient: MockClient((request) async {
      if (request.url.path != '/weapi/v1/radio/get') {
        throw StateError('Unexpected ${request.url}');
      }
      final body = await batches[call++]();
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    }),
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('starting FM with shuffle on keeps FM active', () async {
    final client = _clientServing([
      () async => _fm([1, 2]),
    ]);
    addTearDown(client.close);
    final player = _FakePlayback(
      queue: [_track(100), _track(101)],
      isShuffle: true,
    );
    final fm = PersonalFmService(client: client, player: player);
    addTearDown(fm.dispose);

    await fm.start();

    expect(player.isShuffle, isFalse);
    expect(player.tracks.map((t) => t.id), [1, 2]);
    expect(fm.isActive, isTrue);
  });

  test('a refill that lands after the last track ended resumes', () async {
    final second = Completer<Map<String, Object>>();
    final client = _clientServing([
      () async => _fm([1, 2]),
      () => second.future,
    ]);
    addTearDown(client.close);
    final player = _FakePlayback();
    final fm = PersonalFmService(client: client, player: player);
    addTearDown(fm.dispose);

    await fm.start();
    await player.next(); // reach the last track -> refill starts
    expect(fm.isLoading, isTrue);
    await player.next(userInitiated: false); // it ends before the refill
    expect(player.reachedEnd, isTrue);

    second.complete(_fm([3, 4]));
    await _settle();

    expect(player.tracks.map((t) => t.id), [1, 2, 3, 4]);
    expect(player.currentIndex, 2);
    expect(player.reachedEnd, isFalse);
    expect(fm.isActive, isTrue);
  });

  test('replacing the queue still ends FM', () async {
    final client = _clientServing([
      () async => _fm([1, 2]),
    ]);
    addTearDown(client.close);
    final player = _FakePlayback();
    final fm = PersonalFmService(client: client, player: player);
    addTearDown(fm.dispose);

    await fm.start();
    await player.setQueue([_track(50)]);

    expect(fm.isActive, isFalse);
  });
}
