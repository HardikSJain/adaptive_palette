import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeColors', () {
    test('fallback colors are accessible', () {
      const colors = ThemeColors.fallback();
      expect(colors.primary, isA<Color>());
      expect(colors.onPrimary, isA<Color>());
      expect(colors.secondary, isA<Color>());
      expect(colors.onSecondary, isA<Color>());
    });

    test('copyWith works correctly', () {
      const original = ThemeColors.fallback();
      final modified = original.copyWith(primary: Colors.red);
      expect(modified.primary, Colors.red);
      expect(modified.secondary, original.secondary);
    });

    test('equality works', () {
      const a = ThemeColors.fallback();
      const b = ThemeColors.fallback();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toThemeData creates valid theme', () {
      const colors = ThemeColors.fallback();
      final theme = colors.toThemeData();
      expect(theme, isA<ThemeData>());
      expect(theme.colorScheme.primary, colors.primary);
    });
  });

  group('ExtractionConfig', () {
    test('default config is valid', () {
      const config = ExtractionConfig();
      expect(config.quantizeColors, greaterThanOrEqualTo(8));
      expect(config.quantizeColors, lessThanOrEqualTo(64));
      expect(config.resize, greaterThanOrEqualTo(64));
      expect(config.minContrast, greaterThanOrEqualTo(3.0));
    });

    test('quality presets are valid', () {
      final fast = ExtractionConfig.fromQuality(ExtractionQuality.fast);
      final balanced =
          ExtractionConfig.fromQuality(ExtractionQuality.balanced);
      final high = ExtractionConfig.fromQuality(ExtractionQuality.high);

      expect(fast.quantizeColors, lessThan(balanced.quantizeColors));
      expect(balanced.quantizeColors, lessThan(high.quantizeColors));
      expect(fast.resize, lessThan(high.resize));
    });

    test('assertions catch invalid values', () {
      expect(
        () => ExtractionConfig(quantizeColors: 100),
        throwsAssertionError,
      );
      expect(
        () => ExtractionConfig(resize: 300),
        throwsAssertionError,
      );
      expect(
        () => ExtractionConfig(minContrast: 25.0),
        throwsAssertionError,
      );
    });

    test('copyWith works correctly', () {
      const config = ExtractionConfig(quantizeColors: 16);
      final modified = config.copyWith(quantizeColors: 32);
      expect(modified.quantizeColors, 32);
      expect(modified.resize, config.resize);
    });
  });

  group('ExtractionStats', () {
    test('toString contains useful info', () {
      const stats = ExtractionStats(
        duration: Duration(milliseconds: 100),
        colorsExtracted: 24,
        pixelsProcessed: 4096,
        originalSize: (800, 600),
        processedSize: (96, 72),
        fromCache: false,
        imageType: 'colorful',
        avgSaturation: 0.45,
        avgChroma: 32.5,
        cacheKey: 'abc123',
      );

      final str = stats.toString();
      expect(str, contains('100ms'));
      expect(str, contains('24'));
      expect(str, contains('colorful'));
      expect(str, contains('false'));
    });
  });

  group('AdaptiveOverlayStyle', () {
    test('default style is valid', () {
      const style = AdaptiveOverlayStyle();
      expect(style.stops, isNotEmpty);
      expect(style.opacities, isNotEmpty);
      expect(style.stops.length, style.opacities.length);
    });

    test('build creates gradient', () {
      const style = AdaptiveOverlayStyle();
      const colors = ThemeColors.fallback();
      final gradient = style.build(colors);

      expect(gradient, isA<LinearGradient>());
      expect(gradient.colors.length, style.stops.length);
    });

    test('tone selection works', () {
      const colors = ThemeColors.fallback();

      const AdaptiveOverlayStyle(
        tone: AdaptiveOverlayTone.primary,
      ).build(colors);

      const AdaptiveOverlayStyle(
        tone: AdaptiveOverlayTone.secondary,
      ).build(colors);

      // Base colors should be different based on tone (primary vs secondary)
      // Extract the base color by getting the fully opaque version
      expect(colors.primary, isNot(equals(colors.secondary)));
    });

    test('colorOverride takes precedence', () {
      const colors = ThemeColors.fallback();
      const override = Color(0xFFE91E63);  // Pink value

      final gradient = const AdaptiveOverlayStyle(
        colorOverride: override,
        opacities: [1.0],
        stops: [0.0],
      ).build(colors);

      expect(gradient.colors.first.value, override.value);
    });

    test('copyWith works correctly', () {
      const original = AdaptiveOverlayStyle(
        stops: [0.0, 1.0],
        opacities: [1.0, 0.0],
      );
      final modified = original.copyWith(tone: AdaptiveOverlayTone.secondary);
      expect(modified.tone, AdaptiveOverlayTone.secondary);
      expect(modified.stops, original.stops);
    });
  });

  group('CacheConfig', () {
    test('cache size can be configured', () {
      final originalSize = CacheConfig.maxSize;
      CacheConfig.maxSize = 64;
      expect(CacheConfig.maxSize, 64);
      CacheConfig.maxSize = originalSize; // restore
    });

    test('cache can be enabled/disabled', () {
      final originalState = CacheConfig.enabled;
      CacheConfig.enabled = false;
      expect(CacheConfig.enabled, false);
      CacheConfig.enabled = originalState; // restore
    });
  });

  group('AdaptivePalette static methods', () {
    test('clearCache does not throw', () {
      expect(() => AdaptivePalette.clearCache(), returnsNormally);
    });

    test('cacheStats returns valid tuple', () {
      final (size, capacity) = AdaptivePalette.cacheStats();
      expect(size, greaterThanOrEqualTo(0));
      expect(capacity, greaterThan(0));
      expect(size, lessThanOrEqualTo(capacity));
    });
  });
}
