// Behaviour tests for FluidBackground: loading, transitions, motion,
// rendering, and resource handling.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:adaptive_palette/src/material.dart';
import 'package:adaptive_palette/src/widgets/fluid_background.dart'
    show FluidShaderPainter;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Image providers
// ---------------------------------------------------------------------------

/// Serves a pre-decoded image without going through a codec.
///
/// Every instance is its own cache key, so two providers for the same image
/// count as different images to the widget.
class _StaticImage extends ImageProvider<_StaticImage> {
  _StaticImage(this.image, {this.delay});

  final ui.Image image;

  /// Fake-time delay before the image arrives.
  final Duration? delay;

  @override
  Future<_StaticImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_StaticImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _StaticImage key,
    ImageDecoderCallback decode,
  ) {
    // The stream completer owns (and eventually disposes) the handle it is
    // given, so hand it a clone and keep the shared test image alive.
    ImageInfo info() => ImageInfo(image: image.clone());
    return OneFrameImageStreamCompleter(
      delay == null
          ? SynchronousFuture<ImageInfo>(info())
          : Future<ImageInfo>.delayed(delay!, info),
    );
  }
}

/// Never resolves, simulating a hanging image load.
class _NeverLoadingImage extends ImageProvider<_NeverLoadingImage> {
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

/// Fails to load.
class _FailingImage extends ImageProvider<_FailingImage> {
  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FailingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImage key,
    ImageDecoderCallback decode,
  ) {
    final completer = _ErrorImageStreamCompleter();
    scheduleMicrotask(completer.fail);
    return completer;
  }
}

class _ErrorImageStreamCompleter extends ImageStreamCompleter {
  void fail() => reportError(
        exception: StateError('image failed to load'),
        silent: true,
      );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

late ui.Image _red;
late ui.Image _blue;
late ui.Image _green;

/// Checkerboard image, so moving or rotating it changes the rendered pixels
/// (a solid colour looks identical however it moves).
Future<ui.Image> _checkerboard(int a, int b) async {
  const int size = 64;
  final Uint8List pixels = Uint8List(size * size * 4);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final int c = ((x ~/ 8) + (y ~/ 8)).isEven ? a : b;
      final int i = (y * size + x) * 4;
      pixels[i + 0] = (c >> 16) & 0xFF;
      pixels[i + 1] = (c >> 8) & 0xFF;
      pixels[i + 2] = c & 0xFF;
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

/// Lets real asynchronous engine work make progress, then builds a frame
/// without advancing the fake clock.
///
/// Palette extraction reads the image back through the engine, which only
/// completes outside the fake async zone. Reading a pixel buffer back here
/// goes through the same queue, so once it returns, readbacks requested
/// earlier have been answered too.
Future<void> _spin(WidgetTester tester, {int times = 1}) async {
  for (int i = 0; i < times; i++) {
    await tester.runAsync(
      () => _red.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    await tester.pump();
  }
}

/// Spins until [condition] holds. Fake time does not advance.
Future<void> _spinUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
}) async {
  for (int i = 0; i < 100 && !condition(); i++) {
    await _spin(tester);
  }
  expect(condition(), isTrue, reason: 'timed out waiting until $reason');
}

/// Lets pending image loads and palette extractions finish, for asserting
/// that something did NOT happen as a result.
Future<void> _letLoadsFinish(WidgetTester tester) => _spin(tester, times: 5);

/// The fluid layer painter currently in the tree, or null when only the matte
/// fallback is showing.
FluidShaderPainter? _painter(WidgetTester tester) {
  final Iterable<CustomPaint> paints = tester.widgetList<CustomPaint>(
    find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is FluidShaderPainter,
    ),
  );
  expect(paints.length, lessThanOrEqualTo(1));
  return paints.isEmpty ? null : paints.single.painter! as FluidShaderPainter;
}

bool _shows(WidgetTester tester, ui.Image image) =>
    _painter(tester)?.image?.isCloneOf(image) ?? false;

bool _fadesFrom(WidgetTester tester, ui.Image image) =>
    _painter(tester)?.outgoingImage?.isCloneOf(image) ?? false;

/// Waits for [image] to be showing with no transition left to finish.
Future<void> _settleOn(WidgetTester tester, ui.Image image) async {
  await _spinUntil(tester, () => _shows(tester, image), reason: 'image shows');
  await _finishTransition(tester);
  expect(_shows(tester, image), isTrue);
  expect(_painter(tester)!.outgoingImage, isNull);
}

const Duration _transition = Duration(milliseconds: 1400);

/// Advances fake time past the end of a running transition and builds the
/// frame that follows its completion.
Future<void> _finishTransition(WidgetTester tester) async {
  // An animation only completes on the first tick after its duration.
  await tester.pump(_transition + const Duration(milliseconds: 16));
  await tester.pump();
}

final GlobalKey _captureKey = GlobalKey();

/// Rasterizes the widget under [_captureKey].
Future<Uint8List> _capture(WidgetTester tester) async {
  late final Uint8List bytes;
  await tester.runAsync(() async {
    final RenderRepaintBoundary boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
    final ui.Image image = await boundary.toImage();
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    bytes = data!.buffer.asUint8List();
  });
  return bytes;
}

/// Largest per-channel difference between two raw RGBA captures.
int _maxDelta(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  int maxDelta = 0;
  for (int i = 0; i < a.length; i++) {
    final int d = (a[i] - b[i]).abs();
    if (d > maxDelta) maxDelta = d;
  }
  return maxDelta;
}

/// Average per-channel difference between two raw RGBA captures.
double _meanDelta(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  int sum = 0;
  for (int i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}

/// Hosts a [FluidBackground] whose configuration can be changed with
/// [_HostState.update].
class _Host extends StatefulWidget {
  const _Host({
    this.imageProvider,
    this.smoothTransitions = false,
    this.animate = false,
    this.blurSigma = 80,
    this.child = const SizedBox.expand(),
  });

  final ImageProvider? imageProvider;
  final bool smoothTransitions;
  final bool animate;
  final double blurSigma;
  final Widget child;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late ImageProvider? imageProvider = widget.imageProvider;
  late bool smoothTransitions = widget.smoothTransitions;
  late bool animate = widget.animate;
  Duration transitionDuration = _transition;
  bool showBackground = true;

  void update(VoidCallback change) => setState(change);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        home: showBackground
            ? FluidBackground(
                imageProvider: imageProvider,
                smoothTransitions: smoothTransitions,
                animate: animate,
                blurSigma: widget.blurSigma,
                transitionDuration: transitionDuration,
                child: widget.child,
              )
            : const SizedBox.expand(),
      ),
    );
  }
}

_HostState _host(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host));

/// Counts how often it paints.
class _CountingPainter extends CustomPainter {
  _CountingPainter(this.onPaint);

  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint();

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Color _scaffoldColor(WidgetTester tester) => tester
    .widget<Scaffold>(
      find.descendant(
        of: find.byType(FluidBackground),
        matching: find.byType(Scaffold),
      ),
    )
    .backgroundColor!;

void main() {
  // Decoded with real async before any test runs: the engine codec does not
  // complete under the fake async zone of testWidgets.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _red = await _checkerboard(0xFF0000, 0x400000);
    _blue = await _checkerboard(0x0000FF, 0x000040);
    _green = await _checkerboard(0x00FF00, 0x004000);
  });

  setUp(() => FluidPaletteCache.instance.clear());

  group('FluidBackground loading', () {
    testWidgets('shows only the matte fallback without an image',
        (tester) async {
      await tester.pumpWidget(const _Host());
      await _letLoadsFinish(tester);
      expect(_painter(tester), isNull);
    });

    testWidgets('reveals the image once it has loaded', (tester) async {
      await tester.pumpWidget(_Host(imageProvider: _StaticImage(_red)));
      await _settleOn(tester, _red);
    });

    testWidgets('cuts to the matte fallback while a new image loads',
        (tester) async {
      await tester.pumpWidget(_Host(imageProvider: _StaticImage(_red)));
      await _settleOn(tester, _red);

      _host(tester).update(
        () => _host(tester).imageProvider = _NeverLoadingImage(),
      );
      await tester.pump();
      expect(_painter(tester), isNull);
    });

    testWidgets('shows the matte fallback when the image fails to load',
        (tester) async {
      await tester.pumpWidget(_Host(imageProvider: _StaticImage(_red)));
      await _settleOn(tester, _red);

      _host(tester).update(() => _host(tester).imageProvider = _FailingImage());
      await tester.pump();
      await _letLoadsFinish(tester);
      expect(_painter(tester), isNull);
    });

    testWidgets('clearing the image cuts to the matte fallback',
        (tester) async {
      await tester.pumpWidget(_Host(imageProvider: _StaticImage(_red)));
      await _settleOn(tester, _red);

      _host(tester).update(() => _host(tester).imageProvider = null);
      await tester.pump();
      expect(_painter(tester), isNull);
    });

    testWidgets('a superseded load never shows', (tester) async {
      await tester.pumpWidget(
        _Host(
          imageProvider: _StaticImage(
            _red,
            delay: const Duration(milliseconds: 300),
          ),
        ),
      );
      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(_blue),
      );
      await tester.pump();
      await _settleOn(tester, _blue);

      // The red load finishes after blue is already on screen.
      await tester.pump(const Duration(milliseconds: 400));
      await _letLoadsFinish(tester);
      expect(_shows(tester, _blue), isTrue);
      expect(_painter(tester)!.outgoingImage, isNull);
    });

    testWidgets('a changed transitionDuration applies to the next reveal',
        (tester) async {
      await tester.pumpWidget(const _Host());
      _host(tester).update(() {
        _host(tester)
          ..transitionDuration = const Duration(milliseconds: 200)
          ..smoothTransitions = true
          ..imageProvider = _StaticImage(_red);
      });
      await tester.pump();
      await _spinUntil(tester, () => _shows(tester, _red), reason: 'red shows');

      // 200ms is enough to finish the first reveal...
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(_blue),
      );
      await tester.pump();
      await _spinUntil(
        tester,
        () => _shows(tester, _blue),
        reason: 'blue shows',
      );
      expect(_fadesFrom(tester, _red), isTrue);

      // ...and the crossfade; the default 1400ms would not be.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(_painter(tester)!.outgoingImage, isNull);
    });
  });

  group('FluidBackground smooth transitions', () {
    testWidgets('keeps the current image while the next one loads',
        (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), smoothTransitions: true),
      );
      await _settleOn(tester, _red);

      _host(tester).update(
        () => _host(tester).imageProvider = _NeverLoadingImage(),
      );
      await tester.pump();
      await _letLoadsFinish(tester);
      expect(_shows(tester, _red), isTrue);
      expect(_painter(tester)!.outgoingImage, isNull);
    });

    testWidgets('crossfades from the previous image to the new one',
        (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), smoothTransitions: true),
      );
      await _settleOn(tester, _red);

      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(_blue),
      );
      await tester.pump();
      await _spinUntil(
        tester,
        () => _shows(tester, _blue),
        reason: 'blue is being revealed',
      );
      expect(_fadesFrom(tester, _red), isTrue);

      // Still crossfading halfway through.
      await tester.pump(_transition ~/ 2);
      expect(_fadesFrom(tester, _red), isTrue);

      // Only the new image remains once the crossfade completes.
      await _finishTransition(tester);
      expect(_shows(tester, _blue), isTrue);
      expect(_painter(tester)!.outgoingImage, isNull);
    });

    testWidgets('crossfading shows no change when both images are the same',
        (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), smoothTransitions: true),
      );
      await _settleOn(tester, _red);
      final Uint8List steady = await _capture(tester);

      // A different provider for the same pixels: a full crossfade runs, and
      // every frame of an exact crossfade between equal images is identical.
      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(_red),
      );
      await tester.pump();
      await _spinUntil(
        tester,
        () => _painter(tester)?.outgoingImage != null,
        reason: 'crossfade started',
      );

      for (int step = 0; step < 6; step++) {
        await tester.pump(_transition ~/ 7);
        expect(_painter(tester)!.outgoingImage, isNotNull);
        expect(
          _maxDelta(steady, await _capture(tester)),
          lessThanOrEqualTo(1),
          reason: 'frame ${step + 1} of the crossfade',
        );
      }
    });

    testWidgets('an image that loads mid-transition waits for it to finish',
        (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), smoothTransitions: true),
      );
      await _settleOn(tester, _red);

      // Red-to-blue starts.
      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(_blue),
      );
      await tester.pump();
      await _spinUntil(
        tester,
        () => _shows(tester, _blue),
        reason: 'blue is being revealed',
      );

      // Green loads 400ms into the red-to-blue crossfade.
      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(
          _green,
          delay: const Duration(milliseconds: 400),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _letLoadsFinish(tester);

      // The red-to-blue crossfade is still the one on screen.
      expect(_shows(tester, _blue), isTrue);
      expect(_fadesFrom(tester, _red), isTrue);

      // Once it finishes, blue-to-green starts.
      await _finishTransition(tester);
      expect(_shows(tester, _green), isTrue);
      expect(_fadesFrom(tester, _blue), isTrue);

      await _finishTransition(tester);
      expect(_shows(tester, _green), isTrue);
      expect(_painter(tester)!.outgoingImage, isNull);
    });

    testWidgets('rapid changes collapse into one transition to the latest',
        (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), smoothTransitions: true),
      );
      await _settleOn(tester, _red);

      // Blue is superseded by green before either has been shown.
      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(
          _blue,
          delay: const Duration(milliseconds: 100),
        ),
      );
      await tester.pump();
      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(
          _green,
          delay: const Duration(milliseconds: 100),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await _spinUntil(
        tester,
        () => _shows(tester, _green),
        reason: 'green is being revealed',
      );
      expect(_fadesFrom(tester, _red), isTrue);

      await _finishTransition(tester);
      await _letLoadsFinish(tester);
      expect(_shows(tester, _green), isTrue);
      expect(_painter(tester)!.outgoingImage, isNull);
    });

    testWidgets(
        'a finished transition drops the previous image even while '
        'another load is pending', (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), smoothTransitions: true),
      );
      await _settleOn(tester, _red);

      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(_blue),
      );
      await tester.pump();
      await _spinUntil(
        tester,
        () => _shows(tester, _blue),
        reason: 'blue is being revealed',
      );

      // The next provider never resolves.
      _host(tester).update(
        () => _host(tester).imageProvider = _NeverLoadingImage(),
      );
      await tester.pump();

      await _finishTransition(tester);
      expect(_shows(tester, _blue), isTrue);
      expect(_painter(tester)!.outgoingImage, isNull);
    });

    testWidgets('keeps the current image when the next one fails to load',
        (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), smoothTransitions: true),
      );
      await _settleOn(tester, _red);

      _host(tester).update(() => _host(tester).imageProvider = _FailingImage());
      await tester.pump();
      await _letLoadsFinish(tester);
      await _finishTransition(tester);
      expect(_shows(tester, _red), isTrue);
      expect(_painter(tester)!.outgoingImage, isNull);
    });

    testWidgets('clearing the image fades out to the matte fallback',
        (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), smoothTransitions: true),
      );
      await _settleOn(tester, _red);
      final Uint8List withImage = await _capture(tester);

      _host(tester).update(() => _host(tester).imageProvider = null);
      await tester.pump();
      await _spinUntil(
        tester,
        () => _fadesFrom(tester, _red),
        reason: 'fade-out started',
      );
      expect(_painter(tester)!.image, isNull);

      // Nothing has changed on the first frame of the fade.
      expect(
          _maxDelta(withImage, await _capture(tester)), lessThanOrEqualTo(1));

      await _finishTransition(tester);
      expect(_painter(tester), isNull);
    });

    testWidgets('turning smooth transitions off mid-crossfade lets it finish',
        (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), smoothTransitions: true),
      );
      await _settleOn(tester, _red);

      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(_blue),
      );
      await tester.pump();
      await _spinUntil(
        tester,
        () => _shows(tester, _blue),
        reason: 'blue is being revealed',
      );
      await tester.pump(_transition ~/ 2);

      _host(tester).update(() => _host(tester).smoothTransitions = false);
      await tester.pump();
      expect(_fadesFrom(tester, _red), isTrue);

      await _finishTransition(tester);
      expect(_shows(tester, _blue), isTrue);
      expect(_painter(tester)!.outgoingImage, isNull);
    });
  });

  group('FluidBackground motion', () {
    testWidgets('animate: true moves the background', (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), animate: true),
      );
      await _settleOn(tester, _red);

      final Uint8List before = await _capture(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(_maxDelta(before, await _capture(tester)), greaterThan(0));
    });

    testWidgets('animate: false keeps the background still', (tester) async {
      await tester.pumpWidget(_Host(imageProvider: _StaticImage(_red)));
      await _settleOn(tester, _red);

      final Uint8List before = await _capture(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(_maxDelta(before, await _capture(tester)), 0);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('toggling animate pauses and resumes from the same frame',
        (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), animate: true),
      );
      await _settleOn(tester, _red);
      await tester.pump(const Duration(seconds: 2));

      _host(tester).update(() => _host(tester).animate = false);
      await tester.pump();
      final Uint8List paused = await _capture(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(_maxDelta(paused, await _capture(tester)), 0);
      expect(tester.binding.transientCallbackCount, 0);

      // Resuming continues from the paused frame instead of jumping.
      _host(tester).update(() => _host(tester).animate = true);
      await tester.pump();
      expect(_maxDelta(paused, await _capture(tester)), 0);
      await tester.pump(const Duration(seconds: 1));
      expect(_maxDelta(paused, await _capture(tester)), greaterThan(0));
    });

    testWidgets('the orbit is continuous across the cycle wrap',
        (tester) async {
      // A light blur, so that a jump in rotation is clearly visible.
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), blurSigma: 4),
      );
      await _settleOn(tester, _red);

      // Start the orbit now, so its clock starts at a known point: the cycle
      // is 12s and starts at phase 0.35, so it wraps 7.8s in. Compare the
      // frames 16ms either side of the wrap.
      _host(tester).update(() => _host(tester).animate = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 7800 - 16));
      final Uint8List beforeWrap = await _capture(tester);
      await tester.pump(const Duration(milliseconds: 32));
      final Uint8List afterWrap = await _capture(tester);
      await tester.pump(const Duration(milliseconds: 32));
      final Uint8List next = await _capture(tester);

      // The step across the wrap is about the size of an ordinary step. A
      // rotation that snapped back at the wrap would move the whole picture.
      final double wrapStep = _meanDelta(beforeWrap, afterWrap);
      final double ordinaryStep = _meanDelta(afterWrap, next);
      expect(ordinaryStep, greaterThan(0));
      expect(wrapStep, lessThan(ordinaryStep * 1.5));
    });

    testWidgets('does not schedule frames while there is no image to move',
        (tester) async {
      await tester.pumpWidget(const _Host(animate: true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);

      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(_red),
      );
      await tester.pump();
      await _settleOn(tester, _red);
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      _host(tester).update(() => _host(tester).imageProvider = null);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('stays still when the platform asks for reduced motion',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), animate: true),
      );
      await _settleOn(tester, _red);

      final Uint8List before = await _capture(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(_maxDelta(before, await _capture(tester)), 0);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('FluidBackground rendering', () {
    testWidgets('content is not repainted by the orbit or by a transition',
        (tester) async {
      int paints = 0;
      await tester.pumpWidget(
        _Host(
          imageProvider: _StaticImage(_red),
          smoothTransitions: true,
          animate: true,
          child: CustomPaint(painter: _CountingPainter(() => paints++)),
        ),
      );
      await _settleOn(tester, _red);
      final int settled = paints;

      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(paints, settled, reason: 'orbit frames');

      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(_blue),
      );
      await tester.pump();
      await _spinUntil(
        tester,
        () => _shows(tester, _blue),
        reason: 'blue is being revealed',
      );
      final int started = paints;
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(paints, started, reason: 'transition frames');
    });

    testWidgets('fallbackMode.auto follows the Material theme brightness',
        (tester) async {
      Future<Color> colorFor(ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const FluidBackground(child: SizedBox.expand()),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        return _scaffoldColor(tester);
      }

      expect(
        await colorFor(ThemeData.dark()),
        const FluidPalette.fallback().baseDark,
      );
      expect(
        await colorFor(ThemeData.light()),
        const FluidPalette.fallbackLight().baseDark,
      );
    });

    testWidgets(
        'fallbackMode.auto follows the platform brightness without a '
        'Material theme', (tester) async {
      Future<Color> colorFor(Brightness brightness) async {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(platformBrightness: brightness),
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: FluidBackground(child: SizedBox.expand()),
            ),
          ),
        );
        return _scaffoldColor(tester);
      }

      expect(
        await colorFor(Brightness.dark),
        const FluidPalette.fallback().baseDark,
      );
      expect(
        await colorFor(Brightness.light),
        const FluidPalette.fallbackLight().baseDark,
      );
    });
  });

  group('FluidBackground resources', () {
    testWidgets('disposes images it no longer shows', (tester) async {
      await tester.pumpWidget(
        _Host(imageProvider: _StaticImage(_red), smoothTransitions: true),
      );
      await _settleOn(tester, _red);
      final ui.Image redHandle = _painter(tester)!.image!;

      _host(tester).update(
        () => _host(tester).imageProvider = _StaticImage(_blue),
      );
      await tester.pump();
      await _settleOn(tester, _blue);
      final ui.Image blueHandle = _painter(tester)!.image!;

      expect(redHandle.debugDisposed, isTrue);
      expect(blueHandle.debugDisposed, isFalse);

      // Removing the widget releases the image it was showing.
      _host(tester).update(() => _host(tester).showBackground = false);
      await tester.pump();
      expect(blueHandle.debugDisposed, isTrue);

      // The source images themselves are untouched.
      expect(_red.debugDisposed, isFalse);
      expect(_blue.debugDisposed, isFalse);
    });

    testWidgets('disposes the image when cutting to the matte fallback',
        (tester) async {
      await tester.pumpWidget(_Host(imageProvider: _StaticImage(_red)));
      await _settleOn(tester, _red);
      final ui.Image redHandle = _painter(tester)!.image!;

      _host(tester).update(() => _host(tester).imageProvider = null);
      await tester.pump();
      expect(redHandle.debugDisposed, isTrue);
    });

    testWidgets('disposes an image that loads after the widget is gone',
        (tester) async {
      final provider = _StaticImage(
        _red,
        delay: const Duration(milliseconds: 100),
      );
      await tester.pumpWidget(_Host(imageProvider: provider));
      _host(tester).update(() => _host(tester).showBackground = false);
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 200));
      await _letLoadsFinish(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
