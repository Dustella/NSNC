import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../models/track.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../services/ui_preferences.dart';
import 'navigation.dart';
import 'track_list_screen.dart';
import 'widgets/common.dart';
import 'widgets/media_widgets.dart';
import 'widgets/track_widgets.dart';

enum _Category {
  song('单曲', SearchType.song),
  playlist('歌单', SearchType.playlist),
  album('专辑', SearchType.album),
  artist('歌手', SearchType.artist),
  radio('电台', SearchType.radio);

  const _Category(this.label, this.type);
  final String label;
  final SearchType type;
}

class _Results {
  const _Results({this.tracks = const [], this.items = const []});
  final List<Track> tracks;
  final List<MediaItem> items;
  bool get isEmpty => tracks.isEmpty && items.isEmpty;
}

/// Search: trending + history when idle, categorized results otherwise.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  _Category _category = _Category.song;
  String _keywords = '';
  Future<_Results>? _results;
  Future<List<Map<String, dynamic>>>? _hot;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadHot() async {
    final raw = await context.read<AppState>().client.hotSearches();
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  void _submit(String raw) {
    final keywords = raw.trim();
    if (keywords.isEmpty) return;
    _controller.text = keywords;
    FocusScope.of(context).unfocus();
    unawaited(_maybePrefs()?.addRecentSearch(keywords));
    setState(() {
      _keywords = keywords;
      _results = _search(keywords, _category);
    });
  }

  UiPreferences? _maybePrefs() {
    try {
      return context.read<UiPreferences>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<_Results> _search(String keywords, _Category category) async {
    final body = await context.read<AppState>().client.search(
      keywords,
      type: category.type,
      limit: 40,
    );
    final result = (body['result'] as Map?) ?? const {};
    List<Map<String, dynamic>> maps(String key) =>
        ((result[key] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    return switch (category) {
      _Category.song => _Results(tracks: parseTracks(maps('songs'))),
      _Category.playlist => _Results(
        items: maps('playlists').map(MediaItem.playlist).toList(),
      ),
      _Category.album => _Results(
        items: maps('albums').map(MediaItem.album).toList(),
      ),
      _Category.artist => _Results(
        items: maps('artists').map(MediaItem.artist).toList(),
      ),
      _Category.radio => _Results(
        items: maps('djRadios').map(MediaItem.radio).toList(),
      ),
    };
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _keywords = '';
      _results = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Read preferences here: MIUIX builds `content` in a nested builder, where
    // `context.select` on this State's context is not allowed.
    final prefs = _maybePrefs() == null ? null : context.watch<UiPreferences>();
    final recent = prefs?.recentSearches ?? const <String>[];
    final layout =
        prefs?.layoutFor(LayoutSurface.search) ?? CollectionLayout.list;
    return MiuixScaffold(
      topBar: MiuixSmallTopAppBar(
        title: '搜索',
        bottomContent: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: MiuixTextField(
                  controller: _controller,
                  label: '搜索歌曲、歌手、专辑、电台',
                  useLabelAsPlaceholder: true,
                  leadingIcon: const Icon(Icons.search),
                  singleLine: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submit,
                ),
              ),
              if (_keywords.isNotEmpty)
                Tooltip(
                  message: '清除',
                  child: MiuixIconButton(
                    onPressed: _clear,
                    child: const Icon(Icons.close_rounded),
                  ),
                ),
            ],
          ),
        ),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: _keywords.isEmpty ? _idle(prefs, recent) : _resultsView(layout),
      ),
    );
  }

  Widget _idle(UiPreferences? prefs, List<String> recent) {
    _hot ??= _loadHot();
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (recent.isNotEmpty) ...[
          SectionHeader(
            title: '搜索历史',
            trailing: [
              Tooltip(
                message: '清空历史',
                child: MiuixIconButton(
                  onPressed: () => prefs?.clearRecentSearches(),
                  child: const Icon(Icons.delete_sweep_outlined, size: 22),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final keyword in recent)
                  ActionChip(
                    label: Text(keyword),
                    onPressed: () => _submit(keyword),
                    shape: const StadiumBorder(),
                    side: BorderSide.none,
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                  ),
              ],
            ),
          ),
        ],
        const SectionHeader(title: '热搜榜', subtitle: '大家正在搜'),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _hot,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: LoadingView(),
              );
            }
            if (snap.hasError) {
              return MessageView(
                icon: Icons.search_rounded,
                message: '搜索歌曲、歌手、专辑、电台',
                actionLabel: '重新加载热搜',
                onAction: () => setState(() => _hot = _loadHot()),
              );
            }
            return _HotList(items: snap.data!, onTap: _submit);
          },
        ),
      ],
    );
  }

  Widget _resultsView(CollectionLayout layout) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: MiuixTabRow(
                  tabs: [for (final c in _Category.values) c.label],
                  selectedTabIndex: _category.index,
                  onTabSelected: (i) => setState(() {
                    _category = _Category.values[i];
                    _results = _search(_keywords, _category);
                  }),
                ),
              ),
              if (_category != _Category.song)
                const LayoutToggle(surface: LayoutSurface.search),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<_Results>(
            future: _results,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const LoadingView();
              }
              if (snap.hasError) {
                return MessageView.error(
                  snap.error!,
                  onRetry: () =>
                      setState(() => _results = _search(_keywords, _category)),
                );
              }
              final results = snap.data!;
              if (results.isEmpty) {
                return const MessageView(
                  icon: Icons.music_off_rounded,
                  message: '未找到结果',
                );
              }
              if (_category == _Category.song) {
                final tracks = results.tracks;
                return ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) => TrackTile(
                    track: tracks[i],
                    onTap: () => context.read<PlayerService>().setQueue(
                      tracks,
                      startAt: i,
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  MediaCollection(
                    items: results.items,
                    layout: layout,
                    onTap: (item) => openMedia(context, item),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HotList extends StatelessWidget {
  const _HotList({required this.items, required this.onTap});

  final List<Map<String, dynamic>> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 640 ? 2 : 1;
        final perColumn = (items.length / columns).ceil();
        Widget row(int i) {
          final item = items[i];
          final word = (item['searchWord'] ?? '').toString();
          final content = (item['content'] ?? '').toString();
          final top = i < 3;
          return InkWell(
            onTap: () => onTap(word),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: top ? cs.primary : cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          word,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: top ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        if (content.isNotEmpty)
                          Text(
                            content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (columns == 1) {
          return Column(
            children: [for (var i = 0; i < items.length; i++) row(i)],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var col = 0; col < columns; col++)
              Expanded(
                child: Column(
                  children: [
                    for (
                      var i = col * perColumn;
                      i < (col + 1) * perColumn && i < items.length;
                      i++
                    )
                      row(i),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
