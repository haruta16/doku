# Meowdoku recovered Godot project

This is the editable, buildable recovery of Meowdoku 1.8.1 (`com.oakever.meowdoku`, version code 418).

## Required editor

The shipped Android binary identifies itself as `Godot Engine v4.6.1.stable.custom_build` and uses Spine 4.2.43 assets. A stock Godot editor cannot load `SpineSprite`, `SpineAnimationTrack`, or the Spine resource importers. Use the matching editor already placed at:

`../tools/spine-godot/4.2-4.6.1/godot-4.2-4.6.1-stable.exe`

From the workspace root, open the project with:

```powershell
& .\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --editor --path .\recovered_project
```

## Validation

```powershell
& .\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --path .\recovered_project --script res://tools/validate_recovery.gd
```

The expected final line is `VALIDATION_OK`.

## Android build

The Android 35 SDK, Build-Tools 35.0.1, NDK r28b, CMake, and matching Spine export templates are installed under `../tools`. Configure the per-user Godot paths once:

```powershell
& .\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --editor --path .\recovered_project --script res://tools/setup_editor_settings.gd
```

Then export:

```powershell
& .\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --path .\recovered_project --export-debug Android .\build\meowdoku-recovered.apk
```

The reconstructed build uses `com.oakever.meowdoku.recovered`, so it can coexist with the store version.

## Recovery notes

- 257/257 exported GDScript bytecode files were decompiled without failure.
- 740/741 imported resources were converted. The sole failed item was the Rider editor GDExtension descriptor whose platform binaries were intentionally absent from the Android export.
- All 75 compiled runtime translation resources are preserved. GDRETools could only reconstruct 875/1035 source CSV keys, so the incomplete CSV is retained under `.assets/` as evidence and is not used to replace the working runtime translations.
- 26 XOR-obfuscated level-bank files were decoded to editable JSON under `assets/editor/levels`; together they contain 20,746 entries. The reconstructed `Level Bank Encryptor` editor plugin regenerates the runtime copies under `assets/resources/levels`.
- The Android export excluded the project-only `LevelGeneratorEditor`; a compatible implementation was reconstructed under `scripts/editor/queendoku` for the shipped debug screens.
- The export excluded Godot MCP Pro while leaving its autoload entries. The public v1.15.0 addon at commit `1beb50bc7b6fe6b1b5a440da5cb7187646afd9d0` was restored.
- The standalone build intentionally uses the existing GDScript offline adapter when the proprietary UniKit advertising/analytics Android plugin is unavailable. Core gameplay, saves, localization, audio, Spine animation, tutorial, level progression, settings, and debug API are functional.

The untouched recovery baseline is in `../artifacts/recovered_baseline`, and the extracted XAPK/APK material is in `../artifacts`.

Upstream references:

- Godot RE Tools: https://github.com/GDRETools/gdsdecomp
- Spine-Godot runtime documentation: https://esotericsoftware.com/spine-godot
- Godot Android export setup: https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html
- Godot MCP Pro source: https://github.com/youichi-uda/godot-mcp-pro
