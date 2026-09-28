import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsnc/ui/widgets/miuix_extras.dart';

Widget _app(Widget child) => MiuixTheme(
  data: MiuixThemeData.light(),
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('floating sheet dismisses when tapping outside the card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showMiuixSheet<void>(
                context,
                title: '选择音质',
                builder: (_) =>
                    const SizedBox(height: 120, child: Text('body')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsOneWidget);
    expect(find.text('选择音质'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsNothing);
  });

  testWidgets('shortcut grid balances rows on narrow widths', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        ShortcutGrid(
          items: [
            for (var i = 0; i < 6; i++)
              Shortcut('item$i', Icons.star, Colors.red, () {}),
          ],
        ),
      ),
    );
    final first = tester.getTopLeft(find.text('item0'));
    final third = tester.getTopLeft(find.text('item2'));
    final fourth = tester.getTopLeft(find.text('item3'));
    expect(third.dy, first.dy, reason: 'first row holds three items');
    expect(fourth.dy, greaterThan(first.dy), reason: 'then wraps 3 + 3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirm dialog resolves true on confirm', (tester) async {
    bool? result;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showMiuixConfirm(
              context,
              title: '删除',
              message: '确定？',
              confirmLabel: '删除它',
              destructive: true,
            ),
            child: const Text('ask'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除它'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
