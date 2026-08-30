import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'services/app_state.dart';
import 'services/player_service.dart';
import 'services/session_store.dart';
import 'services/cache_service.dart';
import 'services/playlist_repository.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must run before any media_kit Player is constructed.
  MediaKit.ensureInitialized();

  final store = await SessionStore.open();
  final device = await store.loadOrCreateDevice();
  final cacheSettings = await CacheSettings.open();
  CachedNetworkImageProvider.defaultCacheManager = cacheSettings.coverCache;
  final client = NcmClient(device: device);
  final PlayerService player;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    player = await AudioService.init<PlayerService>(
      builder: () =>
          PlayerService(client: client, audioStore: cacheSettings.audioStore),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.dustella.nsnc.playback',
        androidNotificationChannelName: '音乐播放',
        androidNotificationChannelDescription: '显示当前歌曲和播放控制',
        androidStopForegroundOnPause: false,
      ),
      cacheManager: cacheSettings.coverCache,
    );
  } else {
    player = PlayerService(
      client: client,
      audioStore: cacheSettings.audioStore,
    );
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    await player.initializeWindowsSmtc(coverCache: cacheSettings.coverCache);
  }

  runApp(
    NsncApp(
      client: client,
      store: store,
      player: player,
      cacheSettings: cacheSettings,
    ),
  );
}

class NsncApp extends StatelessWidget {
  const NsncApp({
    super.key,
    required this.client,
    required this.store,
    required this.player,
    required this.cacheSettings,
  });

  final NcmClient client;
  final SessionStore store;
  final PlayerService player;
  final CacheSettings cacheSettings;
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(client: client, store: store)..bootstrap(),
        ),
        ChangeNotifierProvider<PlayerService>.value(value: player),
        ChangeNotifierProvider<CacheSettings>.value(value: cacheSettings),
        Provider(
          create: (_) => PlaylistRepository(
            client: client,
            cache: cacheSettings.playlistCache,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'NSNC',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        home: const HomeShell(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    const seed = Color(0xFFC20C0C); // Netease red
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'sans-serif',
    );
  }
}
