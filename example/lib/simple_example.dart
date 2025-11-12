import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:flutter/material.dart';

/// Simple example showing basic adaptive palette usage
void main() {
  runApp(const SimpleExample());
}

class SimpleExample extends StatelessWidget {
  const SimpleExample({super.key});

  @override
  Widget build(BuildContext context) {
    return const PaletteScope(
      seed: ThemeColors.fallback(),
      child: MaterialApp(home: HomePage()),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    // Extract colors from an image
    final colors = await AdaptivePalette.fromImage(
      const NetworkImage('https://picsum.photos/400/400'),
      targetBrightness: Brightness.dark,
    );

    if (!mounted) return;

    // Update the theme
    PaletteScope.of(context).animateTo(colors);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adaptive Palette')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.palette, size: 64),
            const SizedBox(height: 16),
            const Text('Theme adapts to image', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loadTheme,
              child: const Text('Reload Theme'),
            ),
          ],
        ),
      ),
    );
  }
}
