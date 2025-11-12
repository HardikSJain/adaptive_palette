# adaptive_palette Example

This example demonstrates the key features of the `adaptive_palette` package:

## Features Showcased

1. **Dynamic Theme Extraction** - Extract vibrant colors from images
2. **Smooth Animations** - Animated theme transitions using `PaletteScope`
3. **Blurred Backgrounds** - Create beautiful image backgrounds
4. **WCAG Contrast** - Accessible color schemes

## Running the Example

```bash
cd example
flutter pub get
flutter run
```

## Basic Usage

```dart
import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:flutter/material.dart';

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
      theme: PaletteScope.of(context).theme,
      home: const HomePage(),
    );
  }
}
```

## Extract Colors from Image

```dart
final colors = await AdaptivePalette.fromImage(
  const NetworkImage('https://example.com/image.jpg'),
  targetBrightness: Brightness.dark,
  resize: 64,
  quantizeColors: 32,
  minContrast: 4.5,
);

// Animate to new theme
PaletteScope.of(context).animateTo(colors);
```
