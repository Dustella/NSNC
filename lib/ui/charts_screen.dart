import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../services/app_state.dart';
import '../services/ui_preferences.dart';
import 'navigation.dart';
import 'widgets/common.dart';
import 'widgets/detail_scaffold.dart';
import 'widgets/media_widgets.dart';

/// All official charts: the headline charts as cards, the rest in a
/// list/card collection.
class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  late Future<List<MediaItem>> _future = _load();

  Future<List<MediaItem>> _load() async {
    final raw = await context.read<AppState>().client.toplists();
    return raw
        .whereType<Map>()
        .map((e) => MediaItem.chart(Map<String, dynamic>.from(e)))
        .where((e) => e.id != 0)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<UiPreferences>().layoutFor(
      LayoutSurface.charts,
    );
    return DetailScaffold(
      title: '排行榜',
      body: FutureBuilder<List<MediaItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return MessageView.error(
              snap.error!,
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final charts = snap.data!;
          final featured = charts.take(4).toList();
          final rest = charts.skip(4).toList();
          void open(MediaItem item) => openMedia(context, item);
          return ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const SectionHeader(title: '官方榜', subtitle: '每日/每周更新'),
              MediaCollection(
                items: featured,
                layout: CollectionLayout.grid,
                maxCardWidth: 200,
                onTap: open,
              ),
              if (rest.isNotEmpty) ...[
                SectionHeader(
                  title: '更多榜单',
                  subtitle: '${rest.length} 个榜单',
                  trailing: const [LayoutToggle(surface: LayoutSurface.charts)],
                ),
                MediaCollection(items: rest, layout: layout, onTap: open),
              ],
            ],
          );
        },
      ),
    );
  }
}
