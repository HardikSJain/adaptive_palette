# adaptive_palette example

A music-player style screen built on `FluidBackground`
([lib/main.dart](lib/main.dart)). Skip between tracks to watch the background
follow the album art; the two app bar buttons toggle the orbital motion and
smooth crossfades.

```dart
FluidBackground(
  imageProvider: NetworkImage(albumArtUrl),
  animate: true,
  smoothTransitions: true,
  child: Scaffold(
    backgroundColor: Colors.transparent,
    body: YourContent(),
  ),
)
```

## Running it

```bash
cd example
flutter run
```

The platform folders are kept in the repository. If you are working from the
copy published on pub.dev, which leaves them out, run `flutter create .` in
this folder first.

## Legacy examples

[lib/legacy/](lib/legacy/) holds examples for the deprecated v2 API
(`AdaptivePalette`, `PaletteScope` and the `Adaptive*` widgets), which will be
removed in 4.0.0. Run one with, for example:

```bash
flutter run -t lib/legacy/palette_scope_example.dart
```
