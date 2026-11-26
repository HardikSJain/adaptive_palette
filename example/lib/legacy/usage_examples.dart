/// Comprehensive usage examples for Adaptive Palette package.
///
/// This file demonstrates various ways to use the package, from basic
/// to advanced usage patterns.
library;

import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:flutter/material.dart';

// ============================================================================
// EXAMPLE 1: Basic Usage - Extract colors from an image
// ============================================================================

Future<void> basicUsageExample() async {
  // Simple extraction with defaults
  final colors = await AdaptivePalette.fromImage(
    const NetworkImage('https://picsum.photos/800/600'),
    targetBrightness: Brightness.dark,
  );

  print('Primary color: ${colors.primary}');
  print('Secondary color: ${colors.secondary}');
}

// ============================================================================
// EXAMPLE 2: Quality Presets - Fast, Balanced, High
// ============================================================================

Future<void> qualityPresetsExample() async {
  // Fast extraction for scrolling lists
  await AdaptivePalette.fromImage(
    const NetworkImage('https://example.com/thumbnail.jpg'),
    config: ExtractionConfig.fromQuality(ExtractionQuality.fast),
  );

  // Balanced for general use (default)
  await AdaptivePalette.fromImage(
    const NetworkImage('https://example.com/image.jpg'),
    config: ExtractionConfig.fromQuality(ExtractionQuality.balanced),
  );

  // High quality for hero images
  await AdaptivePalette.fromImage(
    const NetworkImage('https://example.com/hero.jpg'),
    config: ExtractionConfig.fromQuality(ExtractionQuality.high),
  );
}

// ============================================================================
// EXAMPLE 3: Advanced Configuration
// ============================================================================

Future<void> advancedConfigExample() async {
  await AdaptivePalette.fromImage(
    const NetworkImage('https://example.com/image.jpg'),
    config: ExtractionConfig(
      targetBrightness: Brightness.dark,
      quantizeColors: 32, // More colors = better selection
      resize: 128, // Larger = more accurate
      minContrast: 7.0, // WCAG AAA (stricter)
      diversityWeight: 1.5, // Favor diverse colors
      onDebug: (stats) {
        print('Extraction took: ${stats.duration.inMilliseconds}ms');
        print('Image type: ${stats.imageType}');
        print('Colors extracted: ${stats.colorsExtracted}');
        print('From cache: ${stats.fromCache}');
      },
      onError: (error, stack) {
        print('Extraction failed: $error');
      },
    ),
  );
}

// ============================================================================
// EXAMPLE 4: Full App with PaletteScope
// ============================================================================

class FullAppExample extends StatelessWidget {
  const FullAppExample({super.key});

  @override
  Widget build(BuildContext context) {
    return const PaletteScope(
      seed: ThemeColors.fallback(),
      brightness: Brightness.dark,
      child: _MyApp(),
    );
  }
}

class _MyApp extends StatelessWidget {
  const _MyApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: PaletteScope.of(context).theme,
      home: const _HomePage(),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  @override
  void initState() {
    super.initState();
    _loadPalette();
  }

  Future<void> _loadPalette() async {
    final colors = await AdaptivePalette.fromImage(
      const NetworkImage('https://picsum.photos/800/600'),
      config: ExtractionConfig.fromQuality(ExtractionQuality.high),
    );

    if (!mounted) return;

    // Animate to new theme
    PaletteScope.of(context).animateTo(
      colors,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adaptive Palette')),
      body: const Center(child: Text('Theme adapts to image')),
    );
  }
}

// ============================================================================
// EXAMPLE 5: Spotify-Style Hero Card
// ============================================================================

class SpotifyStyleCard extends StatelessWidget {
  const SpotifyStyleCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveImageOverlay.network(
      'https://picsum.photos/1600/900',
      aspectRatio: 16 / 9,
      borderRadius: BorderRadius.circular(28),
      overlayStyle: const AdaptiveOverlayStyle(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: [0.0, 0.4, 0.7, 1.0],
        opacities: [0.95, 0.65, 0.25, 0.0],
        tone: AdaptiveOverlayTone.primary,
      ),
      padding: const EdgeInsets.all(32),
      config: ExtractionConfig.fromQuality(ExtractionQuality.high),
      onColorsReady: (colors) {
        print('Extracted colors: $colors');
      },
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Playlist Name',
            style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          Text(
            'Adaptive colors from your image',
            style: TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EXAMPLE 6: YouTube-Style Thumbnail Glow
// ============================================================================

class YouTubeStyleThumbnail extends StatelessWidget {
  const YouTubeStyleThumbnail({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveGlowImageFrame.network(
      'https://picsum.photos/2000/1100',
      aspectRatio: 21 / 9,
      blurRadius: 48,
      spreadRadius: 10,
      layers: 2,
      tone: AdaptiveOverlayTone.secondary,
      config: ExtractionConfig.fromQuality(ExtractionQuality.balanced),
      onColorsReady: (colors) {
        print('Glow color: ${colors.secondary}');
      },
    );
  }
}

// ============================================================================
// EXAMPLE 7: Full-Screen Adaptive Background
// ============================================================================

class AdaptiveBackgroundPage extends StatelessWidget {
  const AdaptiveBackgroundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveGradientScaffold.network(
      'https://picsum.photos/1800/1200',
      gradientStyle: const AdaptiveOverlayStyle(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.45, 1.0],
        opacities: [0.95, 0.55, 0.1],
        tone: AdaptiveOverlayTone.surface,
      ),
      appBar: AppBar(
        title: const Text('Adaptive Background'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Text('Content adapts to image colors'),
          SizedBox(height: 16),
          Text('Smooth gradient background'),
        ],
      ),
      syncWithPaletteScope: true, // Drive app-wide theme
      config: ExtractionConfig.fromQuality(ExtractionQuality.high),
    );
  }
}

// ============================================================================
// EXAMPLE 8: Cache Warming for Lists
// ============================================================================

class ImageGridExample extends StatefulWidget {
  const ImageGridExample({super.key});

  @override
  State<ImageGridExample> createState() => _ImageGridExampleState();
}

class _ImageGridExampleState extends State<ImageGridExample> {
  final List<String> imageUrls = [
    'https://picsum.photos/400/400?random=1',
    'https://picsum.photos/400/400?random=2',
    'https://picsum.photos/400/400?random=3',
    'https://picsum.photos/400/400?random=4',
  ];

  @override
  void initState() {
    super.initState();
    _warmupCache();
  }

  Future<void> _warmupCache() async {
    // Preload all palettes
    final providers = imageUrls.map((url) => NetworkImage(url)).toList();
    final preloaded = await AdaptivePalette.warmup(
      providers,
      config: ExtractionConfig.fromQuality(ExtractionQuality.fast),
    );
    print('Preloaded ${preloaded.length} palettes');
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: imageUrls.length,
      itemBuilder: (context, index) {
        return AdaptiveImageOverlay.network(
          imageUrls[index],
          aspectRatio: 1,
          child: Text('Item $index'),
        );
      },
    );
  }
}

// ============================================================================
// EXAMPLE 9: Custom Gradient Patterns
// ============================================================================

class CustomGradientExample extends StatelessWidget {
  const CustomGradientExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Diagonal gradient
        AdaptiveImageOverlay.network(
          'https://picsum.photos/800/600?random=1',
          overlayStyle: const AdaptiveOverlayStyle(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            stops: [0.0, 0.45, 1.0],
            opacities: [0.95, 0.45, 0.0],
            tone: AdaptiveOverlayTone.secondary,
          ),
          child: const Text('Diagonal Gradient'),
        ),
        const SizedBox(height: 16),
        // Vertical gradient
        AdaptiveImageOverlay.network(
          'https://picsum.photos/800/600?random=2',
          overlayStyle: const AdaptiveOverlayStyle(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.3, 0.7, 1.0],
            opacities: [0.0, 0.3, 0.7, 0.95],
            tone: AdaptiveOverlayTone.background,
          ),
          child: const Text('Vertical Gradient'),
        ),
      ],
    );
  }
}

// ============================================================================
// EXAMPLE 10: Manual Color Extraction & Usage
// ============================================================================

class ManualColorExample extends StatefulWidget {
  const ManualColorExample({super.key});

  @override
  State<ManualColorExample> createState() => _ManualColorExampleState();
}

class _ManualColorExampleState extends State<ManualColorExample> {
  ThemeColors? _colors;

  @override
  void initState() {
    super.initState();
    _extract();
  }

  Future<void> _extract() async {
    final colors = await AdaptivePalette.fromImage(
      const NetworkImage('https://picsum.photos/800/600'),
      config: ExtractionConfig(
        targetBrightness: Brightness.dark,
        onDebug: (stats) {
          print('Extraction stats: $stats');
        },
      ),
    );

    setState(() => _colors = colors);
  }

  @override
  Widget build(BuildContext context) {
    if (_colors == null) {
      return const CircularProgressIndicator();
    }

    return Column(
      children: [
        // Use extracted colors manually
        Container(
          color: _colors!.primary,
          padding: const EdgeInsets.all(16),
          child: Text(
            'Primary Color',
            style: TextStyle(color: _colors!.onPrimary),
          ),
        ),
        Container(
          color: _colors!.secondary,
          padding: const EdgeInsets.all(16),
          child: Text(
            'Secondary Color',
            style: TextStyle(color: _colors!.onSecondary),
          ),
        ),
        Container(
          color: _colors!.background,
          padding: const EdgeInsets.all(16),
          child: Text(
            'Background Color',
            style: TextStyle(color: _colors!.onBackground),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// EXAMPLE 11: Cache Management
// ============================================================================

class CacheManagementExample extends StatelessWidget {
  const CacheManagementExample({super.key});

  void _demonstrateCacheManagement() {
    // Configure cache size
    CacheConfig.maxSize = 64; // Store more palettes

    // Check cache stats
    final (size, capacity) = AdaptivePalette.cacheStats();
    print('Cache: $size/$capacity');

    // Clear cache when needed
    AdaptivePalette.clearCache();
    print('Cache cleared');

    // Disable caching if needed
    CacheConfig.enabled = false;
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _demonstrateCacheManagement,
      child: const Text('Manage Cache'),
    );
  }
}

// ============================================================================
// EXAMPLE 12: Animated Theme Transitions
// ============================================================================

class AnimatedThemeExample extends StatefulWidget {
  const AnimatedThemeExample({super.key});

  @override
  State<AnimatedThemeExample> createState() => _AnimatedThemeExampleState();
}

class _AnimatedThemeExampleState extends State<AnimatedThemeExample> {
  int _currentImage = 0;
  final List<String> _images = [
    'https://picsum.photos/800/600?random=1',
    'https://picsum.photos/800/600?random=2',
    'https://picsum.photos/800/600?random=3',
  ];

  Future<void> _changeTheme() async {
    setState(() {
      _currentImage = (_currentImage + 1) % _images.length;
    });

    final colors = await AdaptivePalette.fromImage(
      NetworkImage(_images[_currentImage]),
      config: ExtractionConfig.fromQuality(ExtractionQuality.high),
    );

    if (!mounted) return;

    // Smooth animated transition
    PaletteScope.of(context).animateTo(
      colors,
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.network(_images[_currentImage]),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _changeTheme,
          child: const Text('Change Theme'),
        ),
      ],
    );
  }
}

// ============================================================================
// EXAMPLE 13: Error Handling
// ============================================================================

Future<void> errorHandlingExample() async {
  try {
    final colors = await AdaptivePalette.fromImage(
      const NetworkImage('https://invalid-url.com/image.jpg'),
      config: ExtractionConfig(
        onError: (error, stack) {
          print('Custom error handler: $error');
          // Log to analytics, show user message, etc.
        },
      ),
    );

    // Even on error, you get fallback colors
    print('Colors (may be fallback): ${colors.primary}');
  } catch (e) {
    print('Caught exception: $e');
    // Use fallback
    print('Using fallback colors: ${ThemeColors.fallback().primary}');
  }
}

// ============================================================================
// EXAMPLE 14: Different Image Sources
// ============================================================================

Future<void> imageSources() async {
  // Network image
  await AdaptivePalette.fromImage(
    const NetworkImage('https://example.com/image.jpg'),
  );

  // Asset image
  await AdaptivePalette.fromImage(
    const AssetImage('assets/hero.jpg'),
  );

  // File image (from device storage)
  // await AdaptivePalette.fromImage(
  //   FileImage(File('/path/to/image.jpg')),
  // );

  // Memory image (from bytes)
  // await AdaptivePalette.fromImage(
  //   MemoryImage(imageBytes),
  // );
}

// ============================================================================
// EXAMPLE 15: Performance Monitoring
// ============================================================================

class PerformanceMonitoringExample extends StatefulWidget {
  const PerformanceMonitoringExample({super.key});

  @override
  State<PerformanceMonitoringExample> createState() =>
      _PerformanceMonitoringExampleState();
}

class _PerformanceMonitoringExampleState
    extends State<PerformanceMonitoringExample> {
  final List<ExtractionStats> _stats = [];

  Future<void> _extractWithMonitoring() async {
    await AdaptivePalette.fromImage(
      const NetworkImage('https://picsum.photos/800/600'),
      config: ExtractionConfig(
        onDebug: (stats) {
          setState(() => _stats.add(stats));
          print('Performance: ${stats.duration.inMilliseconds}ms');
          print('Cache hit rate: ${_calculateCacheHitRate()}%');
        },
      ),
    );
  }

  double _calculateCacheHitRate() {
    if (_stats.isEmpty) return 0;
    final hits = _stats.where((s) => s.fromCache).length;
    return (hits / _stats.length) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _extractWithMonitoring,
          child: const Text('Extract with Monitoring'),
        ),
        Text('Extractions: ${_stats.length}'),
        Text('Cache hit rate: ${_calculateCacheHitRate().toStringAsFixed(1)}%'),
        if (_stats.isNotEmpty)
          Text(
              'Avg duration: ${_stats.map((s) => s.duration.inMilliseconds).reduce((a, b) => a + b) ~/ _stats.length}ms'),
      ],
    );
  }
}
