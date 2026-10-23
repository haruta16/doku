# Meowdoku 1.8.1 源码还原精度审计

## 1. 审计口径

本次审计只评价 APK/XAPK 中可观察到的程序和数据是否被准确还原。原注释、Git 历史以及从未进入发布包的源码不计入核心业务代码还原率，也不对无法从发布包证明的内容作“原版实现”声明。

原始输入：

- `originals/Meowdoku_+Brain+Puzzle+Games_1.8.1_APKPure.xapk`
- SHA-256：`f8b3dd5460adacfe0232eb23c783da991545951ade268c528de5fdf5d86cf179`
- Godot：`4.6.1.stable.custom_build`
- GDScript 字节码版本：`ebc36a7`（4.5.0-stable 起沿用到 4.6.1）

## 2. 核心脚本同一性

安装时资源包内有 257 个 `.gdc`，工程的 `.autoconverted` 目录完整保留这 257 个原始字节码，每个字节码均有一份对应的 `.gd`。

在统一格式化之前，使用 GDRETools v2.5.0-beta.5 将 257 份恢复源码重新编译为同一字节码版本，再与 APK 中的 `.gdc` 逐文件比较：

| 结果 | 数量 | 说明 |
| --- | ---: | --- |
| 字节完全一致 | 255 | 重新编译结果与 APK 原字节码 SHA/内容完全一致 |
| 有意保留的环境差异 | 2 | 不改变核心业务逻辑 |
| 无法编译或无法对应 | 0 | 所有 APK 脚本均有对应源码 |

两处环境差异为：

1. `scripts/common/unikit_manager.gd`：非 Android 环境下的一条告警输出改为普通日志，离线适配行为不变。
2. `addons/unikit_ios_exporter/export_plugin.gd`：增加 iOS feature 判断，阻止 iOS 导出插件在 Android/其他平台导出时执行。

没有发现 `var_0`、`local_0`、`func_1` 等合成标识符。现有类名、函数名、参数名、成员名和局部变量名均直接来自可恢复的 GDScript token，不做“易读化”重命名。这里的“变量名已还原”指 APK 字节码实际保存的名称；无法证明它们是否等于更早、混淆前或未发布仓库中的名称。

## 3. 格式损失修复

257 份 APK 对应脚本已统一经过 GDScript 格式化，修复反编译输出中的空行、缩进、续行、运算符间距、类型推断间距和长表达式排版。格式化只调整语法布局，不改标识符和业务表达式。

格式器在两个包含深层嵌套 lambda 的文件中产生了错误缩进，已按反编译 token 的原始调用结构人工排回，并由匹配的 Godot 编译器验证：

- `scripts/module/gameplay/view/cell_view.gd`
- `scripts/module/debug/view/generator_page.gd`

另修复一处反编译器输出的非法 NodePath 简写：

- `scripts/module/daily_streak/view/streak_page.gd`
- `$StreakContent / StreakPanel / "2Txt"` 改为 `$"StreakContent/StreakPanel/2Txt"`
- 场景中确有该节点，改动恢复的是原 token 所表达的节点路径，不是业务重写。

将原字节码重新反编译并使用相同格式规则生成规范参照后，257 份源码中有 251 份文本完全一致；其余 6 份由上述 2 个环境适配、2 个 lambda 排版、1 个 NodePath 语法修复和 1 个纯缩进风格差异构成。最后一项忽略空白后完全一致。

## 4. 数据同一性

- 26 份运行时 XOR 关卡库均已解密为编辑用 JSON。
- 编辑 JSON 与运行时文件逐份解密后进行结构比较，结果为 `26/26` 相同。
- 总计 20,746 条顶层关卡记录，其中 20,710 条包含 `solution` 与 `regionMap`。
- 原始数据内有 63 条 solution 会被原运行时 `QueendokuCore.validate_solution_entry` 拒绝；这些脏数据来自原包，当前工程忠实保留，业务加载逻辑也保留原有跳过行为。
- 75 份编译后的运行时翻译资源全部保留。反编译生成的源 CSV 不完整，因此没有用 CSV 覆盖运行时翻译资源。

## 5. 没有进入 APK 的代码

原始 `global_script_class_cache.cfg` 记录了 241 个全局类。与资源包实际脚本逐项核对后，有 29 个类路径没有对应字节码：

- 28 个 `addons/art2godot/` 文件：全部是美术/Figma 导入和场景编辑期工具，不参与发布包运行。
- `scripts/editor/queendoku/level_generator_editor.gd`：编辑/调试用关卡生成器。

28 个 `art2godot` 文件没有可供语义还原的字节码，当前工程未伪造其实现。

缺失路径明细：

```text
addons/art2godot/art2godot.gd
addons/art2godot/config/font_config.gd
addons/art2godot/config/name_transform_config.gd
addons/art2godot/config/path_template.gd
addons/art2godot/config/prefab_map_config.gd
addons/art2godot/config/sprite_map_config.gd
addons/art2godot/core/font_registry.gd
addons/art2godot/core/fui_converter.gd
addons/art2godot/core/fui_field_map.gd
addons/art2godot/core/fui_loader.gd
addons/art2godot/core/fui_parser.gd
addons/art2godot/core/image_transforms.gd
addons/art2godot/core/node_builder.gd
addons/art2godot/core/node_index.gd
addons/art2godot/core/node_name_builder.gd
addons/art2godot/core/patch_plan.gd
addons/art2godot/core/prefab_registry.gd
addons/art2godot/core/sprite_cleanup.gd
addons/art2godot/core/sprite_dedup_index.gd
addons/art2godot/core/sprite_importer.gd
addons/art2godot/core/sprite_registry.gd
addons/art2godot/core/three_way_merge.gd
addons/art2godot/core/tscn_parser.gd
addons/art2godot/core/tscn_patcher.gd
addons/art2godot/figma/figma_channel_dock.gd
addons/art2godot/figma/figma_channel_tools.gd
addons/art2godot/figma/figma_node_tools.gd
addons/art2godot/figma/figma_ws_client.gd
scripts/editor/queendoku/level_generator_editor.gd
```

`LevelGeneratorEditor` 当前文件是依据现存调用接口制作的兼容性重建，不是从 APK 字节码恢复的原实现。发布包只证明了类名、路径和调用接口，不能证明原算法；因此它不计入核心还原率，也不再作为自动验收通过条件。正常游戏运行使用 APK 内已有的 `scripts/module/gameplay/core/level_generator.gd` 和预制关卡库，不依赖该编辑器生成器。

工程另外包含 35 个 Godot MCP 脚本、关卡库加密插件以及两个恢复辅助脚本。这些均是开发/恢复工具，不冒充 APK 业务源码。

## 6. 最终验证

使用官方 Spine 4.2 + Godot 4.6.1 custom editor 完成：

- 全工程 headless import：退出码 0，无脚本解析、编译、资源加载错误或警告。
- 深度验收：257 个恢复脚本、74 个场景、75 个翻译、26 组关卡库全部加载；编辑/运行时关卡数据一致。
- 主场景 headless 启动：能够从 splash 进入 homepage，无脚本错误；强制退出时仅有对象泄漏提示，不属于启动失败。

验收成功输出：

```text
LEVEL_DATA_INFO: 63 original solution entries are rejected by runtime validation
VALIDATION_OK: 257 recovered scripts, 74 scenes, 75 translations, 26 level banks, 20,746 records, and 20,710 solution entries
```

## 7. 结论与上限

如果评价对象是“APK 中实际发布的核心业务 GDScript 和运行时数据”，当前证据支持接近满分的还原质量：全部脚本有对应源码，格式化前 255/257 字节完全一致，另 2 份差异均为明确的环境适配，业务代码没有发现推测性重写或标识符替换。

无法宣称整个原始开发仓库 100% 复原，因为发布包没有保存注释、Git 历史、28 个 `art2godot` 工具和编辑器生成器实现。继续猜写这些文件只会降低“忠实还原”可信度；对缺乏证据的部分保留缺失说明，比制作一个看似完整但无法证明的实现更接近本项目的核心目标。

## 8. 复核工具

| 工具 | 文件 SHA-256 |
| --- | --- |
| GDRETools v2.5.0-beta.5 macOS zip | `01211b4dd82f874bb21dfc11483d19affad9cff9c1912eacf561972b750011e6` |
| GDRETools 可执行文件 | `65eb334c49714643f71cc813c0e6d6294ac3d888682e9be2259877479bb637a9` |
| Spine-Godot 4.2/4.6.1 macOS zip | `75749b6a4bcc0d3af253eaa90eab7a44660be3cae4ead7ce56ab2ed5a3973022` |
| Spine-Godot 可执行文件 | `38a1848cb855b8baef5f83ec82648bde2ec275c1c4ba2d690383000ce3c4836b` |

审计完成日期：2026-07-11。
