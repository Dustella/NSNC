import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/cache_service.dart';
import '../services/download_location_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _coverOptions = [64, 128, 256, 512, 1024];
  static const _playlistOptions = [16, 32, 64, 128, 256];
  static const _audioOptions = [1024, 2048, 5120, 10240, 20480];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<CacheSettings>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionTitle('下载'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('下载位置'),
            subtitle: Text(
              '${settings.downloadLocationLabel}\n${settings.downloadLocationHint}',
            ),
            isThreeLine: true,
            trailing:
                settings.usesAndroidDownloadCollections ||
                    settings.canChooseDownloadDirectory
                ? const Icon(Icons.chevron_right)
                : const Icon(Icons.info_outline),
            onTap: () => _changeDownloadLocation(context, settings),
          ),
          const Divider(indent: 16, endIndent: 16),
          const _SectionTitle('缓存'),
          _LimitTile(
            title: '封面缓存上限',
            subtitle: '磁盘 LRU；最多同时下载 4 张封面',
            value: settings.coverLimitMiB,
            options: _coverOptions,
            onChanged: settings.setCoverLimitMiB,
          ),
          _LimitTile(
            title: '歌单缓存上限',
            subtitle: '缓存歌单索引与每 100 首一页的歌曲信息',
            value: settings.playlistLimitMiB,
            options: _playlistOptions,
            onChanged: settings.setPlaylistLimitMiB,
          ),
          _LimitTile(
            title: '音频缓存上限',
            subtitle: '播放过的音频按最近使用时间淘汰；下载歌曲不计入上限',
            value: settings.audioLimitMiB,
            options: _audioOptions,
            onChanged: settings.setAudioLimitMiB,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('清空封面缓存'),
            onTap: () => _clear(
              context,
              action: settings.clearCovers,
              message: '封面缓存已清空',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_outlined),
            title: const Text('清空歌单缓存'),
            onTap: () => _clear(
              context,
              action: settings.clearPlaylists,
              message: '歌单缓存已清空',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.audio_file_outlined),
            title: const Text('清空音频缓存'),
            subtitle: const Text('不会删除手动下载的歌曲'),
            onTap: () => _clear(
              context,
              action: settings.clearAudioCache,
              message: '音频缓存已清空',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeDownloadLocation(
    BuildContext context,
    CacheSettings settings,
  ) async {
    try {
      if (settings.usesAndroidDownloadCollections) {
        final selected = await showDialog<DownloadLocation>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: const Text('选择下载位置'),
            children: [
              ListTile(
                leading: Icon(
                  settings.selectedDownloadLocation == DownloadLocation.music
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: const Text('音乐'),
                subtitle: const Text('Music/NSNC；其他音乐播放器可以发现'),
                onTap: () =>
                    Navigator.pop(dialogContext, DownloadLocation.music),
              ),
              ListTile(
                leading: Icon(
                  settings.selectedDownloadLocation ==
                          DownloadLocation.downloads
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: const Text('下载'),
                subtitle: const Text('Downloads/NSNC；可在文件管理器中查看'),
                onTap: () =>
                    Navigator.pop(dialogContext, DownloadLocation.downloads),
              ),
            ],
          ),
        );
        if (selected != null) {
          await settings.setAndroidDownloadLocation(selected);
        }
        return;
      }

      if (settings.canChooseDownloadDirectory) {
        await settings.chooseDownloadDirectory();
        return;
      }

      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('iOS 下载位置'),
          content: const Text(
            'iOS 不允许普通应用直接写入系统 Music 或 Downloads。'
            'NSNC 会把歌曲保存到“文件”App > 我的 iPhone > NSNC > Downloads，'
            '你可以在那里移动或分享文件，无需额外权限。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法更改下载位置：$error')));
    }
  }

  Future<void> _clear(
    BuildContext context, {
    required Future<void> Function() action,
    required String message,
  }) async {
    await action();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _LimitTile extends StatelessWidget {
  const _LimitTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final int value;
  final List<int> options;
  final Future<void> Function(int value) onChanged;

  @override
  Widget build(BuildContext context) {
    final values = List<int>.of(options);
    if (!values.contains(value)) values.add(value);
    values.sort();
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: DropdownButton<int>(
        value: value,
        items: [
          for (final option in values)
            DropdownMenuItem(
              value: option,
              child: Text(
                option >= 1024 && option % 1024 == 0
                    ? '${option ~/ 1024} GiB'
                    : '$option MiB',
              ),
            ),
        ],
        onChanged: (next) {
          if (next != null && next != value) onChanged(next);
        },
      ),
    );
  }
}
