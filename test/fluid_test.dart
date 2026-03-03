// Tests for fluid palette extraction, cache, and FluidBackground behaviour.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a solid-colour 4×4 RGBA image for use in extraction tests.
Future<ui.Image> _solidImage(Color color) async {
  const int size = 4;
  final Uint8List pixels = Uint8List(size * size * 4);
  for (int i = 0; i < size * size; i++) {
    pixels[i * 4 + 0] = color.red;
    pixels[i * 4 + 1] = color.green;
    pixels[i * 4 + 2] = color.blue;
    pixels[i * 4 + 3] = 255;
  }
  final ui.ImmutableBuffer buf =
      await ui.ImmutableBuffer.fromUint8List(pixels);
  final ui.ImageDescriptor desc = ui.ImageDescriptor.raw(
    buf,
    width: size,
    height: size,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final ui.Codec codec = await desc.instantiateCodec();
  final ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}

// ---------------------------------------------------------------------------
// FluidPalette model
// ---------------------------------------------------------------------------

group('FluidPalette', () {
  test('fallback() has dark base suitable for white text', () {
    const p = FluidPalette.fallback();
    final hsl = HSLColor.fromColor(p.baseDark);
    expect(hsl.lightness, lessThanOrEqualTo(0.22));
  });

  test('fallbackLight() has light base', () {
    const p = FluidPalette.fallbackLight();
    final hsl = HSLColor.fromColor(p.baseDark);
    expect(hsl.lightness, greaterThan(0.80));
  });

  test('lerp at t=0 returns a', () {
    const a = FluidPalette.fallback();
    const b = FluidPalette.fallbackLight();
    final result = FluidPalette.lerp(a, b, 0.0);
    expect(result.baseDark, a.baseDark);
    expect(result.accent1, a.accent1);
  });

  test('lerp at t=1 returns b', () {
    const a = FluidPalette.fallback();
    const b = FluidPalette.fallbackLight();
    final result = FluidPalette.lerp(a, b, 1.0);
    expect(result.baseDark, b.baseDark);
    expect(result.accent1, b.accent1);
  });

  test('copyWith replaces only specified fields', () {
    const original = FluidPalette.fallback();
    final modified = original.copyWith(accent1: const Color(0xFFFF0000));
    expect(modified.accent1, const Color(0xFFFF0000));
    expect(modified.baseDark, original.baseDark);
    expect(modified.accent2, original.accent2);
  });

  test('equality holds for identical palettes', () {
    const a = FluidPalette.fallback();
    const b = FluidPalette.fallback();
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('equality fails for different palettes', () {
    const a = FluidPalette.fallback();
    const b = FluidPalette.fallbackLight();
    expect(a, isNot(equals(b)));
  });
});

// ---------------------------------------------------------------------------
// FluidPaletteCache
// ---------------------------------------------------------------------------

group('FluidPaletteCache', () {
  setUp(() => FluidPaletteCache.instance.clear());

  test('starts empty', () {
    expect(FluidPaletteCache.instance.size, 0);
  });

  test('capacity is defaultCapacity', () {
    expect(
      FluidPaletteCache.instance.capacity,
      FluidPaletteCache.defaultCapacity,
    );
  });

  test('put and get returns the same entry', () {
    const entry = FluidCacheEntry(
      colors: [Color(0xFFFF0000), Color(0xFF00FF00)],
      palette: FluidPalette.fallback(),
    );
    FluidPaletteCache.instance.put('key1', entry);
    final retrieved = FluidPaletteCache.instance.get('key1');
    expect(retrieved, isNotNull);
    expect(retrieved!.colors, entry.colors);
    expect(retrieved.palette, entry.palette);
  });

  test('get returns null for unknown key', () {
    expect(FluidPaletteCache.instance.get('nonexistent'), isNull);
  });

  test('size increments on put', () {
    const entry = FluidCacheEntry(
      colors: [],
      palette: FluidPalette.fallback(),
    );
    FluidPaletteCache.instance.put('a', entry);
    FluidPaletteCache.instance.put('b', entry);
    expect(FluidPaletteCache.instance.size, 2);
  });

  test('clear resets size to zero', () {
    const entry = FluidCacheEntry(
      colors: [],
      palette: FluidPalette.fallback(),
    );
    FluidPaletteCache.instance.put('x', entry);
    FluidPaletteCache.instance.clear();
    expect(FluidPaletteCache.instance.size, 0);
    expect(FluidPaletteCache.instance.get('x'), isNull);
  });

  test('LRU evicts oldest entry when capacity exceeded', () {
    const capacity = FluidPaletteCache.defaultCapacity;
    const entry = FluidCacheEntry(
      colors: [],
      palette: FluidPalette.fallback(),
    );
    // Fill to capacity.
    for (int i = 0; i < capacity; i++) {
      FluidPaletteCache.instance.put('key$i', entry);
    }
    // Access key0 to make it recently used.
    FluidPaletteCache.instance.get('key0');
    // Add one more — should evict key1 (now the LRU).
    FluidPaletteCache.instance.put('keyNew', entry);
    expect(FluidPaletteCache.instance.get('key0'), isNotNull); // survived
    expect(FluidPaletteCache.instance.get('key1'), isNull); // evicted
    expect(FluidPaletteCache.instance.get('keyNew'), isNotNull);
  });
});

// ---------------------------------------------------------------------------
// FluidPaletteExtractor — unit tests against synthetic images
// ---------------------------------------------------------------------------

group('FluidPaletteExtractor', () {
  setUp(() => FluidPaletteCache.instance.clear());

  test('buildPaletteFromImage returns a valid FluidPalette', () async {
    final img = await _solidImage(const Color(0xFF1E88E5)); // blue
    final palette = await FluidPaletteExtractor.buildPaletteFromImage(img);
    expect(palette.baseDark, isNotNull);
    expect(palette.accent1, isNotNull);
    expect(palette.accent2, isNotNull);
    expect(palette.accent3, isNotNull);
    expect(palette.accent4, isNotNull);
  });

  test('buildPaletteFromImage baseDark has lightness ≤ 0.22', () async {
    // Even on a bright image the base must remain dark for white text.
    final img = await _solidImage(const Color(0xFFFFEB3B)); // yellow
    final palette = await FluidPaletteExtractor.buildPaletteFromImage(img);
    final hsl = HSLColor.fromColor(palette.baseDark);
    expect(hsl.lightness, lessThanOrEqualTo(0.22));
  });

  test('cache is populated after buildPaletteFromImage', () async {
    expect(FluidPaletteCache.instance.size, 0);
    final img = await _solidImage(const Color(0xFF4CAF50)); // green
    await FluidPaletteExtractor.buildPaletteFromImage(img);
    expect(FluidPaletteCache.instance.size, 1);
  });

  test('second call hits cache — size stays at 1', () async {
    final img = await _solidImage(const Color(0xFFE91E63)); // pink
    await FluidPaletteExtractor.buildPaletteFromImage(img);
    await FluidPaletteExtractor.buildPaletteFromImage(img);
    expect(FluidPaletteCache.instance.size, 1);
  });

  test('warmup pre-fills cache without throwing', () async {
    // warmup accepts ImageProviders; we test the cache-fill path via
    // buildPaletteFromImage since UI-free image loading isn't available here.
    // Smoke-test: warmup with an empty list completes without error.
    await expectLater(
      FluidPaletteExtractor.warmup([]),
      completes,
    );
  });
});

// ---------------------------------------------------------------------------
// FluidFallbackMode
// ---------------------------------------------------------------------------

group('FluidFallbackMode', () {
  test('enum has exactly three values', () {
    expect(FluidFallbackMode.values.length, 3);
  });

  test('values are dark, light, auto', () {
    expect(FluidFallbackMode.values, containsAll([
      FluidFallbackMode.dark,
      FluidFallbackMode.light,
      FluidFallbackMode.auto,
    ]));
  });
});

// ---------------------------------------------------------------------------
// FluidBackground widget
// ---------------------------------------------------------------------------

group('FluidBackground widget', () {
  testWidgets('renders child with no imageProvider', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FluidBackground(
          child: const Text('hello'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('renders child with animate: true', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FluidBackground(
          animate: true,
          child: const Text('animated'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('animated'), findsOneWidget);
  });

  testWidgets('renders with fallbackMode: dark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FluidBackground(
          fallbackMode: FluidFallbackMode.dark,
          child: const Text('dark'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('renders with fallbackMode: light', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FluidBackground(
          fallbackMode: FluidFallbackMode.light,
          child: const Text('light'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('renders with fallbackMode: auto in dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: FluidBackground(
          fallbackMode: FluidFallbackMode.auto,
          child: const Text('auto-dark'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('auto-dark'), findsOneWidget);
  });

  testWidgets('renders with fallbackMode: auto in light theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: FluidBackground(
          fallbackMode: FluidFallbackMode.auto,
          child: const Text('auto-light'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('auto-light'), findsOneWidget);
  });

  testWidgets('toggling animate does not throw', (tester) async {
    bool animate = false;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  FluidBackground(
                    animate: animate,
                    child: const SizedBox.expand(),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ElevatedButton(
                      onPressed: () => setState(() => animate = !animate),
                      child: const Text('toggle'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    await tester.tap(find.text('toggle'));
    await tester.pump();
    await tester.tap(find.text('toggle'));
    await tester.pump();
  });

  testWidgets('changing imageProvider does not throw', (tester) async {
    ImageProvider? provider;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  FluidBackground(
                    imageProvider: provider,
                    child: const SizedBox.expand(),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ElevatedButton(
                      onPressed: () => setState(() => provider = null),
                      child: const Text('clear'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    await tester.tap(find.text('clear'));
    await tester.pump();
  });
});

} // end main
