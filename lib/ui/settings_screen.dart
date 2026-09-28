import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/cache_service.dart';
import '../services/download_location_service.dart';
import '../services/ui_preferences.dart';
import 'login_screen.dart';
import 'widgets/common.dart';

enum _SettingsDialog { androidLocation, iosInfo }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _coverOptions = [64, 128, 256, 512, 1024];
  static const _playlistOptions = [16, 32, 64, 128, 256];
  static const _audioOptions = [1024, 2048, 5120, 10240, 20480];

  final _snackbarState = MiuixSnackbarHostState();
  _SettingsDialog? _dialog;

  @override
  void dispose() {
    _snackbarState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<CacheSettings>();
    return MiuixScaffold(
      topBar: const MiuixTopAppBar(title: '设置'),
      snackbarHost: MiuixSnackbarHost(state: _snackbarState),
      content: (padding) => Stack(
        children: [
          ListView(
            padding: padding.add(const EdgeInsets.symmetric(vertical: 8)),
            children: [
              const _AccountSettings(),
              const _AppearanceSettings(),
              const MiuixHorizontalDivider(),
              const MiuixSmallTitle('下载'),
              MiuixArrowPreference(
                title: '下载位置',
                summary:
                    '${settings.downloadLocationLabel}\n${settings.downloadLocationHint}',
                startAction: const Icon(Icons.folder_outlined),
                endActions:
                    settings.usesAndroidDownloadCollections ||
                        settings.canChooseDownloadDirectory
                    ? null
                    : const [Icon(Icons.info_outline)],
                onClick: () => unawaited(_changeDownloadLocation(settings)),
              ),
              const MiuixHorizontalDivider(),
              const MiuixSmallTitle('缓存'),
              _LimitPreference(
                title: '封面缓存上限',
                summary: '磁盘 LRU；最多同时下载 4 张封面',
                value: settings.coverLimitMiB,
                options: _coverOptions,
                onChanged: settings.setCoverLimitMiB,
              ),
              _LimitPreference(
                title: '歌单缓存上限',
                summary: '缓存歌单索引与每 100 首一页的歌曲信息',
                value: settings.playlistLimitMiB,
                options: _playlistOptions,
                onChanged: settings.setPlaylistLimitMiB,
              ),
              _LimitPreference(
                title: '音频缓存上限',
                summary: '播放过的音频按最近使用时间淘汰；下载歌曲不计入上限',
                value: settings.audioLimitMiB,
                options: _audioOptions,
                onChanged: settings.setAudioLimitMiB,
              ),
              const MiuixHorizontalDivider(),
              MiuixBasicComponent(
                title: '清空封面缓存',
                startAction: const Icon(Icons.image_outlined),
                onClick: () => unawaited(
                  _clear(action: settings.clearCovers, message: '封面缓存已清空'),
                ),
              ),
              MiuixBasicComponent(
                title: '清空歌单缓存',
                startAction: const Icon(Icons.queue_music_outlined),
                onClick: () => unawaited(
                  _clear(action: settings.clearPlaylists, message: '歌单缓存已清空'),
                ),
              ),
              MiuixBasicComponent(
                title: '清空音频缓存',
                summary: '不会删除手动下载的歌曲',
                startAction: const Icon(Icons.audio_file_outlined),
                onClick: () => unawaited(
                  _clear(action: settings.clearAudioCache, message: '音频缓存已清空'),
                ),
              ),
            ],
          ),
          _locationDialog(settings),
        ],
      ),
    );
  }

  Widget _locationDialog(CacheSettings settings) {
    final android = _dialog == _SettingsDialog.androidLocation;
    return MiuixOverlayDialog(
      show: _dialog != null,
      title: android ? '选择下载位置' : 'iOS 下载位置',
      summary: android
          ? null
          : 'iOS 不允许普通应用直接写入系统 Music 或 Downloads。'
                'NSNC 会把歌曲保存到“文件”App > 我的 iPhone > NSNC > Downloads，'
                '你可以在那里移动或分享文件，无需额外权限。',
      onDismissRequest: _closeDialog,
      content: android
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiuixRadioButtonPreference(
                  title: '音乐',
                  summary: 'Music/NSNC；其他音乐播放器可以发现',
                  selected:
                      settings.selectedDownloadLocation ==
                      DownloadLocation.music,
                  onClick: () => unawaited(
                    _selectAndroidLocation(settings, DownloadLocation.music),
                  ),
                ),
                MiuixRadioButtonPreference(
                  title: '下载',
                  summary: 'Downloads/NSNC；可在文件管理器中查看',
                  selected:
                      settings.selectedDownloadLocation ==
                      DownloadLocation.downloads,
                  onClick: () => unawaited(
                    _selectAndroidLocation(
                      settings,
                      DownloadLocation.downloads,
                    ),
                  ),
                ),
              ],
            )
          : Align(
              alignment: Alignment.centerRight,
              child: MiuixTextButton('知道了', onPressed: _closeDialog),
            ),
    );
  }

  Future<void> _changeDownloadLocation(CacheSettings settings) async {
    try {
      if (settings.usesAndroidDownloadCollections) {
        setState(() => _dialog = _SettingsDialog.androidLocation);
        return;
      }
      if (settings.canChooseDownloadDirectory) {
        await settings.chooseDownloadDirectory();
        return;
      }
      if (mounted) setState(() => _dialog = _SettingsDialog.iosInfo);
    } catch (error) {
      if (mounted) {
        unawaited(_snackbarState.showSnackbar('无法更改下载位置：$error'));
      }
    }
  }

  Future<void> _selectAndroidLocation(
    CacheSettings settings,
    DownloadLocation location,
  ) async {
    _closeDialog();
    try {
      await settings.setAndroidDownloadLocation(location);
    } catch (error) {
      if (mounted) {
        unawaited(_snackbarState.showSnackbar('无法更改下载位置：$error'));
      }
    }
  }

  void _closeDialog() {
    if (mounted) setState(() => _dialog = null);
  }

  Future<void> _clear({
    required Future<void> Function() action,
    required String message,
  }) async {
    try {
      await action();
      if (mounted) unawaited(_snackbarState.showSnackbar(message));
    } catch (error) {
      if (mounted) unawaited(_snackbarState.showSnackbar('操作失败：$error'));
    }
  }
}

class _LimitPreference extends StatelessWidget {
  const _LimitPreference({
    required this.title,
    required this.summary,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String summary;
  final int value;
  final List<int> options;
  final Future<void> Function(int value) onChanged;

  @override
  Widget build(BuildContext context) {
    final values = List<int>.of(options);
    if (!values.contains(value)) values.add(value);
    values.sort();
    return MiuixOverlayDropdownPreference(
      title: title,
      summary: summary,
      items: [for (final option in values) _formatSize(option)],
      selectedIndex: values.indexOf(value),
      onSelectedIndexChange: (index) => unawaited(onChanged(values[index])),
    );
  }

  String _formatSize(int value) => value >= 1024 && value % 1024 == 0
      ? '${value ~/ 1024} GiB'
      : '$value MiB';
}

/// Appearance, Discover-page modules and player customisation.
class _AppearanceSettings extends StatelessWidget {
  const _AppearanceSettings();

  static const _themeModes = [
    (ThemeMode.system, '跟随系统'),
    (ThemeMode.light, '浅色'),
    (ThemeMode.dark, '深色'),
  ];

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UiPreferences>();
    final isWallpaper = prefs.accent == NsncAccent.wallpaper;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MiuixSmallTitle('外观'),
        MiuixOverlayDropdownPreference(
          title: '深色模式',
          items: [for (final m in _themeModes) m.$2],
          selectedIndex: _themeModes.indexWhere((m) => m.$1 == prefs.themeMode),
          onSelectedIndexChange: (i) =>
              unawaited(prefs.setThemeMode(_themeModes[i].$1)),
        ),
        MiuixBasicComponent(
          title: '主题色',
          summary: isWallpaper
              ? '跟随系统壁纸取色（Android 12+，其他平台使用默认色）'
              : prefs.accent.label,
          bottomAction: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final accent in NsncAccent.values)
                  _AccentSwatch(
                    accent: accent,
                    selected: accent == prefs.accent,
                    onTap: () => unawaited(prefs.setAccent(accent)),
                  ),
              ],
            ),
          ),
        ),
        if (prefs.accent != NsncAccent.miuix)
          MiuixOverlayDropdownPreference(
            title: '色彩风格',
            summary: '由主题色生成整套配色的方式',
            items: [for (final p in PaletteStyle.values) p.label],
            selectedIndex: prefs.palette.index,
            onSelectedIndexChange: (i) =>
                unawaited(prefs.setPalette(PaletteStyle.values[i])),
          ),
        MiuixOverlayDropdownPreference(
          title: '封面圆角',
          items: [for (final c in CoverCorner.values) c.label],
          selectedIndex: prefs.coverCorner.index,
          onSelectedIndexChange: (i) =>
              unawaited(prefs.setCoverCorner(CoverCorner.values[i])),
        ),
        MiuixOverlayDropdownPreference(
          title: '默认列表样式',
          summary: '歌单、榜单与电台的默认展示方式；各页面右上角可单独切换',
          items: const ['列表', '卡片'],
          selectedIndex: prefs.defaultLayout == CollectionLayout.list ? 0 : 1,
          onSelectedIndexChange: (i) => unawaited(
            prefs.setDefaultLayout(
              i == 0 ? CollectionLayout.list : CollectionLayout.grid,
            ),
          ),
        ),
        const MiuixHorizontalDivider(),
        const MiuixSmallTitle('发现页模块'),
        for (final section in HomeSection.values)
          MiuixSwitchPreference(
            title: section.label,
            summary: section == HomeSection.daily ? '需要登录' : null,
            value: prefs.showsSection(section),
            onChanged: (v) => unawaited(prefs.setSection(section, v)),
          ),
        const MiuixHorizontalDivider(),
        const MiuixSmallTitle('播放页'),
        MiuixOverlayDropdownPreference(
          title: '播放页背景',
          items: [for (final b in PlayerBackground.values) b.label],
          selectedIndex: prefs.playerBackground.index,
          onSelectedIndexChange: (i) =>
              unawaited(prefs.setPlayerBackground(PlayerBackground.values[i])),
        ),
        MiuixSliderPreference(
          title: '歌词字号',
          value: prefs.lyricScale,
          min: 0.8,
          max: 1.6,
          steps: 7,
          valueText: '${(prefs.lyricScale * 100).round()}%',
          onValueChange: (v) => unawaited(prefs.setLyricScale(v)),
        ),
        MiuixSwitchPreference(
          title: '显示歌词翻译',
          summary: '外文歌曲在原文下方显示中文翻译',
          value: prefs.showTranslation,
          onChanged: (v) => unawaited(prefs.setShowTranslation(v)),
        ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final NsncAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wallpaper = accent == NsncAccent.wallpaper;
    return Tooltip(
      message: accent.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: '主题色 ${accent.label}',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? cs.onSurface : Colors.transparent,
                width: 2,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: wallpaper ? null : accent.color,
                gradient: wallpaper
                    ? const SweepGradient(
                        colors: [
                          Color(0xFFE57373),
                          Color(0xFFFFD54F),
                          Color(0xFF81C784),
                          Color(0xFF64B5F6),
                          Color(0xFFBA68C8),
                          Color(0xFFE57373),
                        ],
                      )
                    : null,
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 18,
                    )
                  : wallpaper
                  ? const Icon(
                      Icons.wallpaper_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountSettings extends StatelessWidget {
  const _AccountSettings();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final loggedIn = app.status == AuthStatus.loggedIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MiuixSmallTitle('账号'),
        MiuixArrowPreference(
          title: loggedIn ? app.nickname : '未登录',
          summary: loggedIn ? '点击退出登录' : '扫码或手机号登录网易云音乐',
          startAction: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: CoverArt(
              url: loggedIn ? app.avatarUrl : null,
              size: 40,
              circle: true,
              icon: Icons.person_rounded,
              imageSize: 120,
            ),
          ),
          onClick: () => loggedIn
              ? _confirmLogout(context)
              : Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                ),
        ),
        const MiuixHorizontalDivider(),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
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
  }
}
