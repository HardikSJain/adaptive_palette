import 'package:adaptive_palette/src/config.dart';
import 'package:adaptive_palette/src/models.dart';
import 'package:adaptive_palette/src/scoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Image Characteristics Analysis', () {
    test('detects colorful images', () {
      final swatches = [
        Swatch(Colors.red, 100),
        Swatch(Colors.blue, 100),
        Swatch(Colors.green, 100),
      ];

      final characteristics = analyzeImageCharacteristics(swatches);

      expect(characteristics.isColorful, isTrue);
      expect(characteristics.isMonochromatic, isFalse);
      expect(characteristics.type, 'colorful');
    });

    test('detects monochromatic images', () {
      final swatches = [
        const Swatch(Color(0xFFEEEEEE), 100),
        const Swatch(Color(0xFFCCCCCC), 100),
        const Swatch(Color(0xFF888888), 100),
      ];

      final characteristics = analyzeImageCharacteristics(swatches);

      expect(characteristics.isMonochromatic, isTrue);
      expect(characteristics.isColorful, isFalse);
      expect(characteristics.type, 'monochromatic');
    });

    test('detects few colors', () {
      final swatches = [
        Swatch(Colors.red, 100),
        Swatch(Colors.blue, 50),
      ];

      final characteristics = analyzeImageCharacteristics(swatches);

      expect(characteristics.hasFewColors, isTrue);
    });

    test('handles empty swatches', () {
      final characteristics = analyzeImageCharacteristics([]);

      expect(characteristics.isMonochromatic, isTrue);
      expect(characteristics.avgSaturation, 0);
      expect(characteristics.avgChroma, 0);
    });
  });

  group('Adaptive Thresholds', () {
    test('monochromatic images have lower thresholds', () {
      const mono = ImageCharacteristics(
        avgSaturation: 0.1,
        avgChroma: 10,
        isColorful: false,
        isMonochromatic: true,
        hasFewColors: false,
      );

      const colorful = ImageCharacteristics(
        avgSaturation: 0.5,
        avgChroma: 40,
        isColorful: true,
        isMonochromatic: false,
        hasFewColors: false,
      );

      final monoThresholds = getAdaptiveThresholds(mono);
      final colorfulThresholds = getAdaptiveThresholds(colorful);

      expect(monoThresholds.satThreshold,
          lessThan(colorfulThresholds.satThreshold));
      expect(monoThresholds.chromaThreshold,
          lessThan(colorfulThresholds.chromaThreshold));
    });
  });

  group('Adaptive Weights', () {
    test('colorful images prioritize chroma', () {
      const colorful = ImageCharacteristics(
        avgSaturation: 0.5,
        avgChroma: 40,
        isColorful: true,
        isMonochromatic: false,
        hasFewColors: false,
      );

      const mono = ImageCharacteristics(
        avgSaturation: 0.1,
        avgChroma: 10,
        isColorful: false,
        isMonochromatic: true,
        hasFewColors: false,
      );

      final colorfulWeights = getAdaptiveWeights(colorful);
      final monoWeights = getAdaptiveWeights(mono);

      expect(colorfulWeights.chromaWeight, greaterThan(monoWeights.chromaWeight));
      expect(colorfulWeights.popWeight, lessThan(monoWeights.popWeight));
    });

    test('weights sum to ~1.0', () {
      const characteristics = ImageCharacteristics(
        avgSaturation: 0.3,
        avgChroma: 20,
        isColorful: false,
        isMonochromatic: false,
        hasFewColors: false,
      );

      final weights = getAdaptiveWeights(characteristics);
      final sum = weights.popWeight + weights.chromaWeight + weights.toneWeight;

      expect(sum, closeTo(1.0, 0.01));
    });
  });

  group('Color Scoring', () {
    test('vibrant colors score higher', () {
      const characteristics = ImageCharacteristics(
        avgSaturation: 0.4,
        avgChroma: 30,
        isColorful: true,
        isMonochromatic: false,
        hasFewColors: false,
      );

      final vibrantSwatch = Swatch(Colors.red, 100);
      final graySwatch = const Swatch(Color(0xFF888888), 100);

      final vibrantScore = scoreColor(
        vibrantSwatch,
        characteristics,
        100,
      );
      final grayScore = scoreColor(
        graySwatch,
        characteristics,
        100,
      );

      expect(vibrantScore, greaterThan(grayScore));
    });

    test('near-black colors are penalized', () {
      const characteristics = ImageCharacteristics(
        avgSaturation: 0.4,
        avgChroma: 30,
        isColorful: true,
        isMonochromatic: false,
        hasFewColors: false,
      );

      final darkSwatch = const Swatch(Color(0xFF111111), 100);
      final normalSwatch = Swatch(Colors.blue, 100);

      final darkScore = scoreColor(darkSwatch, characteristics, 100);
      final normalScore = scoreColor(normalSwatch, characteristics, 100);

      expect(darkScore, lessThan(normalScore));
    });

    test('near-white colors are penalized', () {
      const characteristics = ImageCharacteristics(
        avgSaturation: 0.4,
        avgChroma: 30,
        isColorful: true,
        isMonochromatic: false,
        hasFewColors: false,
      );

      final lightSwatch = const Swatch(Color(0xFFF0F0F0), 100);
      final normalSwatch = Swatch(Colors.blue, 100);

      final lightScore = scoreColor(lightSwatch, characteristics, 100);
      final normalScore = scoreColor(normalSwatch, characteristics, 100);

      expect(lightScore, lessThan(normalScore));
    });

    test('diversity boost works', () {
      const characteristics = ImageCharacteristics(
        avgSaturation: 0.4,
        avgChroma: 30,
        isColorful: true,
        isMonochromatic: false,
        hasFewColors: false,
      );

      final topColors = [
        ScoredSwatch(Swatch(Colors.red, 100), 1.0),
      ];

      // Similar color to red
      final similarSwatch = const Swatch(Color(0xFFDD0000), 100);
      // Very different color
      final differentSwatch = Swatch(Colors.blue, 100);

      final similarScore = scoreColor(
        similarSwatch,
        characteristics,
        100,
        topColors: topColors,
        diversityWeight: 1.5,
      );

      final differentScore = scoreColor(
        differentSwatch,
        characteristics,
        100,
        topColors: topColors,
        diversityWeight: 1.5,
      );

      expect(differentScore, greaterThan(similarScore));
    });
  });

  group('Score Swatches Integration', () {
    test('returns sorted list by score', () {
      final swatches = [
        const Swatch(Color(0xFF888888), 200), // Gray, high pop
        Swatch(Colors.red, 50), // Vibrant, low pop
        Swatch(Colors.blue, 100), // Vibrant, medium pop
      ];

      const config = ExtractionConfig(diversityWeight: 1.1);
      final scored = scoreSwatches(swatches, config);

      expect(scored, isNotEmpty);
      expect(scored.length, swatches.length);

      // Check sorted descending by score
      for (int i = 0; i < scored.length - 1; i++) {
        expect(scored[i].score, greaterThanOrEqualTo(scored[i + 1].score));
      }
    });

    test('handles empty swatches', () {
      const config = ExtractionConfig();
      final scored = scoreSwatches([], config);
      expect(scored, isEmpty);
    });
  });

  group('Color Distance', () {
    test('identical colors have zero distance', () {
      final distance = computeColorDistance(Colors.red, Colors.red);
      expect(distance, closeTo(0, 0.1));
    });

    test('very different colors have high distance', () {
      final distance = computeColorDistance(Colors.red, Colors.blue);
      expect(distance, greaterThan(50));
    });

    test('similar colors have low distance', () {
      const color1 = Color(0xFFFF0000);
      const color2 = Color(0xFFFF1111);
      final distance = computeColorDistance(color1, color2);
      expect(distance, lessThan(20));
    });
  });
}
