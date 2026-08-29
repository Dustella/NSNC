import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'package:ncm_api/ncm_api.dart';
import '../models/track.dart';

enum RepeatMode { off, one, all }

/// Cross-platform audio playback service, backed by media_kit (native mpv on
/// every target). Owns the play queue and resolves Netease stream URLs lazily
/// per-track, since those URLs are single-song and expire — media_kit is
/// driven as a single-media player, not with its internal playlist.
class PlayerService extends ChangeNotifier {
  PlayerService({
    required NcmClient client,
    SongLevel level = SongLevel.exhigh,
  })
      // ignore: prefer_initializing_formals
      : _client = client,
        // ignore: prefer_initializing_formals
        _level = level {
    _init();
  }

  // Note: initializing formals (`this._client`) are avoided here so the public
  // parameter names stay unprefixed (`client:`, `level:`) at the call site.

  final NcmClient _client;
  final mk.Player _player = mk.Player();
  SongLevel _level;
  final _rng = Random();

  final List<Track> _queue = [];
  final List<int> _shuffleOrder = []; // indices into _queue
  int _orderPos = -1; // position within _shuffleOrder / sequential index

  RepeatMode _repeat = RepeatMode.off;
  bool _shuffle = false;
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100;
  Object? _lastError;
  bool _advancing = false;

  final List<StreamSubscription> _subs = [];

  // --- public state ---
  List<Track> get queue => List.unmodifiable(_queue);
  Track? get current =>
      (_orderPos >= 0 && _orderPos < _shuffleOrder.length)
          ? _queue[_shuffleOrder[_orderPos]]
          : null;
  int get currentIndex =>
      (_orderPos >= 0 && _orderPos < _shuffleOrder.length)
          ? _shuffleOrder[_orderPos]
          : -1;
  bool get isPlaying => _playing;
  bool get isBuffering => _buffering;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  RepeatMode get repeatMode => _repeat;
  bool get isShuffle => _shuffle;
  SongLevel get level => _level;
  Object? get lastError => _lastError;

  void _init() {
    _subs.add(_player.stream.playing.listen((v) {
      _playing = v;
      notifyListeners();
    }));
    _subs.add(_player.stream.position.listen((v) {
      _position = v;
      notifyListeners();
    }));
    _subs.add(_player.stream.duration.listen((v) {
      _duration = v;
      notifyListeners();
    }));
    _subs.add(_player.stream.buffering.listen((v) {
      _buffering = v;
      notifyListeners();
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (done) _onCompleted();
    }));
    _subs.add(_player.stream.error.listen((e) {
      _lastError = e;
      notifyListeners();
    }));
  }

  // --- queue control ---

  /// Replace the queue and start playing at [startAt].
  Future<void> setQueue(List<Track> tracks, {int startAt = 0}) async {
    _queue
      ..clear()
      ..addAll(tracks);
    _rebuildOrder(anchor: startAt);
    await _playCurrent();
  }

  /// Append a track and start it immediately (single-track "play now").
  Future<void> playNow(Track track) => setQueue([track], startAt: 0);

  /// Add to the end of the queue without interrupting playback.
  void enqueue(Track track) {
    _queue.add(track);
    _shuffleOrder.add(_queue.length - 1);
    notifyListeners();
  }

  Future<void> playAt(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= _queue.length) return;
    _orderPos = _shuffleOrder.indexOf(queueIndex);
    await _playCurrent();
  }

  Future<void> next({bool userInitiated = true}) async {
    if (_queue.isEmpty) return;
    if (_repeat == RepeatMode.one && !userInitiated) {
      await _playCurrent();
      return;
    }
    if (_orderPos + 1 < _shuffleOrder.length) {
      _orderPos++;
    } else if (userInitiated || _repeat == RepeatMode.all) {
      _orderPos = 0; // wrap to start on manual next or repeat-all
    } else {
      return; // auto-advance reached the end with no loop
    }
    await _playCurrent();
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    // Restart current if we're past the first few seconds.
    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_orderPos > 0) {
      _orderPos--;
    } else {
      _orderPos = _shuffleOrder.length - 1;
    }
    await _playCurrent();
  }

  // --- transport ---

  Future<void> togglePlay() =>
      _playing ? _player.pause() : _player.play();
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration to) => _player.seek(to);

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0, 100);
    await _player.setVolume(_volume);
    notifyListeners();
  }

  void setRepeatMode(RepeatMode mode) {
    _repeat = mode;
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    final anchor = currentIndex;
    _rebuildOrder(anchor: anchor < 0 ? 0 : anchor);
    notifyListeners();
  }

  /// Change the requested audio quality. Takes effect on the next resolve;
  /// re-resolves the current track immediately.
  Future<void> setLevel(SongLevel level) async {
    if (level == _level) return;
    _level = level;
    if (current != null) {
      final pos = _position;
      await _playCurrent();
      await _player.seek(pos);
    }
  }

  // --- internals ---

  void _rebuildOrder({required int anchor}) {
    _shuffleOrder
      ..clear()
      ..addAll(List.generate(_queue.length, (i) => i));
    if (_shuffle && _queue.isNotEmpty) {
      _shuffleOrder.shuffle(_rng);
      // Move the anchor track to the front so playback continues from it.
      if (anchor >= 0 && anchor < _queue.length) {
        _shuffleOrder.remove(anchor);
        _shuffleOrder.insert(0, anchor);
      }
      _orderPos = 0;
    } else {
      _orderPos = (anchor >= 0 && anchor < _queue.length) ? anchor : 0;
    }
  }

  Future<void> _onCompleted() async {
    if (_advancing) return;
    if (_repeat == RepeatMode.one) {
      await _playCurrent();
    } else {
      await next(userInitiated: false);
    }
  }

  /// Resolve the current track's stream URL and hand it to media_kit.
  Future<void> _playCurrent() async {
    final track = current;
    if (track == null) return;
    _advancing = true;
    _lastError = null;
    notifyListeners();
    try {
      var url = track.playableUrl;
      if (url == null || url.isEmpty) {
        url = await _resolveUrl(track.id);
      }
      if (url == null || url.isEmpty) {
        _lastError = '无法获取播放地址（可能需要会员或无版权）: ${track.name}';
        _advancing = false;
        notifyListeners();
        // Skip to next if this was auto-advance.
        return;
      }
      // Cache resolved URL on the queue entry.
      final qi = currentIndex;
      if (qi >= 0) _queue[qi] = track.copyWith(playableUrl: url);
      await _player.open(mk.Media(url));
      await _player.play();
    } catch (e) {
      _lastError = e;
    } finally {
      _advancing = false;
      notifyListeners();
    }
  }

  Future<String?> _resolveUrl(int id) async {
    final data = await _client.songUrl([id], level: _level);
    if (data.isEmpty) return null;
    return data.first['url'] as String?;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
