// Headless render proof for the UI screens. No display, native libs, or
// network needed: we pump each screen's initial state and assert its widget
// tree builds and shows the expected content.
//
// These complement the on-device integration test (which proves playback) and
// the Windows build (which proves compilation): here we prove the widgets
// actually render without throwing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:nsnc/services/app_state.dart';
import 'package:nsnc/services/session_store.dart';
import 'package:nsnc/ui/library_screen.dart';
import 'package:nsnc/ui/search_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final store = await SessionStore.open();
  // No bootstrap() call -> status stays AuthStatus.unknown (logged out view).
  return AppState(client: NcmClient(), store: store);
}

Widget _wrap(AppState app, Widget child) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(home: child),
    );

void main() {
  testWidgets('SearchScreen renders its idle prompt', (tester) async {
    final app = await _freshAppState();
    await tester.pumpWidget(_wrap(app, const SearchScreen()));
    await tester.pump();

    // A search field and the idle hint should be present, no exceptions thrown.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('搜索'), findsWidgets);
  });

  testWidgets('LibraryScreen shows the login prompt when logged out',
      (tester) async {
    final app = await _freshAppState();
    expect(app.status, AuthStatus.unknown);

    await tester.pumpWidget(_wrap(app, const LibraryScreen()));
    await tester.pump();

    expect(find.text('登录后查看你的音乐库'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
  });
}
