# Meowdoku 玩法实现

本目录属于 [Meowdoku 产品](../README.md)，按规则、用例、内容和表现组织。它不是一个整体可直接复用的公共玩法 SDK。

| 子目录 | 所有权与边界 |
|---|---|
| `domain/` | 已有独立边界的棋盘纯规则，可单独取用；不读取产品单例、页面或文件 |
| `application/` | Meowdoku 的产品用例：选题、冻结策略、资格、残局兼容和结算 |
| `content/` | Meowdoku 的配置、题库格式及语义校验，不是通用内容协议 |
| `presentation/` | 本产品的棋盘、输入、主线、每日、教程和结果表现 |

例如 `MeowdokuRoundSettlement` 决定本产品通关后的进度和奖励；另一个 Block 产品无需使用它。应用用例中存在不依赖页面的可测试组件，也不意味着其业务政策通用于其他产品。

另一产品需要相似功能时，先实现其具体规则；确有相同且稳定的机制，再考虑提取。可复用基础设施统一看 [framework](../../../scripts/framework/README.md)，接入步骤见 [框架使用指南](../../../docs/framework-usage.md)。
