import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    const PaletteScope(
      seed: ThemeColors.fallback(),
      brightness: Brightness.dark,
      child: AdaptiveOverlayDemoApp(),
    ),
  );
}

class AdaptiveOverlayDemoApp extends StatelessWidget {
  const AdaptiveOverlayDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PaletteScope.of(context).theme,
      home: const AdaptiveOverlayShowcase(),
    );
  }
}

class AdaptiveOverlayShowcase extends StatelessWidget {
  const AdaptiveOverlayShowcase({super.key});

  static const heroImage = 'https://picsum.photos/seed/overlay-hero/1600/900';
  static const cardImage = 'https://picsum.photos/seed/overlay-card/1400/800';
  static const glowImage = 'https://picsum.photos/seed/overlay-glow/2000/900';

  @override
  Widget build(BuildContext context) {
    return AdaptiveGradientScaffold.network(
      heroImage,
      appBar: AppBar(
        title: const Text('Adaptive Palette Overlay Kit'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
        children: [
          const SizedBox(height: 16),
          AdaptiveImageOverlay.network(
            heroImage,
            overlayStyle: const AdaptiveOverlayStyle(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [0.0, 0.35, 0.7, 1.0],
              opacities: [0.95, 0.65, 0.25, 0.0],
            ),
            borderRadius: BorderRadius.circular(28),
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text('Gradient Overlay', style: TextStyle(fontSize: 24)),
                SizedBox(height: 12),
                Text('Spotify/Luma style hero overlay in one widget.'),
              ],
            ),
          ),
          const SizedBox(height: 28),
          AdaptiveImageOverlay.network(
            cardImage,
            overlayStyle: const AdaptiveOverlayStyle(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              stops: [0.0, 0.55, 1.0],
              opacities: [0.95, 0.5, 0.0],
              tone: AdaptiveOverlayTone.secondary,
            ),
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Diagonal Accent', style: TextStyle(fontSize: 22)),
                SizedBox(height: 8),
                Text('Switch tones for cooler overlays.'),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Glow Frame',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              AdaptiveGlowImageFrame.network(
                glowImage,
                aspectRatio: 21 / 9,
                blurRadius: 48,
                spreadRadius: 10,
                tone: AdaptiveOverlayTone.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
