# Meowdoku 恢复工程

Meowdoku 1.8.1（`com.oakever.meowdoku`，version code 418）的可编辑、可构建恢复工程。

## 前置条件

项目使用了 Spine 4.2.43 骨骼动画资源。官方 Godot 编辑器无法识别 `SpineSprite`、`SpineAnimationTrack` 等类型，直接打开会报错。必须使用匹配的 Spine-Godot 编辑器。

从 Spine-Godot 发布页下载对应平台的编辑器：

<https://github.com/EsotericSoftware/spine-runtimes/releases>

放到工程目录外部，相对路径为：

```
../tools/spine-godot/4.2-4.6.1/godot-4.2-4.6.1-stable.exe
```

## 打开工程

在工程根目录执行：

**Windows:**
```powershell
& ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --editor --path .
```

**macOS / Linux:**
```bash
../tools/spine-godot/4.2-4.6.1/godot-4.2-4.6.1-stable --editor --path .
```

## 运行验收

```powershell
& ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --path . --script res://tools/validate_recovery.gd
```

预期输出：

```
VALIDATION_OK: main scene, level banks, tutorial data, and generators 4x4-10x10
```

## Android 构建

需要 Spine-Godot Android 导出模板和 Android SDK/NDK 环境。从上述 releases 页面下载匹配的导出模板，解压到：

```
../tools/spine-godot/4.2-4.6.1/templates/
```

配置 SDK 和 JDK 路径（只需一次）：

```powershell
& ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --editor --path . --script res://tools/setup_editor_settings.gd
```

导出 APK：

```powershell
& ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --path . --export-debug Android ..\build\meowdoku-recovered.apk
```

恢复版使用独立包名 `com.oakever.meowdoku.recovered`，可与商店版共存。

## 恢复概况

- 257 个 GDScript 字节码文件全部反编译成功。
- 740/741 个导入资源完成转换。唯一失败项是 Rider 编辑器 GDExtension 描述文件，因 Android 导出包不含其平台二进制。
- 75 个运行时翻译资源全部保留。
- 26 个 XOR 混淆的关卡库文件已解码为可编辑 JSON（`assets/editor/levels/`），共 20,746 条关卡记录。`Level Bank Encryptor` 编辑器插件可将编辑后的明文重新加密到运行时目录 `assets/resources/levels/`。
- 专有的 UniKit 广告/统计 Android 插件在导出包中缺失，独立构建使用 GDScript 离线适配层。核心玩法、存档、本地化、音频、Spine 动画、教程、关卡推进、设置和调试 API 均正常可用。

## 参考资料

- Spine-Godot 运行时文档：<https://esotericsoftware.com/spine-godot>
- Godot Android 导出文档：<https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html>
- Godot MCP Pro 源码：<https://github.com/youichi-uda/godot-mcp-pro>
