import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

enum DownloadLocation { music, downloads, custom, appDocuments }

class DownloadLocationService extends ChangeNotifier {
  DownloadLocationService._({
    required this._preferences,
    required this._platform,
    required this._location,
    required this._customPath,
    MethodChannel? androidChannel,
    Future<Directory> Function()? documentsDirectory,
    Future<Directory?> Function()? downloadsDirectory,
    Future<String?> Function()? directoryPicker,
  }) : _androidChannel = androidChannel ?? _defaultAndroidChannel,
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _downloadsDirectory = downloadsDirectory ?? getDownloadsDirectory,
       _directoryPicker = directoryPicker ?? FilePicker.getDirectoryPath;

  static const _locationKey = 'download_location_v1';
  static const _customPathKey = 'download_custom_path_v1';
  static const _defaultAndroidChannel = MethodChannel(
    'com.dustella.nsnc/downloads',
  );

  final SharedPreferences _preferences;
  final TargetPlatform _platform;
  final MethodChannel _androidChannel;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory?> Function() _downloadsDirectory;
  final Future<String?> Function() _directoryPicker;

  DownloadLocation _location;
  String? _customPath;

  static Future<DownloadLocationService> open(
    SharedPreferences preferences,
  ) async {
    final platform = defaultTargetPlatform;
    final stored = preferences.getString(_locationKey);
    final customPath = preferences.getString(_customPathKey);
    final fallback = _defaultLocation(platform);
    final location = DownloadLocation.values
        .where((value) => value.name == stored)
        .firstOrNull;

    return DownloadLocationService._(
      preferences: preferences,
      platform: platform,
      location: _isSupported(location, platform) ? location! : fallback,
      customPath: customPath,
    );
  }

  @visibleForTesting
  factory DownloadLocationService.forTesting({
    required SharedPreferences preferences,
    required TargetPlatform platform,
    required Future<Directory> Function() documentsDirectory,
    required Future<Directory?> Function() downloadsDirectory,
    required Future<String?> Function() directoryPicker,
    MethodChannel? androidChannel,
  }) {
    final stored = preferences.getString(_locationKey);
    final location = DownloadLocation.values
        .where((value) => value.name == stored)
        .firstOrNull;
    return DownloadLocationService._(
      preferences: preferences,
      platform: platform,
      location: _isSupported(location, platform)
          ? location!
          : _defaultLocation(platform),
      customPath: preferences.getString(_customPathKey),
      documentsDirectory: documentsDirectory,
      downloadsDirectory: downloadsDirectory,
      directoryPicker: directoryPicker,
      androidChannel: androidChannel,
    );
  }

  DownloadLocation get location => _location;
  String? get customPath => _customPath;
  bool get isAndroid => _platform == TargetPlatform.android;
  bool get isIOS => _platform == TargetPlatform.iOS;
  bool get canChooseCustomDirectory =>
      _platform == TargetPlatform.windows ||
      _platform == TargetPlatform.macOS ||
      _platform == TargetPlatform.linux;

  String get label => switch (_location) {
    DownloadLocation.music => 'Music/NSNC',
    DownloadLocation.downloads => 'Downloads/NSNC',
    DownloadLocation.custom => _customPath ?? '选择文件夹',
    DownloadLocation.appDocuments => '文件 App/NSNC/Downloads',
  };

  String get platformHint {
    if (isAndroid) {
      return 'Android 10 及以上无需存储权限；旧版系统会在首次下载时请求授权';
    }
    if (isIOS) {
      return '受 iOS 沙盒限制，文件保存在“文件”App 的 NSNC/Downloads 中';
    }
    return '下载文件会保留在所选文件夹中';
  }

  Future<void> setAndroidLocation(DownloadLocation value) async {
    if (!isAndroid ||
        (value != DownloadLocation.music &&
            value != DownloadLocation.downloads)) {
      throw ArgumentError.value(value, 'value');
    }
    await _setLocation(value);
  }

  Future<bool> chooseCustomDirectory() async {
    if (!canChooseCustomDirectory) return false;
    final selected = await _directoryPicker();
    if (selected == null || selected.trim().isEmpty) return false;
    _customPath = selected;
    await _preferences.setString(_customPathKey, selected);
    await _setLocation(DownloadLocation.custom);
    return true;
  }

  Future<String> exportAudio({
    required File source,
    required Track track,
  }) async {
    if (!await source.exists()) {
      throw FileSystemException('下载源文件不存在', source.path);
    }
    final fileName = downloadFileName(track, source.path);
    final mimeType = _mimeType(fileName);

    if (isAndroid) {
      final result = await _androidChannel.invokeMethod<String>('exportAudio', {
        'sourcePath': source.path,
        'fileName': fileName,
        'mimeType': mimeType,
        'collection': _location == DownloadLocation.downloads
            ? 'downloads'
            : 'music',
        'title': track.name,
        'artist': track.artistLabel,
        'album': track.album,
      });
      if (result == null || result.isEmpty) {
        throw const FileSystemException('Android 未返回下载文件位置');
      }
      return result;
    }

    final directory = await _resolveFileDirectory();
    await directory.create(recursive: true);
    final target = File('${directory.path}${Platform.pathSeparator}$fileName');
    final temporary = File('${target.path}.part');
    if (await temporary.exists()) await temporary.delete();
    await source.copy(temporary.path);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    return target.path;
  }

  @visibleForTesting
  static String downloadFileName(Track track, String sourcePath) {
    final separator = sourcePath.lastIndexOf('.');
    final extension = separator >= 0
        ? sourcePath.substring(separator).toLowerCase()
        : '.audio';
    final safeExtension = RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension)
        ? extension
        : '.audio';
    final base = _sanitize(
      '${track.artistLabel} - ${track.name} [${track.id}]',
    );
    return '$base$safeExtension';
  }

  Future<Directory> _resolveFileDirectory() async {
    if (_location == DownloadLocation.custom && _customPath != null) {
      return Directory(_customPath!);
    }
    if (_platform == TargetPlatform.iOS) {
      final documents = await _documentsDirectory();
      return Directory('${documents.path}${Platform.pathSeparator}Downloads');
    }
    final downloads = await _downloadsDirectory();
    if (downloads != null) {
      return Directory('${downloads.path}${Platform.pathSeparator}NSNC');
    }
    final documents = await _documentsDirectory();
    return Directory('${documents.path}${Platform.pathSeparator}NSNC');
  }

  Future<void> _setLocation(DownloadLocation value) async {
    if (_location == value) return;
    _location = value;
    await _preferences.setString(_locationKey, value.name);
    notifyListeners();
  }

  static DownloadLocation _defaultLocation(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.android => DownloadLocation.music,
        TargetPlatform.iOS => DownloadLocation.appDocuments,
        _ => DownloadLocation.downloads,
      };

  static bool _isSupported(
    DownloadLocation? location,
    TargetPlatform platform,
  ) {
    if (location == null) return false;
    return switch (platform) {
      TargetPlatform.android =>
        location == DownloadLocation.music ||
            location == DownloadLocation.downloads,
      TargetPlatform.iOS => location == DownloadLocation.appDocuments,
      _ =>
        location == DownloadLocation.downloads ||
            location == DownloadLocation.custom,
    };
  }

  static String _sanitize(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (cleaned.isEmpty) return 'NSNC download';
    return cleaned.length <= 140 ? cleaned : cleaned.substring(0, 140).trim();
  }

  static String _mimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'mp3' => 'audio/mpeg',
      'flac' => 'audio/flac',
      'm4a' || 'mp4' => 'audio/mp4',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'aac' => 'audio/aac',
      _ => 'application/octet-stream',
    };
  }
}
