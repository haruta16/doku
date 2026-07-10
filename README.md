# Meowdoku recovered Godot project

This is the editable, buildable recovery of Meowdoku 1.8.1 (`com.oakever.meowdoku`, version code 418).

## Prerequisites

The project uses Spine 4.2.43 assets. A stock Godot editor cannot load `SpineSprite`, `SpineAnimationTrack`, or the Spine resource importers — the project will fail to open. You must use the matching Spine-Godot editor.

Download the editor for your platform from the Spine-Godot releases page:

<https://github.com/EsotericSoftware/spine-runtimes/releases>

Place it outside the repo, relative to the project root:

```
../tools/spine-godot/4.2-4.6.1/godot-4.2-4.6.1-stable.exe
```

The project was recovered from a Windows build; the editor on other platforms is functionally identical.

## Open the project

From the project root:

**Windows:**
```powershell
& ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --editor --path .
```

**macOS / Linux:**
```bash
../tools/spine-godot/4.2-4.6.1/godot-4.2-4.6.1-stable --editor --path .
```

## Validate

```powershell
& ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --path . --script res://tools/validate_recovery.gd
```

Expected output:

```
VALIDATION_OK: main scene, level banks, tutorial data, and generators 4x4-10x10
```

## Android build

Requires the Spine-Godot Android export templates and a full Android SDK/NDK setup. Download the matching export templates from the same releases page above and extract them to:

```
../tools/spine-godot/4.2-4.6.1/templates/
```

Configure SDK and JDK paths once:

```powershell
& ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --editor --path . --script res://tools/setup_editor_settings.gd
```

Export:

```powershell
& ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --path . --export-debug Android ..\build\meowdoku-recovered.apk
```

The reconstructed build uses `com.oakever.meowdoku.recovered`, so it coexists with the store version.

## Recovery notes

- 257/257 exported GDScript bytecode files were decompiled without failure.
- 740/741 imported resources were converted. The sole failed item was the Rider editor GDExtension descriptor whose platform binaries were intentionally absent from the Android export.
- All 75 compiled runtime translation resources are preserved. The incomplete CSV source reconstruction (875/1035 keys) is retained under `.assets/` as evidence.
- 26 XOR-obfuscated level-bank files were decoded to editable JSON under `assets/editor/levels`; together they contain 20,746 entries. The `Level Bank Encryptor` editor plugin regenerates the runtime copies under `assets/resources/levels`.
- The standalone build uses the GDScript offline adapter when the proprietary UniKit advertising/analytics Android plugin is unavailable. Core gameplay, saves, localization, audio, Spine animation, tutorial, level progression, settings, and debug API are functional.

## References

- Spine-Godot runtime documentation: <https://esotericsoftware.com/spine-godot>
- Godot Android export documentation: <https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html>
- Godot MCP Pro source: <https://github.com/youichi-uda/godot-mcp-pro>
