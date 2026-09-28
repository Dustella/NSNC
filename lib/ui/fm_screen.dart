import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/library_services.dart';
import '../services/player_service.dart';
import 'login_screen.dart';
import 'player_screen.dart';
import 'widgets/common.dart';

/// Personal FM: an endless personalised stream with like / dislike.
class PersonalFmScreen extends StatefulWidget {
  const PersonalFmScreen({super.key});

  @override
  State<PersonalFmScreen> createState() => _PersonalFmScreenState();
}

class _PersonalFmScreenState extends State<PersonalFmScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fm = context.read<PersonalFmService>();
      final loggedIn = context.read<AppState>().status == AuthStatus.loggedIn;
      if (loggedIn && !fm.isActive && !fm.isLoading) unawaited(_start());
    });
  }

  Future<void> _start() async {
    try {
      await context.read<PersonalFmService>().start();
    } catch (e) {
      if (mounted) showToast(context, '私人 FM 启动失败：${describeError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fm = context.watch<PersonalFmService>();
    final player = context.watch<PlayerService>();
    final track = fm.isActive ? player.current : null;
    final cs = Theme.of(context).colorScheme;

    Widget body;
    if (app.status != AuthStatus.loggedIn) {
      body = MessageView(
        icon: Icons.radio_rounded,
        message: '登录后即可收听根据你的口味生成的私人 FM',
        actionLabel: '去登录',
        onAction: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen())),
      );
    } else if (track == null) {
      body = fm.isLoading
          ? const LoadingView()
          : MessageView(
              icon: Icons.radio_rounded,
              message: fm.error == null
                  ? '私人 FM 已暂停'
                  : describeError(fm.error!),
              actionLabel: '开始收听',
              onAction: _start,
            );
    } else {
      final liked = context.select<LikeService, bool>(
        (l) => l.isLiked(track.id),
      );
      body = Stack(
        fit: StackFit.expand,
        children: [
          BlurredCover(url: track.albumArtUrl),
          SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, c) {
                final side = (c.maxWidth - 64).clamp(120.0, 340.0);
                final byHeight = (c.maxHeight - 260).clamp(120.0, 340.0);
                final coverSide = side < byHeight ? side : byHeight;
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PlayerScreen(),
                            ),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                coverRadiusOf(context, scale: 1.6),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 28,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: CoverArt(
                              url: track.albumArtUrl,
                              size: coverSide.toDouble(),
                              radius: coverRadiusOf(context, scale: 1.6),
                              imageSize: 800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            track.name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            track.artistLabel,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 14,
                          children: [
                            _RoundAction(
                              icon: Icons.thumb_down_alt_outlined,
                              tooltip: '不喜欢（跳过并减少推荐）',
                              onPressed: fm.trashCurrent,
                            ),
                            _RoundAction(
                              icon: liked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: liked ? cs.primary : null,
                              tooltip: liked ? '取消喜欢' : '喜欢',
                              onPressed: () => context
                                  .read<LikeService>()
                                  .toggle(track)
                                  .catchError((Object e) {
                                    if (context.mounted) {
                                      showToast(
                                        context,
                                        '操作失败：${describeError(e)}',
                                      );
                                    }
                                  }),
                            ),
                            SizedBox.square(
                              dimension: 72,
                              child: player.isBuffering
                                  ? const Padding(
                                      padding: EdgeInsets.all(20),
                                      child: MiuixCircularProgressIndicator(),
                                    )
                                  : MiuixFloatingActionButton(
                                      onPressed: player.togglePlay,
                                      child: Icon(
                                        player.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        size: 40,
                                      ),
                                    ),
                            ),
                            _RoundAction(
                              icon: Icons.skip_next_rounded,
                              tooltip: '下一首',
                              onPressed: player.next,
                            ),
                            _RoundAction(
                              icon: Icons.lyrics_outlined,
                              tooltip: '歌词与完整播放页',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const PlayerScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return MiuixScaffold(
      topBar: MiuixSmallTopAppBar(
        title: '私人 FM',
        navigationIcon: Tooltip(
          message: '返回',
          child: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Icon(Icons.arrow_back_rounded),
          ),
        ),
      ),
      content: (padding) => Padding(padding: padding, child: body),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.8),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 52,
            child: Icon(icon, color: color ?? cs.onSurface),
          ),
        ),
      ),
    );
  }
}
