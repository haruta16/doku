# Meowdoku 1.8.1 recovery report

## Deliverables

- Editable project: `recovered_project/`
- Untouched GDRETools baseline: `artifacts/recovered_baseline/`
- Extracted XAPK, asset pack, and arm64 split: `artifacts/`
- Reproducible arm64 APK: `build/meowdoku-recovered.apk`
- Final device screenshot: `build/meowdoku-recovered-final.png`

## Verified result

- Matching runtime: Godot 4.6.1 custom build with Spine 4.2.43.
- Exact import pass: zero script, scene, resource, or plugin errors.
- Android export pass: zero warnings and zero errors.
- APK: package `com.oakever.meowdoku.recovered`, version `1.8.1` (418), min SDK 24, target SDK 35, arm64-v8a, APK Signature Scheme v2/v3.
- Final APK SHA-256: `2A4241174AF56D0C53CE91A49AEC50DE5DA3F67EC78B0D0D19BD4B9FFEB7F5F4`.
- Source XAPK SHA-256: `F8B3DD5460ADACFE0232EB23C783DA991545951ADE268C528DE5FDF5D86CF179`.
- Installed and launched on the connected Pixel 6a.
- Cold-start tutorial rendered correctly; tutorial completion, level 1 completion, level 2 start, settings dialog, and back navigation were observed in device logs.
- Debug API listened on port 8090 and returned `{"result":"pong"}` through ADB forwarding.

See `recovered_project/README.md` for run/build commands and the boundary between directly recovered and reconstructed development-only components.
