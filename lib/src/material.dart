/// Single import point for Flutter's Material library.
///
/// Flutter 3.47 moved Material into the separate `material_ui` package and
/// deprecated `package:flutter/material.dart`. `material_ui` needs Flutter
/// 3.47 or newer, while this package supports Flutter 3.27 and newer, so the
/// SDK copy is used until the minimum supported Flutter version catches up.
/// Migrating later only requires changing the export below.
library;

// ignore: deprecated_member_use
export 'package:flutter/material.dart';
