import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:media_kit/media_kit.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:provider/provider.dart';

import 'services/app_state.dart';
import 'services/cache_service.dart';
import 'services/library_services.dart';
import 'services/player_service.dart';
import 'services/playlist_repository.dart';
import 'services/session_store.dart';
import 'services/ui_preferences.dart';
import 'theme/nsnc_theme.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must run before any media_kit Player is constructed.
  MediaKit.ensureInitialized();

  final store = await SessionStore.open();
  final device = await store.loadOrCreateDevice();
  final cacheSettings = await CacheSettings.open();
  final uiPreferences = await UiPreferences.open();
  CachedNetworkImageProvider.defaultCacheManager = cacheSettings.coverCache;
  final client = NcmClient(device: device);
  final PlayerService player;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    player = await AudioService.init<PlayerService>(
      builder: () => PlayerService(
        client: client,
        audioStore: cacheSettings.audioStore,
        downloadLocation: cacheSettings.downloadLocation,
      ),
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
      downloadLocation: cacheSettings.downloadLocation,
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
      uiPreferences: uiPreferences,
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
    required this.uiPreferences,
  });

  final NcmClient client;
  final SessionStore store;
  final PlayerService player;
  final CacheSettings cacheSettings;
  final UiPreferences uiPreferences;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(client: client, store: store)..bootstrap(),
        ),
        ChangeNotifierProvider<PlayerService>.value(value: player),
        ChangeNotifierProvider<CacheSettings>.value(value: cacheSettings),
        ChangeNotifierProvider<UiPreferences>.value(value: uiPreferences),
        ChangeNotifierProxyProvider<AppState, LikeService>(
          create: (_) => LikeService(client: client),
          update: (_, app, likes) =>
              (likes ?? LikeService(client: client))..sync(app),
        ),
        ChangeNotifierProvider(
          create: (_) => PersonalFmService(client: client, player: player),
        ),
        Provider(
          create: (_) => PlaylistRepository(
            client: client,
            cache: cacheSettings.playlistCache,
          ),
        ),
      ],
      child: const _ThemedApp(),
    );
  }
}

/// Resolves the MIUIX palette from the user's theme settings and derives the
/// Material theme from the same colours, so both widget families agree.
class _ThemedApp extends StatelessWidget {
  const _ThemedApp();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UiPreferences>();
    final staticPalette = prefs.accent == NsncAccent.miuix;
    final mode = switch ((prefs.themeMode, staticPalette)) {
      (ThemeMode.light, true) => MiuixColorSchemeMode.light,
      (ThemeMode.dark, true) => MiuixColorSchemeMode.dark,
      (ThemeMode.system, true) => MiuixColorSchemeMode.system,
      (ThemeMode.light, false) => MiuixColorSchemeMode.monetLight,
      (ThemeMode.dark, false) => MiuixColorSchemeMode.monetDark,
      (ThemeMode.system, false) => MiuixColorSchemeMode.monetSystem,
    };
    return MediaQuery.fromView(
      view: View.of(context),
      child: MiuixThemeController(
        colorSchemeMode: mode,
        keyColor: prefs.accent == NsncAccent.wallpaper
            ? null
            : prefs.accent.color,
        paletteStyle: prefs.palette.miuix,
        fontWeightAdjustment: 0,
        child: Builder(
          builder: (context) {
            final miuix = MiuixTheme.of(context);
            final dark = miuix.brightness == Brightness.dark;
            return MaterialApp(
              title: 'NSNC',
              debugShowCheckedModeBanner: false,
              theme: NsncTheme.light(miuix: dark ? null : miuix.colors),
              darkTheme: NsncTheme.dark(miuix: dark ? miuix.colors : null),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, child) => Material(
                type: MaterialType.transparency,
                child: child ?? const SizedBox.shrink(),
              ),
              home: const HomeShell(),
            );
          },
        ),
      ),
    );
  }
}
