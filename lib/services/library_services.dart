import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ncm_api/ncm_api.dart';

import '../models/track.dart';
import 'app_state.dart';
import 'player_service.dart';

/// Account-wide liked-song ids, so any row or the player can show a heart.
class LikeService extends ChangeNotifier {
  LikeService({required NcmClient client, this.onLikesChanged})
    : _client = client; // ignore: prefer_initializing_formals

  final NcmClient _client;

  /// Called with the user's uid after a like/unlike is confirmed by the
  /// server, so cached copies of the liked-songs playlist can be dropped.
  final Future<void> Function(int uid)? onLikesChanged;
  final Set<int> _liked = {};
  final Set<int> _pending = {};
  int? _uid;

  bool get ready => _uid != null;
  bool isLiked(int id) => _liked.contains(id);
  bool isPending(int id) => _pending.contains(id);

  /// Called whenever the auth state changes.
  void sync(AppState app) {
    final uid = app.status == AuthStatus.loggedIn ? app.uid : null;
    if (uid == _uid) return;
    _uid = uid;
    _liked.clear();
    notifyListeners();
    if (uid != null) unawaited(refresh());
  }

  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final ids = await _client.likedSongIds(uid);
      if (uid != _uid) return;
      _liked
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (_) {
      // Hearts are decorative until the next refresh; keep the old set.
    }
  }

  /// Flip the like state optimistically; rolls back and rethrows on failure.
  Future<void> toggle(Track track) async {
    final uid = _uid;
    if (uid == null || _pending.contains(track.id)) return;
    final like = !_liked.contains(track.id);
    _pending.add(track.id);
    like ? _liked.add(track.id) : _liked.remove(track.id);
    notifyListeners();
    try {
      await _client.likeSong(track.id, like: like);
    } catch (_) {
      like ? _liked.remove(track.id) : _liked.add(track.id);
      rethrow;
    } finally {
      _pending.remove(track.id);
      notifyListeners();
    }
    try {
      await onLikesChanged?.call(uid);
    } catch (_) {
      // Cache invalidation is best effort; the like itself succeeded.
    }
  }
}

/// Drives personal FM on top of [PlayerService]: fills the queue in batches
/// and refills it as the listener nears the end. FM mode ends by itself as
/// soon as something else replaces the queue.
class PersonalFmService extends ChangeNotifier {
  PersonalFmService({required NcmClient client, required FmPlayback player})
    : _client = client, // ignore: prefer_initializing_formals
      // ignore: prefer_initializing_formals
      _player = player {
    _player.addListener(_onPlayerChanged);
  }

  final NcmClient _client;
  final FmPlayback _player;
  final List<int> _fmIds = [];
  bool _active = false;
  bool _loading = false;
  Object? _error;

  bool get isActive => _active;
  bool get isLoading => _loading;
  Object? get error => _error;

  Future<List<Track>> _fetchBatch() async {
    final raw = await _client.personalFm();
    return raw
        .whereType<Map>()
        .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
        .where((t) => !_fmIds.contains(t.id))
        .toList(growable: false);
  }

  /// Start (or restart) FM from a fresh batch.
  Future<void> start() async {
    if (_loading) return;
    // Stay inactive while the queue is swapped: turning shuffle off and
    // installing the batch both publish intermediate player states that
    // would otherwise look like "something else replaced the queue".
    _active = false;
    _setLoading(true);
    try {
      _fmIds.clear();
      final batch = await _fetchBatch();
      if (batch.isEmpty) throw StateError('私人 FM 暂时没有返回歌曲');
      _fmIds.addAll(batch.map((t) => t.id));
      if (_player.isShuffle) _player.toggleShuffle();
      await _player.setQueue(batch);
      // Only claim the queue if it is still ours after playback started.
      _active = _isFmQueue();
      if (!_active) _fmIds.clear();
    } catch (e) {
      _error = e;
      _active = false;
      _fmIds.clear();
      rethrow;
    } finally {
      _setLoading(false);
    }
    _onPlayerChanged(); // a one-track batch already needs a refill
  }

  /// Dislike the current FM song and skip it.
  Future<void> trashCurrent() async {
    final track = _player.current;
    if (!_active || track == null) return;
    unawaited(
      _client
          .fmTrash(track.id, seconds: _player.position.inSeconds)
          .catchError((_) {}),
    );
    await _player.next();
  }

  void _setLoading(bool value) {
    _loading = value;
    if (value) _error = null;
    notifyListeners();
  }

  bool _isFmQueue() {
    final queue = _player.tracks;
    return queue.isNotEmpty &&
        queue.length == _fmIds.length &&
        queue.first.id == _fmIds.first;
  }

  void _onPlayerChanged() {
    if (!_active) return;
    if (!_isFmQueue()) {
      _active = false;
      _fmIds.clear();
      notifyListeners();
      return;
    }
    if (!_loading && _player.currentIndex >= _player.tracks.length - 1) {
      unawaited(_refill());
    }
  }

  Future<void> _refill() async {
    _setLoading(true);
    try {
      final batch = await _fetchBatch();
      if (!_active || batch.isEmpty) return;
      final firstNew = _player.tracks.length;
      // If the last track already finished while we were fetching, the
      // player has stopped at the end and appending alone will not resume.
      final resume = _player.reachedEnd;
      _fmIds.addAll(batch.map((t) => t.id));
      _player.enqueueAll(batch);
      if (resume) await _player.playAt(firstNew);
    } catch (e) {
      _error = e;
    } finally {
      _setLoading(false);
    }
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    super.dispose();
  }
}
