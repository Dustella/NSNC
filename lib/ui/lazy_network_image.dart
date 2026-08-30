import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Cached image used by lazily built list and grid children.
class LazyNetworkImage extends StatelessWidget {
  const LazyNetworkImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final Widget placeholder;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final imageUrl = normalizeCoverUrl(url);
    if (imageUrl == null || imageUrl.isEmpty) return placeholder;
    return Image(
      image: CachedNetworkImageProvider(imageUrl),
      width: width,
      height: height,
      fit: fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return placeholder;
      },
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}

String? normalizeCoverUrl(String? value) {
  if (value == null || value.isEmpty) return value;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'http') return value;
  if (uri.host == 'music.126.net' || uri.host.endsWith('.music.126.net')) {
    return uri.replace(scheme: 'https').toString();
  }
  return value;
}
