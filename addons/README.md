# 当前工程接入的插件与工具

`addons/` 保留 Godot 插件约定的安装位置，**不表示这里都是跨产品公共框架**。根 `project.godot` 选择启用的插件和 Autoload，仍属于当前 Meowdoku 工程配置。

| 范围 | 当前用途与归属 |
|---|---|
| `level_bank_encryptor/`、`ui_code_generator/` | Meowdoku 的题库制作和产品页面生成工具，含本产品目录与约定 |
| `unikit_ios_exporter/`、`cheat_manager/` | 当前产品的平台导出适配和开发调试接入 |
| `helpshift_plugin/`、`in_app_review_plugin/`、`shortcut_plugin/`、`vibrate_plugin/` | 当前工程使用的平台插件；其他产品应单独评估依赖、配置和原生端支持 |
| `godot_mcp/`、`resolution_picker/`、`screenshot_tool/` | 编辑器与调试工具，按各插件自己的接入合同使用 |

这些工具与适配器不会因为留在根 `addons/` 就进入公共框架的兼容承诺。新产品不应整目录复制当前工程的插件与 Autoload；按实际需要接入，并分别验证。产品资源和业务代码统一位于 [products/meowdoku](../products/meowdoku/README.md)，可独立复用的基础机制位于 [scripts/framework](../scripts/framework/README.md)。
