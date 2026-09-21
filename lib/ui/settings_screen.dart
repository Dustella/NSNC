import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../services/cache_service.dart';
import '../services/download_location_service.dart';

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
