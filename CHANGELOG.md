# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.2] - 2025-12-21

### Added

- Package preview image (`adaptive_palette.png`) showing the library in action

### Changed

- Updated README installation instructions to reference correct version

## [2.0.1] - 2025-12-01

### Fixed

- **Critical Fix**: Added missing `dart:ui` import in `theme.dart` for `Brightness` enum
- Package now compiles correctly when used as a dependency

## [2.0.0] - 2025-12-01

### Major Release - Architectural Rewrite

This release restructures the package with improved modularity, performance, and developer experience. The core API remains backward compatible - most v1.x code continues to work without changes.

### Added

- **Quality Presets**: `ExtractionQuality.fast`, `balanced`, and `high` for different use cases
- **ExtractionConfig**: Unified configuration object with quality presets and callbacks
- **Performance Monitoring**: `ExtractionStats` with duration, cache hits, and image type detection
- **Cache Management**: Configurable size (default: 32), warmup API, and statistics
- **Debug Callbacks**: `onDebug` and `onError` for real-time insights
- **Diversity Control**: Configurable weight (0.0-2.0) to prevent selecting similar colors
- **Comprehensive Tests**: 59 unit tests covering all core algorithms
- **Extensive Documentation**: 15+ usage examples and migration guide

### Changed

- **Modular Architecture**: Refactored from 1636-line monolithic file into 12 clean modules
- **Improved WCAG Compliance**: More reliable contrast ratio calculations
- **Better Default Parameters**: Optimized for real-world performance
- **Enhanced Theme Generation**: Fixed color contrast bugs, improved fallback behavior
- **Larger Cache**: Increased from 16 to 32 entries by default

### Breaking Changes

1. **Widget Parameters**: Now use `ExtractionConfig` instead of individual parameters
   ```dart
   // Before
   AdaptiveImageOverlay.network(url, resize: 96, quantizeColors: 24)

   // After
   AdaptiveImageOverlay.network(url, config: ExtractionConfig.fromQuality(ExtractionQuality.high))
   ```

2. **ThemeColors.toThemeData()**: Changed from static to instance method
   ```dart
   // Before
   ThemeColors.toThemeData(colors, brightness: Brightness.dark)

   // After
   colors.toThemeData(brightness: Brightness.dark)
   ```

3. **Internal Imports**: Don't import from `lib/src/` - use public API only

### Backward Compatible

The following v1.x code works without changes:
- `AdaptivePalette.fromImage()` with named parameters
- `PaletteScope` widget and controller
- All `ThemeColors` properties and `copyWith()`

See [MIGRATING.md](MIGRATING.md) for detailed upgrade instructions.

### Fixed

- WCAG contrast calculation bugs in theme generation
- Type safety issues (34 analyzer warnings → 0)
- Memory leaks in cache management
- Documentation accuracy

### Performance

Typical extraction times (MacBook Pro M1, Release mode):

| Quality | Time | Use Case |
|---------|------|----------|
| Fast | 30-50ms | Lists, thumbnails |
| Balanced | 60-90ms | General use (default) |
| High | 90-140ms | Hero images |
| Cache Hit | <1ms | All cached images |

---

## [1.0.7] - 2025-11-18

### Changed
- Major algorithm improvement with adaptive scoring for different image types
- Increased default `quantizeColors` to 32 and `resize` to 128
- Now uses CAM16 perceptual color space for better accuracy

### Improved
- Adaptive thresholds for colorful, monochromatic, and normal images
- Better color diversity through hue distance calculations
- Smart filtering prevents selecting multiple shades of same color

---

## [1.0.6] - 2025-11-18

### Fixed
- Critical compatibility fix: replaced `toARGB32()` with `.value` for Flutter 3.0+

---

## [1.0.5] - 2025-11-18

### Fixed
- Universal compatibility using bit operations for color component extraction

---

## [1.0.4] - 2025-11-16

### Changed
- Lowered minimum SDK to `>=3.0.0 <4.0.0` (Flutter 3.0+ support)

---

## [1.0.0] - 2025-11-11

### Added
- Initial release with CAM16/HCT color extraction
- WCAG AA/AAA contrast compliance
- PaletteScope for animated theme transitions
- Three pre-built widgets
- Material Design 3 integration

---

[2.0.2]: https://github.com/HardikSJain/adaptive_palette/releases/tag/v2.0.2
[2.0.1]: https://github.com/HardikSJain/adaptive_palette/releases/tag/v2.0.1
[2.0.0]: https://github.com/HardikSJain/adaptive_palette/releases/tag/v2.0.0
[1.0.7]: https://github.com/HardikSJain/adaptive_palette/releases/tag/v1.0.7
[1.0.6]: https://github.com/HardikSJain/adaptive_palette/releases/tag/v1.0.6
[1.0.5]: https://github.com/HardikSJain/adaptive_palette/releases/tag/v1.0.5
[1.0.4]: https://github.com/HardikSJain/adaptive_palette/releases/tag/v1.0.4
[1.0.0]: https://github.com/HardikSJain/adaptive_palette/releases/tag/v1.0.0
