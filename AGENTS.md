# Agent Instructions

## Swift File Structure

- Keep Swift code in a one-file-per-type structure.
- Every `struct`, `class`, `actor`, `enum`, `protocol`, and `extension` should live in its own `.swift` file.
- Name each file after the type it declares, for example `WaveGeneratorViewModel.swift` or `PulseSettings.swift`.
- Name extension files as `TypeName+Purpose.swift`, for example `Array+SafeSubscript.swift`.
- This rule applies to small helper types too, including command structs, coding-key enums, state classes, and persistence models.
- Do not add new nested helper types inside views, view models, or engine classes. Create a separate top-level file instead.
- SwiftUI previews may stay in the same file as the view they preview.

When changing existing code, preserve this structure and split any newly introduced types before committing.
