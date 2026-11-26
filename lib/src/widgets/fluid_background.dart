/// Immersive fluid animated background widget with layered image shaders.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../extraction.dart';
import '../fluid_extractor.dart';
import '../fluid_palette.dart';
import '../material.dart';

/// Fallback palette mode when image is unavailable or extraction fails.
enum FluidFallbackMode {
  /// Always use the dark fallback palette.
  dark,

  /// Always use the light fallback palette.
  light,

  /// Match the fallback palette to the surrounding app.
  ///
  /// Uses the brightness of the nearest Material [Theme]. When there is none
  /// (for example in a Cupertino app, or an app built on the separate
  /// `material_ui` package without its compatibility bridge), the platform
  /// brightness from [MediaQuery] is used instead.
  auto,
}

/// Immersive animated background widget inspired by modern music apps.
///
/// Features:
/// - **Optional image** - Shows matte fallback immediately, cross-fades when image loads
/// - **Fluid shader layers** - Multiple transformed ImageShaders create depth
/// - **Heavy blur** - 80σ blur for soft, atmospheric effect
/// - **Corner glows** - Radial gradients using extracted accent colors
/// - **Smooth transitions** - Palette colors tween during image changes
/// - **Optional animation** - Slow orbital motion (12s cycle), paused
///   automatically when the platform asks for reduced motion
///
/// Usage:
/// ```dart
/// FluidBackground(
///   imageProvider: imageUrl == null ? null : NetworkImage(imageUrl),
///   child: YourContent(),
/// )
/// ```
///
/// The widget automatically:
/// 1. Shows a matte gradient background immediately
/// 2. Loads and extracts colors from the image in the background
/// 3. Smoothly transitions to the extracted palette
/// 4. Fades in the fluid shader layers
/// 5. Applies corner glows and dark overlay for legibility
///
/// Example with full configuration:
/// ```dart
/// FluidBackground(
///   imageProvider: NetworkImage('https://example.com/album.jpg'),
///   blurSigma: 80,
///   overlayDarken: 0.10,
///   animate: true,
///   transitionDuration: Duration(milliseconds: 1400),
///   child: Scaffold(
///     backgroundColor: Colors.transparent,
///     body: YourContent(),
///   ),
/// )
/// ```
class FluidBackground extends StatefulWidget {
  /// Creates an immersive fluid background.
  ///
  /// [imageProvider] is optional - if null, shows only the matte fallback.
  /// [child] is the content to display on top of the background.
  const FluidBackground({
    super.key,
    this.imageProvider,
    required this.child,
    this.blurSigma = 80,
    this.overlayDarken = 0.10,
    this.animate = false,
    this.fallbackMode = FluidFallbackMode.auto,
    this.transitionDuration = const Duration(milliseconds: 1400),
    this.smoothTransitions = false,
  });

  /// Optional image to extract colors from.
  ///
  /// If null, shows only the matte fallback background.
  /// If provided, extracts palette and shows fluid shader layers.
  final ImageProvider? imageProvider;

  /// Content to display on top of the background.
  final Widget child;

  /// Blur intensity (sigma) for the fluid shader layers.
  ///
  /// Higher values create softer, more atmospheric backgrounds.
  /// Default: 80 (recommended range: 60-120)
  final double blurSigma;

  /// Dark overlay opacity for text legibility.
  ///
  /// Small values preserve colors while ensuring white text is readable.
  /// Default: 0.10 (recommended range: 0.05-0.20)
  final double overlayDarken;

  /// Enable slow orbital motion animation.
  ///
  /// When true, shader layers slowly rotate and translate (12s cycle).
  /// The motion only runs while an image is on screen, and is paused when the
  /// platform requests reduced motion ([MediaQueryData.disableAnimations]).
  /// Default: false (battery-friendly, deterministic fallback)
  final bool animate;

  /// Fallback palette mode when image is missing or extraction fails.
  ///
  /// Default: [FluidFallbackMode.auto]
  final FluidFallbackMode fallbackMode;

  /// Duration for palette color transitions.
  ///
  /// Controls how long it takes to fade/tween from fallback to extracted colors.
  /// Default: 1400ms
  final Duration transitionDuration;

  /// Smoothly crossfade between the previous and the new image.
  ///
  /// When true, changing [imageProvider] keeps the previous image and palette
  /// fully visible until the new one loads, then crossfades to it instead of
  /// dropping to the matte fallback first. Setting [imageProvider] to null
  /// fades the current image out to the matte fallback.
  ///
  /// A transition that is already running always finishes before the next one
  /// starts, so an image that loads mid-transition appears up to one
  /// [transitionDuration] later. Rapid changes collapse into a single
  /// transition to the latest image.
  ///
  /// If the new image fails to load, the current background stays on screen.
  ///
  /// Default: false (cut to the matte fallback while the new image loads)
  final bool smoothTransitions;

  @override
  State<FluidBackground> createState() => _FluidBackgroundState();
}

class _FluidBackgroundState extends State<FluidBackground>
    with TickerProviderStateMixin {
  static const Duration _motionDuration = Duration(seconds: 12);

  /// Orbit phase shown while the motion is not running.
  static const double _restingMotionPhase = 0.35;

  /// The image and palette being shown (or revealed). Both are null while the
  /// matte fallback is the target.
  ui.Image? _image;
  FluidPalette? _palette;

  /// What the running smooth transition started from. A null palette stands
  /// for the matte fallback.
  ui.Image? _outgoingImage;
  FluidPalette? _outgoingPalette;

  late final AnimationController _motionController = AnimationController(
    vsync: this,
    duration: _motionDuration,
    value: _restingMotionPhase,
  );

  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: widget.transitionDuration,
  );

  int _loadSession = 0;

  /// Completes when the running reveal ends, however it ends. Null when idle.
  /// New commits wait for it so the blend on screen always completes before
  /// the next transition starts.
  Future<void>? _activeReveal;

  /// Bumped whenever a reveal starts or is cancelled; a reveal's completion
  /// cleanup runs only if it still owns the latest reveal.
  int _revealSession = 0;

  FluidPalette _fallbackFor(BuildContext context) {
    switch (widget.fallbackMode) {
      case FluidFallbackMode.dark:
        return const FluidPalette.fallback();
      case FluidFallbackMode.light:
        return const FluidPalette.fallbackLight();
      case FluidFallbackMode.auto:
        return _ambientBrightness(context) == Brightness.light
            ? const FluidPalette.fallbackLight()
            : const FluidPalette.fallback();
    }
  }

  /// Brightness of the surrounding app.
  ///
  /// `Theme.of` silently returns a light fallback theme when no Material
  /// theme is installed, so check for one first and otherwise follow the
  /// platform brightness.
  static Brightness _ambientBrightness(BuildContext context) {
    if (context.findAncestorWidgetOfExactType<Theme>() != null) {
      return Theme.of(context).brightness;
    }
    return MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
  }

  @override
  void initState() {
    super.initState();
    _kickLoad();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion can be switched on or off at any time.
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant FluidBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.transitionDuration != widget.transitionDuration) {
      _revealController.duration = widget.transitionDuration;
    }
    if (oldWidget.imageProvider != widget.imageProvider) {
      _kickLoad();
    }
    _syncMotion();
  }

  @override
  void dispose() {
    _motionController.dispose();
    _revealController.dispose();
    _image?.dispose();
    _outgoingImage?.dispose();
    super.dispose();
  }

  /// Runs the orbit only while it can be seen: [FluidBackground.animate] is
  /// on, the platform does not ask for reduced motion, and there is an image
  /// to move. Stopping keeps the current phase, so resuming is seamless.
  void _syncMotion() {
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bool shouldRun = widget.animate &&
        !reduceMotion &&
        (_image != null || _outgoingImage != null);
    if (shouldRun == _motionController.isAnimating) return;
    if (shouldRun) {
      // Continues from the current phase. Deliberately not animateTo/forward:
      // those run 20x faster when the platform disables animations.
      _motionController.repeat();
    } else {
      _motionController.stop();
    }
  }

  void _kickLoad() {
    final int loadToken = ++_loadSession;
    final ImageProvider? provider = widget.imageProvider;

    if (!widget.smoothTransitions) {
      // Cut to the matte fallback until the new image (if any) has loaded.
      _cancelReveal();
      _image?.dispose();
      _outgoingImage?.dispose();
      _image = null;
      _palette = null;
      _outgoingImage = null;
      _outgoingPalette = null;
      if (provider == null) return;
    } else if (provider == null && _image == null) {
      // Nothing on screen to fade out.
      return;
    }
    // With smooth transitions the current image and palette stay on screen
    // until the new target is ready.

    unawaited(_resolve(provider, loadToken: loadToken));
  }

  Future<void> _resolve(
    ImageProvider? provider, {
    required int loadToken,
  }) async {
    ui.Image? image;
    FluidPalette? palette;

    if (provider != null) {
      try {
        image = await loadImageFromProvider(provider);
        palette = await FluidPaletteExtractor.buildPaletteFromImage(image);
      } catch (_) {
        // Without smooth transitions the matte fallback is already showing;
        // with them the current background simply stays on screen.
        image?.dispose();
        return;
      }
    }

    // Let the running reveal finish so the blend on screen (e.g. an A-to-B
    // crossfade) completes before blending toward the new target. Superseded
    // loads bail out below, so rapid provider changes collapse into a single
    // transition to the latest image instead of piling up reveals.
    final Future<void>? pending = _activeReveal;
    if (pending != null && mounted && loadToken == _loadSession) {
      await pending;
    }

    if (!mounted || loadToken != _loadSession) {
      image?.dispose();
      return;
    }
    _commit(image, palette);
  }

  /// Makes [image] and [palette] the new target and reveals them. Both are
  /// null when fading out to the matte fallback.
  void _commit(ui.Image? image, FluidPalette? palette) {
    setState(() {
      _outgoingImage?.dispose();
      if (widget.smoothTransitions) {
        _outgoingImage = _image;
        _outgoingPalette = _palette;
      } else {
        _image?.dispose();
        _outgoingImage = null;
        _outgoingPalette = null;
      }
      _image = image;
      _palette = palette;
    });
    _syncMotion();

    final int revealToken = ++_revealSession;
    final Completer<void> done = Completer<void>();
    _activeReveal = done.future;
    _revealController.forward(from: 0).whenCompleteOrCancel(() {
      if (identical(_activeReveal, done.future)) _activeReveal = null;
      // Whoever cancelled or superseded this reveal owns the display state.
      if (mounted && revealToken == _revealSession) {
        setState(() {
          _outgoingImage?.dispose();
          _outgoingImage = null;
          _outgoingPalette = null;
        });
        _syncMotion();
      }
      done.complete();
    });
  }

  void _cancelReveal() {
    _revealSession++;
    _activeReveal = null;
    // Setting the value stops the running ticker.
    _revealController.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final FluidPalette fallback = _fallbackFor(context);
    final FluidPalette from = _outgoingPalette ?? fallback;
    final FluidPalette target = _palette ?? fallback;
    final Color overlayColor = fallback.baseDark.computeLuminance() > 0.55
        ? Colors.white.withValues(alpha: widget.overlayDarken * 0.45)
        : Colors.black.withValues(alpha: widget.overlayDarken);
    final bool hasImage = _image != null || _outgoingImage != null;

    return Scaffold(
      backgroundColor: fallback.baseDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The background paints into its own layer: its repaints (palette
          // tween, orbit) do not repaint the content, and content repaints do
          // not repaint the background.
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _revealController,
              builder: (context, _) {
                final FluidPalette current = FluidPalette.lerp(
                  from,
                  target,
                  _revealController.value,
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Matte fallback base (always visible)
                    _MatteFallbackBase(palette: current),

                    // Fluid shader layers. Outgoing and incoming images are
                    // painted by one painter inside one blur layer, driven
                    // directly by the animations, so neither the orbit nor
                    // the crossfade rebuilds any widgets.
                    if (hasImage)
                      RepaintBoundary(
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: widget.blurSigma,
                            sigmaY: widget.blurSigma,
                            tileMode: ui.TileMode.clamp,
                          ),
                          child: CustomPaint(
                            painter: FluidShaderPainter(
                              image: _image,
                              outgoingImage: _outgoingImage,
                              reveal: _revealController,
                              motion: _motionController,
                            ),
                          ),
                        ),
                      ),

                    // Corner glows
                    _CornerGlows(
                      tl: current.accent1,
                      tr: current.accent2,
                      bl: current.accent3,
                      br: current.accent4,
                    ),

                    // Adaptive overlay for legibility in dark/light fallback
                    // modes
                    ColoredBox(color: overlayColor),
                  ],
                );
              },
            ),
          ),

          // User content
          widget.child,
        ],
      ),
    );
  }
}

/// Matte gradient fallback base layer.
class _MatteFallbackBase extends StatelessWidget {
  const _MatteFallbackBase({required this.palette});
  final FluidPalette palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                palette.accent1.withValues(alpha: 0.55),
                palette.accent2.withValues(alpha: 0.45),
                palette.baseDark,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        const _MatteNoiseOverlay(),
      ],
    );
  }
}

/// Paints the blurred fluid layers of a [FluidBackground].
///
/// Internal to the package; public only so tests can inspect it.
@visibleForTesting
class FluidShaderPainter extends CustomPainter {
  /// Creates a painter for [image], optionally transitioning from
  /// [outgoingImage] as [reveal] runs from 0 to 1.
  FluidShaderPainter({
    required this.image,
    required this.outgoingImage,
    required this.reveal,
    required this.motion,
  }) : super(repaint: Listenable.merge([reveal, motion]));

  /// Image being revealed, or null when fading out to the matte fallback.
  final ui.Image? image;

  /// Image the transition started from, if any.
  final ui.Image? outgoingImage;

  /// Transition progress, 0 to 1.
  final Animation<double> reveal;

  /// Orbit phase, 0 to 1 per cycle.
  final Animation<double> motion;

  static const Color _backdrop = Color(0xFF0F1419);

  static const List<_ShaderLayer> _layers = <_ShaderLayer>[
    _ShaderLayer(
      scale: 1.35,
      rotFrom: -0.08,
      rotTo: 0.10,
      ampX: 0.10,
      ampY: 0.08,
      phase: 0.0,
      alpha: 0.55,
    ),
    _ShaderLayer(
      scale: 0.95,
      rotFrom: 0.12,
      rotTo: -0.06,
      ampX: 0.18,
      ampY: 0.14,
      phase: 0.33,
      alpha: 0.45,
    ),
    _ShaderLayer(
      scale: 0.70,
      rotFrom: -0.18,
      rotTo: 0.04,
      ampX: 0.22,
      ampY: 0.18,
      phase: 0.66,
      alpha: 0.35,
    ),
    _ShaderLayer(
      scale: 1.85,
      rotFrom: 0.05,
      rotTo: -0.12,
      ampX: 0.06,
      ampY: 0.06,
      phase: 0.18,
      alpha: 0.25,
    ),
  ];

  /// Phase offset of the rotation wave. Chosen so the resting frame (motion
  /// phase 0.35) has exactly the rotation it had in 3.1.0 and earlier, where
  /// rotation was a linear ramp that jumped at every cycle wrap.
  static final double _rotationPhase = math.acos(0.3) / (2 * math.pi) - 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = motion.value;
    final double incoming = Curves.easeInOutCubic.transform(reveal.value);
    final ui.Image? current = image;
    final ui.Image? outgoing = outgoingImage;

    if (outgoing != null) {
      // Under an incoming image the outgoing one stays opaque, so the result
      // is an exact crossfade that never lets the matte base show through.
      // With nothing incoming it fades out to the matte base instead.
      final double opacity = current == null ? 1.0 - incoming : 1.0;
      if (current == null || incoming < 1.0) {
        _paintImage(canvas, size, outgoing, t, opacity);
      }
    }
    if (current != null) {
      _paintImage(canvas, size, current, t, incoming);
    }
  }

  void _paintImage(
    Canvas canvas,
    Size size,
    ui.Image image,
    double t,
    double opacity,
  ) {
    if (opacity <= 0.0) return;
    final Rect rect = Offset.zero & size;

    // Fade the layers as one group; fading each layer separately would let
    // the backdrop and lower layers show through mid-transition.
    final bool group = opacity < 1.0;
    if (group) {
      canvas.saveLayer(
        rect,
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }

    canvas.drawRect(rect, Paint()..color = _backdrop);

    final Paint paint = Paint()..blendMode = ui.BlendMode.srcOver;
    for (final _ShaderLayer layer in _layers) {
      final double phase = t + layer.phase;
      paint
        ..shader = ui.ImageShader(
          image,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          _layerMatrix(
            size: size,
            image: image,
            scale: layer.scale,
            rotation: _oscillate(layer.rotFrom, layer.rotTo, t),
            dx: math.sin(phase * 2 * math.pi) * layer.ampX,
            dy: math.cos(phase * 2 * math.pi) * layer.ampY,
          ),
        )
        ..color = Color.fromRGBO(255, 255, 255, layer.alpha);
      canvas.drawRect(rect, paint);
    }

    if (group) canvas.restore();
  }

  /// Column-major 4x4 matrix that centers the image on the canvas, scales and
  /// rotates it about its center, and offsets it by a fraction of the canvas.
  static Float64List _layerMatrix({
    required Size size,
    required ui.Image image,
    required double scale,
    required double rotation,
    required double dx,
    required double dy,
  }) {
    final double cosR = math.cos(rotation) * scale;
    final double sinR = math.sin(rotation) * scale;
    final double halfW = image.width / 2.0;
    final double halfH = image.height / 2.0;
    final Float64List m = Float64List(16);
    m[0] = cosR;
    m[1] = sinR;
    m[4] = -sinR;
    m[5] = cosR;
    m[10] = 1.0;
    m[12] = size.width * (0.5 + dx) - cosR * halfW + sinR * halfH;
    m[13] = size.height * (0.5 + dy) - sinR * halfW - cosR * halfH;
    m[15] = 1.0;
    return m;
  }

  /// Oscillates between [a] and [b] and back over one motion cycle, so the
  /// value is continuous across the wrap of the repeating controller.
  static double _oscillate(double a, double b, double t) {
    final double wave =
        0.5 - 0.5 * math.cos((t + _rotationPhase) * 2 * math.pi);
    return a + (b - a) * wave;
  }

  @override
  bool shouldRepaint(covariant FluidShaderPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.outgoingImage != outgoingImage ||
      oldDelegate.reveal != reveal ||
      oldDelegate.motion != motion;
}

/// Shader layer configuration.
class _ShaderLayer {
  const _ShaderLayer({
    required this.scale,
    required this.rotFrom,
    required this.rotTo,
    required this.ampX,
    required this.ampY,
    required this.phase,
    required this.alpha,
  });

  final double scale;
  final double rotFrom;
  final double rotTo;
  final double ampX;
  final double ampY;
  final double phase;
  final double alpha;
}

/// Corner radial glow accents.
class _CornerGlows extends StatelessWidget {
  const _CornerGlows({
    required this.tl,
    required this.tr,
    required this.bl,
    required this.br,
  });

  final Color tl;
  final Color tr;
  final Color bl;
  final Color br;

  @override
  Widget build(BuildContext context) {
    Widget glow(Color c, Alignment a) {
      return Align(
        alignment: a,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: 90,
            sigmaY: 90,
            tileMode: ui.TileMode.clamp,
          ),
          child: Container(
            width: 360,
            height: 360,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  c.withValues(alpha: 0.28),
                  c.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Stack(
        children: [
          glow(tl, Alignment.topLeft),
          glow(tr, Alignment.topRight),
          glow(bl, Alignment.bottomLeft),
          glow(br, Alignment.bottomRight),
        ],
      ),
    );
  }
}

/// Matte noise overlay for texture.
class _MatteNoiseOverlay extends StatelessWidget {
  const _MatteNoiseOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.06,
        child: CustomPaint(painter: _NoisePainter()),
      ),
    );
  }
}

/// Simple noise texture painter.
class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final rnd = math.Random(1);
    for (int i = 0; i < 1200; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final a = 20 + rnd.nextInt(30);
      paint.color = Colors.white.withAlpha(a);
      canvas.drawRect(Rect.fromLTWH(dx, dy, 1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
