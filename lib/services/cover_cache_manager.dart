import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

final Set<String> _loggedCoverRequests = <String>{};
final Set<String> _loggedCoverErrors = <String>{};

void logCoverRequest(String url) {
  if (!kDebugMode || !_loggedCoverRequests.add(url)) return;
  debugPrint('[cover] widget request url=$url');
}

void logCoverError(String url, Object error) {
  if (!kDebugMode || !_loggedCoverErrors.add(url)) return;
  debugPrint('[cover] decode/error url=$url error=$error');
}

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
          fileService: _TimedLoggingHttpFileService()..concurrentFetches = 4,
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
    if (kDebugMode) {
      debugPrint('[cover] cache lookup url=$url key=${key ?? url}');
    }
    try {
      await for (final response in super.getFileStream(
        url,
        key: key,
        headers: headers,
        withProgress: withProgress,
      )) {
        if (kDebugMode && response is FileInfo) {
          final bytes = await response.file.length();
          debugPrint(
            '[cover] file source=${response.source.name} bytes=$bytes '
            'path=${response.file.path} url=$url',
          );
        }
        yield response;
        if (response is FileInfo) unawaited(trimToLimit());
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[cover] cache/error url=$url error=$error');
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
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

class _TimedLoggingHttpFileService extends HttpFileService {
  static const _timeout = Duration(seconds: 15);
  int _active = 0;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final started = DateTime.now();
    _active++;
    if (kDebugMode) debugPrint('[cover] HTTP start active=$_active url=$url');
    try {
      final requestHeaders = coverRequestHeaders(url, headers);
      final response = await super
          .get(url, headers: requestHeaders)
          .timeout(_timeout);
      if (kDebugMode) {
        debugPrint(
          '[cover] HTTP headers status=${response.statusCode} '
          'length=${response.contentLength} elapsedMs='
          '${DateTime.now().difference(started).inMilliseconds} url=$url',
        );
      }
      if (response.statusCode != 200 &&
          response.statusCode != 202 &&
          response.statusCode != 304) {
        _active--;
        if (kDebugMode) {
          debugPrint('[cover] HTTP rejected active=$_active url=$url');
        }
        return response;
      }
      return _TimedLoggingResponse(response, url, () {
        _active--;
        if (kDebugMode) {
          debugPrint('[cover] HTTP done active=$_active url=$url');
        }
      });
    } catch (error) {
      _active--;
      if (kDebugMode) {
        debugPrint('[cover] HTTP error active=$_active url=$url error=$error');
      }
      rethrow;
    }
  }
}

class _TimedLoggingResponse implements FileServiceResponse {
  _TimedLoggingResponse(this._delegate, this._url, this._onDone);

  final FileServiceResponse _delegate;
  final String _url;
  final VoidCallback _onDone;
  bool _completed = false;

  void _complete() {
    if (_completed) return;
    _completed = true;
    _onDone();
  }

  @override
  Stream<List<int>> get content => _delegate.content
      .timeout(_TimedLoggingHttpFileService._timeout)
      .transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleDone: (sink) {
            _complete();
            sink.close();
          },
          handleError: (error, stackTrace, sink) {
            _complete();
            if (kDebugMode) {
              debugPrint('[cover] HTTP stream error url=$_url error=$error');
            }
            sink.addError(error, stackTrace);
          },
        ),
      );

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
