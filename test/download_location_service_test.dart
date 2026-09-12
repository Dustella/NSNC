import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsnc/models/track.dart';
import 'package:nsnc/services/download_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory documents;
  late Directory downloads;
  late Directory custom;

  const track = Track(
    id: 42,
    name: 'A/B: Song?',
    artists: ['Artist'],
    album: 'Album',
    durationMs: 1000,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nsnc_download_test_');
    documents = Directory('${root.path}${Platform.pathSeparator}documents');
    downloads = Directory('${root.path}${Platform.pathSeparator}downloads');
    custom = Directory('${root.path}${Platform.pathSeparator}custom');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  DownloadLocationService createService(
    SharedPreferences preferences, {
    String? pickedDirectory,
  }) => DownloadLocationService.forTesting(
    preferences: preferences,
    platform: TargetPlatform.windows,
    documentsDirectory: () async => documents,
    downloadsDirectory: () async => downloads,
    directoryPicker: () async => pickedDirectory,
  );

  test('exports a user-visible copy to the default downloads folder', () async {
    final preferences = await SharedPreferences.getInstance();
    final service = createService(preferences);
    final source = File('${root.path}${Platform.pathSeparator}source.flac');
    await source.writeAsBytes([1, 2, 3, 4]);

    final exportedPath = await service.exportAudio(
      source: source,
      track: track,
    );

    expect(exportedPath, contains('${Platform.pathSeparator}NSNC'));
    expect(exportedPath, endsWith('Artist - A_B_ Song_ [42].flac'));
    expect(await File(exportedPath).readAsBytes(), [1, 2, 3, 4]);
    expect(await source.exists(), isTrue);
  });

  test('persists and uses a custom desktop download directory', () async {
    final preferences = await SharedPreferences.getInstance();
    final service = createService(preferences, pickedDirectory: custom.path);

    expect(await service.chooseCustomDirectory(), isTrue);
    expect(service.location, DownloadLocation.custom);
    expect(service.label, custom.path);

    final reopened = createService(preferences);
    expect(reopened.location, DownloadLocation.custom);
    expect(reopened.customPath, custom.path);

    final source = File('${root.path}${Platform.pathSeparator}source.mp3');
    await source.writeAsBytes([9, 8, 7]);
    final exportedPath = await reopened.exportAudio(
      source: source,
      track: track,
    );
    expect(File(exportedPath).parent.path, custom.path);
    expect(await File(exportedPath).readAsBytes(), [9, 8, 7]);
  });
}
