# Meowdoku 应用装配与产品功能

本目录属于 [Meowdoku 产品](../README.md)，负责产品启动、存档、UI 路由、首页、设置、签到、广告接入、声音、会话和埋点。名称含 `Manager`、`Service`、`common` 或 `base`，也不改变其产品归属。

- `GameState` / `MeowdokuStore` 定义本产品数据，不是其他产品必须继承的存档。
- `UIManager` / `UIRegistry` 装配本产品页面；公共窗口机制在 `scripts/framework/ui/`。
- `ContentRuntime` 装配本产品热更启动、配置与健康确认；公共交付机制在 `scripts/framework/content/`。
- `ui/common/` 和 `ui/extensions/` 可以存放依赖本产品场景与样式的控件，例如 `PopUpToast` 和 `UnderlineLink`。

与棋盘流程紧密相关的本产品业务放在 [gameplay](../gameplay/README.md)。另一个产品可直接使用 [framework](../../../scripts/framework/README.md)，无需复制本目录。

详见 [框架接入指南](../../../docs/framework-usage.md)。
