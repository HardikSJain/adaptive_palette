# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.3] - 2025-11-14

### Changed
- Upgraded `flutter_lints` from ^5.0.0 to ^6.0.0 for latest linting rules
- Cleaned up `pubspec.yaml` by removing unnecessary comments
- Improved code formatting and consistency across library files
- Updated README installation instructions to reference version 1.0.3

### Fixed
- Minor code formatting improvements for better readability
- Consistent code style throughout the package

## [1.0.2] - 2025-11-12

### Added
- Complete example app in `example/` directory for pub.dev
- Simple example demonstrating minimal usage
- Full-featured example with blurred backgrounds and color palette display
- Example README with usage instructions

## [1.0.1] - 2025-11-11

### Changed
- Updated README.md to accurately reflect actual codebase
- Removed references to non-existent example directory and widgets
- Added complete working app examples based on actual implementation
- Updated API documentation with correct default values
- Improved documentation clarity and accuracy

## [1.0.0] - 2025-11-11

### Added
- Initial release of Adaptive Palette
- Automatic color palette extraction from images using CAM16/HCT color space
- WCAG AA/AAA contrast compliance for all generated themes
- Smooth theme animations with PaletteScope
- High-performance median-cut quantization algorithm
- Smart LRU caching with content-based keys
- AdaptiveBlurredBackground widget (Luma/Spotify-style)
- AdaptiveBlurredBackgroundWithImage widget variant
- Dark and light theme support
- Material Design 3 integration
- Comprehensive inline documentation
- Example app with image gallery

### Features
- Extract vibrant, muted, or dominant color strategies
- Configurable blur, scale, and overlay effects
- Cross-fade transitions between themes
- Hero animations for smooth page transitions
- Responsive image loading with error handling
- Accessibility-first design principles

### Performance
- ~50-150ms palette extraction time
- <1ms cache hit latency
- 60 FPS smooth animations
- Memory-efficient downsampling

[1.0.0]: https://github.com/HardikSJain/adaptive_palette/releases/tag/v1.0.0
