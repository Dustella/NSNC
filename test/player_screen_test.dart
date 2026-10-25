import 'dart:convert';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:nsnc/models/track.dart';
import 'package:nsnc/services/app_state.dart';
import 'package:nsnc/services/library_services.dart';
import 'package:nsnc/services/player_service.dart';
import 'package:nsnc/services/session_store.dart';
import 'package:nsnc/services/ui_preferences.dart';
import 'package:nsnc/theme/nsnc_theme.dart';
import 'package:nsnc/ui/player_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends Fake with ChangeNotifier implements PlayerService {
  _Player({this.isDownloading = false});

  @override
  bool isDownloading;
  @override
  final positionListenable = ValueNotifier(Duration.zero);
  @override
  final current = Track.fromJson({'id': 1, 'name': 'Test song'});
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  bool get isPlaying => false;
  @override
  bool get isBuffering => false;
  @override
  SongLevel get level => SongLevel.exhigh;
  @override
  Object? get lastError => null;
  @override
  bool get isShuffle => false;
  @override
  RepeatMode get repeatMode => RepeatMode.off;
  @override
  double get volume => 100;
  @override
  bool get isCurrentDownloaded => false;
  @override
  double get downloadProgress => 0.5;

  void finishDownload() {
    isDownloading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    positionListenable.dispose();
    super.dispose();
  }
}

Future<Widget> _app(_Player player) async {
  SharedPreferences.setMockInitialValues({});
  final client = NcmClient(
    httpClient: MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'code': 200,
            'lrc': {'lyric': '[00:00.00]Test lyric line'},
          }),
        ),
        200,
      ),
    ),
  );
  final app = AppState(client: client, store: await SessionStore.open());
  final prefs = UiPreferences.forTesting(await SharedPreferences.getInstance());
  await prefs.setPlayerBackground(PlayerBackground.plain);
  final likes = LikeService(client: client);
  addTearDown(client.close);
  addTearDown(app.dispose);
  addTearDown(prefs.dispose);
  addTearDown(likes.dispose);
  addTearDown(player.dispose);
  final theme = MiuixThemeData.light();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<PlayerService>.value(value: player),
      ChangeNotifierProvider<UiPreferences>.value(value: prefs),
      ChangeNotifierProvider<LikeService>.value(value: likes),
    ],
    child: MiuixTheme(
      data: theme,
      child: MaterialApp(
        theme: NsncTheme.light(miuix: theme.colors),
        home: const PlayerScreen(),
      ),
    ),
  );
}

void main() {
  testWidgets('lyrics survive resize and remain reachable from compact menu', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await _app(_Player()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('quality-selector')), findsNothing);
    await tester.tap(find.bySemanticsLabel('点击显示歌词'));
    await tester.pumpAndSettle();
    expect(find.text('Test lyric line'), findsOneWidget);

    tester.view.physicalSize = const Size(840, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quality-selector')), findsOneWidget);
    expect(find.text('Test lyric line'), findsOneWidget);

    tester.view.physicalSize = const Size(839, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quality-selector')), findsNothing);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示封面'));
    await tester.pumpAndSettle();
    expect(find.text('Test lyric line'), findsNothing);
    await tester.tap(find.bySemanticsLabel('点击显示歌词'));
    await tester.pumpAndSettle();
    expect(find.text('Test lyric line'), findsOneWidget);
  });

  testWidgets('download menu tracks completion without closing the sheet', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 860);
    addTearDown(tester.view.reset);
    final player = _Player(isDownloading: true);
    await tester.pumpWidget(await _app(player));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    final progress = find.text('正在下载：50%');
    await tester.ensureVisible(progress);
    await tester.tap(progress);
    await tester.pumpAndSettle();
    expect(progress, findsOneWidget);
    expect(find.text('选择音质'), findsNothing);

    player.finishDownload();
    await tester.pumpAndSettle();
    expect(progress, findsNothing);
    expect(find.text('下载当前歌曲'), findsOneWidget);

    final quality = find.text('音质：极高');
    await tester.ensureVisible(quality);
    await tester.tap(quality);
    await tester.pumpAndSettle();
    expect(progress, findsNothing);
    expect(find.text('选择音质'), findsOneWidget);
  });
}
