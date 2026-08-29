import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import 'discover_screen.dart';
import 'library_screen.dart';
import 'login_screen.dart';
import 'now_playing_bar.dart';
import 'search_screen.dart';

/// Root scaffold: adaptive navigation (bottom bar on narrow, rail on wide)
/// across Discover / Search / Library, with a persistent mini-player above.
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
  ];

  final _pages = const [
    DiscoverScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 720;
    final body = IndexedStack(index: _index, children: _pages);

    return Scaffold(
      body: SafeArea(
        child: wide ? _wideLayout(body) : body,
      ),
      bottomNavigationBar: wide
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NowPlayingBar(),
                NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: [
                    for (final d in _destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: d.label,
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _wideLayout(Widget body) {
    return Row(
      children: [
        NavigationRail(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          labelType: NavigationRailLabelType.all,
          leading: const _RailHeader(),
          destinations: [
            for (final d in _destinations)
              NavigationRailDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: Text(d.label),
              ),
          ],
        ),
        const VerticalDivider(width: 1),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const Text('NSNC',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _onAccountTap(context, loggedIn),
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
      ),
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
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('退出')),
          ],
        ),
      );
      if (confirm == true && context.mounted) {
        await context.read<AppState>().logout();
      }
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }
}

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
