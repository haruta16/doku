# Meowdoku 1.8.1 逆向恢复全流程总结

## 一、任务目标与最终结论

本次任务的目标，是从 `Meowdoku_+Brain+Puzzle+Games_1.8.1_APKPure.xapk` 中恢复一个能够继续编辑、导入、构建和运行的 Godot 工程，并在 Android 真机上验证核心功能。

最终结果：**恢复工程已经能够使用匹配的 Spine-Godot 编辑器无错误导入，能够重新导出 arm64 Android APK，并已在 Pixel 6a 上完成冷启动、教程、关卡、设置、返回导航和调试 API 验证。**

需要说明的是，发布包本身不包含原开发仓库的版本历史、注释、未导出源文件和专有第三方插件源码，因此无法声称与原始开发仓库逐字节一致。本次交付属于“功能可用、可编辑、可复现构建”的工程级恢复。

## 二、输入文件与基础信息

| 项目 | 内容 |
| --- | --- |
| 原始文件 | `Meowdoku_+Brain+Puzzle+Games_1.8.1_APKPure.xapk` |
| 原始 XAPK SHA-256 | `F8B3DD5460ADACFE0232EB23C783DA991545951ADE268C528DE5FDF5D86CF179` |
| 原包名 | `com.oakever.meowdoku` |
| 版本 | `1.8.1` |
| Version Code | `418` |
| 目标设备 | Pixel 6a，设备编号 `26221JEGR36500` |
| 识别出的引擎 | `Godot Engine v4.6.1.stable.custom_build` |
| Spine 资源版本 | `4.2.43` |
| 目标架构 | `arm64-v8a` |

XAPK 不是单一 APK，其中包含基础 APK、安装时资源包、arm64 原生库拆分包以及语言拆分包。真正的 Godot 工程资源主要位于安装时资源包中，因此恢复时不能只分析基础 APK。

## 三、使用的主要工具与版本

| 工具 | 用途 | 本次使用版本或位置 |
| --- | --- | --- |
| GDRETools | 提取 Godot PCK、反编译 GDScript、恢复导入资源 | `tools/gdre/v2.5.0-beta.5/gdre_tools.exe` |
| Spine-Godot 编辑器 | 加载项目中的 SpineSprite、SpineAnimationTrack 和 Spine 资源 | `tools/spine-godot/4.2-4.6.1/godot-4.2-4.6.1-stable.exe` |
| Spine-Godot 导出模板 | Android 重新导出 | `tools/spine-godot/4.2-4.6.1/templates/` |
| Android SDK | Android 构建和安装 | `tools/android-sdk/` |
| JDK | Android 构建 | Microsoft OpenJDK 17 |
| ADB | 安装、启动、抓取日志、端口转发 | Android Platform Tools 37 |

最初尝试的较新 GDRETools 版本在任务结束时触发了 Windows 空指针读内存崩溃，错误表现为读取地址 `0x50`。该问题发生在工具退出路径，不是游戏资源本身损坏。后续切换到 `v2.5.0-beta.5` 完成全部恢复，避免继续使用不稳定版本。

## 四、完整处理流程

### 1. 原始包审计与拆分提取

首先计算原始 XAPK 哈希，并检查包内所有 APK 和资源包结构。提取结果保存在：

```text
artifacts/xapk/
artifacts/asset_pack_apk/
artifacts/arm64_apk/
```

资源包共发现约 1605 个条目，其中包括：

- 257 个编译后的 GDScript 文件（`.gdc`）；
- 73 个场景文件；
- 391 个 Godot 导入描述文件；
- 75 个运行时翻译资源；
- `project.binary`、`sparsepck` 和大量纹理、音频、Spine 资源。

### 2. 引擎与资源版本识别

通过二进制字符串和资源头信息确认：

- Android 二进制使用 `Godot 4.6.1 stable custom build`；
- Spine 骨骼文件版本为 `4.2.43`；
- 项目依赖 Spine-Godot 自定义引擎模块，而不是普通 Godot 编辑器。

普通 Godot 4.6.1 无法识别该项目的 `SpineSprite`、`SpineAnimationTrack` 和 Spine 导入器，因此下载并固定使用匹配的 Spine-Godot 4.2/4.6.1 编辑器和 Android 导出模板。

### 3. Godot 工程恢复

使用 GDRETools v2.5.0-beta.5 对资源包执行工程恢复，并同时保留一份不做人工修改的原始恢复基线：

```text
recovered_project/                 # 后续修复、可编辑和可构建的工作工程
artifacts/recovered_baseline/      # 未修改的 GDRETools 恢复基线
```

恢复统计：

| 类型 | 结果 |
| --- | --- |
| GDScript 反编译 | `257/257` 成功，0 失败 |
| 导入资源转换 | `740/741` 成功 |
| 场景和主工程配置 | 已恢复 |
| 运行时翻译资源 | 75 个全部保留 |

唯一未转换的项目是 Rider 编辑器 GDExtension 描述文件。Android 发布包没有携带其桌面平台二进制文件，它只影响 Rider 编辑器集成，不参与游戏运行。

### 4. 关卡数据解密与编辑能力恢复

运行时关卡库位于 `assets/resources/levels`，共 26 个经过 XOR 混淆的 JSON 文件。

通过分析恢复后的 `LevelBankIO` 找到密钥：

```text
meowdoku-2026-bank-secret
```

随后机械解密全部关卡库，并将可编辑明文写入：

```text
recovered_project/assets/editor/levels/
```

共恢复 **20,746 条关卡记录**。

同时重建 `addons/level_bank_encryptor` 编辑器插件，提供 `Encrypt Level Banks` 菜单，可以将编辑后的明文 JSON 重新编码回运行时目录 `assets/resources/levels`，从而恢复关卡的正常编辑和再打包工作流。

### 5. 缺失代码与插件重建

发布包会排除部分只在开发期使用的源文件和插件，因此根据现存调用关系、数据格式和运行时行为完成以下重建：

1. 重建 `scripts/editor/queendoku/level_generator_editor.gd`。
   - 支持 4×4 至 10×10 棋盘；
   - 每行、每列恰好一个猫位置；
   - 猫之间不能相邻或对角接触；
   - 能生成连通区域和对应颜色数据；
   - 接口与现有调试页面保持兼容。

2. 恢复 Godot MCP Pro。
   - 原发布包排除了插件文件，但残留了 Autoload 配置；
   - 使用公开的 v1.15.0、提交 `1beb50bc7b6fe6b1b5a440da5cb7187646afd9d0` 恢复 `addons/godot_mcp`。

3. 移除发布包中不存在的编辑器插件引用。
   - `art2godot`；
   - `build_helper`；
   - 缺少平台二进制的 Rider GDExtension。

这些内容在未修改基线中仍然保留，便于后续审计对照。

### 6. 场景、UID 与资源引用修复

精确导入过程中发现并修复了以下问题：

| 问题 | 修复 |
| --- | --- |
| 教程场景引用了失效的 `cell.tscn` UID | 将 `uid://kuuaeg2sts5f` 更新为实际 UID `uid://lboxa1b8xq3o` |
| `ui_logo.tres` 的 Spine atlas UID 失效 | 更新为 `uid://dgl566y085hbi` |
| `ui_logo.tres` 的 Spine skeleton UID 失效 | 更新为 `uid://cwmuhercrl8q5` |
| iOS 导出插件在 Android 构建阶段错误执行 | 对 `_export_begin` 和 `_export_end` 增加 iOS feature 判断 |
| UniKit 专有 Android 插件不在发布资源中 | 使用现有 GDScript 离线适配层，避免阻塞游戏启动 |

修复后，使用匹配的 Spine-Godot 编辑器重新导入，脚本、场景、资源和插件均无解析错误。

### 7. Android 构建环境配置

根据 Godot 4.6 Android 导出要求，在工作区配置：

```text
Android Platform Tools 37
Android Build-Tools 35.0.1
Android Platform 35
CMake 3.10.2.4988404
Android NDK 28.1.13356709
Microsoft OpenJDK 17.0.19
```

新增 `recovered_project/tools/setup_editor_settings.gd`，用于将 Godot 编辑器的 Android SDK 和 JDK 路径指向本地工具链。

新增 `recovered_project/export_presets.cfg`，主要配置包括：

- 使用匹配的 Spine-Godot Android 模板；
- 仅导出 `arm64-v8a`；
- 恢复版包名为 `com.oakever.meowdoku.recovered`；
- 版本保持 `1.8.1 (418)`；
- 最低 SDK 24，目标 SDK 35；
- 排除编辑期明文关卡和 Rider 文件；
- 保留网络、Wi-Fi 状态和振动权限。

使用独立包名是为了让恢复版与商店原版可以同时安装，避免覆盖用户原有应用数据。

### 8. APK 构建与签名验证

最终 APK：

```text
build/meowdoku-recovered.apk
```

构建结果：

| 项目 | 结果 |
| --- | --- |
| Godot Android 导出 | 0 warning，0 error |
| 包名 | `com.oakever.meowdoku.recovered` |
| 版本 | `1.8.1 (418)` |
| 架构 | `arm64-v8a` |
| APK 大小 | `98,560,862 bytes` |
| 签名 | APK Signature Scheme v2/v3 验证通过，调试证书 |
| APK SHA-256 | `2A4241174AF56D0C53CE91A49AEC50DE5DA3F67EC78B0D0D19BD4B9FFEB7F5F4` |

### 9. Android 真机验证

恢复版曾安装到连接的 Pixel 6a，原版包未被覆盖。真机冷启动日志和操作验证覆盖：

- Godot 主 Activity 正常启动；
- Spine 动画和教程画面正常显示；
- 中文文本和运行时翻译资源正常；
- 教程完成流程正常；
- 第 1 关完成并进入第 2 关；
- 设置弹窗正常；
- Android 返回导航正常；
- 存档、工具数量和关卡状态能够加载；
- 日志中没有 `SCRIPT ERROR`、`ERROR` 或 `WARNING`；
- 调试 API 在设备 8090 端口监听；
- 通过 ADB 转发到本机 18090 后，ping 返回 `{"result":"pong"}`。

真机证据文件：

```text
build/meowdoku-recovered-final.png
build/meowdoku-recovered-device.png
build/meowdoku-recovered-step2.png
```

### 10. 自动验收

新增 `recovered_project/tools/validate_recovery.gd`，自动执行以下检查：

- 加载项目主场景；
- 检查 4、5、6、7、8、9、10、12 尺寸关卡库；
- 检查 57 个特殊关卡和教程数据；
- 对 4×4 至 10×10 生成器逐一生成并验证规则。

最终验收命令退出码为 0，输出：

```text
VALIDATION_OK: main scene, level banks, tutorial data, and generators 4x4-10x10
```

完整输出保存在工作区根目录的 `validation_stdout.log`。

## 五、直接恢复内容与推导重建内容

为了便于审计，本次工程内容可分为两类。

### 直接从发布包恢复

- 257 个反编译 GDScript；
- 场景、纹理、音频、字体和 Spine 资源；
- 运行时关卡库；
- 75 个运行时翻译资源；
- 项目设置、Autoload 和大部分资源 UID；
- arm64 原生库和 Android 清单信息。

### 根据现存接口和行为推导重建

- `LevelGeneratorEditor` 编辑期实现；
- `Level Bank Encryptor` 编辑器插件；
- Godot MCP Pro 公开版本；
- Android 导出预设和本地工具链配置脚本；
- 少量失效 UID 和平台导出保护；
- 自动验收脚本及交付文档。

## 六、已知边界与不影响核心运行的缺失项

1. **UniKit 专有广告/统计插件**
   - 原 APK 没有包含该插件的开发源码和完整构建工程；
   - 恢复版使用 GDScript 离线适配层；
   - 核心游戏、存档、音频、动画、关卡和设置不受影响；
   - 广告投放、商业分析和原后台服务不能保证与线上原版一致。

2. **翻译源 CSV 不完整**
   - 运行时 75 个编译翻译资源全部保留并可正常使用；
   - GDRETools 仅重建出 875/1035 个源 CSV key；
   - 不完整 CSV 保留在 `.assets/` 作为证据，没有覆盖可用的运行时翻译资源。

3. **Rider 编辑器扩展**
   - Android 发布包缺少桌面 Rider GDExtension 二进制；
   - 已从工作工程中移除失效加载项；
   - 不影响 Godot 编辑、构建或游戏运行。

4. **签名与包名**
   - 恢复版使用调试签名和独立包名；
   - 不能作为原商店签名包的直接升级包；
   - 独立包名可保护原版应用和存档不被覆盖。

5. **源码同一性**
   - 反编译结果无法恢复原注释、格式、变量原名保证、Git 历史和未随发布包导出的文件；
   - 因此本项目保证的是已验证的可用性和可复现性，而不是原始开发仓库的字节级同一性。

## 七、为什么没有使用 Frida

任务过程中没有发现必须依靠动态 Hook 才能绕过的加固、反调试或密钥保护。GDScript 可以直接反编译，关卡混淆算法和密钥也能从恢复代码中静态确认。因此使用 Frida 不会增加恢复完整度，本次没有引入不必要的动态注入步骤。

## 八、交付目录说明

```text
E:\workspace\meowdoku\
├─ recovered_project\                 可编辑、可导入、可构建的最终工程
├─ artifacts\recovered_baseline\     未修改的 GDRETools 恢复基线
├─ artifacts\xapk\                   原始 XAPK 拆分内容
├─ artifacts\asset_pack_apk\         安装时资源包提取内容
├─ artifacts\arm64_apk\              arm64 拆分 APK 提取内容
├─ tools\gdre\                        固定版本 GDRETools
├─ tools\spine-godot\                匹配的 Spine-Godot 编辑器和模板
├─ tools\android-sdk\                本地 Android SDK/NDK/CMake
├─ build\meowdoku-recovered.apk       最终恢复版 APK
├─ validation_stdout.log              最终自动验收输出
├─ RECOVERY_REPORT.md                 简版恢复报告
└─ MEOWDOKU_逆向恢复全流程总结.md      本文档
```

## 九、复现与使用命令

以下命令均在 `E:\workspace\meowdoku` 下执行。

### 打开工程

```powershell
& .\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --editor --path .\recovered_project
```

### 运行自动验收

```powershell
& .\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --path .\recovered_project --script res://tools/validate_recovery.gd
```

预期看到：

```text
VALIDATION_OK: main scene, level banks, tutorial data, and generators 4x4-10x10
```

### 配置 Android SDK/JDK 路径

```powershell
& .\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --editor --path .\recovered_project --script res://tools/setup_editor_settings.gd
```

### 重新导出 APK

```powershell
& .\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --path .\recovered_project --export-debug Android .\build\meowdoku-recovered.apk
```

### 安装到 Android 手机

```powershell
adb install -r .\build\meowdoku-recovered.apk
```

如果 ADB 没有显示设备，需要重新连接 USB、解锁手机，并确认 USB 调试授权：

```powershell
adb devices -l
```

## 十、参考资料

- GDRETools：<https://github.com/GDRETools/gdsdecomp>
- Spine-Godot 文档：<https://esotericsoftware.com/spine-godot>
- Godot 4.6 Android 导出文档：<https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html>
- Godot MCP Pro：<https://github.com/youichi-uda/godot-mcp-pro>

---

本次恢复完成日期：2026-07-10。
