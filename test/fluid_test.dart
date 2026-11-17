// Tests for fluid palette extraction, cache, and FluidBackground behaviour.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Helpers used by the smooth-transition widget tests.

/// Image provider that never resolves, simulating a hanging image load.
class _NeverLoadingImage extends ImageProvider<_NeverLoadingImage> {
  const _NeverLoadingImage();

  @override
  Future<_NeverLoadingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_NeverLoadingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _NeverLoadingImage key,
    ImageDecoderCallback decode,
  ) =>
      OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

/// Serves a pre-decoded image without going through a codec, so widget tests
/// resolve it instantly under fake async.
class _StaticImageProvider extends ImageProvider<_StaticImageProvider> {
  const _StaticImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_StaticImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_StaticImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _StaticImageProvider key,
    ImageDecoderCallback decode,
  ) =>
      OneFrameImageStreamCompleter(
        Future<ImageInfo>.value(ImageInfo(image: image)),
      );
}

/// Like [_StaticImageProvider], but the image only arrives after [delay] of
/// fake time, so a commit can be placed mid-reveal deterministically.
class _DelayedImage extends ImageProvider<_DelayedImage> {
  const _DelayedImage(this.image, this.delay);

  final ui.Image image;
  final Duration delay;

  @override
  Future<_DelayedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_DelayedImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _DelayedImage key,
    ImageDecoderCallback decode,
  ) =>
      OneFrameImageStreamCompleter(
        Future<ImageInfo>.delayed(delay, () => ImageInfo(image: image)),
      );
}

ui.Image? _redImage;
ui.Image? _blueImage;
ui.Image? _greenImage;
Uint8List? _redBytes;
Uint8List? _blueBytes;
Uint8List? _greenBytes;

/// Counts the fluid shader layers currently painted by [FluidBackground].
int _fluidPainterCount(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter?.runtimeType.toString() == '_FluidShaderPainter',
      ),
    )
    .length;

/// The images of the currently painted shader layers, in paint order
/// (outgoing first, then incoming). Reads `_FluidShaderPainter.image` through
/// `dynamic`, since the painter class is private to the library.
List<ui.Image> _paintedImages(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter?.runtimeType.toString() == '_FluidShaderPainter',
      ),
    )
    .map((paint) => (paint.painter as dynamic).image as ui.Image)
    .toList();

Uint8List _bytes(ByteData data) => data.buffer.asUint8List();

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether the painted shader layers' pixel content matches [refs], in order.
/// Identity cannot be used: the framework clones `ui.Image`s when delivering
/// them through the image stream.
Future<bool> _paintedImagesMatch(
  WidgetTester tester,
  List<Uint8List> refs,
) async {
  final images = _paintedImages(tester);
  if (images.length != refs.length) return false;
  for (var i = 0; i < images.length; i++) {
    late final Uint8List bytes;
    await tester.runAsync(() async {
      final ByteData? data =
          await images[i].toByteData(format: ui.ImageByteFormat.rawRgba);
      bytes = _bytes(data!);
    });
    if (!_bytesEqual(bytes, refs[i])) return false;
  }
  return true;
}

/// Lets the real event loop run briefly so engine futures initiated under
/// fake async (e.g. `ui.Image.toByteData` inside palette extraction) can
/// deliver their responses.
Future<void> _spinEventLoop(WidgetTester tester) => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );

/// Vertical colour stripes, so orbiting/rotating the image actually changes
/// the rendered pixels (a solid colour looks identical however it moves).
Future<ui.Image> _stripedImage(Color a, Color b) async {
  const int size = 64;
  final Uint8List pixels = Uint8List(size * size * 4);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final Color c = ((x ~/ 8) + (y ~/ 8)).isEven ? a : b;
      final int i = (y * size + x) * 4;
      pixels[i + 0] = c.red;
      pixels[i + 1] = c.green;
      pixels[i + 2] = c.blue;
      pixels[i + 3] = 255;
    }
  }
  final ui.ImmutableBuffer buf = await ui.ImmutableBuffer.fromUint8List(pixels);
  final ui.ImageDescriptor desc = ui.ImageDescriptor.raw(
    buf,
    width: size,
    height: size,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final ui.Codec codec = await desc.instantiateCodec();
  return (await codec.getNextFrame()).image;
}

/// Rasterizes the [RepaintBoundary] under [key].
Future<Uint8List> _capture(WidgetTester tester, Key key) async {
  late final Uint8List bytes;
  await tester.runAsync(() async {
    final RenderRepaintBoundary boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final ui.Image image = await boundary.toImage();
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = data!.buffer.asUint8List();
  });
  return bytes;
}

/// Largest per-channel difference between two raw RGBA captures.
int _maxDelta(Uint8List a, Uint8List b) {
  var maxDelta = 0;
  for (var i = 0; i < a.length && i < b.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > maxDelta) maxDelta = d;
  }
  return maxDelta;
}

/// Pumps (advancing fake time and spinning the real event loop) until
/// [predicate] holds, so assertions don't depend on engine callback timing.
Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var i = 0; i < 40 && !predicate(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await _spinEventLoop(tester);
  }
}

void main() {
// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

  /// Builds a solid-colour 4×4 RGBA image for use in extraction tests.
  Future<ui.Image> solidImage(Color color) async {
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

// Decodes the solid images used by the widget tests below, before any test
// runs (plain async, so the engine codec actually completes — it stalls under
// fake async). This keeps filtered (`--plain-name`) and randomized-ordering
// runs working, which would otherwise crash on the null images.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _redImage = await _stripedImage(
      const Color(0xFFFF0000),
      const Color(0xFF400000),
    );
    _blueImage = await _stripedImage(
      const Color(0xFF0000FF),
      const Color(0xFF000040),
    );
    _greenImage = await _stripedImage(
      const Color(0xFF00FF00),
      const Color(0xFF004000),
    );
    // The framework clones `ui.Image`s when delivering them through the image
    // stream, so painter images are compared by pixel content, not identity.
    final binding = TestWidgetsFlutterBinding.instance;
    Future<Uint8List> bytes(ui.Image image) async =>
        _bytes((await image.toByteData(format: ui.ImageByteFormat.rawRgba))!);
    _redBytes = await binding.runAsync(() => bytes(_redImage!));
    _blueBytes = await binding.runAsync(() => bytes(_blueImage!));
    _greenBytes = await binding.runAsync(() => bytes(_greenImage!));
  });

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
      final img = await solidImage(const Color(0xFF1E88E5)); // blue
      final palette = await FluidPaletteExtractor.buildPaletteFromImage(img);
      expect(palette.baseDark, isNotNull);
      expect(palette.accent1, isNotNull);
      expect(palette.accent2, isNotNull);
      expect(palette.accent3, isNotNull);
      expect(palette.accent4, isNotNull);
    });

    test('buildPaletteFromImage baseDark has lightness ≤ 0.22', () async {
      // Even on a bright image the base must remain dark for white text.
      final img = await solidImage(const Color(0xFFFFEB3B)); // yellow
      final palette = await FluidPaletteExtractor.buildPaletteFromImage(img);
      final hsl = HSLColor.fromColor(palette.baseDark);
      expect(hsl.lightness, lessThanOrEqualTo(0.22));
    });

    test('cache is populated after buildPaletteFromImage', () async {
      expect(FluidPaletteCache.instance.size, 0);
      final img = await solidImage(const Color(0xFF4CAF50)); // green
      await FluidPaletteExtractor.buildPaletteFromImage(img);
      expect(FluidPaletteCache.instance.size, 1);
    });

    test('second call hits cache — size stays at 1', () async {
      final img = await solidImage(const Color(0xFFE91E63)); // pink
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
      expect(
          FluidFallbackMode.values,
          containsAll([
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

    testWidgets('renders with fallbackMode: auto in dark theme',
        (tester) async {
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

    testWidgets('renders with fallbackMode: auto in light theme',
        (tester) async {
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

    testWidgets('legacy mode drops to the matte while a new image loads',
        (tester) async {
      ImageProvider provider = _StaticImageProvider(_redImage!);

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
                        onPressed: () => setState(
                            () => provider = const _NeverLoadingImage()),
                        child: const Text('swap'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 1);
      expect(_fluidPainterCount(tester), 1);

      // swapping to a provider that never resolves wipes the display
      await tester.tap(find.text('swap'));
      await tester.pump();
      expect(_fluidPainterCount(tester), 0);
    });

    testWidgets('smooth mode crossfades from the previous image',
        (tester) async {
      final followUps = <ImageProvider>[
        const _NeverLoadingImage(),
        _StaticImageProvider(_blueImage!),
      ];
      var swaps = 0;
      ImageProvider provider = _StaticImageProvider(_redImage!);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Stack(
                  children: [
                    FluidBackground(
                      imageProvider: provider,
                      smoothTransitions: true,
                      child: const SizedBox.expand(),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ElevatedButton(
                        onPressed: () => setState(
                          () =>
                              provider = followUps[swaps++ % followUps.length],
                        ),
                        child: const Text('swap'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 1);
      expect(_fluidPainterCount(tester), 1);

      // the previous image stays on screen while the new one is loading
      await tester.tap(find.text('swap'));
      await tester.pump();
      expect(_fluidPainterCount(tester), 1);

      // the new image crossfades in on top of the old one
      await tester.tap(find.text('swap'));
      await tester.pump();
      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 2);
      expect(_fluidPainterCount(tester), 2);

      // and only the new one remains once the crossfade completes
      await tester.pumpAndSettle();
      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 1);
      expect(_fluidPainterCount(tester), 1);
    });

    testWidgets('a commit mid-reveal waits for the running blend to finish',
        (tester) async {
      final followUps = <ImageProvider>[
        _StaticImageProvider(_blueImage!),
        _DelayedImage(_greenImage!, const Duration(milliseconds: 400)),
      ];
      var swaps = 0;
      ImageProvider provider = _StaticImageProvider(_redImage!);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Stack(
                  children: [
                    FluidBackground(
                      imageProvider: provider,
                      smoothTransitions: true,
                      child: const SizedBox.expand(),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ElevatedButton(
                        onPressed: () => setState(
                          () =>
                              provider = followUps[swaps++ % followUps.length],
                        ),
                        child: const Text('swap'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      // red settled
      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 1);
      await tester.pump(const Duration(milliseconds: 1600));

      // swap to blue: commits right away, red-to-blue reveal starts
      await tester.tap(find.text('swap'));
      await tester.pump();
      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 2);
      expect(
        await _paintedImagesMatch(tester, [_redBytes!, _blueBytes!]),
        isTrue,
      );

      // swap to green, which loads 400ms into the red-to-blue reveal
      await tester.tap(find.text('swap'));
      await tester.pump();

      // advance past the green load (palette extraction needs a real loop spin)
      await tester.pump(const Duration(milliseconds: 500));
      await _spinEventLoop(tester);
      await tester.pump();

      // the green commit must wait for the in-flight blend: the painted
      // layers are still the red-to-blue pair (this used to snap to blue)
      expect(
        await _paintedImagesMatch(tester, [_redBytes!, _blueBytes!]),
        isTrue,
      );

      // and green is shown afterwards, with no leaked painter left behind
      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 1);
      await tester.pump(const Duration(milliseconds: 1600));
      expect(_fluidPainterCount(tester), 1);
      expect(await _paintedImagesMatch(tester, [_greenBytes!]), isTrue);
    });

    testWidgets(
        'a completed reveal clears the previous image even if a newer load '
        'is pending', (tester) async {
      final followUps = <ImageProvider>[
        _StaticImageProvider(_blueImage!),
        const _NeverLoadingImage(),
      ];
      var swaps = 0;
      ImageProvider provider = _StaticImageProvider(_redImage!);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Stack(
                  children: [
                    FluidBackground(
                      imageProvider: provider,
                      smoothTransitions: true,
                      child: const SizedBox.expand(),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ElevatedButton(
                        onPressed: () => setState(
                          () =>
                              provider = followUps[swaps++ % followUps.length],
                        ),
                        child: const Text('swap'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      // red settled
      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 1);
      await tester.pump(const Duration(milliseconds: 1600));

      // blue commits and the red-to-blue reveal starts; the next provider
      // never resolves, so its load stays pending forever
      await tester.tap(find.text('swap'));
      await tester.pump();
      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 2);
      expect(
        await _paintedImagesMatch(tester, [_redBytes!, _blueBytes!]),
        isTrue,
      );
      await tester.tap(find.text('swap'));
      await tester.pump();

      // once the reveal completes, the red painter must be cleared even
      // though the pending load never finishes (it used to leak forever)
      await tester.pump(const Duration(milliseconds: 1600));
      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_fluidPainterCount(tester), 1);
      expect(await _paintedImagesMatch(tester, [_blueBytes!]), isTrue);
    });

    testWidgets('animate: true actually animates the background',
        (tester) async {
      final bgKey = GlobalKey();

      await tester.pumpWidget(
        RepaintBoundary(
          key: bgKey,
          child: MaterialApp(
            home: Scaffold(
              body: FluidBackground(
                imageProvider: _StaticImageProvider(_redImage!),
                animate: true,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 1);
      await tester.pump(const Duration(milliseconds: 1600));

      final before = await _capture(tester, bgKey);
      await tester.pump(const Duration(milliseconds: 1000));
      final after = await _capture(tester, bgKey);
      expect(_maxDelta(before, after), greaterThan(0));
    });

    testWidgets('animate: false keeps the background static', (tester) async {
      final bgKey = GlobalKey();

      await tester.pumpWidget(
        RepaintBoundary(
          key: bgKey,
          child: MaterialApp(
            home: Scaffold(
              body: FluidBackground(
                imageProvider: _StaticImageProvider(_redImage!),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      await _pumpUntil(tester, () => _fluidPainterCount(tester) == 1);
      await tester.pump(const Duration(milliseconds: 1600));

      final before = await _capture(tester, bgKey);
      await tester.pump(const Duration(milliseconds: 1000));
      final after = await _capture(tester, bgKey);
      expect(_maxDelta(before, after), 0);
    });
  });
} // end main
