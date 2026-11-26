// FluidBackground hosted in an app that uses package:material_ui, whose
// Theme, Scaffold and MaterialApp are different classes from the ones in
// package:flutter/material.dart that adaptive_palette is built on.
import 'dart:ui' as ui;

import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:adaptive_palette/src/widgets/fluid_background.dart'
    show FluidShaderPainter;
// The legacy Scaffold is what FluidBackground puts in the tree.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Serves a pre-decoded image without going through a codec.
class _StaticImage extends ImageProvider<_StaticImage> {
  _StaticImage(this.image);

  final ui.Image image;

  @override
  Future<_StaticImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_StaticImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _StaticImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
  );
}

late ui.Image _image;

Future<ui.Image> _solidImage(int rgb) async {
  const int size = 32;
  final Uint8List pixels = Uint8List(size * size * 4);
  for (int i = 0; i < size * size; i++) {
    pixels[i * 4 + 0] = (rgb >> 16) & 0xFF;
    pixels[i * 4 + 1] = (rgb >> 8) & 0xFF;
    pixels[i * 4 + 2] = rgb & 0xFF;
    pixels[i * 4 + 3] = 255;
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

/// Background colour of the Scaffold that FluidBackground builds, which is
/// the base colour of the fallback palette in use.
Color _fallbackBase(WidgetTester tester) => tester
    .widget<legacy.Scaffold>(
      find.descendant(
        of: find.byType(FluidBackground),
        matching: find.byType(legacy.Scaffold),
      ),
    )
    .backgroundColor!;

bool _showsFluidLayers(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(FluidBackground),
        matching: find.byType(CustomPaint),
      ),
    )
    .any((paint) => paint.painter is FluidShaderPainter);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _image = await _solidImage(0x1E88E5);
  });

  setUp(() => FluidPaletteCache.instance.clear());

  void setPlatformBrightness(WidgetTester tester, Brightness brightness) {
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  testWidgets('renders and reveals an image inside a material_ui app', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: FluidBackground(
          imageProvider: _StaticImage(_image),
          animate: true,
          smoothTransitions: true,
          child: const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: Text('Now Playing')),
          ),
        ),
      ),
    );
    expect(find.text('Now Playing'), findsOneWidget);

    for (int i = 0; i < 20 && !_showsFluidLayers(tester); i++) {
      await tester.runAsync(
        () => _image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      await tester.pump();
    }
    expect(_showsFluidLayers(tester), isTrue);

    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'fallbackMode.auto follows the platform brightness when the app theme '
    'is not bridged',
    (tester) async {
      Future<Color> baseFor(Brightness platform) async {
        setPlatformBrightness(tester, platform);
        await tester.pumpWidget(
          MaterialApp(
            // The app theme is invisible to code built on the SDK's Material
            // library, so the platform setting decides.
            theme: ThemeData.light(),
            home: const FluidBackground(child: SizedBox.expand()),
          ),
        );
        await tester.pump();
        return _fallbackBase(tester);
      }

      expect(
        await baseFor(Brightness.dark),
        const FluidPalette.fallback().baseDark,
      );
      expect(
        await baseFor(Brightness.light),
        const FluidPalette.fallbackLight().baseDark,
      );
    },
  );

  testWidgets('fallbackMode.auto follows the app theme through '
      'MaterialUiCompatibilityBridge', (tester) async {
    Future<Color> baseFor(ThemeData theme) async {
      // Opposite of the theme, to show the theme wins.
      setPlatformBrightness(
        tester,
        theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (context, child) =>
              // The bridge is deprecated because it is a temporary migration
              // aid; it is exactly what this test is about.
              // ignore: deprecated_member_use
              MaterialUiCompatibilityBridge(child: child!),
          home: const FluidBackground(child: SizedBox.expand()),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      return _fallbackBase(tester);
    }

    expect(
      await baseFor(ThemeData.dark()),
      const FluidPalette.fallback().baseDark,
    );
    expect(
      await baseFor(ThemeData.light()),
      const FluidPalette.fallbackLight().baseDark,
    );
  });

  testWidgets('explicit fallback modes ignore both theme and platform', (
    tester,
  ) async {
    setPlatformBrightness(tester, Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: const FluidBackground(
          fallbackMode: FluidFallbackMode.dark,
          child: SizedBox.expand(),
        ),
      ),
    );
    expect(_fallbackBase(tester), const FluidPalette.fallback().baseDark);
  });
}
