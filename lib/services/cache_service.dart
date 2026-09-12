import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_store.dart';
import 'cover_cache_manager.dart';
import 'download_location_service.dart';

const _mib = 1024 * 1024;

class CacheSettings extends ChangeNotifier {
  CacheSettings._(
    this._prefs,
    this.coverCache,
    this.playlistCache,
    this.audioStore,
    this.downloadLocation,
  );

  static const _coverLimitKey = 'cover_cache_limit_mib_v1';
  static const _playlistLimitKey = 'playlist_cache_limit_mib_v1';
  static const _audioLimitKey = 'audio_cache_limit_mib_v1';

  final SharedPreferences _prefs;
  final CoverCacheManager coverCache;
  final PlaylistCache playlistCache;
  final AudioStore audioStore;
  final DownloadLocationService downloadLocation;

  int get coverLimitMiB => coverCache.maxBytes ~/ _mib;
  int get playlistLimitMiB => playlistCache.maxBytes ~/ _mib;
  int get audioLimitMiB => audioStore.maxCacheBytes ~/ _mib;
  String get downloadLocationLabel => downloadLocation.label;
  String get downloadLocationHint => downloadLocation.platformHint;
  bool get canChooseDownloadDirectory =>
      downloadLocation.canChooseCustomDirectory;
  bool get usesAndroidDownloadCollections => downloadLocation.isAndroid;
  bool get usesIOSDocuments => downloadLocation.isIOS;
  DownloadLocation get selectedDownloadLocation => downloadLocation.location;

  Future<void> setAndroidDownloadLocation(DownloadLocation value) async {
    await downloadLocation.setAndroidLocation(value);
    notifyListeners();
  }

  Future<bool> chooseDownloadDirectory() async {
    final changed = await downloadLocation.chooseCustomDirectory();
    if (changed) notifyListeners();
    return changed;
  }

  static Future<CacheSettings> open() async {
    final prefs = await SharedPreferences.getInstance();
    final storedCoverLimit = prefs.getInt(_coverLimitKey) ?? 256;
    final storedPlaylistLimit = prefs.getInt(_playlistLimitKey) ?? 64;
    final storedAudioLimit = prefs.getInt(_audioLimitKey) ?? 5120;
    final coverLimit = storedCoverLimit > 0 ? storedCoverLimit : 256;
    final playlistLimit = storedPlaylistLimit > 0 ? storedPlaylistLimit : 64;
    final audioLimit = storedAudioLimit > 0 ? storedAudioLimit : 5120;
    final coverCache = CoverCacheManager(maxBytes: coverLimit * _mib);
    final playlistCache = await PlaylistCache.open(
      maxBytes: playlistLimit * _mib,
    );
    final audioStore = await AudioStore.open(maxCacheBytes: audioLimit * _mib);
    final downloadLocation = await DownloadLocationService.open(prefs);
    return CacheSettings._(
      prefs,
      coverCache,
      playlistCache,
      audioStore,
      downloadLocation,
    );
  }

  Future<void> setCoverLimitMiB(int value) async {
    if (value <= 0) throw ArgumentError.value(value, 'value');
    coverCache.maxBytes = value * _mib;
    await _prefs.setInt(_coverLimitKey, value);
    await coverCache.trimToLimit();
    notifyListeners();
  }

  Future<void> setPlaylistLimitMiB(int value) async {
    if (value <= 0) throw ArgumentError.value(value, 'value');
    playlistCache.maxBytes = value * _mib;
    await _prefs.setInt(_playlistLimitKey, value);
    await playlistCache.trimToLimit();
    notifyListeners();
  }

  Future<void> setAudioLimitMiB(int value) async {
    if (value <= 0) throw ArgumentError.value(value, 'value');
    audioStore.maxCacheBytes = value * _mib;
    await _prefs.setInt(_audioLimitKey, value);
    await audioStore.trimToLimit();
    notifyListeners();
  }

  Future<void> clearCovers() async {
    await coverCache.emptyCache();
    notifyListeners();
  }

  Future<void> clearPlaylists() async {
    await playlistCache.clear();
    notifyListeners();
  }

  Future<void> clearAudioCache() async {
    await audioStore.clearCache();
    notifyListeners();
  }
}

class PlaylistCache {
  PlaylistCache._(this._directory, this._index, this.maxBytes);

  final Directory _directory;
  final Map<String, _PlaylistCacheEntry> _index;
  int maxBytes;

  static Future<PlaylistCache> open({
    required int maxBytes,
    Directory? directory,
  }) async {
    final Directory cacheDirectory;
    if (directory != null) {
      cacheDirectory = directory;
    } else {
      final support = await getApplicationSupportDirectory();
      cacheDirectory = Directory(
        '${support.path}${Platform.pathSeparator}playlist_cache_v1',
      );
    }
    await cacheDirectory.create(recursive: true);
    final indexFile = File(
      '${cacheDirectory.path}${Platform.pathSeparator}index.json',
    );
    var index = <String, _PlaylistCacheEntry>{};
    if (await indexFile.exists()) {
      try {
        final decoded =
            jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
        index = decoded.map(
          (key, value) => MapEntry(
            key,
            _PlaylistCacheEntry.fromJson(value as Map<String, dynamic>),
          ),
        );
      } catch (_) {
        index = {};
      }
    }
    final cache = PlaylistCache._(cacheDirectory, index, maxBytes);
    await cache._removeMissingEntries();
    await cache.trimToLimit();
    return cache;
  }

  Future<Map<String, dynamic>?> read(String key) async {
    final entry = _index[key];
    if (entry == null) return null;
    final file = _file(entry.fileName);
    if (!await file.exists()) {
      _index.remove(key);
      await _saveIndex();
      return null;
    }
    try {
      final value =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      entry.touched = DateTime.now().millisecondsSinceEpoch;
      await _saveIndex();
      return value;
    } catch (_) {
      await _remove(key);
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> value) async {
    final bytes = utf8.encode(jsonEncode(value));
    final fileName =
        '${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}.json';
    await _file(fileName).writeAsBytes(bytes, flush: true);
    _index[key] = _PlaylistCacheEntry(
      fileName: fileName,
      size: bytes.length,
      touched: DateTime.now().millisecondsSinceEpoch,
    );
    await trimToLimit();
    await _saveIndex();
  }

  Future<void> trimToLimit() async {
    var total = _index.values.fold<int>(0, (sum, entry) => sum + entry.size);
    if (total <= maxBytes) return;
    final oldest = _index.entries.toList()
      ..sort((a, b) => a.value.touched.compareTo(b.value.touched));
    for (final item in oldest) {
      if (total <= maxBytes) break;
      total -= item.value.size;
      await _remove(item.key, save: false);
    }
    await _saveIndex();
  }

  Future<void> clear() async {
    for (final entry in _index.values) {
      final file = _file(entry.fileName);
      if (await file.exists()) await file.delete();
    }
    _index.clear();
    await _saveIndex();
  }

  Future<void> removePrefix(String prefix) async {
    final keys = _index.keys.where((key) => key.startsWith(prefix)).toList();
    for (final key in keys) {
      await _remove(key, save: false);
    }
    if (keys.isNotEmpty) await _saveIndex();
  }

  Future<void> _removeMissingEntries() async {
    final missing = <String>[];
    for (final item in _index.entries) {
      if (!await _file(item.value.fileName).exists()) missing.add(item.key);
    }
    for (final key in missing) {
      _index.remove(key);
    }
    if (missing.isNotEmpty) await _saveIndex();
  }

  Future<void> _remove(String key, {bool save = true}) async {
    final entry = _index.remove(key);
    if (entry != null) {
      final file = _file(entry.fileName);
      if (await file.exists()) await file.delete();
    }
    if (save) await _saveIndex();
  }

  File _file(String name) =>
      File('${_directory.path}${Platform.pathSeparator}$name');

  Future<void> _saveIndex() =>
      File(
        '${_directory.path}${Platform.pathSeparator}index.json',
      ).writeAsString(
        jsonEncode(_index.map((key, value) => MapEntry(key, value.toJson()))),
        flush: true,
      );
}

class _PlaylistCacheEntry {
  _PlaylistCacheEntry({
    required this.fileName,
    required this.size,
    required this.touched,
  });

  factory _PlaylistCacheEntry.fromJson(Map<String, dynamic> json) =>
      _PlaylistCacheEntry(
        fileName: json['fileName'] as String,
        size: (json['size'] as num).toInt(),
        touched: (json['touched'] as num).toInt(),
      );

  final String fileName;
  final int size;
  int touched;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'size': size,
    'touched': touched,
  };
}
