# Migration Guide: v1.x → v2.0

This guide will help you upgrade from adaptive_palette v1.x to v2.0.

## Overview

Version 2.0 is a major architectural rewrite with significantly improved modularity, performance, and developer experience. **The good news:** Most v1.x code continues to work without changes. Breaking changes only affect specific widget parameters and one method signature.

## Quick Upgrade Checklist

- [ ] Update `pubspec.yaml` to `^2.0.0`
- [ ] Run `flutter pub get`
- [ ] Fix widget configurations (if using AdaptiveImageOverlay, AdaptiveGlowImageFrame, or AdaptiveGradientScaffold)
- [ ] Update `ThemeColors.toThemeData()` calls (if any)
- [ ] Remove imports from `lib/src/` (if any)
- [ ] Run `flutter analyze` and `flutter test`
- [ ] (Optional) Adopt new features like quality presets and performance monitoring

## Breaking Changes

### 1. Widget Configuration Parameters

**Affects:** `AdaptiveImageOverlay`, `AdaptiveGlowImageFrame`, `AdaptiveGradientScaffold`

**Change:** Individual extraction parameters are now grouped in `ExtractionConfig`

```dart
// ❌ v1.x
AdaptiveImageOverlay.network(
  'https://example.com/image.jpg',
  targetBrightness: Brightness.dark,
  resize: 96,
  quantizeColors: 24,
  minContrast: 4.5,
)

// ✅ v2.0
AdaptiveImageOverlay.network(
  'https://example.com/image.jpg',
  config: ExtractionConfig(
    targetBrightness: Brightness.dark,
    resize: 96,
    quantizeColors: 24,
    minContrast: 4.5,
  ),
)

// ✅ v2.0 (recommended - use presets)
AdaptiveImageOverlay.network(
  'https://example.com/image.jpg',
  config: ExtractionConfig.fromQuality(ExtractionQuality.high),
)
```

**Why?** Cleaner API, easier to extend, supports new features like callbacks.

### 2. ThemeColors.toThemeData() Method

**Change:** Static method → Instance method

```dart
// ❌ v1.x
final theme = ThemeColors.toThemeData(colors, brightness: Brightness.dark);

// ✅ v2.0
final theme = colors.toThemeData(brightness: Brightness.dark);
```

**Find & Replace:**
1. Search: `ThemeColors.toThemeData(colors,`
2. Replace: `colors.toThemeData(`

### 3. Internal Imports

**Change:** Don't import from `lib/src/`

```dart
// ❌ v1.x (if you did this)
import 'package:adaptive_palette/src/some_file.dart';

// ✅ v2.0
import 'package:adaptive_palette/adaptive_palette.dart';
```

All public APIs are exported from the main package.

## What Still Works (No Changes Needed)

### ✅ Core Extraction API

```dart
// Still works exactly the same!
final colors = await AdaptivePalette.fromImage(
  image,
  targetBrightness: Brightness.dark,
  quantizeColors: 32,
  resize: 128,
  minContrast: 4.5,
);
```

### ✅ PaletteScope

```dart
// Still works exactly the same!
PaletteScope(
  seed: ThemeColors.fallback(),
  brightness: Brightness.dark,
  child: MyApp(),
)
```

### ✅ Theme Animation

```dart
// Still works exactly the same!
PaletteScope.of(context).animateTo(
  colors,
  duration: Duration(milliseconds: 800),
  curve: Curves.easeOutCubic,
);
```

### ✅ ThemeColors Model

```dart
// All properties still work!
colors.primary
colors.onPrimary
colors.secondary
colors.copyWith(primary: Colors.red)
const ThemeColors.fallback()
```

## New Features to Adopt (Optional but Recommended)

### 1. Quality Presets

Instead of tweaking parameters, use presets:

```dart
// For lists/thumbnails (fast)
config: ExtractionConfig.fromQuality(ExtractionQuality.fast)

// For general use (balanced)
config: ExtractionConfig.fromQuality(ExtractionQuality.balanced)

// For hero images (high quality)
config: ExtractionConfig.fromQuality(ExtractionQuality.high)
```

### 2. Performance Monitoring

Add debug callbacks to monitor extraction performance:

```dart
await AdaptivePalette.fromImage(
  image,
  config: ExtractionConfig(
    onDebug: (stats) {
      print('⏱️  ${stats.duration.inMilliseconds}ms');
      print('🎨 ${stats.colorsExtracted} colors');
      print('📊 Type: ${stats.imageType}');
      print('💾 Cached: ${stats.fromCache}');
    },
  ),
);
```

### 3. Cache Warming

Preload palettes for better perceived performance:

```dart
// Before showing a list
await AdaptivePalette.warmup([
  NetworkImage('image1.jpg'),
  NetworkImage('image2.jpg'),
  NetworkImage('image3.jpg'),
]);

// Now all these are cached and instant!
```

### 4. Cache Configuration

Control cache size and behavior:

```dart
// Increase cache size for image-heavy apps
CacheConfig.maxSize = 64; // Default: 32

// Monitor cache usage
final (size, capacity) = AdaptivePalette.cacheStats();
print('Cache: $size/$capacity');

// Clear cache when needed
AdaptivePalette.clearCache();
```

### 5. Error Handling

Add custom error handlers:

```dart
await AdaptivePalette.fromImage(
  image,
  config: ExtractionConfig(
    onError: (error, stack) {
      // Log to your analytics service
      logError('Palette extraction failed', error);

      // Show user notification if needed
      showSnackBar('Could not extract colors from image');
    },
  ),
);
```

### 6. Diversity Control

Fine-tune color diversity:

```dart
// Default (1.1)
config: ExtractionConfig(diversityWeight: 1.1)

// Strongly favor diverse colors (1.5)
config: ExtractionConfig(diversityWeight: 1.5)

// No diversity preference (0.0)
config: ExtractionConfig(diversityWeight: 0.0)
```

## Step-by-Step Migration Example

### Before (v1.x):

```dart
class MyPage extends StatefulWidget {
  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  ThemeColors? _colors;

  @override
  void initState() {
    super.initState();
    _extractColors();
  }

  Future<void> _extractColors() async {
    final colors = await AdaptivePalette.fromImage(
      NetworkImage('https://example.com/image.jpg'),
      targetBrightness: Brightness.dark,
      quantizeColors: 32,
      resize: 128,
    );

    if (!mounted) return;
    setState(() => _colors = colors);
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveImageOverlay.network(
      'https://example.com/image.jpg',
      targetBrightness: Brightness.dark,
      resize: 96,
      quantizeColors: 24,
      child: Text('Hello'),
    );
  }
}
```

### After (v2.0):

```dart
class MyPage extends StatefulWidget {
  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  ThemeColors? _colors;

  @override
  void initState() {
    super.initState();
    _extractColors();
  }

  Future<void> _extractColors() async {
    // Option 1: Keep old style (still works!)
    final colors = await AdaptivePalette.fromImage(
      NetworkImage('https://example.com/image.jpg'),
      targetBrightness: Brightness.dark,
      quantizeColors: 32,
      resize: 128,
    );

    // Option 2: Use new config style (recommended)
    final colors = await AdaptivePalette.fromImage(
      NetworkImage('https://example.com/image.jpg'),
      config: ExtractionConfig(
        targetBrightness: Brightness.dark,
        quantizeColors: 32,
        resize: 128,
        onDebug: (stats) => print('Extracted in ${stats.duration.inMilliseconds}ms'),
      ),
    );

    // Option 3: Use preset (simplest!)
    final colors = await AdaptivePalette.fromImage(
      NetworkImage('https://example.com/image.jpg'),
      config: ExtractionConfig.fromQuality(ExtractionQuality.high),
    );

    if (!mounted) return;
    setState(() => _colors = colors);
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveImageOverlay.network(
      'https://example.com/image.jpg',
      // ✅ Updated to use ExtractionConfig
      config: ExtractionConfig.fromQuality(ExtractionQuality.high),
      onColorsReady: (colors) => print('Colors ready: $colors'),
      child: Text('Hello'),
    );
  }
}
```

## Testing Your Migration

After making changes:

```bash
# 1. Analyze for issues
flutter analyze

# 2. Run tests
flutter test

# 3. Try a hot reload in your app
flutter run

# 4. Test extraction performance
# Check debug output if you added onDebug callbacks
```

## Common Migration Issues

### Issue: "The named parameter 'config' isn't defined"

**Solution:** Update your widgets to use `ExtractionConfig`:

```dart
// Change this:
AdaptiveImageOverlay.network(url, resize: 96)

// To this:
AdaptiveImageOverlay.network(url, config: ExtractionConfig(resize: 96))
```

### Issue: "The method 'toThemeData' isn't defined for the type 'ThemeColors'"

**Solution:** It's now an instance method:

```dart
// Change this:
ThemeColors.toThemeData(colors)

// To this:
colors.toThemeData()
```

### Issue: "Undefined name 'ExtractionConfig'"

**Solution:** Make sure you're importing the package:

```dart
import 'package:adaptive_palette/adaptive_palette.dart';
```

## Performance Improvements in v2.0

After migration, you should see:

- ✅ Larger cache (32 entries vs 16)
- ✅ Better default parameters
- ✅ Ability to monitor and optimize extraction times
- ✅ Cache warming for instant-feel UX
- ✅ Configurable cache size for your needs

## Getting Help

- **Documentation**: See `example/lib/usage_examples.dart` for 15 complete examples
- **Quick Reference**: See `example/lib/quick_reference.dart` for code snippets
- **Issues**: https://github.com/HardikSJain/adaptive_palette/issues
- **Changelog**: See `CHANGELOG.md` for full v2.0 details

## Summary

**Most code continues to work without changes.** The main updates needed are:

1. Widget parameters → Use `ExtractionConfig`
2. `ThemeColors.toThemeData()` → `colors.toThemeData()`
3. Remove `lib/src/` imports (if any)

Then enjoy the new features like quality presets, performance monitoring, and cache management!
