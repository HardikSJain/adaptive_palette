# Adaptive Palette

Dynamic theming from images for Flutter. Extract colors and create accessible themes automatically.

## Installation

```yaml
dependencies:
  adaptive_palette: ^1.0.0
```

## Quick Start

```dart
import 'package:adaptive_palette/adaptive_palette.dart';

final colors = await AdaptivePalette.fromImage(
  NetworkImage('https://example.com/image.jpg'),
);
```

## Example App

See the [example](example/) directory for a complete demo app showing:
- Music player with Spotify-style backgrounds
- Photo gallery with adaptive themes  
- E-commerce product pages
- Basic color extraction

To run the example:

```bash
git clone https://github.com/HardikSJain/adaptive_palette.git
cd adaptive_palette/example
flutter pub get
flutter run
```

### App-Wide Theme

```dart
void main() => runApp(
  PaletteScope(
    seed: const ThemeColors.fallback(),
    child: MyApp(),
  ),
);

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: PaletteScope.of(context).theme,
      home: MyHome(),
    );
  }
}

// Later, animate to new theme
AdaptivePalette.fromImage(image).then((colors) {
  PaletteScope.of(context).animateTo(colors);
});
```

### Blurred Background Widget

```dart
import 'package:adaptive_palette/widgets.dart';

AdaptiveBlurredBackground(
  image: NetworkImage('album-art.jpg'),
  blurSigma: 100,
  child: YourContent(),
)
```

### Mesh Gradient Widget (NEW!)

iOS 18 / Apple Music-style mesh gradients with perceptual color blending using HCT color space. More advanced than other gradient packages:

```dart
import 'package:adaptive_palette/widgets.dart';

AdaptiveMeshGradient(
  image: NetworkImage('cover-art.jpg'),
  focalPoints: 5,                              // 2-8 gradient focal points
  animationStyle: MeshGradientAnimation.flow,  // none, pulse, flow, breathe
  intensity: 0.85,                             // 0.0-1.0
  blurLayers: 3,                               // 1-4 layers for depth
  child: YourContent(),
)
```

## API

### AdaptivePalette.fromImage()

```dart
Future<ThemeColors> fromImage(
  ImageProvider provider, {
  Brightness targetBrightness = Brightness.light,
  int quantizeColors = 48,        // 8-64, more = better quality
  int resize = 128,                // 64-256, larger = slower
  double minContrast = 4.5,        // WCAG: 4.5=AA, 7.0=AAA
})
```

### ThemeColors

```dart
class ThemeColors {
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color background;
  final Color onBackground;
  final Color surface;
  final Color onSurface;
}
```

### AdaptiveBlurredBackground

```dart
AdaptiveBlurredBackground({
  required ImageProvider image,
  required Widget child,
  double blurSigma = 100.0,        // Blur intensity
  double scale = 1.3,              // Zoom level
  double overlayOpacity = 0.2,     // Color overlay strength
  Duration transitionDuration = const Duration(milliseconds: 800),
})
```

### AdaptiveMeshGradient

```dart
AdaptiveMeshGradient({
  required ImageProvider image,
  required Widget child,
  int focalPoints = 5,                         // 2-8 focal points
  MeshGradientAnimation animationStyle = flow, // Animation type
  BlendStrategy blendStrategy = auto,          // Blend mode selection
  double intensity = 0.85,                     // Effect intensity
  int blurLayers = 3,                          // 1-4 depth layers
  Duration transitionDuration = 1200ms,
})
```

**Animation Styles:**
- `MeshGradientAnimation.none` - Static gradient
- `MeshGradientAnimation.pulse` - Gentle pulsing intensity
- `MeshGradientAnimation.flow` - Organic flowing movement (recommended)
- `MeshGradientAnimation.breathe` - Breathing scale effect

## Examples

Run the demo to see 5 different use cases:

```bash
flutter run
```

Examples included:
- Music player (Spotify-style)
- Photo gallery (Hero animations)
- E-commerce (Product theming)
- Basic extraction
- Image grid

See `lib/examples/` for source code.

## How It Works

1. **Median-cut quantization** - Extract dominant colors from image
2. **CAM16/HCT color space** - Perceptual color adjustments (Material Design 3)
3. **WCAG contrast validation** - Ensures text readability
4. **Content-based caching** - SHA-1 hash for fast lookups
5. **Smooth animations** - AnimationController-based theme transitions

## Performance Tips

**Fast extraction (for lists):**
```dart
AdaptivePalette.fromImage(image, resize: 64, quantizeColors: 24)
```

**High quality (for detail views):**
```dart
AdaptivePalette.fromImage(image, resize: 256, quantizeColors: 64)
```

**Preload palettes:**
```dart
// During splash screen
await Future.wait(
  images.map((img) => AdaptivePalette.fromImage(img)),
);
```