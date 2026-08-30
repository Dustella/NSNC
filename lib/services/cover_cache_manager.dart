import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

@visibleForTesting
Map<String, String> coverRequestHeaders(
  String url, [
  Map<String, String>? headers,
]) {
  final result = <String, String>{...?headers};
  final uri = Uri.tryParse(url);
  if (uri != null &&
      (uri.host == 'music.126.net' || uri.host.endsWith('.music.126.net'))) {
    result.putIfAbsent('Referer', () => 'https://music.163.com/');
    result.putIfAbsent('User-Agent', () => 'Mozilla/5.0 NSNC/0.1.0');
  }
  return result;
}

class CoverCacheManager extends CacheManager with ImageCacheManager {
  CoverCacheManager({required this.maxBytes})
    : super(
        Config(
          'nsnc_covers_v2',
          stalePeriod: const Duration(days: 90),
          maxNrOfCacheObjects: 10000,
          fileService: _TimedHttpFileService()..concurrentFetches = 4,
        ),
      );

  int maxBytes;
  Future<void>? _trimOperation;
  bool _trimRequested = false;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    await for (final response in super.getFileStream(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
    )) {
      yield response;
      if (response is FileInfo) unawaited(trimToLimit());
    }
  }

  Future<void> trimToLimit() {
    _trimRequested = true;
    final running = _trimOperation;
    if (running != null) return running;
    final operation = _drainTrimRequests();
    _trimOperation = operation;
    return operation.whenComplete(() => _trimOperation = null);
  }

  Future<void> _drainTrimRequests() async {
    while (_trimRequested) {
      _trimRequested = false;
      await _trim();
    }
  }

  Future<void> _trim() async {
    final repo = config.repo;
    await repo.open();
    final objects = await repo.getAllObjects();
    var total = objects.fold<int>(0, (sum, item) => sum + (item.length ?? 0));
    if (total <= maxBytes) return;
    objects.sort(
      (a, b) => (a.touched ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        b.touched ?? DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
    for (final object in objects) {
      if (total <= maxBytes) break;
      total -= object.length ?? 0;
      await removeFile(object.key);
    }
  }
}

class _TimedHttpFileService extends HttpFileService {
  static const _timeout = Duration(seconds: 15);

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await super
        .get(url, headers: coverRequestHeaders(url, headers))
        .timeout(_timeout);
    if (response.statusCode != 200 &&
        response.statusCode != 202 &&
        response.statusCode != 304) {
      return response;
    }
    return _TimedResponse(response);
  }
}

class _TimedResponse implements FileServiceResponse {
  _TimedResponse(this._delegate);

  final FileServiceResponse _delegate;

  @override
  Stream<List<int>> get content =>
      _delegate.content.timeout(_TimedHttpFileService._timeout);

  @override
  int? get contentLength => _delegate.contentLength;
  @override
  String? get eTag => _delegate.eTag;
  @override
  String get fileExtension => _delegate.fileExtension;
  @override
  int get statusCode => _delegate.statusCode;
  @override
  DateTime get validTill => _delegate.validTill;
}
