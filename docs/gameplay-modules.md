# 玩法模块与对局业务边界

这次拆分的目标是：同一个提示、定位、撤销或结算动作，可以在没有具体页面的情况下计算结果并完成存档；换成 Block 或交换三消时，存档事务、对局标识和重试机制可以继续使用。它不要求不同玩法共享棋盘类型、动作列表或对局页面。

本文说明当前已经接入的代码，也明确尚由旧页面适配的部分。资源发布、下载和切换是另一条边界；玩法通过开局上下文保存本局使用的内容身份，不自行下载资源或读取远端配置。

现在 Meowdoku 的玩法代码集中在 `products/meowdoku/gameplay/`：纯棋盘规则放 `domain`，本产品策略与用例放 `application`，题库及产品内容合同放 `content`，页面与输入放 `presentation`。`application` 中的 `LevelData`/策略捕获仍是产品装配入口，可以读取产品配置；不要将整个目录误认为纯函数。跨玩法的产品存档结构与平台接入在 `products/meowdoku/app/`，公共设施在 `scripts/framework/`。Block 不继承 Doku 的产品策略或页面。

## 1. 三种状态，各自只负责一件事

| 数据 | 所在位置 | 含义 |
| --- | --- | --- |
| 当前正在显示、交互的棋盘 | `DokuBoardState` | 同一棋盘唯一的活状态；所有 CellView 绑定到它 |
| 对局的可恢复快照与最后一条回执 | `LocalCoreStore.round_services[module/mode]` | 上次成功提交的状态；用于恢复、事务和请求重试 |
| 动画、手势、临时覆盖层 | BoardView、CellView、页面和输入方案 | 显示与交互过程，不是另一份权威棋盘 |

存档快照与活模型同时存在是正常的。不能同时存在的是两套可以各自修改、却没有同步规则的活棋盘。提示、工具和赠命的事务入口从唯一活模型捕获 `runtime_snapshot`，把最近的普通操作一并纳入本次事务。事务成功后，页面才呈现这些事务返回的变化。普通点按及逐格动画执行纯规则计划，由产品检查点保存，不为每个动画格同步写一整份存档。

`runtime_snapshot` 是本地兼容接缝，不是允许外部客户端任意上传权威状态的网络协议。本项目没有因此获得服务端防作弊或多人同步能力。

## 2. Doku 的纯逻辑

### DokuBoardState

路径：`products/meowdoku/gameplay/domain/doku_board_state.gd`。

它是 `RefCounted`，不引用节点、SceneTree、GameState 或 AB 单例。负责格子值、输入锁、曾经画叉/犯错的追踪，以及传入时间戳后的改叉语义。

- `set_cell_state` 是经过值校验的直接写入，供恢复、演示及已决定结果使用。
- `transition_cell` 保留原 CellView 的普通变化语义。需要时间时由视图边界传入毫秒数，模型自己不读取时钟。
- `get_board`、`get_folded_board` 返回副本，外部修改数组不会改变活模型。
- `restore_board` 先完整验证，再替换状态；无效输入不会只恢复半个棋盘。
- 模型的 `revision` 反映当前模型内的棋盘变化；它不等于存档事务版本，也不等于跨重启的对局 `board_revision`。

BoardView 保留原有 setter、信号及动画调用形式，CellView 的状态读取转发到绑定的模型。教学演示中独立创建的 CellView 有自己的 1×1 模型，不必为了画一格创建完整对局。

`refresh_from_model` 只重画已有结果，不发出一次新的落子事件，不重记历史、不重做消费。它适合恢复或回执重放后的静态对齐。普通交互仍应使用对应的显示变化接口，以保留原有演出。

### DokuActionRules

路径：`products/meowdoku/gameplay/domain/doku_action_rules.gd`。

这是无节点、无时钟、无存档副作用的规则与动作计划集合。输入方案、真实页面与无界面模块复用它，不各自维护一份草稿或落子规则。

| 输入/动作 | 纯逻辑产物 | 页面保留的工作 |
| --- | --- | --- |
| 点按、拖动、双击 | 是否允许、目标值、并步前值、错猜后的生命与最终错误状态 | 识别手势、播放点击与错误反馈、提交一条手势历史 |
| 草稿提交/丢弃 | 变化顺序、正确/错误猫、批量扣命、全对/矛盾判定 | 按原顺序转正、画叉、扣心表现、烟花与完成回调 |
| 自动排叉、锁叉、轴打叉 | 受影响格子与可锁定约束集合 | 扩散方向、等待时长、临时输入锁 |
| 自动完成 | 可展示条件，以及叉/猫两个阶段的坐标计划 | 分阶段呈现、取消与收尾检查点 |
| 生命 +1 | 二选一区域、时间/命数/局内资格/概率条件 | 提交事务成功后显示新生命及首次引导 |

计划是一次性结果，不是第二套活模型。错猜计划区分 `after=MARK` 的历史/动画阶段和 `final_state=ERROR` 的落定状态；无界面宿主可直接应用最终值，页面保留原错误演出。草稿一次提交只产生一条复合历史，批量错误不会把生命扣成负数。

取消也属于显示边界：隐藏或复用页面会递增动作代次，清理临时输入锁；延迟错误、草稿自动提交、烟花与提示冷却回调先确认代次。CellView 重置会使上一轮草稿动画结束回调失效。

### DokuHintService

路径：`products/meowdoku/gameplay/domain/doku_hint_service.gd`。

`find_hint(board, regions, solution)` 保留现有规则顺序：已有猫的排除提示、答案位置错叉兜底、R1、R2、R3/R4、推理链。`apply_hint` 接受保存过的原始提示，返回新棋盘和变化列表，不读取或修改页面。

变化中的 `before` 是真实格子值；`history_before` 保留旧产品的撤销记录语义。例如草稿叉转成正式叉，真实原值是草稿，但旧回看记录的原值是空白。R3/R4 的变化顺序也保留先行后列，避免改变回看播放顺序。

页面可以复制提示再补充翻译、覆盖层和显示文案，不能拿修改后的显示对象替换已保存的凭证。

### DokuToolService

路径：`products/meowdoku/gameplay/domain/doku_tool_service.gd`。

- `locate` 选择未完成的答案格，按所属区域剩余候选数量、行、列确定目标。无目标时规划器返回 `no_locate_target`；对局模块按原版把它作为一次有效使用收费，返回无棋盘变化的回执。
- `undo(..., "revert", ...)` 从后向前寻找可撤销步骤，跳过错误猜测，保护正式猫、错误格及锁定叉；返回新的历史和棋盘。选中可编辑步骤后，即使格值已等于原值，也按原版移除相应历史并收费；完全没有可选步骤时不收费。
- `undo(..., "highlight", ...)` 只选择回看范围，返回坐标历史与游标，不修改棋盘。高亮时长、声音和播放过程仍由视图决定。

这些函数没有库存操作。是否免费、是否允许广告授权、主线工具使用如何影响 DDA，由产品层决定。定位按使用次数计费，撤销先检查可选步骤；没有视觉变化不代表所有道具都免费。模块将有效使用结果与库存变化一同提交，真实失败不提交。

### DokuRoundModule

路径：`products/meowdoku/gameplay/domain/doku_round_module.gd`。

它把棋盘规则、提示和工具组合为对局用例，校验本局题面、生命数及历史，维护持久 `board_revision`、未应用提示和结算条件。它不持有页面或视图。

独立动作包括 `set_mark`、`place_cat`、`draft_mark`、`draft_commit`、`draft_clear`、`auto_mark`、`axis_mark`、`lock_marks`、`auto_complete`，以及提示/定位/撤销/复活/赠命。普通落子和草稿提交同时更新棋盘、历史及生命。自动完成是否犯过错由棋盘/历史推导，不能用玩家参数覆盖。具体玩法动作没有进入通用 RoundService 的分支中。

提示按原版“每次重新打开成功都收费、应用时不再收费”：

1. `request_hint` 计算提示，生成绑定 `round_id`、请求序号与 `board_revision` 的凭证。
2. 宿主把凭证和扣费放在一次核心存档提交中。
3. 即使本局棋盘未变，新一次 `request_hint` 仍重新计费并替换旧凭证。库存不足或提交失败时不扣费、不替换，原请求序号可重试。
4. `apply_hint` 只接受当前凭证标识。新提示成功购买或棋盘版本改变后，旧提示失效；应用本次提示不再收费，重复应用不再产生棋盘变化。

凭证仍随业务快照持久化以保证提交和应用一致，但页面重开并重新请求提示属于新购买，不提供免费复看权益。同一个已提交请求序号的重复调用仍返回原回执，不再次扣费；它与玩家主动再次打开不同。普通关找不到提示方案不收费，SP关沿用定位降级；原有免费策略保持不变。

生命 +1 同样具有事务边界：新生命、每局已使用标记、产品首次赠送标记与可恢复残局一次提交。写盘失败不会先消耗首次资格；重复回调不会再次加命。首次标记只区分首次保证赠送/引导与以后局的概率赠送，不把以后局全部禁用。

### 本局产品策略快照

路径：`products/meowdoku/gameplay/application/meowdoku_gameplay_policy.gd`。

`MeowdokuGameplayPolicy` 在开局最后一次 AB 染色后，把影响规则与收费的值冻结成普通字典：草稿变体、撤销模式/免费状态、工具解锁关卡、自动排叉/自动完成、生命 +1、复活生命数/免费模式、残局保存开关、滑动保护参数与影响输入语义的开关。DDA 结算的四个布尔策略也在此固定，包括按当时规则组与内容计算的“下一关是否跳过正常难度递进”。主线恢复、失败重试与业务内容上下文携带同一快照；本局不会因后来读取到的 AB 值而改变规则。

完整有效的恢复快照直接复制，不先查询当前内容或 AB。没有此字段的旧残局使用本次启动策略生成兼容快照；早期 schema 1 若缺少新增字段，只补齐缺项，保留已有冻结值。视觉实验不必全部冻结。一次性免费复活是否已经消费、今日广告是否已解锁自动排叉属于会变化的业务资格，继续在产品事务中判断，不伪装成静态 AB 值。失败弹窗只展示资格并发出请求，免费次数仍与复活结果同次提交。

## 3. RoundService 的契约

路径：`scripts/framework/application/round_service.gd`。

这是小型应用服务，不是本地 HTTP 服务、万能规则引擎或统一棋盘父类。它只理解命名空间、对局标识、请求序号、库存增减与存档提交。

### 存储端口

构造时传入一个提供以下方法的对象：

```gdscript
is_open() -> bool
revision() -> int
snapshot() -> Dictionary
commit(candidate: Dictionary, expected_revision: int) -> Dictionary
```

测试直接传 `LocalCoreStore`。实际 Meowdoku 传产品适配端口，借此将旧残局格式、尚未落盘的产品统计和新对局记录合并到同一份候选状态中；通用宿主不认识这些旧字段。

### 玩法模块

模块以 `RefCounted` 实现五个方法，不要求继承项目定义的玩法父类：

| 方法 | 职责 |
| --- | --- |
| `create_snapshot(context)` | 校验开局数据，生成本玩法初始快照 |
| `validate_snapshot(snapshot)` | 返回空字符串表示有效，否则返回原因 |
| `sync_runtime(snapshot, runtime)` | 可选的旧活模型适配；不需要的模块可以拒绝覆盖 |
| `apply_action(snapshot, kind, payload, call_context)` | 计算动作结果，不能直接存档或调用 UI |
| `settle_snapshot(snapshot, payload)` | 验证结束条件，产生结算结果与奖励增量 |

成功的动作/结算返回：

```gdscript
{
    "ok": true,
    "snapshot": next_snapshot,
    "result": result_data,
    "changes": presentation_data,
    "inventory_delta": {"hint": -1},
}
```

`snapshot`、`result` 和 `changes` 由玩法自己定义。宿主不枚举 Doku 的格子状态，也不解释 Block 的清行事件。值必须能够持久化，不得夹带 Node、Callable、Signal 等运行时引用。模块失败返回 `{"ok": false, "error": "..."}`；宿主不提交失败动作。

`call_context` 包含宿主提供的 `round_id`、请求 `sequence` 和产品提供的 `policy`。动作 `payload` 与产品策略分开：例如玩家请求 `undo`，产品决定当前使用撤销还是高亮、价格为 0 还是 1。把按钮显示状态直接当作收费授权会让业务重新依赖 UI，应避免。

### 调用与重试

```gdscript
var host := RoundService.new(core_store)
host.register_module("block_probe", BlockProbeModule.new())
var opened: Dictionary = host.start("block_probe", "main", 1, context)
var placed: Dictionary = host.action(
    "block_probe", "main", opened.round_id, opened.next_sequence,
    "place", {"row": 0, "col": 0}
)
```

- 存储键为 `module_id/mode_id`，如 `doku/main`、`doku/daily`、`block_probe/main`。
- 每个命名空间保存当前一局。新局的 `start_sequence` 是上一局加一，形成稳定 `round_id`；用同一开局序号改变上下文会被拒绝。
- 同一局动作序号严格递增；失败且未提交的动作可以用原序号重试。
- 只保存最后一条回执。同序号、同动作、同 payload 重试返回该回执；同序号改动作被拒绝。更早的序号拒绝执行，避免无限保存每一格的去重记录。
- 新局开始后，旧 `round_id` 的延迟请求会被拒绝。
- 完成结算后再结算返回原结算，不重复发奖励；结束后的普通动作会被拒绝。
- 返回 `duplicate: true` 表示回执已存在，显示层应恢复已提交状态，不能当作新动作再记历史、重复播整段流程或触发埋点。

宿主对候选快照和库存执行一次提交。库存不足、未知道具、溢出或存档失败都会阻止发布。这不是分布式事务：跨设备冲突、联网权威和远程支付校验不在此契约内。

## 4. 现有项目如何接入

`products/meowdoku/gameplay/application/meowdoku_round_session.gd` 是产品适配器。它创建 Doku 模块、恢复业务局号，把新快照映射到旧残局结构，提交成功后把结果交给页面呈现。

它接收普通 Object 方法端口，生产环境传 GameState，独立验证传 RefCounted 内存适配器，不依赖 Node 生命周期。端口需要 `is_storage_ready()`、`get_core_store()`、`get_core_candidate()`、`commit_core_candidate(candidate, expected_revision)`；其中 core store 提供 `revision()`。`MeowdokuRoundSettlement.stage()` 只操作调用者持有的候选字典；冻结题面交给纯 `DokuLevelDefinition` 校验，不再为了结算加载当前题库或内容环境。发布时额外的场景媒体合同仍由 `DokuLevelCatalog` 检查。

`LevelData.resolve_level_entry` 负责在选择状态的副本上解析题目，返回 `entry + expected_selection + next_selection`。它可以读取题库与冻结的产品配置，但不推进正式游标、不消费当天首次资格、不写“已见题目”。`commit_selected` 在棋盘准备完成后，把最终选中的游标、当天资格、重试缓存及初始残局一次提交。普通统计变化不使选择失效；相关选择字段或内容代次改变才会拒绝旧计划。

现有输入与演出适配边界：

- 输入方案识别点按、双击和拖动，调用纯规则获取变化；页面负责手势合并后的历史提交。
- 草稿提交/丢弃、自动排叉与自动完成已从页面迁出规则计算；页面执行计划并保留原时序。它们没有改成每格一次独立磁盘事务。
- 生命变化展示、计时器、页面暂停、教程覆盖、提示翻译、音效和高亮执行器仍属于产品/显示层。
- 无界面模块可独立执行上述动作；真实产品页面对普通输入使用同一纯规则计划，对付费工具/提示/复活/赠命走事务用例。两条执行路径共享规则而不共享动画实现。

新增动作仍应明确输入、规则结果、消费/奖励、历史和恢复点。普通动画动作不承诺进程在任意动画帧退出都恢复到那一帧；成功业务事务保证对应结果及消费一起恢复，普通对局进度以最后成功检查点为准。不要让新工具改另一套棋盘、旧手势继续改独立格子字段。

## 5. Block Probe 验证了什么

路径：`scripts/examples/block/domain/block_probe_module.gd`。

它实现固定方块队列的放置、越界/重叠拒绝、同时消行消列、计分与结束判断。快照是 `occupied + pieces + piece_index + score`；动作是 `place`。它没有引用 Doku 的 BoardState、CellState、HintEngine、题库或页面。

`test_round_service.gd` 将 Doku 与 Block 注册到同一个未修改的宿主、使用同一个真实 LocalCoreStore，验证非法放置不推进请求、合法放置清行、分数与结束状态保存、重启恢复、结算奖励只发一次，以及两个命名空间互不覆盖。这比空接口或只创建一个 Block 类更能证明边界可复用。

现已增加独立可交互页面（`scripts/examples/block/`），支持点击/拖放、合法位置预览、清行、新局、读取与领取；通过 `python3 tools/run_block_example.py` 运行，使用独立产品和存档。示例还验证旧拖拽不能落到新局或下一块。它尚不包含商业 Block 的随机出块、三格托盘或难度策略，也没有实现交换三消的连锁表现。使用与测试见 [框架使用指南](framework-usage.md)。

## 6. 换成 Block 或交换三消时的实际工作

可以保留：LocalCoreStore、RoundService、库存事务、请求重试、内容发布/冻结机制，以及适用的产品菜单、设置、广告入口和基础 UI 管理。

需要新增或替换：

1. 玩法自己的状态模型、动作、规则与快照校验。三消需要交换合法性、匹配、掉落、补充和连锁结果；Block 需要形状、托盘与消行规则。不要为了适配 Doku 的 CAT/MARK 状态而扭曲这些模型。
2. 相应模块的五个契约方法，以及自己的存档 schema/旧版本迁移策略。
3. 内容结构与关卡解析器。复用资源定位和发布基础设施，不复用 Doku 的区域题库规则。
4. 自己的输入适配器、棋盘视图和对局页面。可以复用按钮等组件，但不要求强行共用 BaseGamePage。
5. 产品装配：注册模块、路由到页面、注入价格/奖励/难度政策、定义恢复与结束体验。不要在通用 RoundService 中新增 `if gameplay == "doku"`。
6. 至少一组独立规则测试和一组跨存档恢复测试，再补对应玩法的真实页面验证。

这是一套能承载第二玩法的基础边界，不是“只换配置就能把 Doku 变成三消”的承诺。可复用部分应随着第二玩法的真实需求验证后增长，而不是提前加入所有玩法都可能用到的字段和生命周期。

## 7. 验证入口

不要直接用主工程启动验证脚本；主工程 autoload 会读写日常存档。使用隔离运行器：

```bash
python3 tools/run_validation.py \
  --script res://tools/validation/test_doku_board_state.gd \
  --script res://tools/validation/test_doku_board_view.gd \
  --script res://tools/validation/test_doku_actions.gd \
  --script res://tools/validation/test_doku_hint_service.gd \
  --script res://tools/validation/test_doku_tools.gd \
  --script res://tools/validation/test_round_service.gd \
  --script res://tools/validation/test_doku_level_selection.gd
```

运行器复制工程及导入缓存，并仅在临时副本中重定向用户数据。业务规则测试覆盖语义，视图测试覆盖兼容信号/显示，存档测试覆盖失败不发布与重试。无界面通过不等于美术演出已完成人工验收；动画节奏与触控体验仍需要正常交互检查。
