// Edge cases, caching and resource handling of palette extraction.
import 'dart:ui' as ui;

import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a [width]x[height] image whose pixel colours come from [colorAt]
/// (0xRRGGBB).
Future<ui.Image> _image(
  int width,
  int height,
  int Function(int x, int y) colorAt,
) async {
  final Uint8List pixels = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int c = colorAt(x, y);
      final int i = (y * width + x) * 4;
      pixels[i + 0] = (c >> 16) & 0xFF;
      pixels[i + 1] = (c >> 8) & 0xFF;
      pixels[i + 2] = c & 0xFF;
      pixels[i + 3] = 255;
    }
  }
  final ui.ImmutableBuffer buf = await ui.ImmutableBuffer.fromUint8List(pixels);
  final ui.ImageDescriptor desc = ui.ImageDescriptor.raw(
    buf,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final ui.Codec codec = await desc.instantiateCodec();
  return (await codec.getNextFrame()).image;
}

/// Serves a pre-decoded image and remembers the handles it hands out (to the
/// caller, and to Flutter's image cache, which listens too).
class _MemoryImage extends ImageProvider<_MemoryImage> {
  _MemoryImage(this.image);

  final ui.Image image;
  final List<ui.Image> handedOut = <ui.Image>[];

  @override
  Future<_MemoryImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_MemoryImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _MemoryImage key,
    ImageDecoderCallback decode,
  ) =>
      _RecordingCompleter(image.clone(), handedOut);
}

/// Like [OneFrameImageStreamCompleter], but records the per-listener image
/// handles so tests can check that they get disposed.
class _RecordingCompleter extends ImageStreamCompleter {
  _RecordingCompleter(ui.Image image, this.handedOut) {
    setImage(ImageInfo(image: image));
  }

  final List<ui.Image> handedOut;

  @override
  void addListener(ImageStreamListener listener) {
    super.addListener(
      ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          handedOut.add(info.image);
          listener.onImage(info, synchronousCall);
        },
        onError: listener.onError,
      ),
    );
  }
}

class _FailingImage extends ImageProvider<_FailingImage> {
  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FailingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImage key,
    ImageDecoderCallback decode,
  ) =>
      _FailingCompleter();
}

class _FailingCompleter extends ImageStreamCompleter {
  @override
  void addListener(ImageStreamListener listener) {
    super.addListener(listener);
    reportError(exception: StateError('image failed to load'), silent: true);
  }
}

int _stripes(int x, int y) => (x ~/ 16).isEven ? 0xE53935 : 0x1E88E5;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FluidPaletteCache.instance.clear();
    // The legacy palette cache is cleared through the deprecated facade.
    // ignore: deprecated_member_use_from_same_package
    AdaptivePalette.clearCache();
  });

  group('FluidPaletteExtractor edge cases', () {
    for (final (int w, int h) in <(int, int)>[
      (1, 1),
      (1, 40),
      (40, 1),
      (3, 3),
    ]) {
      test('handles a ${w}x$h image', () async {
        final ui.Image image = await _image(w, h, (x, y) => 0x4CAF50);
        final FluidPalette palette =
            await FluidPaletteExtractor.buildPaletteFromImage(image);
        expect(
          HSLColor.fromColor(palette.baseDark).lightness,
          lessThanOrEqualTo(0.22),
        );
        // A single-colour image resolves to that colour's family, not to the
        // fallback palette.
        expect(palette, isNot(const FluidPalette.fallback()));
        expect(HSLColor.fromColor(palette.baseDark).hue, closeTo(122, 4));
      });
    }

    test('falls back for images with nothing but white', () async {
      final ui.Image image = await _image(32, 32, (x, y) => 0xFFFFFF);
      expect(
        await FluidPaletteExtractor.buildPaletteFromImage(image),
        const FluidPalette.fallback(),
      );
    });

    test('extractColors returns at most the requested number', () async {
      final ui.Image image = await _image(64, 64, _stripes);
      final List<Color> colors =
          await FluidPaletteExtractor.extractColors(_MemoryImage(image));
      expect(colors, isNotEmpty);
      expect(colors.length, lessThanOrEqualTo(5));

      final List<Color> one = await FluidPaletteExtractor.extractColors(
        _MemoryImage(image),
        count: 1,
      );
      expect(one, hasLength(1));
      expect(one.single, colors.first);
    });

    test('extractColors throws when the image fails to load', () async {
      await expectLater(
        FluidPaletteExtractor.extractColors(_FailingImage()),
        throwsStateError,
      );
    });

    test('warmup skips images that fail to load', () async {
      final ui.Image image = await _image(64, 64, _stripes);
      await FluidPaletteExtractor.warmup([
        _FailingImage(),
        _MemoryImage(image),
      ]);
      expect(FluidPaletteCache.instance.size, 1);
    });
  });

  group('FluidPaletteExtractor caching', () {
    test('the same pixels share one cache entry', () async {
      final ui.Image a = await _image(64, 64, _stripes);
      final ui.Image b = await _image(64, 64, _stripes);
      final FluidPalette first =
          await FluidPaletteExtractor.buildPaletteFromImage(a);
      final FluidPalette second =
          await FluidPaletteExtractor.buildPaletteFromImage(b);
      expect(FluidPaletteCache.instance.size, 1);
      expect(second, first);
    });

    test('different images get different cache entries', () async {
      final ui.Image a = await _image(64, 64, (x, y) => 0xE53935);
      final ui.Image b = await _image(64, 64, (x, y) => 0x1E88E5);
      final FluidPalette first =
          await FluidPaletteExtractor.buildPaletteFromImage(a);
      final FluidPalette second =
          await FluidPaletteExtractor.buildPaletteFromImage(b);
      expect(FluidPaletteCache.instance.size, 2);
      expect(second, isNot(first));
    });

    test('images of different size never share a cache entry', () async {
      // Both images are sampled at the same single pixel.
      final ui.Image a = await _image(4, 4, (x, y) => 0xE53935);
      final ui.Image b = await _image(8, 8, (x, y) => 0xE53935);
      await FluidPaletteExtractor.buildPaletteFromImage(a);
      await FluidPaletteExtractor.buildPaletteFromImage(b);
      expect(FluidPaletteCache.instance.size, 2);
    });

    test('a cache hit returns the same palette as a fresh extraction',
        () async {
      final ui.Image image = await _image(120, 90, (x, y) {
        final int r = (x * 2) & 0xFF;
        final int g = (y * 2) & 0xFF;
        return (r << 16) | (g << 8) | 0x80;
      });
      final FluidPalette fresh =
          await FluidPaletteExtractor.buildPaletteFromImage(image);
      final FluidPalette cached =
          await FluidPaletteExtractor.buildPaletteFromImage(image);
      FluidPaletteCache.instance.clear();
      final FluidPalette again =
          await FluidPaletteExtractor.buildPaletteFromImage(image);
      expect(cached, fresh);
      expect(again, fresh);
    });
  });

  group('image ownership', () {
    test('extractColors disposes the image it loads', () async {
      final ui.Image image = await _image(64, 64, _stripes);
      final provider = _MemoryImage(image);
      await FluidPaletteExtractor.extractColors(provider);
      expect(provider.handedOut, isNotEmpty);
      expect(
        provider.handedOut.where((handle) => !handle.debugDisposed),
        isEmpty,
      );
      expect(image.debugDisposed, isFalse);
    });

    test('warmup disposes the images it loads', () async {
      final ui.Image image = await _image(64, 64, _stripes);
      final provider = _MemoryImage(image);
      await FluidPaletteExtractor.warmup([provider]);
      expect(provider.handedOut, isNotEmpty);
      expect(
        provider.handedOut.where((handle) => !handle.debugDisposed),
        isEmpty,
      );
    });

    test('buildPaletteFromImage leaves the caller\'s image alone', () async {
      final ui.Image image = await _image(64, 64, _stripes);
      await FluidPaletteExtractor.buildPaletteFromImage(image);
      expect(image.debugDisposed, isFalse);
    });

    test('loadImageFromProvider hands ownership to the caller', () async {
      final ui.Image image = await _image(64, 64, _stripes);
      final ui.Image loaded = await loadImageFromProvider(_MemoryImage(image));
      expect(loaded.debugDisposed, isFalse);
      expect(loaded.isCloneOf(image), isTrue);
      loaded.dispose();
    });
  });

  group('AdaptivePalette (deprecated) caching', () {
    test('the cached result depends on the requested brightness', () async {
      final ui.Image image = await _image(64, 64, _stripes);

      // ignore: deprecated_member_use_from_same_package
      final ThemeColors dark = await AdaptivePalette.fromImage(
        _MemoryImage(image),
        targetBrightness: Brightness.dark,
      );
      // ignore: deprecated_member_use_from_same_package
      final ThemeColors light = await AdaptivePalette.fromImage(
        _MemoryImage(image),
        targetBrightness: Brightness.light,
      );
      // ignore: deprecated_member_use_from_same_package
      final ThemeColors darkAgain = await AdaptivePalette.fromImage(
        _MemoryImage(image),
        targetBrightness: Brightness.dark,
      );

      expect(light.background, isNot(dark.background));
      expect(darkAgain.background, dark.background);
      expect(
        light.background.computeLuminance(),
        greaterThan(dark.background.computeLuminance()),
      );
    });

    for (final (int w, int h) in <(int, int)>[(600, 2), (600, 6), (6, 600)]) {
      test('handles a ${w}x$h image', () async {
        final ui.Image image = await _image(w, h, _stripes);
        // ignore: deprecated_member_use_from_same_package
        final ThemeColors colors = await AdaptivePalette.fromImage(
          _MemoryImage(image),
        );
        expect(colors.primary, isNot(const ThemeColors.fallback().primary));
      });
    }
  });
}
