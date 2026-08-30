import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:ncm_api/ncm_api.dart';
import 'package:smtc_windows/smtc_windows.dart' as smtc;

import '../models/track.dart';

enum RepeatMode { off, one, all }

/// Owns the playback queue and is the single source of truth for the app UI,
/// Android MediaSession/notification and Windows SMTC.
class PlayerService extends BaseAudioHandler with ChangeNotifier {
  PlayerService({required NcmClient client, SongLevel level = SongLevel.exhigh})
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
  final ValueNotifier<Duration> positionListenable = ValueNotifier(
    Duration.zero,
  );
  double _volume = 100;
  Object? _lastError;
  bool _advancing = false;
  smtc.SMTCWindows? _smtc;
  StreamSubscription<smtc.PressedButton>? _smtcButtons;
  int? _smtcTrackId;
  bool? _smtcPlaying;
  int _smtcPositionSecond = -1;

  final List<StreamSubscription<dynamic>> _subs = [];

  // --- public state ---
  List<Track> get tracks => List.unmodifiable(_queue);
  Track? get current => (_orderPos >= 0 && _orderPos < _shuffleOrder.length)
      ? _queue[_shuffleOrder[_orderPos]]
      : null;
  int get currentIndex => (_orderPos >= 0 && _orderPos < _shuffleOrder.length)
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
    _subs.add(
      _player.stream.playing.listen((value) {
        _playing = value;
        _publishState();
      }),
    );
    _subs.add(
      _player.stream.position.listen((value) {
        _position = value;
        final rounded = Duration(seconds: value.inSeconds);
        if (positionListenable.value != rounded) {
          positionListenable.value = rounded;
          _syncSmtcPosition();
        }
      }),
    );
    _subs.add(
      _player.stream.duration.listen((value) {
        _duration = value;
        _publishState();
      }),
    );
    _subs.add(
      _player.stream.buffering.listen((value) {
        _buffering = value;
        _publishState();
      }),
    );
    _subs.add(
      _player.stream.completed.listen((done) {
        if (done) unawaited(_onCompleted());
      }),
    );
    _subs.add(
      _player.stream.error.listen((error) {
        _lastError = error;
        _publishState();
      }),
    );
  }

  Future<void> initializeWindowsSmtc() async {
    if (!Platform.isWindows || _smtc != null) return;
    await smtc.SMTCWindows.initialize();
    final controller = smtc.SMTCWindows(enabled: false);
    _smtc = controller;
    _smtcButtons = controller.buttonPressStream.listen((button) {
      switch (button) {
        case smtc.PressedButton.play:
          unawaited(play());
        case smtc.PressedButton.pause:
          unawaited(pause());
        case smtc.PressedButton.next:
          unawaited(next());
        case smtc.PressedButton.previous:
          unawaited(previous());
        case smtc.PressedButton.stop:
          unawaited(stop());
        default:
          break;
      }
    });
    _syncSmtc(force: true);
  }

  // --- queue control ---

  /// Replace the queue and publish the selected track before resolving its URL.
  Future<void> setQueue(List<Track> tracks, {int startAt = 0}) async {
    _queue
      ..clear()
      ..addAll(tracks);
    _rebuildOrder(anchor: startAt);
    queue.add(_queue.map(_mediaItemFor).toList(growable: false));
    _publishState();
    await _playCurrent();
  }

  /// Append a track and start it immediately (single-track "play now").
  Future<void> playNow(Track track) => setQueue([track], startAt: 0);

  /// Add to the end of the queue without interrupting playback.
  void enqueue(Track track) {
    _queue.add(track);
    _shuffleOrder.add(_queue.length - 1);
    queue.add(_queue.map(_mediaItemFor).toList(growable: false));
    _publishState();
  }

  void enqueueAll(Iterable<Track> tracks) {
    final additions = tracks.toList(growable: false);
    if (additions.isEmpty) return;
    final start = _queue.length;
    _queue.addAll(additions);
    _shuffleOrder.addAll(List.generate(additions.length, (i) => start + i));
    queue.add(_queue.map(_mediaItemFor).toList(growable: false));
    _publishState();
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

  Future<void> togglePlay() => _playing ? pause() : play();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _position = position;
    positionListenable.value = Duration(seconds: position.inSeconds);
    _publishState();
  }

  @override
  Future<void> skipToNext() => next();

  @override
  Future<void> skipToPrevious() => previous();

  @override
  Future<void> skipToQueueItem(int index) => playAt(index);

  @override
  Future<void> stop() async {
    await _player.stop();
    _queue.clear();
    _shuffleOrder.clear();
    _orderPos = -1;
    _playing = false;
    _position = Duration.zero;
    positionListenable.value = Duration.zero;
    _duration = Duration.zero;
    queue.add(const []);
    _publishState();
    await super.stop();
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0, 100);
    await _player.setVolume(_volume);
    _publishState();
  }

  void setAppRepeatMode(RepeatMode mode) {
    _repeat = mode;
    _publishState();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    setAppRepeatMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => RepeatMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => RepeatMode.all,
      _ => RepeatMode.off,
    });
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled != _shuffle) toggleShuffle();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    final anchor = currentIndex;
    _rebuildOrder(anchor: anchor < 0 ? 0 : anchor);
    _publishState();
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
    _position = Duration.zero;
    positionListenable.value = Duration.zero;
    _duration = track.duration;
    _publishState();
    try {
      var url = track.playableUrl;
      if (url == null || url.isEmpty) {
        url = await _resolveUrl(track.id);
      }
      if (url == null || url.isEmpty) {
        _lastError = '无法获取播放地址（可能需要会员或无版权）: ${track.name}';
        return;
      }
      final queueIndex = currentIndex;
      if (queueIndex >= 0) {
        _queue[queueIndex] = track.copyWith(playableUrl: url);
      }
      await _player.open(mk.Media(url));
      await _player.play();
    } catch (error) {
      _lastError = error;
    } finally {
      _advancing = false;
      _publishState();
    }
  }

  Future<String?> _resolveUrl(int id) async {
    final data = await _client.songUrl([id], level: _level);
    if (data.isEmpty) return null;
    return data.first['url'] as String?;
  }

  MediaItem _mediaItemFor(Track track) => MediaItem(
    id: track.id.toString(),
    title: track.name,
    album: track.album,
    artist: track.artistLabel,
    duration: track.duration,
    artUri: track.albumArtUrl == null || track.albumArtUrl!.isEmpty
        ? null
        : Uri.tryParse(track.albumArtUrl!),
  );

  void _publishState() {
    final track = current;
    mediaItem.add(track == null ? null : _mediaItemFor(track));
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {MediaAction.seek},
        processingState: _lastError != null
            ? AudioProcessingState.error
            : (_advancing || _buffering)
            ? AudioProcessingState.buffering
            : track == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: _playing,
        updatePosition: _position,
        queueIndex: currentIndex < 0 ? null : currentIndex,
        repeatMode: switch (_repeat) {
          RepeatMode.off => AudioServiceRepeatMode.none,
          RepeatMode.one => AudioServiceRepeatMode.one,
          RepeatMode.all => AudioServiceRepeatMode.all,
        },
        shuffleMode: _shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        errorMessage: _lastError?.toString(),
      ),
    );
    _syncSmtc(force: true);
    notifyListeners();
  }

  void _syncSmtc({bool force = false}) {
    final controller = _smtc;
    final track = current;
    if (controller == null) return;
    if (track == null) {
      if (controller.enabled) unawaited(controller.disableSmtc());
      _smtcTrackId = null;
      _smtcPlaying = null;
      _smtcPositionSecond = -1;
      unawaited(controller.clearMetadata());
      return;
    }
    if (!controller.enabled) unawaited(controller.enableSmtc());
    if (force || _smtcTrackId != track.id) {
      _smtcTrackId = track.id;
      unawaited(
        controller.updateMetadata(
          smtc.MusicMetadata(
            title: track.name,
            artist: track.artistLabel,
            album: track.album,
            albumArtist: track.artistLabel,
            thumbnail: track.albumArtUrl,
          ),
        ),
      );
      unawaited(
        controller.updateTimeline(
          smtc.PlaybackTimeline(
            startTimeMs: 0,
            endTimeMs: _duration.inMilliseconds,
            positionMs: _position.inMilliseconds,
            minSeekTimeMs: 0,
            maxSeekTimeMs: _duration.inMilliseconds,
          ),
        ),
      );
    }
    if (force || _smtcPlaying != _playing) {
      _smtcPlaying = _playing;
      unawaited(
        controller.setPlaybackStatus(
          _playing ? smtc.PlaybackStatus.playing : smtc.PlaybackStatus.paused,
        ),
      );
    }
  }

  void _syncSmtcPosition() {
    final controller = _smtc;
    if (controller == null || _smtcPositionSecond == _position.inSeconds) {
      return;
    }
    _smtcPositionSecond = _position.inSeconds;
    unawaited(controller.setPosition(_position));
  }

  @override
  void dispose() {
    for (final subscription in _subs) {
      unawaited(subscription.cancel());
    }
    unawaited(_smtcButtons?.cancel());
    final controller = _smtc;
    if (controller != null) unawaited(controller.dispose());
    unawaited(_player.dispose());
    positionListenable.dispose();
    super.dispose();
  }
}
