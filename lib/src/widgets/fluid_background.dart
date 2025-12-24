/// Immersive fluid animated background widget with layered image shaders.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../extraction.dart';
import '../fluid_extractor.dart';
import '../fluid_palette.dart';

/// Immersive animated background widget inspired by modern music apps.
///
/// Features:
/// - **Optional image** - Shows matte fallback immediately, cross-fades when image loads
/// - **Fluid shader layers** - Multiple transformed ImageShaders create depth
/// - **Heavy blur** - 80σ blur for soft, atmospheric effect
/// - **Corner glows** - Radial gradients using extracted accent colors
/// - **Smooth transitions** - Palette colors tween during image changes
/// - **Optional animation** - Slow orbital motion (12s cycle)
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
    this.animate = true,
    this.transitionDuration = const Duration(milliseconds: 1400),
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
  /// Default: true
  final bool animate;

  /// Duration for palette color transitions.
  ///
  /// Controls how long it takes to fade/tween from fallback to extracted colors.
  /// Default: 1400ms
  final Duration transitionDuration;

  @override
  State<FluidBackground> createState() => _FluidBackgroundState();
}

class _FluidBackgroundState extends State<FluidBackground>
    with TickerProviderStateMixin {
  ui.Image? _image;
  FluidPalette? _palette;

  late final AnimationController _motionController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: widget.transitionDuration,
  );

  static const FluidPalette _fallbackPalette = FluidPalette.fallback();

  @override
  void initState() {
    super.initState();
    if (widget.animate) _motionController.repeat();
    _kickLoad();
  }

  @override
  void didUpdateWidget(covariant FluidBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.animate != widget.animate) {
      if (widget.animate) {
        _motionController.repeat();
      } else {
        _motionController.stop();
      }
    }

    if (oldWidget.imageProvider != widget.imageProvider) {
      _kickLoad();
    }
  }

  @override
  void dispose() {
    _motionController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  void _kickLoad() {
    _revealController.value = 0;
    _image = null;
    _palette = null;

    final provider = widget.imageProvider;
    if (provider == null) {
      setState(() {});
      return;
    }
    _load(provider);
  }

  Future<void> _load(ImageProvider provider) async {
    try {
      final ui.Image img = await loadImageFromProvider(provider);
      final FluidPalette pal = await FluidPaletteExtractor.extract(img);

      if (!mounted) return;
      setState(() {
        _image = img;
        _palette = pal;
      });

      await _revealController.forward(from: 0);
    } catch (_) {
      if (!mounted) return;
      _image = null;
      _palette = null;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final FluidPalette target = _palette ?? _fallbackPalette;
    final double tMotion = widget.animate ? _motionController.value : 0.35;

    return Scaffold(
      backgroundColor: _fallbackPalette.baseDark,
      body: AnimatedBuilder(
        animation: Listenable.merge([_motionController, _revealController]),
        builder: (context, _) {
          final double k = _revealController.value;
          final FluidPalette current = FluidPalette.lerp(_fallbackPalette, target, k);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Matte fallback base (always visible)
              _MatteFallbackBase(palette: current),

              // Fluid shader layers (fade in when image loads)
              if (_image != null)
                Opacity(
                  opacity: Curves.easeInOutCubic.transform(k),
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: widget.blurSigma,
                      sigmaY: widget.blurSigma,
                      tileMode: ui.TileMode.clamp,
                    ),
                    child: CustomPaint(
                      painter: _FluidShaderPainter(image: _image!, t: tMotion),
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

              // Dark overlay for legibility
              Container(color: Colors.black.withOpacity(widget.overlayDarken)),

              // User content
              widget.child,
            ],
          );
        },
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
                palette.accent1.withOpacity(0.55),
                palette.accent2.withOpacity(0.45),
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

/// Fluid shader painter with multiple transformed image layers.
class _FluidShaderPainter extends CustomPainter {
  _FluidShaderPainter({required this.image, required this.t});

  final ui.Image image;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0F1419),
    );

    final layers = <_ShaderLayer>[
      _ShaderLayer(
        scale: 1.35,
        rot: _lerp(-0.08, 0.10, t),
        dx: _orbitX(0.10, t),
        dy: _orbitY(0.08, t),
        alpha: 0.55,
      ),
      _ShaderLayer(
        scale: 0.95,
        rot: _lerp(0.12, -0.06, t),
        dx: _orbitX(0.18, t + 0.33),
        dy: _orbitY(0.14, t + 0.33),
        alpha: 0.45,
      ),
      _ShaderLayer(
        scale: 0.70,
        rot: _lerp(-0.18, 0.04, t),
        dx: _orbitX(0.22, t + 0.66),
        dy: _orbitY(0.18, t + 0.66),
        alpha: 0.35,
      ),
      _ShaderLayer(
        scale: 1.85,
        rot: _lerp(0.05, -0.12, t),
        dx: _orbitX(0.06, t + 0.18),
        dy: _orbitY(0.06, t + 0.18),
        alpha: 0.25,
      ),
    ];

    for (final layer in layers) {
      final Matrix4 m = Matrix4.identity()
        ..translate(size.width * 0.5, size.height * 0.5)
        ..translate(size.width * layer.dx, size.height * layer.dy)
        ..rotateZ(layer.rot)
        ..scale(layer.scale, layer.scale)
        ..translate(-image.width / 2.0, -image.height / 2.0);

      final paint = Paint()
        ..shader = ui.ImageShader(
          image,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          m.storage,
        )
        ..color = Colors.white.withOpacity(layer.alpha)
        ..blendMode = ui.BlendMode.srcOver;

      canvas.drawRect(Offset.zero & size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FluidShaderPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.image != image;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static double _orbitX(double amp, double t) =>
      math.sin(t * 2 * math.pi) * amp;
  static double _orbitY(double amp, double t) =>
      math.cos(t * 2 * math.pi) * amp;
}

/// Shader layer configuration.
class _ShaderLayer {
  const _ShaderLayer({
    required this.scale,
    required this.rot,
    required this.dx,
    required this.dy,
    required this.alpha,
  });

  final double scale;
  final double rot;
  final double dx;
  final double dy;
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
                  c.withOpacity(0.28),
                  c.withOpacity(0.12),
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
