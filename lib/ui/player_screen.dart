import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/player_service.dart';

/// A single timestamped lyric line parsed from an LRC string.
class _LyricLine {
  const _LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

/// Full-screen now-playing view: large album art, track metadata, a scrubbable
/// progress slider, transport controls, and scrolling LRC lyrics fetched from
/// the lyric endpoint. Lyrics reload whenever the current track id changes.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  /// Local drag value (seconds) while the user is scrubbing, so the slider
  /// doesn't jump back to [PlayerService.position] mid-drag. Null when idle.
  double? _dragValue;

  int? _lyricTrackId; // track id the current lyrics belong to
  bool _lyricLoading = false;
  List<_LyricLine> _lyrics = const [];
  String? _lyricError;

  @override
  void initState() {
    super.initState();
    // Kick off the first fetch once providers are available. Subsequent
    // track changes are picked up in build() via the id comparison.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLyrics());
  }

  /// Fetch lyrics for the current track if they aren't already loaded/loading
  /// for that id. Idempotent: safe to call from initState and from build.
  void _syncLyrics() {
    if (!mounted) return;
    final track = context.read<PlayerService>().current;
    final id = track?.id;
    if (id == _lyricTrackId) return; // already have (or are loading) this track
    if (id == null) {
      setState(() {
        _lyricTrackId = null;
        _lyrics = const [];
        _lyricError = null;
        _lyricLoading = false;
      });
      return;
    }
    setState(() {
      _lyricTrackId = id;
      _lyricLoading = true;
      _lyrics = const [];
      _lyricError = null;
    });
    _fetchLyrics(id);
  }

  Future<void> _fetchLyrics(int id) async {
    final client = context.read<AppState>().client;
    try {
      final body = await client.lyric(id);
      if (!mounted || id != _lyricTrackId) return; // stale / disposed
      final raw = (body['lrc']?['lyric'] ?? '').toString();
      setState(() {
        _lyrics = _parseLrc(raw);
        _lyricLoading = false;
      });
    } catch (e) {
      if (!mounted || id != _lyricTrackId) return;
      setState(() {
        _lyricError = e.toString();
        _lyricLoading = false;
      });
    }
  }

  /// Parse an LRC string into time-ordered lines. Handles multiple timestamps
  /// per line (`[00:12.34][00:15.00]text`) and both `.`/`:` fraction
  /// separators; skips metadata tags like `[ti:]`, `[ar:]`, `[by:]`.
  static List<_LyricLine> _parseLrc(String lrc) {
    final tag = RegExp(r'\[(\d+):(\d+)[.:]?(\d+)?\]');
    final out = <_LyricLine>[];
    for (final line in lrc.split('\n')) {
      final matches = tag.allMatches(line).toList();
      if (matches.isEmpty) continue; // metadata / blank / non-timed
      final text = line.substring(matches.last.end).trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final fracRaw = m.group(3);
        var ms = 0;
        if (fracRaw != null && fracRaw.isNotEmpty) {
          // 2-digit fraction = centiseconds, 3-digit = milliseconds.
          ms = fracRaw.length == 2
              ? int.parse(fracRaw) * 10
              : int.parse(fracRaw.padRight(3, '0').substring(0, 3));
        }
        out.add(_LyricLine(
          Duration(minutes: min, seconds: sec, milliseconds: ms),
          text,
        ));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _cycleRepeat(PlayerService p) {
    final nextMode = switch (p.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    p.setRepeatMode(nextMode);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerService>();
    final cs = Theme.of(context).colorScheme;
    final track = p.current;

    // Reload lyrics after a track change (post-frame to avoid setState in build).
    if (track?.id != _lyricTrackId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncLyrics());
    }

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('未在播放')),
      );
    }

    final duration = p.duration;
    final maxSeconds =
        duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
    final posSeconds =
        p.position.inSeconds.clamp(0, duration.inSeconds).toDouble();
    final sliderValue = (_dragValue ?? posSeconds).clamp(0.0, maxSeconds);

    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: _Artwork(url: track.albumArtUrl, cs: cs),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    track.album.isEmpty
                        ? track.artistLabel
                        : '${track.artistLabel} · ${track.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (p.lastError != null) _ErrorBanner(error: p.lastError!, cs: cs),
            const SizedBox(height: 8),
            // Progress slider + times.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Slider(
                    min: 0,
                    max: maxSeconds,
                    value: sliderValue,
                    onChanged: duration.inSeconds > 0
                        ? (v) => setState(() => _dragValue = v)
                        : null,
                    onChangeEnd: (v) {
                      p.seek(Duration(seconds: v.round()));
                      setState(() => _dragValue = null);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_clock(Duration(seconds: sliderValue.round())),
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                        Text(_clock(duration),
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _Controls(p: p, cs: cs, onRepeat: () => _cycleRepeat(p)),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(child: _lyricsView(p, cs)),
          ],
        ),
      ),
    );
  }

  Widget _lyricsView(PlayerService p, ColorScheme cs) {
    if (_lyricLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lyrics.isEmpty) {
      return Center(
        child: Text(
          _lyricError != null ? '歌词加载失败' : '暂无歌词',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    // Index of the line whose timestamp is the latest <= current position.
    var activeIndex = -1;
    for (var i = 0; i < _lyrics.length; i++) {
      if (_lyrics[i].time <= p.position) {
        activeIndex = i;
      } else {
        break;
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      itemCount: _lyrics.length,
      itemBuilder: (context, i) {
        final active = i == activeIndex;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            _lyrics[i].text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: active ? 16 : 14,
              height: 1.3,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

/// Large rounded square album art, clamped so tall content still fits.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.cs});

  final String? url;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth.clamp(0.0, 260.0);
        final placeholder = Container(
          width: side,
          height: side,
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.music_note, size: side * 0.3, color: cs.onSurfaceVariant),
        );
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: (url == null || url!.isEmpty)
                ? placeholder
                : CachedNetworkImage(
                    imageUrl: url!,
                    width: side,
                    height: side,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => placeholder,
                    errorWidget: (_, _, _) => placeholder,
                  ),
          ),
        );
      },
    );
  }
}

/// Transport controls: shuffle · previous · play/pause · next · repeat.
class _Controls extends StatelessWidget {
  const _Controls({required this.p, required this.cs, required this.onRepeat});

  final PlayerService p;
  final ColorScheme cs;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    final repeatIcon = p.repeatMode == RepeatMode.one
        ? Icons.repeat_one
        : Icons.repeat;
    final repeatActive = p.repeatMode != RepeatMode.off;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.shuffle),
          tooltip: '随机播放',
          color: p.isShuffle ? cs.primary : cs.onSurfaceVariant,
          onPressed: () => p.toggleShuffle(),
        ),
        IconButton(
          iconSize: 36,
          icon: const Icon(Icons.skip_previous),
          tooltip: '上一首',
          onPressed: () => p.previous(),
        ),
        _PlayButton(p: p),
        IconButton(
          iconSize: 36,
          icon: const Icon(Icons.skip_next),
          tooltip: '下一首',
          onPressed: () => p.next(),
        ),
        IconButton(
          icon: Icon(repeatIcon),
          tooltip: '循环模式',
          color: repeatActive ? cs.primary : cs.onSurfaceVariant,
          onPressed: onRepeat,
        ),
      ],
    );
  }
}

/// Big filled play/pause button; shows a spinner while buffering.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.p});

  final PlayerService p;

  @override
  Widget build(BuildContext context) {
    if (p.isBuffering) {
      return const SizedBox(
        width: 64,
        height: 64,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    return IconButton.filled(
      iconSize: 40,
      icon: Icon(p.isPlaying ? Icons.pause : Icons.play_arrow),
      tooltip: p.isPlaying ? '暂停' : '播放',
      onPressed: () => p.togglePlay(),
    );
  }
}

/// Small inline warning banner for the last playback error.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.cs});

  final Object error;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '播放失败: $error',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
