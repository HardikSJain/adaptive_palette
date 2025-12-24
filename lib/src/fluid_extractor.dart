/// Advanced color extraction for fluid immersive backgrounds.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'fluid_palette.dart';

/// Extracts FluidPalette from images using advanced weighted k-means clustering.
///
/// This extractor uses a sophisticated algorithm optimized for creating
/// vibrant, accurate palettes for animated, immersive backgrounds:
///
/// 1. **Smart sampling** - Samples pixels with bias toward center and edges
/// 2. **Weighted clustering** - Uses k-means with vibrancy-based weighting
/// 3. **Perceptual scoring** - Ranks colors by saturation and mid-tone preference
/// 4. **Matte treatment** - Prevents over-bright whites, ensures rich colors
/// 5. **Dark base enforcement** - Guarantees base color is suitable for UI text
///
/// Example:
/// ```dart
/// final image = await loadImageFromProvider(NetworkImage(url));
/// final palette = await FluidPaletteExtractor.extract(image);
/// ```
class FluidPaletteExtractor {
  FluidPaletteExtractor._(); // Private constructor - static API only

  /// Extract a FluidPalette from a ui.Image.
  ///
  /// This is the main entry point for fluid palette extraction.
  ///
  /// The algorithm:
  /// 1. Samples pixels at regular intervals (stride = 10)
  /// 2. Filters out near-white, near-black, and near-gray pixels
  /// 3. Weights samples by vibrancy and distance from center
  /// 4. Runs weighted k-means clustering (k=6, 10 iterations)
  /// 5. Scores clusters by saturation and mid-tone preference
  /// 6. Applies matte treatment to prevent over-bright colors
  /// 7. Ensures base color is dark enough for white text
  ///
  /// Example:
  /// ```dart
  /// final image = await loadImageFromProvider(provider);
  /// final palette = await FluidPaletteExtractor.extract(image);
  /// ```
  static Future<FluidPalette> extract(ui.Image image) async {
    final ByteData? bd = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (bd == null) return const FluidPalette.fallback();

    final Uint8List px = bd.buffer.asUint8List();
    final int w = image.width;
    final int h = image.height;

    final List<_Vec3> samples = [];
    const int stride = 10;

    // Sample pixels with smart filtering
    for (int y = 0; y < h; y += stride) {
      for (int x = 0; x < w; x += stride) {
        final int i = (y * w + x) * 4;
        if (i + 3 >= px.length) continue;

        final int r = px[i];
        final int g = px[i + 1];
        final int b = px[i + 2];
        final int a = px[i + 3];
        if (a < 200) continue;

        final _ColorStats s = _ColorStats.fromRgb(r, g, b);

        // Filter out extremes
        if (s.lightness > 0.96) continue; // near-white
        if (s.lightness < 0.03) continue; // near-black
        if (s.sat < 0.05 && s.lightness > 0.85) continue; // near-gray

        // Weight by vibrancy and center proximity
        final double cx = (x / (w - 1)) - 0.5;
        final double cy = (y / (h - 1)) - 0.5;
        final double centerWeight =
            1.0 + (0.8 * (1.0 - (cx * cx + cy * cy).clamp(0.0, 1.0)));

        final double vib = (s.sat * 0.75 + s.lightness * 0.25);
        final double weight = (0.5 + vib) * centerWeight;

        samples.add(
          _Vec3(r.toDouble(), g.toDouble(), b.toDouble(), weight: weight),
        );
      }
    }

    if (samples.isEmpty) return const FluidPalette.fallback();

    // Run weighted k-means clustering
    final List<_Vec3> centers = _kmeansWeighted(samples, k: 6, iters: 10);
    centers.sort((a, b) => _clusterScore(b).compareTo(_clusterScore(a)));

    // Extract and enhance colors
    Color pick(int idx, {required double satB, required double lightB}) {
      if (idx >= centers.length) return const FluidPalette.fallback().accent1;
      final raw = _amplify(
        _toColor(centers[idx]),
        satBoost: satB,
        lightBoost: lightB,
      );
      return _matteizeIfTooBright(_matteizeWhite(raw));
    }

    final Color c0 = pick(0, satB: 1.15, lightB: 1.05);
    final Color c1 = pick(1, satB: 1.20, lightB: 1.05);
    final Color c2 = pick(2, satB: 1.18, lightB: 1.03);
    final Color c3 = pick(3, satB: 1.16, lightB: 1.02);
    final Color c4 = pick(4, satB: 1.14, lightB: 1.02);

    final Color base = _ensureBaseDark(c0);

    return FluidPalette(
      baseDark: base,
      accent1: c1,
      accent2: c2,
      accent3: c3,
      accent4: c4,
    );
  }

  /// Score a cluster based on vibrancy and mid-tone preference.
  static double _clusterScore(_Vec3 v) {
    final _ColorStats s = _ColorStats.fromRgb(
      v.x.round(),
      v.y.round(),
      v.z.round(),
    );
    final double vivid = s.sat;
    final double mid = 1.0 - (s.lightness - 0.55).abs(); // peak near mid
    final double penaltyGray = s.sat < 0.10 ? 0.25 : 1.0;
    return (vivid * 1.2 + mid * 0.8) * penaltyGray;
  }
}

// -------------------- Internal Helper Classes --------------------

/// 3D vector for RGB color representation with weighting.
class _Vec3 {
  _Vec3(this.x, this.y, this.z, {this.weight = 1.0});
  final double x;
  final double y;
  final double z;
  final double weight;

  /// Squared Euclidean distance to another vector.
  double dist2(_Vec3 o) {
    final dx = x - o.x, dy = y - o.y, dz = z - o.z;
    return dx * dx + dy * dy + dz * dz;
  }
}

/// Color statistics (saturation, lightness).
class _ColorStats {
  _ColorStats({required this.sat, required this.lightness});
  final double sat;
  final double lightness;

  static _ColorStats fromRgb(int r, int g, int b) {
    final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
    return _ColorStats(sat: hsl.saturation, lightness: hsl.lightness);
  }
}

// -------------------- K-means Clustering --------------------

/// Weighted k-means clustering in RGB space.
///
/// Returns k cluster centers weighted by sample importance.
List<_Vec3> _kmeansWeighted(
  List<_Vec3> pts, {
  required int k,
  required int iters,
}) {
  final rnd = math.Random(42);

  // Initialize centers using weighted random selection
  final List<_Vec3> centers = [];
  double sumW = pts.fold(0, (a, b) => a + b.weight);

  for (int i = 0; i < k; i++) {
    double r = rnd.nextDouble() * sumW;
    for (final p in pts) {
      r -= p.weight;
      if (r <= 0) {
        centers.add(_Vec3(p.x, p.y, p.z));
        break;
      }
    }
  }

  final List<int> assign = List.filled(pts.length, 0);

  // Iterate k-means
  for (int it = 0; it < iters; it++) {
    // Assignment step
    for (int i = 0; i < pts.length; i++) {
      double best = double.infinity;
      int bi = 0;
      for (int c = 0; c < centers.length; c++) {
        final d = pts[i].dist2(centers[c]);
        if (d < best) {
          best = d;
          bi = c;
        }
      }
      assign[i] = bi;
    }

    // Update step (weighted by sample weight)
    final sx = List.filled(k, 0.0);
    final sy = List.filled(k, 0.0);
    final sz = List.filled(k, 0.0);
    final sw = List.filled(k, 0.0);

    for (int i = 0; i < pts.length; i++) {
      final int c = assign[i];
      final p = pts[i];
      final w = p.weight;
      sx[c] += p.x * w;
      sy[c] += p.y * w;
      sz[c] += p.z * w;
      sw[c] += w;
    }

    for (int c = 0; c < k; c++) {
      if (sw[c] < 1e-6) continue;
      centers[c] = _Vec3(sx[c] / sw[c], sy[c] / sw[c], sz[c] / sw[c]);
    }
  }

  // Remove near-duplicates (colors within distance threshold)
  final out = <_Vec3>[];
  for (final c in centers) {
    if (out.every((o) => c.dist2(o) > 28 * 28)) {
      out.add(c);
    }
  }
  return out.length >= 5 ? out : centers;
}

// -------------------- Color Enhancement --------------------

/// Convert RGB vector to Flutter Color.
Color _toColor(_Vec3 v) {
  int r = v.x.round().clamp(0, 255);
  int g = v.y.round().clamp(0, 255);
  int b = v.z.round().clamp(0, 255);
  return Color.fromARGB(255, r, g, b);
}

/// Amplify saturation and lightness for more vibrant colors.
Color _amplify(
  Color c, {
  required double satBoost,
  required double lightBoost,
}) {
  final hsl = HSLColor.fromColor(c);
  final s = (hsl.saturation * satBoost).clamp(0.0, 0.95);
  final l = (hsl.lightness * lightBoost).clamp(0.0, 0.90);
  return hsl.withSaturation(s).withLightness(l).toColor();
}

/// Ensure base color is dark enough for white text (lightness ≤ 0.22).
Color _ensureBaseDark(Color c) {
  final hsl = HSLColor.fromColor(c);
  if (hsl.lightness <= 0.22) return c;
  return hsl.withLightness((hsl.lightness * 0.55).clamp(0.08, 0.22)).toColor();
}

/// Treat near-white colors as matte gray tints.
///
/// Prevents harsh pure whites in favor of subtle tinted grays.
Color _matteizeWhite(Color c, {double grayMix = 0.14, double satFloor = 0.10}) {
  final hsl = HSLColor.fromColor(c);
  if (hsl.lightness < 0.90) return c;

  final Color matteGray = const Color(0xFF989CA1);
  final Color mixed = Color.lerp(c, matteGray, grayMix) ?? c;

  final HSLColor m = HSLColor.fromColor(mixed);
  final double newL = (m.lightness * 0.72).clamp(0.50, 0.72);
  final double newS = math.max(m.saturation * 0.6, satFloor);
  return m.withLightness(newL).withSaturation(newS).toColor();
}

/// Clamp overly bright colors to matte range.
///
/// Prevents washed-out highlights while maintaining color character.
Color _matteizeIfTooBright(Color c) {
  final hsl = HSLColor.fromColor(c);
  if (hsl.lightness <= 0.82) return c;

  final HSLColor out = hsl
      .withLightness((hsl.lightness * 0.78).clamp(0.55, 0.78))
      .withSaturation((hsl.saturation * 0.75).clamp(0.06, 0.55));
  return out.toColor();
}
