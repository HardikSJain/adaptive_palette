// Basic test for adaptive_palette package
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_palette/adaptive_palette.dart';

void main() {
  test('ThemeColors.fallback returns valid colors', () {
    const fallback = ThemeColors.fallback();

    expect(fallback.primary, isNotNull);
    expect(fallback.onPrimary, isNotNull);
    expect(fallback.background, isNotNull);
    expect(fallback.onBackground, isNotNull);
  });

  test('ThemeColors.copyWith works correctly', () {
    const original = ThemeColors.fallback();
    final modified = original.copyWith(primary: const Color(0xFF00FF00));

    expect(modified.primary, const Color(0xFF00FF00));
    expect(modified.onPrimary, original.onPrimary);
    expect(modified.background, original.background);
  });
}
