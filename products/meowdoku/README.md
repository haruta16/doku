# Meowdoku 产品

本目录是 **Meowdoku 专属实现的归属边界**。应用、玩法、内容、资源和编辑工具都在这里；目录中的 `common`、`base`、`Manager` 或 `Service` 命名表示本产品内的复用，不自动承诺跨产品可用。

| 位置 | 职责 |
|---|---|
| [app/](app/README.md) | 启动装配、产品存档、首页与设置等功能、路由、声音、平台接入和诊断 |
| [gameplay/](gameplay/README.md) | 本产品的棋盘规则、选题与结算、内容合同、页面和输入 |
| `editor/` | 本产品的玩法编辑工具 |
| `assets/` | 美术、音频、字体、翻译、预制体、内置配置与题库 |
| `launcher.tscn` | 当前产品的启动场景 |

公共机制位于 [scripts/framework](../../scripts/framework/README.md)，独立接入示例位于 `scripts/examples/block/`。新产品可以直接选择公共组件，按自己的需要实现产品逻辑，无需继承 Meowdoku 的存档、页面或政策。

本次目录归属不改变 Godot 工程根：仓库根的 `project.godot` 和 `export_presets.cfg` 仍是 **Meowdoku** 的入口、Autoload 和导出配置。`addons/` 按插件约定保留原位置，其中的产品适配与工具见 [插件说明](../../addons/README.md)。没有引入产品注册器或同一进程切换多产品的机制。

产品标识、存档 schema、`user://` 路径、热更逻辑 ID 和包内 `res://content/...` 命名空间独立于源码目录；不能把移动源码目录当作修改这些合同的理由。原恢复身份继续由 `tools/validation/fixtures/recovered_relocations.json` 映射，原始基线和历史验收记录保留当时路径。

阅读路径与验证命令见 [工程说明](../../docs/README.md)；在另一工程复用公共能力见 [框架接入指南](../../docs/framework-usage.md)。
