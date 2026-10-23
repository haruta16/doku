# 1.22.0 恢复辅助工具

版本和 SHA-256 见 `provenance.json`。原始恢复目录保留不动；格式修复、图集补全与学习注释写入另一个目录。以下路径参数需要使用绝对路径，工作目录示例为 `originals/upgrades/1.22.0/`。

## 图集成员恢复

`tools/recover_atlas_members.gd` 接收四个参数：原始恢复目录、目标工程目录、成员清单、报告路径。以包含 `project.godot` 的独立最小工程运行，避免加载完整游戏的 Autoload：

```text
godot-4.6.1 --headless --path <最小工程> --script <仓库>/tools/recover_atlas_members.gd -- <recovered> <目标目录> <仓库>/docs/recovery/1.22.0/atlas_member_manifest.json <报告.json>
```

清单来自原包 `.import` 与 AtlasTexture `.res` 的 region、UID。326 个成员均已确认没有 margin、旋转等额外变换；工具只做矩形裁切，保存 PNG 后重新加载比对像素，生成标准纹理导入配置并保留 UID。不要对含其他变换的图集直接套用该清单模型。

## 原始纹理像素复核

`tools/audit_recovered_textures.gd` 使用相同四参数形式，清单改为 `all_texture_audit_manifest.json`。它加载原包 `.ctex`，移除 mipmaps 后解压原尺寸图像，并以 RGBA8 像素对照 GDRE 恢复 PNG。只有不一致项才会写入目标目录，报告逐项记录是否匹配。本版 390 项全部一致，没有写入修复图。

原恢复日志的 8 条 ASTC 对齐告警涉及 streak3/streak5 的 start/end、on/off 图片；原尺寸像素复核均通过。此验证不声称恢复了有损压缩前的美术源文件。

## 字节码对齐填充审计

```text
python3.14 tools/audit_bytecode_padding.py --work-dir <恢复工作目录> --report <报告.json>
```

使用 Python 3.14 的 `compression.zstd`。工作目录需有 `roundtrip_results.json`（含 `roundtrip_stem`）、`float_precision_fixes.json`、`asset_pack/assets/`、`roundtrip_compiled/`、`precision_fixed_compiled/`。这些原始或临时产物留在忽略目录；入库摘要 `bytecode_roundtrip.json` 去除了临时文件名。

845 份原始反编译脚本回编译后字节一致；两份经浮点十进制精度修正后也完全一致；另外 6 份仅有 50 字节 String/NodePath 对齐填充差异。工具按 Godot 4.6.1 Variant 编码逐字段解析，只归零真实填充位置；标识符、常量值、行号表与 token 内容都参与比较。无法识别的 Variant 类型直接失败，避免把未知差异当作填充。

本结果针对格式化前源码。添加注释或重新排版会改变行号等 token 信息，因此学习源码另以词法代码差异和引擎导入运行验证。
