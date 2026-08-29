import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:provider/provider.dart';

import 'services/app_state.dart';
import 'services/player_service.dart';
import 'services/session_store.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must run before any media_kit Player is constructed.
  MediaKit.ensureInitialized();

  final store = await SessionStore.open();
  final device = await store.loadOrCreateDevice();
  final client = NcmClient(device: device);

  runApp(NsncApp(client: client, store: store));
}

class NsncApp extends StatelessWidget {
  const NsncApp({super.key, required this.client, required this.store});

  final NcmClient client;
  final SessionStore store;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(client: client, store: store)..bootstrap(),
        ),
        ChangeNotifierProvider(
          create: (_) => PlayerService(client: client),
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
