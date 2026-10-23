# Android 构建与题库验收

最终调试 APK 已导出并独立验收：`../build/meowdoku-recovered-1.22.0.apk`，包名 `com.oakever.meowdoku.recovered`，版本 `1.22.0 (1573)`，仅 arm64-v8a，`minSdkVersion=24 / targetSdkVersion=36`。导出返回码 0，日志无 ERROR/WARNING，v2/v3 签名均通过。未连接 Android 设备，因此没有进行本轮真机测试。

产物大小为 221,772,165 字节，SHA-256 为 `00e2f43d83b953bd9a0a37302a484892ce2aaeaff184c50c01b1b45a4e72947d`。

## 本机工具链

工具放在仓库旁的 `../tools/`，不提交到 Git，也不替换系统 Java：

- `jdk-17/Contents/Home/`：Temurin 17.0.21+9，macOS arm64。
- `android-sdk/platform-tools/`：37.0.1。
- `android-sdk/build-tools/35.0.1/`、`android-sdk/platforms/android-35/`。
- `spine-godot/4.2-4.6.1/templates/android_debug.apk` 和 `android_release.apk`。

下载来源及 SHA-256 见 [android_toolchain.json](android_toolchain.json)。Spine 模板从官方 TPZ 的 ZIP 条目按 HTTP Range 提取，验证了条目 CRC32；没有把部分下载文件冒充完整 TPZ。非 Gradle 导出直接使用预编译模板，本轮未安装 NDK/CMake，也未恢复商用 SDK 的原生构建源码。

在其他机器上，可从 [Spine-Godot 官方下载说明](https://esotericsoftware.com/spine-godot) 获取同版本编辑器和模板，按 [Godot 4.6 Android 导出说明](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html) 安装工具。Windows/Linux 的 JDK 可放在 `../tools/jdk-17/`，或通过 `JAVA_HOME` 指定；SDK 可用 `ANDROID_HOME` 指定。

## Android SDK 版本的局部适配

原 XAPK 是 `minSdkVersion=24 / targetSdkVersion=36`。Spine 4.6.1 模板自身为 `min24 / target35`；初次导出的 target35 仅作为构建报告中的历史记录。最终 APK 已通过 Android `aapt` 独立确认 min24、target36，与原包一致。

Godot 4.6.1 的 `gradle_build/target_sdk` 只能用于 Gradle 导出，不能在当前预编译模板模式填写该选项冒充生效。新增本地插件 `addons/recovery_android_export/` 使用官方的 [`EditorExportPlugin._update_android_prebuilt_manifest`](https://docs.godotengine.org/en/4.6/classes/class_editorexportplugin.html#class-editorexportplugin-private-method-update-android-prebuilt-manifest) 扩展点：解析 Android 二进制 XML，通过 `uses-sdk` 元素及标准 Android 属性资源 ID 定位，只改 `targetSdkVersion` 的四字节整数为 36，保留 min24 和其他全部字节。模板中的 Java/原生代码仍是官方以 API35 构建的版本；此处调整运行行为目标，不宣称重新用 API36 编译引擎。非 Gradle 打包无需安装 platform36 或重编 NDK。

插件在引擎打开模板前预检结构、边界和整数类型；失败时通过官方 `_get_export_options_overrides` 在内存中覆盖为不可打开的路径，让引擎配置检查中止导出并显示具体原因。插件不调用预设的 `set()`，保存文件始终使用原配置，不会把拒绝路径落盘。Godot 的清单扩展回调没有直接取消返回值，所以不能仅打印错误后继续。如果预检后另一个插件把清单改坏，本插件会报告错误并按导出前的 SHA-256 清理本次新建或改写的产物；已有且指纹未变的旧 APK 会保留，无法取得指纹时也不盲删。独立失败导出已验证返回码 1、旧产物字节不变、预设不含临时覆盖路径。切换为 Gradle 构建时应通过 Godot 自带的 `gradle_build/target_sdk="36"` 设置目标；该插件只处理预编译模式。

独立验证工具 `tools/verify_android_manifest.gd` 对 debug/release 两个原始模板验证了最小字节改动、幂等性与损坏输入拒绝，并由 Android `aapt` 独立解析确认 `min24 / target36`，详见 [android_sdk_manifest_report.json](android_sdk_manifest_report.json)。两份清单实际均仅一个字节由 35 变为 36，原模板文件未被修改。随后导出的最终 APK 也已通过 `aapt` 独立复核；真机行为尚未验证。

## 重复验收

以下命令在仓库根目录执行。`godot-4.6.1` 必须是包含 Spine 的版本；本机对应 `/opt/homebrew/bin/godot-4.6.1`。

```sh
godot-4.6.1 --headless --editor --path . --import
godot-4.6.1 --headless --path . --script res://tools/validate_recovery.gd
godot-4.6.1 --headless --path . --script res://tools/verify_level_bank_roundtrip.gd
godot-4.6.1 --headless --editor --path . --script res://tools/setup_editor_settings.gd
godot-4.6.1 --headless --path . --export-debug Android ../build/meowdoku-recovered-1.22.0.apk
```

`setup_editor_settings.gd` 只在 SDK/JDK 路径可用时更新编辑器设置；不再使用旧 Windows 机器的固定 JDK 路径。

`validate_recovery.gd` 使用从 XAPK 独立提取的 [package_manifest.json](package_manifest.json) 和从原包编解码器生成的 [runtime_manifest.json](runtime_manifest.json)。它检查 853 份脚本、187 个场景、75 份翻译、59 份运行题库的完整性，以及 `BankData` 的常规、LKStyle、GC、OneFish 和特殊题库接口。修改关卡后，此“原包保真验收”会按设计报告哈希差异；不要直接改预期清单来隐藏修改。

59 份数据包含 37 份二进制关卡库、21 份节奏元数据 JSON、1 份其他 JSON，共 65,915 条顶层记录；其中 45,133 个条目带 `solution` 和 `regionMap`。原运行校验器拒绝其中 63 个解，恢复工程保留原数据。36 个浮点值经 Godot 的 JSON 文本解析后存在末位舍入，最大绝对差 `1.1102230246251565e-16`，已按文件记入清单；运行文件始终保留原始字节。

`verify_level_bank_roundtrip.gd` 把 59 份编辑 JSON 写入进程专用临时目录，调用与编辑器菜单相同的编码器，再用发布包解码器回读；通过后删除临时输出，不改项目运行题库。

## 编辑关卡与重新打包

在 `assets/editor/levels/` 编辑明文 JSON，随后使用编辑器的 **Project → Tools → Encrypt Level Banks** 菜单。

1.22.0 的正式题库使用 `bankData*.bin`，流程是紧凑数组、Godot Variant 编码、ZSTD 压缩、MDBK 头和 SHA-256、XOR。插件直接调用发布包中的 `BankBinaryFormat.encode`；节奏 JSON 和 `levels-7x7.json` 继续使用 XOR JSON。仅覆盖旧式运行 JSON 会被 `.bin` 优先级遮住，因此旧版插件已升级。

导出预设显式包含运行 `.bin`、`.json` 和配置 JSON，排除编辑题库、恢复工具、文档与原始包。构建结果的包名、版本、架构、签名和包内数据哈希核对结果见 [android_build_report.json](android_build_report.json)。最终 APK 的 59 份运行数据和 75 份翻译均与原包 SHA-256 一致，且集合完全相同，没有多余条目。编辑题库、tools、docs、originals 及恢复工具编译字节码均未打入包；全部 ZIP 条目的 CRC 校验通过。v2/v3 签名校验通过。
