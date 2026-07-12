# 学习笔记

> 从零开始理解 Godot + GDScript 的底层抽象。先搞清楚「每一种东西本质上是什么」，再去看它怎么用。

## 文档定位

这些笔记不是 API 手册，也不是教程逐字复刻。它们的作用是：用项目里的真实代码，建立「抽象是什么 → 在哪里出现 → 为什么这样设计 → 数据怎样流动」的理解框架。

遇到细节参数、完整方法列表、版本差异时，以 Godot 官方文档为准；这里优先记录会影响你读代码和继续学习的核心抽象。

## 阅读顺序

从 [GDScript 七种根基抽象](00-gdscript-seven-abstractions.md) 开始。它建立了读代码的基础框架：任何一行 GDScript 里的每个词，都在扮演値・名・型・令・注・符・释这七种角色之一。先掌握这套分类，再去看本项目的实际代码。

接着读 [launcher.gd 精读](01-launcher-gd-walkthrough.md)——应用启动全流程逐行讲解，覆盖日志、闪屏、隐私合规、A/B 测试、对象池、题库预热、异步轮询等全部概念。读完这个文件你就能独立读懂任何 Godot 项目的入口代码。

然后读 [核心玩法系统精读](02-core-gameplay-systems.md)——`cell_state.gd`（棋盘格子的 7 种状态）和 `queendoku_core.gd`（游戏规则引擎，9 个 static 函数）。这两个文件是 Meowdoku 的纯数据层——不依赖 UI、不碰场景树，纯数据进纯数据出。理解它们就理解了整个游戏的规则。

接着读 [输入系统精读](03-input-system.md)——11 个文件组成的命令模式 + 策略模式架构。从 CellAction 数据包 → StrokeContext 手势状态 → Operation 操作逻辑 → BoardInputScheme 模式切换 → GestureRecognizer 协调 → SwipeGuard 防误触，逐层拆解。

然后读 [Game Page 精读](04-game-page.md)——三大系统的汇聚点。看输入系统产出的 CellAction 怎么被消费、规则引擎怎么被调用、通关/失败流程怎么走。核心认知：BoardView 是棋盘状态的唯一真源，Game Page 只是协调者。

接着读 [Level Data — 难度曲线与关卡分配](05-level-data.md)——棋盘大小怎么随关卡增长（锯齿式难度曲线）、哪些是特殊关卡、预填策略怎么随教学进度变化、题库怎么去重和轮询取题。

然后读 [Hint Engine — 提示引擎](06-hint-engine.md)——提示系统不查标准答案，真的在解题。从 R1（唯一候选格）到 R5（反证法链式推导），五种策略逐层递进。最后还有一个自动解题循环，用于评估题目难度。
