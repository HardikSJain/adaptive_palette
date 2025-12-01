/// Spotify/Luma-style dynamic theming from an image with contrast guardrails.
///
/// # Features
///
/// - **Intelligent color extraction** - Adaptive algorithm automatically adjusts to image types
/// - **Perceptual color science** - Uses CAM16/HCT color space for accurate analysis
/// - **Material Design 3** - Full M3 theming with tonal palettes
/// - **Accessible by default** - WCAG contrast validation ensures readable text
/// - **Animated transitions** - Smooth theme changes with PaletteScope
/// - **Performance optimized** - Content-based caching, efficient quantization
/// - **Ready-made widgets** - Drop-in overlays for Spotify/YouTube-style UIs
///
/// # Quick Start
///
/// ```dart
/// import 'package:adaptive_palette/adaptive_palette.dart';
///
/// // Extract colors from any ImageProvider
/// final colors = await AdaptivePalette.fromImage(
///   NetworkImage('https://example.com/image.jpg'),
///   targetBrightness: Brightness.dark,
/// );
///
/// // Or use quality presets
/// final colors = await AdaptivePalette.fromImage(
///   image,
///   config: ExtractionConfig.fromQuality(ExtractionQuality.high),
/// );
/// ```
///
/// # Usage with PaletteScope
///
/// ```dart
/// return PaletteScope(
///   seed: ThemeColors.fallback(),
///   brightness: Brightness.dark,
///   child: MaterialApp(
///     theme: PaletteScope.of(context).theme,
///     home: MyHomePage(),
///   ),
/// );
/// ```
///
/// # Pre-built Widgets
///
/// ```dart
/// // Spotify-style hero overlay
/// AdaptiveImageOverlay.network(
///   'https://example.com/cover.jpg',
///   child: Text('Your content'),
/// )
///
/// // YouTube-style glow border
/// AdaptiveGlowImageFrame.network(
///   'https://example.com/thumbnail.jpg',
///   blurRadius: 48,
/// )
///
/// // Full-screen adaptive background
/// AdaptiveGradientScaffold.network(
///   'https://example.com/hero.jpg',
///   appBar: AppBar(title: Text('Details')),
///   body: YourContent(),
/// )
/// ```
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// Core modules
import 'src/cache.dart';
import 'src/config.dart';
import 'src/extraction.dart';
import 'src/models.dart';
import 'src/palette_scope.dart';
import 'src/scoring.dart';
import 'src/theme.dart';

// Public exports
export 'src/config.dart';
export 'src/models.dart';
export 'src/palette_scope.dart';
export 'src/widgets/adaptive_glow_frame.dart';
export 'src/widgets/adaptive_gradient_scaffold.dart';
export 'src/widgets/adaptive_image_overlay.dart';

/// Main API for extracting adaptive color palettes from images.
///
/// This class provides the primary interface for color extraction with
/// intelligent algorithm that adapts to different image types.
class AdaptivePalette {
  AdaptivePalette._(); // Private constructor - all methods are static

  /// Extract a contrast-safe color palette from an ImageProvider.
  ///
  /// This is the main entry point for color extraction. It automatically:
  /// 1. Analyzes image characteristics (colorful/monochromatic/normal)
  /// 2. Extracts dominant colors using median-cut quantization
  /// 3. Scores colors based on perceptual qualities
  /// 4. Generates Material Design 3 theme with WCAG contrast validation
  /// 5. Caches results for instant future access
  ///
  /// Example with default settings:
  /// ```dart
  /// final colors = await AdaptivePalette.fromImage(
  ///   NetworkImage('https://example.com/image.jpg'),
  ///   targetBrightness: Brightness.dark,
  /// );
  /// ```
  ///
  /// Example with quality preset:
  /// ```dart
  /// final colors = await AdaptivePalette.fromImage(
  ///   image,
  ///   config: ExtractionConfig.fromQuality(ExtractionQuality.high),
  /// );
  /// ```
  ///
  /// Example with full configuration:
  /// ```dart
  /// final colors = await AdaptivePalette.fromImage(
  ///   image,
  ///   config: ExtractionConfig(
  ///     targetBrightness: Brightness.dark,
  ///     quantizeColors: 32,
  ///     resize: 128,
  ///     minContrast: 4.5,
  ///     diversityWeight: 1.2,
  ///     onDebug: (stats) => print(stats),
  ///   ),
  /// );
  /// ```
  ///
  /// For backwards compatibility, individual parameters are supported:
  /// ```dart
  /// final colors = await AdaptivePalette.fromImage(
  ///   image,
  ///   targetBrightness: Brightness.dark,
  ///   quantizeColors: 32,
  ///   resize: 128,
  ///   minContrast: 4.5,
  /// );
  /// ```
  static Future<ThemeColors> fromImage(
    ImageProvider provider, {
    // New: Accept full config object
    ExtractionConfig? config,
    // Legacy: Individual parameters for backwards compatibility
    Brightness? targetBrightness,
    int? quantizeColors,
    int? resize,
    double? minContrast,
  }) async {
    final startTime = DateTime.now();

    // Merge config with individual parameters (individual params take priority)
    final effectiveConfig = (config ?? const ExtractionConfig()).copyWith(
      targetBrightness: targetBrightness,
      quantizeColors: quantizeColors,
      resize: resize,
      minContrast: minContrast,
    );

    // Load image
    final img = await loadImageFromProvider(provider);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return const ThemeColors.fallback();

    // Check cache
    final key = computeImageHash(bytes.buffer.asUint8List());
    final cached = PaletteCache.instance.get(key);
    if (cached != null) {
      final duration = DateTime.now().difference(startTime);
      effectiveConfig.onDebug?.call(ExtractionStats(
        duration: duration,
        colorsExtracted: 0,
        pixelsProcessed: 0,
        originalSize: (img.width, img.height),
        processedSize: (img.width, img.height),
        fromCache: true,
        imageType: 'cached',
        avgSaturation: 0,
        avgChroma: 0,
        cacheKey: key,
      ));
      return cached;
    }

    final pixels = bytes.buffer.asUint8List();
    final w = img.width;
    final h = img.height;

    // Downsample for performance
    final sampled = downsampleImage(
      pixels,
      w,
      h,
      effectiveConfig.resize,
    );
    final sampledSize = _calculateSampledSize(
      w,
      h,
      effectiveConfig.resize,
    );

    // Extract colors using median-cut
    final swatches = extractColors(sampled, effectiveConfig.quantizeColors);

    // Score colors using adaptive algorithm
    final scored = scoreSwatches(swatches, effectiveConfig);

    if (scored.isEmpty) {
      return const ThemeColors.fallback();
    }

    // Get characteristics for stats
    final characteristics = analyzeImageCharacteristics(swatches);

    // Build theme from best seed color
    final seed = scored.first.color;
    final colors = buildTheme(
      seed,
      targetBrightness: effectiveConfig.targetBrightness,
      minContrast: effectiveConfig.minContrast,
    );

    // Cache result
    PaletteCache.instance.put(key, colors);

    // Report stats
    final duration = DateTime.now().difference(startTime);
    effectiveConfig.onDebug?.call(ExtractionStats(
      duration: duration,
      colorsExtracted: swatches.length,
      pixelsProcessed: sampled.length ~/ 4,
      originalSize: (w, h),
      processedSize: sampledSize,
      fromCache: false,
      imageType: characteristics.type,
      avgSaturation: characteristics.avgSaturation,
      avgChroma: characteristics.avgChroma,
      cacheKey: key,
    ));

    return colors;
  }

  /// Preload palettes for multiple images.
  ///
  /// Useful for warming the cache before showing a list of images.
  /// Failed extractions are omitted from the result.
  ///
  /// Example:
  /// ```dart
  /// final preloaded = await AdaptivePalette.warmup([
  ///   NetworkImage('https://example.com/image1.jpg'),
  ///   NetworkImage('https://example.com/image2.jpg'),
  ///   NetworkImage('https://example.com/image3.jpg'),
  /// ]);
  /// print('Preloaded ${preloaded.length} palettes');
  /// ```
  static Future<Map<ImageProvider, ThemeColors>> warmup(
    List<ImageProvider> providers, {
    ExtractionConfig config = const ExtractionConfig(),
  }) async {
    final results = <ImageProvider, ThemeColors>{};
    await Future.wait(
      providers.map((provider) async {
        try {
          final colors = await fromImage(provider, config: config);
          results[provider] = colors;
        } catch (e, stack) {
          debugPrint('AdaptivePalette.warmup: Failed to extract $provider: $e');
          config.onError?.call(e, stack);
        }
      }),
    );
    return results;
  }

  /// Animate the app theme to new colors inside a [PaletteScope].
  ///
  /// Convenience method equivalent to:
  /// ```dart
  /// PaletteScope.of(context).animateTo(colors);
  /// ```
  ///
  /// Example:
  /// ```dart
  /// final colors = await AdaptivePalette.fromImage(image);
  /// await AdaptivePalette.animateTo(context, colors);
  /// ```
  static Future<void> animateTo(
    BuildContext context,
    ThemeColors colors, {
    Duration duration = const Duration(milliseconds: 800),
    Curve curve = Curves.easeInOutCubicEmphasized,
  }) async {
    PaletteScope.of(context).animateTo(
      colors,
      duration: duration,
      curve: curve,
    );
  }

  /// Clear the palette cache.
  ///
  /// Useful for memory management or when you want to force re-extraction.
  ///
  /// Example:
  /// ```dart
  /// AdaptivePalette.clearCache();
  /// ```
  static void clearCache() {
    PaletteCache.instance.clear();
  }

  /// Get current cache statistics.
  ///
  /// Returns (current size, capacity).
  ///
  /// Example:
  /// ```dart
  /// final (size, capacity) = AdaptivePalette.cacheStats();
  /// print('Cache: $size/$capacity');
  /// ```
  static (int size, int capacity) cacheStats() {
    return (PaletteCache.instance.size, PaletteCache.instance.capacity);
  }
}

// Helper to calculate sampled image size
(int, int) _calculateSampledSize(int w, int h, int target) {
  if (w <= target && h <= target) return (w, h);
  final aspect = w / h;
  if (aspect >= 1.0) {
    return (target, (target / aspect).round());
  } else {
    return ((target * aspect).round(), target);
  }
}

// Update widget_helpers.dart implementation
// This needs to be accessible from widgets
Future<ThemeColors> extractColorsFromProviderImpl(
  ImageProvider provider,
  ExtractionConfig config,
  ThemeColors fallback,
) async {
  try {
    return await AdaptivePalette.fromImage(provider, config: config);
  } catch (error, stack) {
    debugPrint('AdaptivePalette: failed to extract colors: $error');
    if (kDebugMode) debugPrint('$stack');
    config.onError?.call(error, stack);
    return fallback;
  }
}
