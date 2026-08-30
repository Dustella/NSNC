import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ncm_api/ncm_api.dart';
import 'package:path_provider/path_provider.dart';

class AudioStore {
  AudioStore._({
    required this._cacheDirectory,
    required this._downloadDirectory,
    required this._cacheIndex,
    required this._downloadIndex,
    required this.maxCacheBytes,
  });

  final Directory _cacheDirectory;
  final Directory _downloadDirectory;
  final Map<String, _AudioEntry> _cacheIndex;
  final Map<String, _AudioEntry> _downloadIndex;
  final Map<String, Future<File>> _inFlight = {};
  Future<void> _indexMutation = Future.value();

  int maxCacheBytes;

  static Future<AudioStore> open({
    required int maxCacheBytes,
    Directory? rootDirectory,
  }) async {
    final root = rootDirectory ?? await getApplicationSupportDirectory();
    final cacheDirectory = Directory(
      '${root.path}${Platform.pathSeparator}audio_cache_v1',
    );
    final downloadDirectory = Directory(
      '${root.path}${Platform.pathSeparator}audio_downloads_v1',
    );
    await cacheDirectory.create(recursive: true);
    await downloadDirectory.create(recursive: true);

    final store = AudioStore._(
      cacheDirectory: cacheDirectory,
      downloadDirectory: downloadDirectory,
      cacheIndex: await _loadIndex(cacheDirectory),
      downloadIndex: await _loadIndex(downloadDirectory),
      maxCacheBytes: maxCacheBytes,
    );
    await store._removeMissingEntries();
    await store.trimToLimit();
    return store;
  }

  bool isDownloaded(int trackId) =>
      _downloadIndex.values.any((entry) => entry.trackId == trackId);

  int get downloadedCount => _downloadIndex.length;

  Future<File?> localForPlayback(int trackId, SongLevel level) async {
    final downloaded =
        _downloadIndex.entries
            .where((item) => item.value.trackId == trackId)
            .toList(growable: false)
          ..sort((a, b) => b.value.touched.compareTo(a.value.touched));
    if (downloaded.isNotEmpty) {
      return _touchAndResolve(
        downloaded.first.key,
        downloaded.first.value,
        downloaded: true,
      );
    }

    final key = _key(trackId, level);
    final cached = _cacheIndex[key];
    if (cached == null) return null;
    return _touchAndResolve(key, cached, downloaded: false);
  }

  Future<File> cacheFromUrl({
    required int trackId,
    required SongLevel level,
    required String url,
  }) {
    final key = _key(trackId, level);
    final existing = _cacheIndex[key];
    if (existing != null) {
      return _touchAndResolve(key, existing, downloaded: false).then((file) {
        if (file == null) throw StateError('Cached audio file disappeared');
        return file;
      });
    }
    return _downloadToStore(
      operationKey: 'cache:$key',
      directory: _cacheDirectory,
      index: _cacheIndex,
      indexKey: key,
      trackId: trackId,
      level: level,
      url: url,
      trimAfterWrite: true,
    );
  }

  Future<File?> promoteCachedDownload(int trackId, SongLevel level) async {
    final key = _key(trackId, level);
    final downloaded = _downloadIndex[key];
    if (downloaded != null) {
      return _touchAndResolve(key, downloaded, downloaded: true);
    }
    final cached = _cacheIndex[key];
    if (cached != null) return _promoteCached(key, cached, null);
    final caching = _inFlight['cache:$key'];
    if (caching == null) return null;
    await caching;
    final completed = _cacheIndex[key];
    return completed == null ? null : _promoteCached(key, completed, null);
  }

  Future<File> download({
    required int trackId,
    required SongLevel level,
    required String url,
    void Function(double progress)? onProgress,
  }) {
    final key = _key(trackId, level);
    final existing = _downloadIndex[key];
    if (existing != null) {
      return _touchAndResolve(key, existing, downloaded: true).then((file) {
        if (file == null) throw StateError('Downloaded audio file disappeared');
        onProgress?.call(1);
        return file;
      });
    }
    final cached = _cacheIndex[key];
    if (cached != null) {
      return _promoteCached(key, cached, onProgress);
    }
    final caching = _inFlight['cache:$key'];
    if (caching != null) {
      return caching.then((_) {
        final completed = _cacheIndex[key];
        if (completed == null) {
          throw StateError('Completed audio cache entry is missing');
        }
        return _promoteCached(key, completed, onProgress);
      });
    }
    return _downloadToStore(
      operationKey: 'download:$key',
      directory: _downloadDirectory,
      index: _downloadIndex,
      indexKey: key,
      trackId: trackId,
      level: level,
      url: url,
      trimAfterWrite: false,
      onProgress: onProgress,
    );
  }

  Future<File> _promoteCached(
    String key,
    _AudioEntry entry,
    void Function(double progress)? onProgress,
  ) async {
    final source = await _touchAndResolve(key, entry, downloaded: false);
    if (source == null) throw StateError('Cached audio file disappeared');
    final target = _file(_downloadDirectory, entry.fileName);
    final temporary = File('${target.path}.part');
    if (await temporary.exists()) await temporary.delete();
    await source.copy(temporary.path);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    await _mutateIndexes(() async {
      _downloadIndex[key] = _AudioEntry(
        trackId: entry.trackId,
        level: entry.level,
        fileName: entry.fileName,
        size: entry.size,
        touched: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveIndex(_downloadDirectory, _downloadIndex);
    });
    onProgress?.call(1);
    return target;
  }

  Future<void> trimToLimit() => _mutateIndexes(() async {
    var total = _cacheIndex.values.fold<int>(
      0,
      (sum, entry) => sum + entry.size,
    );
    if (total <= maxCacheBytes) return;
    final oldest = _cacheIndex.entries.toList()
      ..sort((a, b) => a.value.touched.compareTo(b.value.touched));
    for (final item in oldest) {
      if (total <= maxCacheBytes) break;
      total -= item.value.size;
      await _deleteEntry(_cacheDirectory, _cacheIndex, item.key, save: false);
    }
    await _saveIndex(_cacheDirectory, _cacheIndex);
  });

  Future<void> clearCache() => _mutateIndexes(() async {
    for (final entry in _cacheIndex.values) {
      final file = _file(_cacheDirectory, entry.fileName);
      if (await file.exists()) await file.delete();
    }
    _cacheIndex.clear();
    await _saveIndex(_cacheDirectory, _cacheIndex);
  });

  Future<File?> _touchAndResolve(
    String key,
    _AudioEntry entry, {
    required bool downloaded,
  }) async {
    final directory = downloaded ? _downloadDirectory : _cacheDirectory;
    final index = downloaded ? _downloadIndex : _cacheIndex;
    final file = _file(directory, entry.fileName);
    if (!await file.exists()) {
      await _mutateIndexes(() async {
        index.remove(key);
        await _saveIndex(directory, index);
      });
      return null;
    }
    await _mutateIndexes(() async {
      final current = index[key];
      if (current == null) return;
      current.touched = DateTime.now().millisecondsSinceEpoch;
      await _saveIndex(directory, index);
    });
    return file;
  }

  Future<File> _downloadToStore({
    required String operationKey,
    required Directory directory,
    required Map<String, _AudioEntry> index,
    required String indexKey,
    required int trackId,
    required SongLevel level,
    required String url,
    required bool trimAfterWrite,
    void Function(double progress)? onProgress,
  }) {
    final running = _inFlight[operationKey];
    if (running != null) return running;
    final operation = _downloadFile(
      directory: directory,
      index: index,
      indexKey: indexKey,
      trackId: trackId,
      level: level,
      url: url,
      trimAfterWrite: trimAfterWrite,
      onProgress: onProgress,
    );
    _inFlight[operationKey] = operation;
    return operation.whenComplete(() => _inFlight.remove(operationKey));
  }

  Future<File> _downloadFile({
    required Directory directory,
    required Map<String, _AudioEntry> index,
    required String indexKey,
    required int trackId,
    required SongLevel level,
    required String url,
    required bool trimAfterWrite,
    void Function(double progress)? onProgress,
  }) async {
    final extension = _extension(url);
    final fileName = '${trackId}_${level.name}$extension';
    final target = _file(directory, fileName);
    final temporary = File('${target.path}.part');
    if (await temporary.exists()) await temporary.delete();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.userAgentHeader, 'NSNC/0.1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'Audio download failed with HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final total = response.contentLength;
      var received = 0;
      final sink = temporary.openWrite();
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call((received / total).clamp(0, 1));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      final size = await target.length();
      await _mutateIndexes(() async {
        final previous = index[indexKey];
        if (previous != null && previous.fileName != fileName) {
          final oldFile = _file(directory, previous.fileName);
          if (await oldFile.exists()) await oldFile.delete();
        }
        index[indexKey] = _AudioEntry(
          trackId: trackId,
          level: level.name,
          fileName: fileName,
          size: size,
          touched: DateTime.now().millisecondsSinceEpoch,
        );
        await _saveIndex(directory, index);
      });
      if (trimAfterWrite) await trimToLimit();
      onProgress?.call(1);
      return target;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _removeMissingEntries() async {
    await _mutateIndexes(() async {
      await _removeMissing(_cacheDirectory, _cacheIndex);
      await _removeMissing(_downloadDirectory, _downloadIndex);
    });
  }

  Future<void> _removeMissing(
    Directory directory,
    Map<String, _AudioEntry> index,
  ) async {
    final missing = <String>[];
    for (final item in index.entries) {
      if (!await _file(directory, item.value.fileName).exists()) {
        missing.add(item.key);
      }
    }
    for (final key in missing) {
      index.remove(key);
    }
    if (missing.isNotEmpty) await _saveIndex(directory, index);
  }

  Future<void> _deleteEntry(
    Directory directory,
    Map<String, _AudioEntry> index,
    String key, {
    required bool save,
  }) async {
    final entry = index.remove(key);
    if (entry != null) {
      final file = _file(directory, entry.fileName);
      if (await file.exists()) await file.delete();
    }
    if (save) await _saveIndex(directory, index);
  }

  Future<T> _mutateIndexes<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _indexMutation = _indexMutation.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static String _key(int trackId, SongLevel level) => '$trackId:${level.name}';

  static String _extension(String url) {
    final segment = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
    final dot = segment.lastIndexOf('.');
    if (dot < 0) return '.audio';
    final extension = segment.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension)
        ? extension
        : '.audio';
  }

  static File _file(Directory directory, String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  static Future<Map<String, _AudioEntry>> _loadIndex(
    Directory directory,
  ) async {
    final file = _file(directory, 'index.json');
    if (!await file.exists()) return {};
    try {
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return decoded.map(
        (key, value) =>
            MapEntry(key, _AudioEntry.fromJson(value as Map<String, dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveIndex(
    Directory directory,
    Map<String, _AudioEntry> index,
  ) => _file(directory, 'index.json').writeAsString(
    jsonEncode(index.map((key, value) => MapEntry(key, value.toJson()))),
    flush: true,
  );
}

class _AudioEntry {
  _AudioEntry({
    required this.trackId,
    required this.level,
    required this.fileName,
    required this.size,
    required this.touched,
  });

  factory _AudioEntry.fromJson(Map<String, dynamic> json) => _AudioEntry(
    trackId: (json['trackId'] as num).toInt(),
    level: json['level'] as String,
    fileName: json['fileName'] as String,
    size: (json['size'] as num).toInt(),
    touched: (json['touched'] as num).toInt(),
  );

  final int trackId;
  final String level;
  final String fileName;
  final int size;
  int touched;

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'level': level,
    'fileName': fileName,
    'size': size,
    'touched': touched,
  };
}
