/// Music-player style demo of the FluidBackground widget.
///
/// Skip between tracks to see the background follow the album art. The two
/// switches in the app bar toggle the orbital motion and smooth crossfades.
///
/// Run with: flutter run
library;

import 'package:adaptive_palette/adaptive_palette.dart';
import 'package:flutter/material.dart';

void main() => runApp(const FluidBackgroundExampleApp());

class FluidBackgroundExampleApp extends StatelessWidget {
  const FluidBackgroundExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FluidBackground Demo',
      theme: ThemeData.dark(useMaterial3: true),
      home: const MusicPlayerPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key});

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  int _currentIndex = 0;
  bool _animate = true;
  bool _smoothTransitions = true;

  final List<String> _albumImages = [
    'https://picsum.photos/seed/album1/800/800',
    'https://picsum.photos/seed/album2/800/800',
    'https://picsum.photos/seed/album3/800/800',
    'https://picsum.photos/seed/album4/800/800',
  ];

  final List<String> _songTitles = [
    'Neon Dreams',
    'Ocean Waves',
    'Mountain Echo',
    'City Lights',
  ];

  final List<String> _artistNames = [
    'Electric Pulse',
    'Coastal Sound',
    'Alpine Harmony',
    'Urban Beats',
  ];

  void _nextSong() {
    setState(() {
      _currentIndex = (_currentIndex + 1) % _albumImages.length;
    });
  }

  void _previousSong() {
    setState(() {
      _currentIndex =
          (_currentIndex - 1 + _albumImages.length) % _albumImages.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FluidBackground(
      imageProvider: NetworkImage(_albumImages[_currentIndex]),
      blurSigma: 80,
      overlayDarken: 0.15,
      animate: _animate,
      smoothTransitions: _smoothTransitions,
      transitionDuration: const Duration(milliseconds: 1400),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () {},
          ),
          title: const Text('Now Playing'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: _animate ? 'Pause motion' : 'Animate background',
              icon: Icon(
                  _animate ? Icons.motion_photos_on : Icons.motion_photos_off),
              onPressed: () => setState(() => _animate = !_animate),
            ),
            IconButton(
              tooltip: _smoothTransitions
                  ? 'Cut between images'
                  : 'Crossfade between images',
              icon: Icon(_smoothTransitions ? Icons.blur_on : Icons.blur_off),
              onPressed: () => setState(
                () => _smoothTransitions = !_smoothTransitions,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Album art
                Hero(
                  tag: 'album-$_currentIndex',
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        _albumImages[_currentIndex],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Song info
                Text(
                  _songTitles[_currentIndex],
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _artistNames[_currentIndex],
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),

                const Spacer(),

                // Progress bar
                Column(
                  children: [
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                      ),
                      child: Slider(
                        value: 0.3,
                        onChanged: (value) {},
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('1:23', style: TextStyle(fontSize: 12)),
                          Text('3:45', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shuffle),
                      iconSize: 24,
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      iconSize: 40,
                      onPressed: _previousSong,
                    ),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.pause,
                        color: Colors.black87,
                        size: 36,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      iconSize: 40,
                      onPressed: _nextSong,
                    ),
                    IconButton(
                      icon: const Icon(Icons.repeat),
                      iconSize: 24,
                      onPressed: () {},
                    ),
                  ],
                ),

                const Spacer(),

                // Bottom actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.devices),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.favorite_border),
                      onPressed: () {},
                    ),
                  ],
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
