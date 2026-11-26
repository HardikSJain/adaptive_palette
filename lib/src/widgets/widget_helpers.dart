/// Shared helpers for adaptive widgets.
library;

import '../material.dart';

import '../../adaptive_palette.dart' show AdaptivePalette;
import '../config.dart';
import '../models.dart';

/// Extract colors from an image provider safely with fallback.
///
/// This is used internally by all adaptive widgets to handle
/// extraction errors gracefully.
Future<ThemeColors> extractColorsFromProvider(
  ImageProvider provider,
  ExtractionConfig config,
  ThemeColors fallback,
) async {
  try {
    return await AdaptivePalette.fromImage(provider, config: config);
  } catch (error, stack) {
    config.onError?.call(error, stack);
    return fallback;
  }
}

/// Network image used by the `.network` factories of the legacy widgets.
///
/// Shows a neutral placeholder until the first frame arrives and when the
/// image fails to load. Uses Flutter's own [NetworkImage], so it shares the
/// in-memory [ImageCache] entry with the provider used for color extraction.
Widget networkBackgroundImage(
  String imageUrl, {
  required BoxFit fit,
  bool showBrokenIcon = false,
}) {
  return Image(
    image: NetworkImage(imageUrl),
    fit: fit,
    frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
      if (wasSynchronouslyLoaded || frame != null) return child;
      return const ColoredBox(color: Colors.black12);
    },
    errorBuilder: (_, __, ___) => ColoredBox(
      color: Colors.black12,
      child: showBrokenIcon
          ? const Icon(Icons.broken_image, color: Colors.white54)
          : null,
    ),
  );
}
