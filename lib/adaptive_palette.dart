/// Spotify/Luma-style dynamic theming from an image with contrast guardrails.
/// - Fast median-cut quantization
/// - CAM16/HCT tonality via material_color_utilities
/// - WCAG contrast checks
/// - Small in-memory cache keyed by image content hash
/// - Simple animated theme handoff via PaletteScope
///
/// Usage (minimal):
/// ```dart
/// return PaletteScope(
///   seed: const ThemeColors.fallback(),
///   child: Builder(
///     builder: (context) {
///       return FutureBuilder<ThemeColors>(
///         future: AdaptivePalette.fromImage(
///           const AssetImage('assets/cover.jpg'),
///         ),
///         builder: (_, snap) {
///           final colors = snap.data;
///           if (colors != null) PaletteScope.of(context).animateTo(colors);
///           return MaterialApp(
///             theme: PaletteScope.of(context).theme,
///             home: const MyHome(),
///           );
///         },
///       );
///     },
///   ),
/// );
/// ```
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart' as mcu;
import 'package:crypto/crypto.dart' as crypto;

// ------------------------------
// Public API
// ------------------------------

class ThemeColors {
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color background;
  final Color onBackground;
  final Color surface;
  final Color onSurface;

  const ThemeColors({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.background,
    required this.onBackground,
    required this.surface,
    required this.onSurface,
  });

  const ThemeColors.fallback()
    : primary = const Color(0xFF0EA5A3),
      onPrimary = Colors.white,
      secondary = const Color(0xFF1E293B),
      onSecondary = Colors.white,
      background = const Color(0xFF0A0A0A),
      onBackground = const Color(0xFFE0E0E0),
      surface = const Color(0xFF121212),
      onSurface = const Color(0xFFE0E0E0);

  ThemeColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? secondary,
    Color? onSecondary,
    Color? background,
    Color? onBackground,
    Color? surface,
    Color? onSurface,
  }) => ThemeColors(
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    secondary: secondary ?? this.secondary,
    onSecondary: onSecondary ?? this.onSecondary,
    background: background ?? this.background,
    onBackground: onBackground ?? this.onBackground,
    surface: surface ?? this.surface,
    onSurface: onSurface ?? this.onSurface,
  );

  static ThemeData toThemeData(
    ThemeColors c, {
    Brightness brightness = Brightness.light,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.secondary,
      onSecondary: c.onSecondary,
      error: const Color(0xFFB00020),
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.onSurface,
    );
    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.background,
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.primary),
      ),
    );
  }
}

class AdaptivePalette {
  /// Builds a contrast-safe ThemeColors from an [ImageProvider].
  /// OPTIMIZED: Reduced defaults for better performance
  static Future<ThemeColors> fromImage(
    ImageProvider provider, {
    Brightness targetBrightness = Brightness.light,
    int quantizeColors = 24, // Reduced from 48 for speed
    int resize = 96, // Reduced from 128 for speed
    double minContrast = 4.5, // WCAG AA small text
  }) async {
    final img = await _imageFromProvider(provider);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return const ThemeColors.fallback();

    final key = _sha1(bytes.buffer.asUint8List());
    final cached = _PaletteCache.instance.get(key);
    if (cached != null) return cached;

    final pixels = bytes.buffer.asUint8List();
    final w = img.width;
    final h = img.height;

    // Downsample aggressively for performance
    final sampled = _downsampleRgba(pixels, w, h, resize);

    // Quantize with fewer colors for speed
    final swatches = _medianCut(sampled, quantizeColors);
    final scored = _scoreSwatches(swatches);

    final seed = scored.first.color; // most promising seed

    final colors = _buildTheme(
      seed,
      targetBrightness: targetBrightness,
      minContrast: minContrast,
    );
    _PaletteCache.instance.put(key, colors);
    return colors;
  }

  /// Animate the app theme to [colors] inside a [PaletteScope].
  static Future<void> animateToPalette(
    BuildContext context,
    ThemeColors colors, {
    Duration duration = const Duration(milliseconds: 800),
    Curve curve = Curves.easeInOutCubicEmphasized,
  }) async {
    PaletteScope.of(
      context,
    ).animateTo(colors, duration: duration, curve: curve);
  }
}

// ------------------------------
// PaletteScope: Animated Theme container
// ------------------------------

class PaletteScope extends StatefulWidget {
  final ThemeColors seed;
  final Widget child;
  final Brightness brightness;

  const PaletteScope({
    super.key,
    required this.seed,
    required this.child,
    this.brightness = Brightness.light,
  });

  static PaletteController of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_PaletteInherited>();
    assert(
      inherited != null,
      'PaletteScope.of() called with no PaletteScope in context',
    );
    return inherited!.controller;
  }

  @override
  State<PaletteScope> createState() => _PaletteScopeState();
}

class _PaletteScopeState extends State<PaletteScope>
    with SingleTickerProviderStateMixin {
  late PaletteController controller;

  @override
  void initState() {
    super.initState();
    controller = PaletteController(
      widget.seed,
      vsync: this,
      brightness: widget.brightness,
    );
  }

  @override
  void didUpdateWidget(covariant PaletteScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brightness != widget.brightness) {
      controller = PaletteController(
        controller.current,
        vsync: this,
        brightness: widget.brightness,
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller._anim,
      builder: (_, child) {
        return _PaletteInherited(
          controller: controller,
          child: Theme(data: controller.theme, child: child!),
        );
      },
      child: widget.child,
    );
  }
}

class _PaletteInherited extends InheritedWidget {
  final PaletteController controller;
  const _PaletteInherited({required this.controller, required super.child});

  @override
  bool updateShouldNotify(covariant _PaletteInherited oldWidget) =>
      controller != oldWidget.controller;
}

class PaletteController extends ChangeNotifier {
  late ThemeColors _current;
  late ThemeColors _target;
  final Brightness brightness;
  final AnimationController _anim;

  PaletteController(
    ThemeColors seed, {
    required TickerProvider vsync,
    required this.brightness,
  }) : _current = seed,
       _target = seed,
       _anim = AnimationController(
         vsync: vsync,
         duration: const Duration(milliseconds: 1),
       )..value = 1.0;

  ThemeData get theme => ThemeColors.toThemeData(
    _lerp(_current, _target, _anim.value),
    brightness: brightness,
  );

  ThemeColors get current => _target;

  void animateTo(
    ThemeColors colors, {
    Duration duration = const Duration(milliseconds: 420),
    Curve curve = Curves.easeOutCubic,
  }) {
    _current = _lerp(
      _current,
      _target,
      _anim.value,
    ); // freeze current from ongoing anim
    _target = colors;
    _anim.stop();
    _anim.duration = duration;
    _anim.forward(from: 0.0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }
}

ThemeColors _lerp(ThemeColors a, ThemeColors b, double t) {
  Color l(Color x, Color y) => Color.lerp(x, y, t)!;
  return ThemeColors(
    primary: l(a.primary, b.primary),
    onPrimary: l(a.onPrimary, b.onPrimary),
    secondary: l(a.secondary, b.secondary),
    onSecondary: l(a.onSecondary, b.onSecondary),
    background: l(a.background, b.background),
    onBackground: l(a.onBackground, b.onBackground),
    surface: l(a.surface, b.surface),
    onSurface: l(a.onSurface, b.onSurface),
  );
}

// ------------------------------
// Quantization + Scoring
// ------------------------------

class _Swatch {
  final Color color;
  final int population;
  const _Swatch(this.color, this.population);
}

// Helper class for median cut algorithm
class _ColorBox {
  final List<int> colors;
  final List<int> counts;
  late int rmin, rmax, gmin, gmax, bmin, bmax, total;

  _ColorBox(this.colors, this.counts) {
    rmin = 31;
    rmax = 0;
    gmin = 63;
    gmax = 0;
    bmin = 31;
    bmax = 0;
    total = 0;
    for (int i = 0; i < colors.length; i++) {
      final c = colors[i];
      final count = counts[i];
      final r = (c >> 11) & 31;
      final g = (c >> 5) & 63;
      final b = c & 31;
      if (r < rmin) rmin = r;
      if (r > rmax) rmax = r;
      if (g < gmin) gmin = g;
      if (g > gmax) gmax = g;
      if (b < bmin) bmin = b;
      if (b > bmax) bmax = b;
      total += count;
    }
  }

  int rangeR() => rmax - rmin;
  int rangeG() => gmax - gmin;
  int rangeB() => bmax - bmin;
}

List<_Swatch> _medianCut(Uint8List rgba, int k) {
  // Build histogram in RGB565 space for speed
  final Map<int, int> hist = {};
  for (int i = 0; i < rgba.length; i += 4) {
    final r = rgba[i];
    final g = rgba[i + 1];
    final b = rgba[i + 2];
    final a = rgba[i + 3];
    if (a < 16) continue; // skip near-transparent
    final key = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
    hist.update(key, (v) => v + 1, ifAbsent: () => 1);
  }

  // Color boxes to split
  List<_ColorBox> boxes = [
    _ColorBox(
      hist.keys.toList(growable: false),
      hist.values.toList(growable: false),
    ),
  ];

  int desired = math.max(2, k);
  while (boxes.length < desired) {
    // pick the box with largest range
    boxes.sort(
      (a, b) =>
          ((b.rangeR() + b.rangeG() + b.rangeB()) -
          (a.rangeR() + a.rangeG() + a.rangeB())),
    );
    final box = boxes.first;
    if (box.colors.length <= 1) break;

    // Decide split channel
    int channel = 0; // 0=r,1=g,2=b
    final rRange = box.rangeR();
    final gRange = box.rangeG();
    final bRange = box.rangeB();
    if (gRange >= rRange && gRange >= bRange) {
      channel = 1;
    } else if (bRange >= rRange && bRange >= gRange) {
      channel = 2;
    }

    // Sort colors in box by channel
    List<int> idx = List.generate(box.colors.length, (i) => i);
    idx.sort((i, j) {
      final ci = box.colors[i];
      final cj = box.colors[j];
      int vi, vj;
      if (channel == 0) {
        vi = (ci >> 11) & 31;
        vj = (cj >> 11) & 31;
      } else if (channel == 1) {
        vi = (ci >> 5) & 63;
        vj = (cj >> 5) & 63;
      } else {
        vi = ci & 31;
        vj = cj & 31;
      }
      return vi.compareTo(vj);
    });

    // Prefix sums to find median by population
    final counts = [for (final i in idx) box.counts[i]];
    int total = counts.fold<int>(0, (a, b) => a + b);
    int acc = 0;
    int cut = 0;
    for (int i = 0; i < counts.length; i++) {
      acc += counts[i];
      if (acc >= total ~/ 2) {
        cut = i;
        break;
      }
    }
    if (cut <= 0 || cut >= idx.length - 1) break;

    List<int> colorsA = [for (int i = 0; i <= cut; i++) box.colors[idx[i]]];
    List<int> countsA = [for (int i = 0; i <= cut; i++) box.counts[idx[i]]];
    List<int> colorsB = [
      for (int i = cut + 1; i < idx.length; i++) box.colors[idx[i]],
    ];
    List<int> countsB = [
      for (int i = cut + 1; i < idx.length; i++) box.counts[idx[i]],
    ];

    boxes.removeAt(0);
    boxes
      ..add(_ColorBox(colorsA, countsA))
      ..add(_ColorBox(colorsB, countsB));
  }

  // Average color for each box weighted by population
  List<_Swatch> out = [];
  for (final box in boxes) {
    int rs = 0, gs = 0, bs = 0, tot = 0;
    for (int i = 0; i < box.colors.length; i++) {
      final c = box.colors[i];
      final count = box.counts[i];
      final r = (c >> 11) & 31;
      final g = (c >> 5) & 63;
      final b = c & 31;
      rs += (r << 3) * count;
      gs += (g << 2) * count;
      bs += (b << 3) * count;
      tot += count;
    }
    if (tot == 0) continue;
    final r8 = (rs / tot).round().clamp(0, 255);
    final g8 = (gs / tot).round().clamp(0, 255);
    final b8 = (bs / tot).round().clamp(0, 255);
    out.add(_Swatch(Color.fromARGB(0xFF, r8, g8, b8), tot));
  }

  // Filter near-greys with low chroma to keep vibrant choices but retain neutrals later if needed
  out.sort((a, b) => b.population.compareTo(a.population));
  return out;
}

class _Scored {
  final _Swatch swatch;
  final double score;
  Color get color => swatch.color;
  const _Scored(this.swatch, this.score);
}

List<_Scored> _scoreSwatches(List<_Swatch> swatches) {
  // OPTIMIZED: Simplified scoring to reduce CAM16 calculations
  final List<_Scored> out = [];
  for (final s in swatches) {
    // Quick saturation approximation without full CAM16
    final c = s.color;
    final r = c.r;
    final g = c.g;
    final b = c.b;
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final saturation = max == 0 ? 0.0 : (max - min) / max;

    final lum = _relativeLuminance(c);
    final lumaScore = 1.0 - (2.0 * (lum - 0.5).abs()); // peak at 0.5

    // Simplified scoring: prefer saturation and mid-luma
    final score =
        (0.7 * saturation) +
        (0.2 * lumaScore) +
        (0.1 * math.log(1 + s.population) / math.log(10));
    out.add(_Scored(s, score));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

// ------------------------------
// Theme synthesis with CAM16/HCT & WCAG guardrails
// ------------------------------

ThemeColors _buildTheme(
  Color seed, {
  Brightness targetBrightness = Brightness.light,
  double minContrast = 4.5,
}) {
  // Build tonal palettes using HCT around the seed
  final hct = mcu.Hct.fromInt(seed.toARGB32());
  final hue = hct.hue;
  final baseChroma = math.max(24.0, mcu.Cam16.fromInt(seed.toARGB32()).chroma);

  Color tone(double t) {
    final h = mcu.Hct.from(hue, baseChroma, t);
    return Color(h.toInt());
  }

  // Primary / Secondary / Neutral scales
  final primary = tone(targetBrightness == Brightness.light ? 55 : 65);
  final secondary = Color(
    mcu.Hct.from(
      (hue + 30) % 360,
      baseChroma * 0.6,
      targetBrightness == Brightness.light ? 45 : 70,
    ).toInt(),
  );
  final neutralBg = mcu.Hct.from(
    hue,
    8,
    targetBrightness == Brightness.light ? 98 : 6,
  );
  final surfaceT = targetBrightness == Brightness.light ? 100.0 : 8.0;
  final surface = Color(mcu.Hct.from(hue, 10, surfaceT).toInt());
  final background = Color(neutralBg.toInt());

  // On-colors with WCAG guardrails
  Color onFor(Color bg, {double preferTone = 20}) {
    final bgHct = mcu.Hct.fromInt(bg.toARGB32());
    for (final t in <double>[preferTone, 10, 0, 90, 95, 99]) {
      final candidate = Color(mcu.Hct.from(bgHct.hue, bgHct.chroma, t).toInt());
      if (_contrastRatio(candidate, bg) >= minContrast) {
        return candidate;
      }
    }
    return _contrastRatio(Colors.white, bg) >= _contrastRatio(Colors.black, bg)
        ? Colors.white
        : Colors.black;
  }

  final onPrimary = onFor(
    primary,
    preferTone: targetBrightness == Brightness.light ? 10 : 95,
  );
  final onSecondary = onFor(
    secondary,
    preferTone: targetBrightness == Brightness.light ? 10 : 95,
  );
  final onBackground = onFor(
    background,
    preferTone: targetBrightness == Brightness.light ? 10 : 95,
  );
  final onSurface = onFor(
    surface,
    preferTone: targetBrightness == Brightness.light ? 10 : 95,
  );

  // Ensure interactive elements keep contrast on background
  Color ensureContrast(Color fg, Color bg) {
    if (_contrastRatio(fg, bg) >= minContrast) return fg;
    // Shift tone using HCT towards contrast
    final bgHct = mcu.Hct.fromInt(bg.toARGB32());
    double t = mcu.Hct.fromInt(fg.toARGB32()).tone;
    if (_relativeLuminance(fg) > _relativeLuminance(bg)) {
      // make lighter
      for (final step in [4, 6, 8, 10, 15, 20]) {
        final c = Color(
          mcu.Hct.from(
            bgHct.hue,
            bgHct.chroma + 2,
            (t + step).clamp(0, 100),
          ).toInt(),
        );
        if (_contrastRatio(c, bg) >= minContrast) return c;
      }
    } else {
      for (final step in [4, 6, 8, 10, 15, 20]) {
        final c = Color(
          mcu.Hct.from(
            bgHct.hue,
            bgHct.chroma + 2,
            (t - step).clamp(0, 100),
          ).toInt(),
        );
        if (_contrastRatio(c, bg) >= minContrast) return c;
      }
    }
    return fg;
  }

  final safePrimary = ensureContrast(primary, background);
  final safeSecondary = ensureContrast(secondary, background);

  return ThemeColors(
    primary: safePrimary,
    onPrimary: onPrimary,
    secondary: safeSecondary,
    onSecondary: onSecondary,
    background: background,
    onBackground: onBackground,
    surface: surface,
    onSurface: onSurface,
  );
}

// ------------------------------
// Imaging + helpers
// ------------------------------

Future<ui.Image> _imageFromProvider(ImageProvider provider) async {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(const ImageConfiguration());
  ImageStreamListener? listener;
  listener = ImageStreamListener(
    (ImageInfo info, bool _) {
      completer.complete(info.image);
      stream.removeListener(listener!);
    },
    onError: (Object e, StackTrace? st) {
      if (!completer.isCompleted) completer.completeError(e, st);
      stream.removeListener(listener!);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

Uint8List _downsampleRgba(Uint8List src, int w, int h, int target) {
  if (w <= target && h <= target) return src; // already small enough
  // Nearest neighbor sampling into roughly target x target
  final aspect = w / h;
  int tw, th;
  if (aspect >= 1.0) {
    tw = target;
    th = (target / aspect).round();
  } else {
    th = target;
    tw = (target * aspect).round();
  }
  final out = Uint8List(tw * th * 4);
  for (int y = 0; y < th; y++) {
    final sy = (y * (h - 1) / (th - 1)).round();
    for (int x = 0; x < tw; x++) {
      final sx = (x * (w - 1) / (tw - 1)).round();
      final si = (sy * w + sx) * 4;
      final di = (y * tw + x) * 4;
      out[di] = src[si];
      out[di + 1] = src[si + 1];
      out[di + 2] = src[si + 2];
      out[di + 3] = src[si + 3];
    }
  }
  return out;
}

String _sha1(Uint8List data) => crypto.sha1.convert(data).toString();

class _PaletteCache {
  static final _PaletteCache instance = _PaletteCache._();
  final _LruMap<String, ThemeColors> _map = _LruMap(
    capacity: 16,
  ); // Reduced from 64
  _PaletteCache._();
  ThemeColors? get(String key) => _map.get(key);
  void put(String key, ThemeColors val) => _map.put(key, val);
}

class _LruMap<K, V> {
  final int capacity;
  final _map = <K, V>{};
  final _order = <K>[];
  _LruMap({required this.capacity});
  V? get(K k) {
    final v = _map[k];
    if (v != null) {
      _order.remove(k);
      _order.add(k);
    }
    return v;
  }

  void put(K k, V v) {
    if (_map.length >= capacity && !_map.containsKey(k)) {
      final oldest = _order.isNotEmpty ? _order.removeAt(0) : null;
      if (oldest != null) _map.remove(oldest);
    }
    _map[k] = v;
    _order.remove(k);
    _order.add(k);
  }
}

// WCAG helpers

double _relativeLuminance(Color c) {
  double f(int ch) {
    final v = ch / 255.0;
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = f((c.r * 255.0).round());
  final g = f((c.g * 255.0).round());
  final b = f((c.b * 255.0).round());
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final l1 = math.max(la, lb);
  final l2 = math.min(la, lb);
  return (l1 + 0.05) / (l2 + 0.05);
}
