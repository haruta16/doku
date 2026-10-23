# Meowdoku 1.22.0 学习工程

本仓库从 Meowdoku 1.22.0（`com.oakever.meowdoku`，version code `1573`）的 Android 发布包恢复，延续 1.8.1 的格式整理、中文教学注释和学习文档。仅用于学习 Godot 与 GDScript。

## 打开与运行

需要 **Godot 4.6.1 + Spine 4.2** 自定义编辑器。普通 Godot 不含本项目使用的 Spine 类型。本机稳定入口为 `godot-4.6.1`；其他机器请安装对应编辑器并替换命令中的可执行文件路径。

```bash
godot-4.6.1 --editor --path .
```

首次导入会重建纹理、音频、字体等缓存，需等待完成。运行主场景为根目录 `launcher.tscn`。学习版使用独立存档目录 `Meowdoku-Recovered-1.22.0`，不会自动改写旧 1.8.1 的存档。

## 自动验收

```bash
python3 tools/audit_recovery.py verify . docs/recovery/1.22.0/package_manifest.json
godot-4.6.1 --headless --path . --script res://tools/validate_recovery.gd
godot-4.6.1 --headless --path . --script res://tools/verify_level_bank_roundtrip.gd
godot-4.6.1 --headless --path . --script res://tools/verify_board_teardown.gd
python3 -m unittest discover -s tools -p 'test_*.py'
```

深度验收预期：853 个发布脚本、187 个发布场景、75 份翻译、59 份关卡文件、65,915 条顶层记录、45,133 条 solution。顶层记录包括节奏配置，不等于独立谜题数量。原包存在的 63 条无效 solution 保留并单独报告，不以修改题库来换取通过。

## 编辑题库

- `assets/editor/levels/`：解码后的 59 份 JSON，供编辑器读取和学习。
- `assets/resources/levels/`：原包的 37 份二进制题库与 22 份 JSON。
- 编辑后使用 Godot 菜单 **Project → Tools → Encrypt Level Banks**。插件按新版 `BankBinaryFormat` 编码再 XOR，避免只改 JSON 却仍读取旧 `.bin`。
- 未编辑的恢复基线可做原包哈希校验；主动修改题库后出现原包哈希差异是预期结果，此时应验证修改内容及编辑/运行数据往返。

## Android 构建

已导出独立包名 `com.oakever.meowdoku.recovered`，版本 `1.22.0 (1573)`，架构 `arm64-v8a`。模板、JDK、SDK 位于仓库外的 `../tools/`，不会混入项目源码。

```bash
godot-4.6.1 --headless --editor --path . --script res://tools/setup_editor_settings.gd
godot-4.6.1 --headless --path . --export-debug Android ../build/meowdoku-recovered-1.22.0.apk
```

工具版本、下载来源和签名检查见 [Android 构建说明](recovery/1.22.0/ANDROID_BUILD.md)。本轮已通过桌面实际教程和关卡验证；未连接 Android 真机，不能沿用旧版的真机验收结论。

## 学习入口

1. [GDScript 七种根基抽象](learning/00-gdscript-seven-abstractions.md)
2. [1.22.0 代码与数据流导读](learning/08-version-1.22.0.md)
3. 回到 `scripts/` 对照中文职责和函数注释阅读。

旧学习笔记继续保留。涉及 1.8.1 具体结构的章节已标明版本，避免拿旧调用链解释新源码。

## 恢复质量与边界

- 853/853 脚本成功反编译。修正两处可由字节码证明的浮点打印精度损失后，格式化前 847 份回编译逐字节一致，另 6 份仅有字符串对齐填充差异。
- 326 张自定义图集成员恢复为可编辑 PNG，保留 UID；另 390 张原纹理完成逐像素核验。
- 75 份运行时翻译原样保留。恢复 CSV 只找回 1,184/2,255 个键，不能覆盖完整运行时翻译。
- 新版发布包中的 UniKit、LXAuth GDScript 层完整保留；未随包提供的原生 SDK 源码、服务器和编辑器插件实现不能宣称已恢复。

详见 [保真审计](RECOVERY_FIDELITY_AUDIT.md)、[升级记录](UPGRADE_1.22.0.md)和 [1.8.1 历史恢复总结](MEOWDOKU_逆向恢复全流程总结.md)。
