import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_miuix/miuix.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import 'lazy_network_image.dart';

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
  List<GlobalKey> _lyricKeys = const [];
  String? _lyricError;
  bool _showLyrics = false;
  bool _showVolume = false;
  int _visibleLyricIndex = -1;

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
        _lyricKeys = const [];
        _lyricError = null;
        _lyricLoading = false;
        _visibleLyricIndex = -1;
      });
      return;
    }
    setState(() {
      _lyricTrackId = id;
      _lyricLoading = true;
      _lyrics = const [];
      _lyricKeys = const [];
      _lyricError = null;
      _visibleLyricIndex = -1;
    });
    _fetchLyrics(id);
  }

  Future<void> _fetchLyrics(int id) async {
    final client = context.read<AppState>().client;
    try {
      final body = await client.lyric(id);
      if (!mounted || id != _lyricTrackId) return; // stale / disposed
      final raw = (body['lrc']?['lyric'] ?? '').toString();
      final lyrics = _parseLrc(raw);
      setState(() {
        _lyrics = lyrics;
        _lyricKeys = List.generate(lyrics.length, (_) => GlobalKey());
        _lyricLoading = false;
        _visibleLyricIndex = -1;
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
        out.add(
          _LyricLine(
            Duration(minutes: min, seconds: sec, milliseconds: ms),
            text,
          ),
        );
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
    p.setAppRepeatMode(nextMode);
  }

  void _toggleLyrics() {
    setState(() {
      _showLyrics = !_showLyrics;
      _visibleLyricIndex = -1;
    });
  }

  void _toggleVolume() {
    setState(() => _showVolume = !_showVolume);
  }

  Widget _mediaPanel(Track track, ColorScheme cs) {
    return Expanded(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _showLyrics
            ? SizedBox.expand(
                key: const ValueKey('lyrics-panel'),
                child: ValueListenableBuilder<Duration>(
                  valueListenable: context
                      .read<PlayerService>()
                      .positionListenable,
                  builder: (context, position, _) => _lyricsView(position, cs),
                ),
              )
            : Padding(
                key: const ValueKey('artwork-panel'),
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = constraints.maxWidth
                        .clamp(0.0, constraints.maxHeight)
                        .clamp(0.0, 260.0);
                    return Center(
                      child: SizedBox.square(
                        dimension: side,
                        child: _Artwork(url: track.albumArtUrl, cs: cs),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _showQueue(PlayerService player) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _QueueSheet(player: player),
    );
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
      return MiuixScaffold(
        topBar: MiuixSmallTopAppBar(
          title: '正在播放',
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(Icons.arrow_back),
          ),
        ),
        content: (padding) => Padding(
          padding: padding,
          child: const Center(child: Text('未在播放')),
        ),
      );
    }

    final duration = p.duration;

    return MiuixScaffold(
      topBar: MiuixSmallTopAppBar(
        title: '正在播放',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(Icons.arrow_back),
        ),
        actions: [
          Tooltip(
            message: '播放列表',
            child: MiuixIconButton(
              onPressed: () => _showQueue(p),
              child: const Icon(Icons.queue_music),
            ),
          ),
        ],
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          children: [
            _mediaPanel(track, cs),
            const SizedBox(height: 12),
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
            _PlaybackOptions(
              player: p,
              showLyrics: _showLyrics,
              showVolume: _showVolume,
              onToggleLyrics: _toggleLyrics,
              onToggleVolume: _toggleVolume,
            ),
            if (p.lastError != null) _ErrorBanner(error: p.lastError!, cs: cs),
            const SizedBox(height: 4),
            _progressView(p, cs, duration),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: _showVolume
                    ? _VolumeControl(player: p, cs: cs)
                    : const SizedBox(width: double.infinity),
              ),
            ),
            _Controls(p: p, cs: cs, onRepeat: () => _cycleRepeat(p)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _progressView(PlayerService p, ColorScheme cs, Duration duration) {
    final maxSeconds = duration.inSeconds > 0
        ? duration.inSeconds.toDouble()
        : 1.0;
    return ValueListenableBuilder<Duration>(
      valueListenable: p.positionListenable,
      builder: (context, position, _) {
        final posSeconds = position.inSeconds
            .clamp(0, duration.inSeconds)
            .toDouble();
        final sliderValue = (_dragValue ?? posSeconds).clamp(0.0, maxSeconds);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              MiuixSlider(
                min: 0,
                max: maxSeconds,
                value: sliderValue,
                onValueChanged: duration.inSeconds > 0
                    ? (value) => setState(() => _dragValue = value)
                    : null,
                onValueChangeFinished: () {
                  final value = _dragValue;
                  if (value != null) {
                    p.seek(Duration(seconds: value.round()));
                  }
                  setState(() => _dragValue = null);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _clock(Duration(seconds: sliderValue.round())),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _clock(duration),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _lyricsView(Duration position, ColorScheme cs) {
    if (_lyricLoading) {
      return const Center(child: MiuixCircularProgressIndicator());
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
      if (_lyrics[i].time <= position) {
        activeIndex = i;
      } else {
        break;
      }
    }

    if (activeIndex >= 0 && activeIndex != _visibleLyricIndex) {
      _visibleLyricIndex = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || activeIndex >= _lyricKeys.length) return;
        final lineContext = _lyricKeys[activeIndex].currentContext;
        if (lineContext == null) return;
        Scrollable.ensureVisible(
          lineContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      });
    }

    return SingleChildScrollView(
      key: const ValueKey('lyrics-scroll-view'),
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 56),
      child: Column(
        children: [
          for (var i = 0; i < _lyrics.length; i++)
            Padding(
              key: _lyricKeys[i],
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                _lyrics[i].text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: i == activeIndex ? 16 : 14,
                  height: 1.35,
                  fontWeight: i == activeIndex
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: i == activeIndex ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final tracks = player.tracks;
        final currentIndex = player.currentIndex;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    '播放列表 · ${tracks.length} 首',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const MiuixHorizontalDivider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: tracks.length,
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      final selected = index == currentIndex;
                      return MiuixBasicComponent(
                        startAction: selected
                            ? const Icon(Icons.graphic_eq)
                            : Text('${index + 1}'),
                        title: track.name,
                        summary: track.artistLabel,
                        onClick: selected ? () {} : () => player.playAt(index),
                      );
                    },
                  ),
                ),
              ],
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
          child: Icon(
            Icons.music_note,
            size: side * 0.3,
            color: cs.onSurfaceVariant,
          ),
        );
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LazyNetworkImage(
              url: url,
              width: side,
              height: side,
              placeholder: placeholder,
            ),
          ),
        );
      },
    );
  }
}

class _PlaybackOptions extends StatelessWidget {
  const _PlaybackOptions({
    required this.player,
    required this.showLyrics,
    required this.showVolume,
    required this.onToggleLyrics,
    required this.onToggleVolume,
  });

  final PlayerService player;
  final bool showLyrics;
  final bool showVolume;
  final VoidCallback onToggleLyrics;
  final VoidCallback onToggleVolume;

  static const _labels = {
    SongLevel.standard: '标准',
    SongLevel.higher: '较高',
    SongLevel.exhigh: '极高',
    SongLevel.lossless: '无损',
    SongLevel.hires: 'Hi-Res',
  };

  Future<void> _showQualityPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<SongLevel>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '选择音质',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            for (final entry in _labels.entries)
              MiuixRadioButtonPreference(
                title: entry.value,
                selected: entry.key == player.level,
                startAction: const Icon(Icons.high_quality_outlined),
                radioButtonLocation: MiuixRadioButtonLocation.end,
                onClick: () => Navigator.pop(sheetContext, entry.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null && selected != player.level) {
      await player.setLevel(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MiuixButton(
            key: const ValueKey('quality-selector'),
            onPressed: player.isBuffering
                ? null
                : () => _showQualityPicker(context),
            insideMargin: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.high_quality_outlined, size: 20),
                const SizedBox(width: 6),
                Text(_labels[player.level]!),
              ],
            ),
          ),
          Tooltip(
            message: showLyrics ? '显示封面' : '显示歌词',
            child: MiuixIconButton(
              key: const ValueKey('lyrics-toggle'),
              onPressed: onToggleLyrics,
              child: Icon(
                showLyrics ? Icons.album_outlined : Icons.lyrics_outlined,
                color: showLyrics ? colorScheme.primary : null,
              ),
            ),
          ),
          Tooltip(
            message: showVolume ? '收起音量' : '调节音量',
            child: MiuixIconButton(
              key: const ValueKey('volume-toggle'),
              onPressed: onToggleVolume,
              child: Icon(
                player.volume == 0
                    ? Icons.volume_off_outlined
                    : Icons.volume_up_outlined,
                color: showVolume ? colorScheme.primary : null,
              ),
            ),
          ),
          if (player.isDownloading)
            SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: MiuixCircularProgressIndicator(
                    progress: player.downloadProgress > 0
                        ? player.downloadProgress
                        : null,
                    strokeWidth: 2.5,
                    size: 24,
                  ),
                ),
              ),
            )
          else
            Tooltip(
              message: player.isCurrentDownloaded ? '重新导出到下载位置' : '下载当前歌曲',
              child: MiuixIconButton(
                onPressed: player.downloadCurrent,
                child: Icon(
                  player.isCurrentDownloaded
                      ? Icons.download_done
                      : Icons.download_outlined,
                  color: player.isCurrentDownloaded
                      ? colorScheme.primary
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({required this.player, required this.cs});

  final PlayerService player;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final volume = player.volume.clamp(0.0, 100.0);
    final icon = volume == 0
        ? Icons.volume_off_outlined
        : volume < 50
        ? Icons.volume_down_outlined
        : Icons.volume_up_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              label: '音量 ${volume.round()}%',
              child: MiuixSlider(
                key: const ValueKey('volume-slider'),
                min: 0,
                max: 100,
                value: volume,
                onValueChanged: player.setVolume,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${volume.round()}%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
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
        Tooltip(
          message: '随机播放',
          child: MiuixIconButton(
            onPressed: p.toggleShuffle,
            child: Icon(
              Icons.shuffle,
              color: p.isShuffle ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
        Tooltip(
          message: '上一首',
          child: MiuixIconButton(
            onPressed: p.previous,
            child: const Icon(Icons.skip_previous, size: 36),
          ),
        ),
        _PlayButton(p: p),
        Tooltip(
          message: '下一首',
          child: MiuixIconButton(
            onPressed: p.next,
            child: const Icon(Icons.skip_next, size: 36),
          ),
        ),
        Tooltip(
          message: '循环模式',
          child: MiuixIconButton(
            onPressed: onRepeat,
            child: Icon(
              repeatIcon,
              color: repeatActive ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
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
          child: MiuixCircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    return Tooltip(
      message: p.isPlaying ? '暂停' : '播放',
      child: MiuixFloatingActionButton(
        onPressed: p.togglePlay,
        child: Icon(p.isPlaying ? Icons.pause : Icons.play_arrow, size: 40),
      ),
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
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: cs.onErrorContainer,
          ),
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
