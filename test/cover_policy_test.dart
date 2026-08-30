import 'package:flutter_test/flutter_test.dart';
import 'package:nsnc/services/cover_cache_manager.dart';
import 'package:nsnc/ui/lazy_network_image.dart';

void main() {
  test('Netease cover URLs use HTTPS', () {
    expect(
      normalizeCoverUrl('http://p1.music.126.net/hash/cover.jpg'),
      'https://p1.music.126.net/hash/cover.jpg',
    );
    expect(
      normalizeCoverUrl('http://example.com/cover.jpg'),
      'http://example.com/cover.jpg',
    );
  });

  test('Netease cover requests include CDN anti-hotlink headers', () {
    final headers = coverRequestHeaders(
      'https://p1.music.126.net/hash/cover.jpg',
    );

    expect(headers['Referer'], 'https://music.163.com/');
    expect(headers['User-Agent'], isNotEmpty);
    expect(coverRequestHeaders('https://example.com/cover.jpg'), isEmpty);
  });

  test('explicit request headers are preserved', () {
    final headers = coverRequestHeaders(
      'https://p1.music.126.net/hash/cover.jpg',
      const {'Referer': 'https://custom.example/', 'X-Test': 'yes'},
    );

    expect(headers['Referer'], 'https://custom.example/');
    expect(headers['X-Test'], 'yes');
  });
}
