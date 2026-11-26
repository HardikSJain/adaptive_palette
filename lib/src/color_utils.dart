/// Internal color helpers that behave the same on every supported Flutter
/// version.
library;

import 'dart:ui' show Color;

int _channel8(double v) => (v * 255.0).round().clamp(0, 255);

/// 8-bit red channel of [c] (0–255).
int red8(Color c) => _channel8(c.r);

/// 8-bit green channel of [c] (0–255).
int green8(Color c) => _channel8(c.g);

/// 8-bit blue channel of [c] (0–255).
int blue8(Color c) => _channel8(c.b);

/// 8-bit alpha channel of [c] (0–255).
int alpha8(Color c) => _channel8(c.a);

/// 32-bit ARGB value of [c], as expected by `material_color_utilities`.
///
/// Equivalent to `Color.toARGB32()`, which is not available on the oldest
/// Flutter release this package supports.
int argb32(Color c) =>
    (alpha8(c) << 24) | (red8(c) << 16) | (green8(c) << 8) | blue8(c);
