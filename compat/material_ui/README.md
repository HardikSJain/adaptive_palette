# material_ui compatibility check

Flutter 3.47 moved Material into the separate
[`material_ui`](https://pub.dev/packages/material_ui) package, whose classes
are distinct from the ones in `package:flutter/material.dart`.
`adaptive_palette` still uses the SDK copy so that it keeps working on older
Flutter releases.

The tests here host `FluidBackground` inside an app built on `material_ui`,
with and without `MaterialUiCompatibilityBridge`, and need Flutter 3.47 or
newer:

```bash
cd compat/material_ui
flutter test
```

This folder is not part of the published package.
