import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import 'discover_screen.dart';
import 'library_screen.dart';
import 'login_screen.dart';
import 'now_playing_bar.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Root scaffold: adaptive navigation (bottom bar on narrow, rail on wide)
/// across Discover / Search / Library / Settings, with a persistent mini-player.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    _Dest('发现', Icons.explore_outlined, Icons.explore),
    _Dest('搜索', Icons.search_outlined, Icons.search),
    _Dest('音乐库', Icons.library_music_outlined, Icons.library_music),
    _Dest('设置', Icons.settings_outlined, Icons.settings),
  ];

  final _pages = const [
    DiscoverScreen(),
    SearchScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < _pages.length; i++)
          ExcludeSemantics(excluding: i != _index, child: _pages[i]),
      ],
    );

    return MiuixScaffold(
      bottomBar: wide
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NowPlayingBar(),
                MiuixNavigationBar(
                  children: [
                    for (var i = 0; i < _destinations.length; i++)
                      MiuixNavigationBarItem(
                        selected: _index == i,
                        onPressed: () => setState(() => _index = i),
                        icon: Icon(
                          _index == i
                              ? _destinations[i].selectedIcon
                              : _destinations[i].icon,
                        ),
                        label: _destinations[i].label,
                      ),
                  ],
                ),
              ],
            ),
      content: (padding) =>
          Padding(padding: padding, child: wide ? _wideLayout(body) : body),
    );
  }

  Widget _wideLayout(Widget body) {
    return Row(
      children: [
        MiuixNavigationRail(
          header: const _RailHeader(),
          children: [
            for (var i = 0; i < _destinations.length; i++)
              MiuixNavigationRailItem(
                selected: _index == i,
                onPressed: () => setState(() => _index = i),
                icon: Icon(
                  _index == i
                      ? _destinations[i].selectedIcon
                      : _destinations[i].icon,
                ),
                label: _destinations[i].label,
              ),
          ],
        ),
        Expanded(
          child: Column(
            children: [
              Expanded(child: body),
              const NowPlayingBar(),
            ],
          ),
        ),
      ],
    );
  }
}

class _RailHeader extends StatelessWidget {
  const _RailHeader();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final loggedIn = app.status == AuthStatus.loggedIn;
    return Column(
      children: [
        const Text(
          'NSNC',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 12),
        MiuixSurface(
          cornerRadius: 24,
          onPressed: () => _onAccountTap(context, loggedIn),
          child: CircleAvatar(
            radius: 20,
            backgroundImage: (loggedIn && app.avatarUrl != null)
                ? NetworkImage(app.avatarUrl!)
                : null,
            child: (loggedIn && app.avatarUrl != null)
                ? null
                : const Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 72,
          child: Text(
            loggedIn ? app.nickname : '未登录',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Future<void> _onAccountTap(BuildContext context, bool loggedIn) async {
    if (loggedIn) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('退出登录'),
          content: const Text('确定要退出当前账号吗？'),
          actions: [
            MiuixTextButton('取消', onPressed: () => Navigator.pop(c, false)),
            MiuixTextButton('退出', onPressed: () => Navigator.pop(c, true)),
          ],
        ),
      );
      if (confirm == true && context.mounted) {
        await context.read<AppState>().logout();
      }
    } else {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }
}

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
