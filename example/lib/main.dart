import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

void main() {
  runApp(
    const PaletteScope(
      seed: ThemeColors.fallback(),
      brightness: Brightness.dark,
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PaletteScope.of(context).theme,
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  ThemeColors? _extractedColors;
  bool _isLoading = true;

  static const String demoImage = 'https://picsum.photos/800/600';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _extractPalette();
  }

  Future<void> _extractPalette() async {
    // Extract colors from image
    final colors = await AdaptivePalette.fromImage(
      const NetworkImage(demoImage),
      targetBrightness: Brightness.dark,
      resize: 64,
      quantizeColors: 32,
      minContrast: 4.5,
    );

    if (!mounted) return;

    setState(() {
      _extractedColors = colors;
      _isLoading = false;
    });

    // Animate to new theme
    PaletteScope.of(context).animateTo(
      colors,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background
          FadeTransition(
            opacity: _fadeAnimation,
            child: RepaintBoundary(
              child: Transform.scale(
                scale: 1.2,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 80,
                    sigmaY: 80,
                    tileMode: TileMode.decal,
                  ),
                  child: Image.network(
                    demoImage,
                    fit: BoxFit.cover,
                    frameBuilder:
                        (context, child, frame, wasSynchronouslyLoaded) {
                          if (wasSynchronouslyLoaded) return child;
                          return frame != null
                              ? child
                              : Container(color: Colors.black);
                        },
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.black),
                  ),
                ),
              ),
            ),
          ),

          // Color overlay
          FadeTransition(
            opacity: _fadeAnimation,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.surface.withValues(alpha: 0.1),
                    scheme.surface.withValues(alpha: 0.3),
                  ],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 40),

                        // Title
                        Text(
                          'Adaptive Palette',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Dynamic theming from images',
                          style: TextStyle(
                            fontSize: 18,
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 48),

                        // Image preview
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            demoImage,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Color palette
                        if (_extractedColors != null)
                          _ColorPaletteDisplay(colors: _extractedColors!),

                        const SizedBox(height: 32),

                        // Feature cards
                        _FeatureCard(
                          icon: Icons.palette,
                          title: 'Smart Color Extraction',
                          description:
                              'Uses median-cut quantization to find vibrant colors',
                        ),
                        const SizedBox(height: 16),
                        _FeatureCard(
                          icon: Icons.accessibility_new,
                          title: 'WCAG Contrast',
                          description:
                              'Ensures readable text with contrast guarantees',
                        ),
                        const SizedBox(height: 16),
                        _FeatureCard(
                          icon: Icons.animation,
                          title: 'Smooth Transitions',
                          description:
                              'Animated theme changes with PaletteScope',
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ColorPaletteDisplay extends StatelessWidget {
  final ThemeColors colors;

  const _ColorPaletteDisplay({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Extracted Colors',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ColorChip(color: colors.primary, label: 'Primary'),
              _ColorChip(color: colors.secondary, label: 'Secondary'),
              _ColorChip(color: colors.background, label: 'Background'),
              _ColorChip(color: colors.surface, label: 'Surface'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  final Color color;
  final String label;

  const _ColorChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: scheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
