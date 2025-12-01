/// Quick Reference Guide for Adaptive Palette
///
/// Copy-paste ready code snippets for common use cases.
library;

import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:flutter/material.dart';

// ============================================================================
// QUICK SETUP
// ============================================================================

// 1. Wrap your app with PaletteScope
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
      theme: PaletteScope.of(context).theme, // <-- Use adaptive theme
      home: const HomePage(),
    );
  }
}

// 2. Extract and apply colors
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    _applyTheme();
  }

  Future<void> _applyTheme() async {
    final colors = await AdaptivePalette.fromImage(
      const NetworkImage('YOUR_IMAGE_URL'),
      targetBrightness: Brightness.dark,
    );

    if (!mounted) return;
    PaletteScope.of(context).animateTo(colors);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Adaptive Palette')),
        body: const Center(child: Text('Your content')),
      );
}

// ============================================================================
// COMMON PATTERNS
// ============================================================================

// Pattern 1: Fast extraction for lists
Future<ThemeColors> fastExtraction(String imageUrl) {
  return AdaptivePalette.fromImage(
    NetworkImage(imageUrl),
    config: ExtractionConfig.fromQuality(ExtractionQuality.fast),
  );
}

// Pattern 2: High quality for hero images
Future<ThemeColors> highQualityExtraction(String imageUrl) {
  return AdaptivePalette.fromImage(
    NetworkImage(imageUrl),
    config: ExtractionConfig.fromQuality(ExtractionQuality.high),
  );
}

// Pattern 3: With performance monitoring
Future<ThemeColors> monitoredExtraction(String imageUrl) {
  return AdaptivePalette.fromImage(
    NetworkImage(imageUrl),
    config: ExtractionConfig(
      onDebug: (stats) => print('Took ${stats.duration.inMilliseconds}ms'),
      onError: (error, stack) => print('Error: $error'),
    ),
  );
}

// Pattern 4: Spotify-style card
Widget spotifyCard() {
  return AdaptiveImageOverlay.network(
    'YOUR_IMAGE_URL',
    overlayStyle: const AdaptiveOverlayStyle(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      stops: [0.0, 0.4, 0.7, 1.0],
      opacities: [0.95, 0.65, 0.25, 0.0],
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Title', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('Subtitle'),
      ],
    ),
  );
}

// Pattern 5: YouTube-style glow
Widget youtubeGlow() {
  return AdaptiveGlowImageFrame.network(
    'YOUR_IMAGE_URL',
    blurRadius: 48,
    spreadRadius: 10,
    layers: 2,
  );
}

// Pattern 6: Full-screen adaptive background
Widget adaptiveScreen() {
  return AdaptiveGradientScaffold.network(
    'YOUR_IMAGE_URL',
    appBar: AppBar(
      title: const Text('Page Title'),
      backgroundColor: Colors.transparent,
    ),
    body: const Center(child: Text('Your content')),
  );
}

// Pattern 7: Cache warming for lists
Future<void> warmupImages(List<String> urls) async {
  final providers = urls.map((url) => NetworkImage(url)).toList();
  await AdaptivePalette.warmup(providers);
}

// Pattern 8: Manual color application
class ManualColorWidget extends StatefulWidget {
  const ManualColorWidget({super.key});

  @override
  State<ManualColorWidget> createState() => _ManualColorWidgetState();
}

class _ManualColorWidgetState extends State<ManualColorWidget> {
  ThemeColors? _colors;

  @override
  void initState() {
    super.initState();
    _loadColors();
  }

  Future<void> _loadColors() async {
    final colors = await AdaptivePalette.fromImage(
      const NetworkImage('YOUR_IMAGE_URL'),
    );
    setState(() => _colors = colors);
  }

  @override
  Widget build(BuildContext context) {
    if (_colors == null) return const CircularProgressIndicator();

    return Container(
      color: _colors!.primary,
      child: Text(
        'Custom styled text',
        style: TextStyle(color: _colors!.onPrimary),
      ),
    );
  }
}

// ============================================================================
// CONFIGURATION REFERENCE
// ============================================================================

// Minimal config (uses defaults)
const minimalConfig = ExtractionConfig();

// Fast config (for lists/thumbnails)
final fastConfig = ExtractionConfig.fromQuality(ExtractionQuality.fast);

// Balanced config (general use)
final balancedConfig = ExtractionConfig.fromQuality(ExtractionQuality.balanced);

// High quality config (hero images)
final highConfig = ExtractionConfig.fromQuality(ExtractionQuality.high);

// Custom config
const customConfig = ExtractionConfig(
  targetBrightness: Brightness.dark,
  quantizeColors: 32, // 8-64 (higher = better quality, slower)
  resize: 128, // 64-256 (larger = more accurate, slower)
  minContrast: 4.5, // 4.5=AA, 7.0=AAA
  diversityWeight: 1.1, // 0.0-2.0 (higher = more diverse colors)
);

// Config with callbacks
final monitoredConfig = ExtractionConfig(
  onDebug: (stats) {
    print('Duration: ${stats.duration.inMilliseconds}ms');
    print('Type: ${stats.imageType}');
    print('Cached: ${stats.fromCache}');
  },
  onError: (error, stack) {
    print('Error: $error');
  },
);

// ============================================================================
// OVERLAY STYLE REFERENCE
// ============================================================================

// Horizontal gradient (Spotify playlist cover)
const horizontalGradient = AdaptiveOverlayStyle(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  stops: [0.0, 0.4, 0.7, 1.0],
  opacities: [0.95, 0.65, 0.25, 0.0],
);

// Vertical gradient (fade to bottom)
const verticalGradient = AdaptiveOverlayStyle(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: [0.0, 0.5, 1.0],
  opacities: [0.0, 0.3, 0.9],
);

// Diagonal gradient
const diagonalGradient = AdaptiveOverlayStyle(
  begin: Alignment.bottomLeft,
  end: Alignment.topRight,
  stops: [0.0, 0.45, 1.0],
  opacities: [0.95, 0.45, 0.0],
);

// Secondary tone gradient
const secondaryGradient = AdaptiveOverlayStyle(
  tone: AdaptiveOverlayTone.secondary,
  stops: [0.0, 0.5, 1.0],
  opacities: [0.9, 0.5, 0.0],
);

// ============================================================================
// CACHE MANAGEMENT
// ============================================================================

void configureCacheAdaptivePalette() {
  // Set cache size (default: 32)
  CacheConfig.maxSize = 64;

  // Check cache stats
  final (size, capacity) = AdaptivePalette.cacheStats();
  print('Cache: $size/$capacity');

  // Clear cache
  AdaptivePalette.clearCache();

  // Disable cache
  CacheConfig.enabled = false;

  // Re-enable cache
  CacheConfig.enabled = true;
}

// ============================================================================
// PERFORMANCE TIPS
// ============================================================================

// Tip 1: Use quality presets for appropriate contexts
void performanceTip1() {
  // Fast for list items
  AdaptivePalette.fromImage(
    const NetworkImage('thumbnail.jpg'),
    config: ExtractionConfig.fromQuality(ExtractionQuality.fast),
  );

  // High for hero/detail views
  AdaptivePalette.fromImage(
    const NetworkImage('hero.jpg'),
    config: ExtractionConfig.fromQuality(ExtractionQuality.high),
  );
}

// Tip 2: Warmup cache before showing list
Future<void> performanceTip2() async {
  final urls = ['image1.jpg', 'image2.jpg', 'image3.jpg'];
  final providers = urls.map((url) => NetworkImage(url)).toList();
  await AdaptivePalette.warmup(providers);
  // Now show the list - all palettes are cached!
}

// Tip 3: Monitor performance in debug mode
void performanceTip3() {
  AdaptivePalette.fromImage(
    const NetworkImage('image.jpg'),
    config: ExtractionConfig(
      onDebug: (stats) {
        if (stats.duration.inMilliseconds > 100) {
          print('Slow extraction: ${stats.duration.inMilliseconds}ms');
        }
      },
    ),
  );
}

// Tip 4: Increase cache size for image-heavy apps
void performanceTip4() {
  CacheConfig.maxSize = 128; // Store more palettes
}

// ============================================================================
// ACCESSIBILITY
// ============================================================================

// WCAG AA (default - 4.5:1 contrast)
final wcagAA = AdaptivePalette.fromImage(
  const NetworkImage('image.jpg'),
  config: const ExtractionConfig(minContrast: 4.5),
);

// WCAG AAA (stricter - 7.0:1 contrast)
final wcagAAA = AdaptivePalette.fromImage(
  const NetworkImage('image.jpg'),
  config: const ExtractionConfig(minContrast: 7.0),
);

// ============================================================================
// COMMON MISTAKES TO AVOID
// ============================================================================

// ❌ WRONG: Not checking mounted before setState
class WrongExample1 extends StatefulWidget {
  const WrongExample1({super.key});

  @override
  State<WrongExample1> createState() => _WrongExample1State();
}

class _WrongExample1State extends State<WrongExample1> {
  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final colors = await AdaptivePalette.fromImage(
      const NetworkImage('image.jpg'),
    );
    // ❌ Widget might be disposed!
    PaletteScope.of(context).animateTo(colors);
  }

  @override
  Widget build(BuildContext context) => Container();
}

// ✅ CORRECT: Check mounted
class CorrectExample1 extends StatefulWidget {
  const CorrectExample1({super.key});

  @override
  State<CorrectExample1> createState() => _CorrectExample1State();
}

class _CorrectExample1State extends State<CorrectExample1> {
  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final colors = await AdaptivePalette.fromImage(
      const NetworkImage('image.jpg'),
    );
    if (!mounted) return; // ✅ Check first!
    PaletteScope.of(context).animateTo(colors);
  }

  @override
  Widget build(BuildContext context) => Container();
}

// ❌ WRONG: Using high quality for all images
Widget wrongExample2() {
  // This will be slow!
  return GridView.builder(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
    ),
    itemCount: 10,
    itemBuilder: (context, index) {
      return FutureBuilder(
        future: AdaptivePalette.fromImage(
          NetworkImage('thumb$index.jpg'),
          config: ExtractionConfig.fromQuality(ExtractionQuality.high), // ❌ Overkill!
        ),
        builder: (context, snapshot) => Container(),
      );
    },
  );
}

// ✅ CORRECT: Use fast quality for lists
Widget correctExample2() {
  return GridView.builder(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
    ),
    itemCount: 10,
    itemBuilder: (context, index) {
      return FutureBuilder(
        future: AdaptivePalette.fromImage(
          NetworkImage('thumb$index.jpg'),
          config: ExtractionConfig.fromQuality(ExtractionQuality.fast), // ✅ Fast!
        ),
        builder: (context, snapshot) => Container(),
      );
    },
  );
}
