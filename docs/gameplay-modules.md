# 玩法模块与对局业务边界

当前实现将 Meowdoku 1.22 的选题、输入、Mouse、草稿、颜色挑战、金鱼关、评分和每日残局接入了原框架的候选状态与事务边界。产品玩法仍是 Doku；公共宿主只负责对局身份、请求顺序、库存与提交，不解释猫、区域、Elo 或实验组。

代码按职责放在 `products/meowdoku/gameplay/`：`domain` 是独立规则，`application` 是本产品用例与策略，`content` 负责题库合同，`presentation` 负责输入、页面与演出。`application` 并非整个目录都纯：`LevelSelector` 的入口负责捕获 GameState、内容与 AB，具体选择则在显式注入的候选状态中执行。产品存档与平台装配在 `products/meowdoku/app/`，跨玩法设施在 `scripts/framework/`。

## 1. 活棋盘、可恢复快照与演出

| 数据 | 位置 | 职责 |
| --- | --- | --- |
| 当前棋盘 | `DokuBoardState` | 唯一活模型；CellView 读取绑定的同一模型 |
| 已提交对局 | `LocalCoreStore.round_services["doku/main" 或 "doku/daily"]` | 棋盘、生命、历史、提示凭证、评分与最后回执 |
| 产品残局镜像 | `endgame.snapshot` / `endgame.daily_snapshot` | 兼容页面恢复，并携带业务局号、冻结题面和策略 |
| 手势、覆盖层、动画 | 输入槽、BoardView、CellView、页面 | 临时交互与显示，不是另一份权威存档 |

普通画叉等手势可以先更新活模型，在检查点保存。事务动作从活模型捕获 `runtime_snapshot`，将已发生的普通进度一并放入候选；成功后才接受回执、消费库存并呈现结果。Mouse 的逐格动画不是逐格交易：目标棋盘、评分与消费先完整提交，动画被隐藏或销毁不会留下“已扣费但只恢复半个动作”的状态。

`runtime_snapshot` 是本地页面适配接口，不是外部客户端可以上传权威棋盘的网络协议。这里不包含服务端防作弊或跨设备分布式事务。

## 2. 纯领域模块

### 棋盘与动作规则

`domain/doku_board_state.gd` 不访问节点、单例、时钟或存档。它负责格值、输入锁、改叉与曾经犯错的追踪；需要时间时由调用者传入时间戳。读取返回副本，恢复先完整校验。

`restore_board` 用于建立恢复基线；`apply_committed_board` 用于接受本局已提交动作，保留仍有效的追踪与临时输入锁。`clear_input_locks` 只清临时锁，不清棋盘、历史或模型版本。BoardView 的 `refresh_from_model` 只重画，不再次触发落子、计分或消费；`present_cell_transition` 保留相应震动、区域高亮、格子和猫动画。

CellView 在独立演示或预热时使用自己的 1×1 模型。真正 `setup` 后才绑定有效尺寸的共享棋盘；预热 12×12 个视图不会把它们绑定到尺寸为 0 的模型。非法题面在模型和页面入场前都被拒绝。

`domain/doku_action_rules.gd` 返回点按、画叉、猜猫、草稿提交和自动完成等计划。它不播动画、不扣库存。草稿一次提交的致命分支与 1.22 一致：若错误数足以耗尽剩余生命，只执行实际扣命的错误格，正确猫和叉不转正；复活时页面将相应错误格回滚作为同一次复活事务的运行时输入。无限命与大于 3 的生命上限由快照保存，不能套用旧版固定三命假设。

### 提示、定位、Mouse 与草稿

`domain/doku_hint_service.gd` 复用 `HintEngine` 的规则顺序，包含 1.22 的颜色排除、R3b/R4b 反向集合锁定。是否启用由本局冻结的 `hint_func` 决定。提示的逻辑结果不包含翻译或 UI 节点；页面可复制结果补充文案、颜色与高亮，不能替换已保存的原始提示凭证。

| 动作 | 领域结果 | 事务与表现 |
| --- | --- | --- |
| `request_hint` | 提示与绑定局号、请求序号、棋盘版本的凭证 | 成功打开一次计费一次；失败不替换旧凭证 |
| `apply_hint` | 凭证对应的棋盘变化 | 不二次收费；旧棋盘版本或旧凭证被拒绝；已应用结果可幂等重放 |
| `locate` | 未完成答案格与变化 | 无候选返回已受理的 `no_effect` 回执，按原版计次；存储失败仍是失败 |
| `mouse` | 注入 RNG 选择的目标列表、前后值及最终棋盘 | 全部目标、库存、步数和分数同次提交；页面按目标顺序演出 |
| `activate_draft` | 本局 `draft_active=true` | 每次进入草稿收费；已激活不能重复扣费 |
| `draft_clear` / `draft_commit` | 丢弃或提交草稿并关闭激活状态 | 退出统计、耗时与结果同次提交；再次进入是新的使用 |

`HintOverlay` 显示说明并发出应用/关闭/详情信号；提示高亮执行器负责演出。`MouseToolSelector` 在领域层，只使用传入棋盘、答案、区域与 RNG。

当前 1.22 页面使用 Mouse 和草稿等入口。旧 `undo`、轴打叉等纯动作/API 作为兼容和独立规则测试保留，不代表当前页面仍提供旧版撤销按钮。兼容 `undo` 仍先查可撤销历史，再决定收费；不能用它的规则替代 Mouse。

### 评分、步数与通关奖励

`domain/doku_round_performance.gd` 把 1.22 评分公式投影为可保存的普通数据：

```text
performance = score, combo, max_combo, se_count, se_last_step,
              step_used, tool_used, draft_elapsed_ms
```

猫的基础增分随连击从 576 开始，每档增加 96，上限 1440；步数档位奖励按冻结的 `score_encourage`、棋盘尺寸和实际步数差计算。草稿提交保留多猫均摊步数的语义。Mouse、定位、提示应用的步数和工具次数在动作提交时记入，动画监听器只消费 `score_events` / `combo_events`，不会再次加分或把总分回退到中间格。

`win_bonus(board, policy, perfect, full_hp, draft_used)` 产生通关补叉与奖励计划。`auto_x_fill_variant` 决定是否补叉及瞬间/逐格表现；`win_encourage_variant` 决定完美或满命奖励。页面 `_win_business_runtime()` 在结算前投影最终棋盘和分数，结算成功后 `_accept_win_bonus()` 接受一次，补叉动画仅显示已提交结果。保存失败不会推进关卡或发布奖励；同一结算标识重试不会再次加分。

`DokuRoundModule` 组合上述规则，负责题面、生命、历史、performance 的校验，维护 `board_revision`、草稿状态、提示凭证与结算条件。它不持有页面或 GameState。

## 3. 冻结策略与候选选题

`application/meowdoku_gameplay_policy.gd` 保存 `schema=1, rules_revision=122` 的规则快照，包含草稿、Mouse、提示、生命、评分、通关补叉、多触点、双击与滑动解释等值。旧兼容字段不等于重新启用旧版 UI。完整快照直接复用；旧快照缺少新增字段时仅补兼容缺项，保留已有冻结值。

输入解释器由冻结值构造为局部实例，不调用会写调试存档、切换实验组或发全局信号的 `set_debug_override()`。开局后切换实时 AB 不会改变本局单触点/多触点、双击保护、滑动解释或 Mouse 资格。纯输入识别器通过注入的高频重置回调工作，不直接重置全局 AB 配置对象。视觉实验可以按表现时机读取；当天广告资格等动态业务条件仍在事务中核验。

选题相关代码位于 `application/selection/`：

1. `LevelSelector.create_entry_state()` 捕获初始状态与内容代次。`DokuSelectionState` 保留独立的原始候选、可变候选及相关字段读取记录。
2. `DokuSelectionRuntime` 注入候选状态、局部 RNG、冻结配置解释器、时间、日期与推荐队列副本。各 NL 策略、预填猫、颜色和金鱼选择均在该环境中运行，不直接推进 live GameState。
3. `select_from_candidate()` 接受页面已准备的候选，避免前置入场变化被另一次 live 快照覆盖。重试、恢复、每日和调试题通过 `prepare_existing_entry()` 形成同类计划；`refresh_plan_state()` 纳入后续入场准备结果。
4. 计划携带读取依赖、前后差异、内容/推荐代次、冻结策略、唯一选择标识及待发布效果。选择过程不写盘、不实际出队。
5. 棋盘建立成功后，`LevelData.stage_selected()` 在候选中校验并合并选择结果，随后与初始 RoundService 记录一次提交。相关字段或代次冲突会拒绝旧计划；不相关统计变化不会盲目覆盖。

主线、新颜色/金鱼插入关、每日和 preview 各有入场语义。每日使用独立残局和统计槽，恢复保留身份与计数；新局清理本模式局内计数，重开只重置本轮步骤、不删除累计步骤。preview 不覆盖主线或每日残局。固定关卡表优先于随机算法；恢复使用保存的题面与策略，不重新取当前内容。

推荐队列的消费与 `delivered_qids` 一起写入候选的 `features.recommendation.queue`，随对局建立提交，不采用“开局成功后再单独 ack”的两次写盘。辅助玩家标签刷新与无效推荐报告由产品注入的 `publish_selection_effects(plan, guard)` 在成功提交后执行；相同选择标识不重复发布，重置或新选题造成代次变化时停止旧效果。标签缓存与异步回包同样绑定存档代次。已持久确认的辅助玩家在冷启动首局仍生效，未知标签的刷新结果影响后续捕获的上下文。

特殊关表统一通过 `SpecialProvider.levels_for(runtime)` 读取；未提供覆盖时使用内置表，显式空表表示删除全部特殊关。回流、推荐、困难关交替与实际取题使用同一冻结表，不能一个分支读内置常量、另一个读下载内容。1.22 的压缩题库在读取 API 边界解码，JSON 发布使用物化数组；内容、provider 和排序缓存按内容代次失效，不用文件数量推测内容是否变化。

开发诊断入口同样必须消费计划。`fastjump` 将选题、候选 Elo 事实与胜负进度合并提交；模拟器将候选游标、去重记录、重试题和概率胜负合并提交，保存失败立即停止。模拟器留空尺寸覆盖时使用当前 1.22 策略，明确输入时才按 `size_cycle` 尺寸表对照；它只模拟胜负、脏标记和去重，不生成 Elo 计分事实。缓存重试保留题目身份与冻结策略。兼容的 `GameState.on_level_won/failed(..., selection_plan)` 返回提交是否成功，并按选择标识防止同一诊断结果重复推进；正式对局仍使用带局号校验的结算入口。

## 4. RoundService 与产品端口

公共宿主位于 `scripts/framework/application/round_service.gd`，只理解命名空间、局号、请求序号、库存增减和存储提交。模块提供：

| 方法 | 职责 |
| --- | --- |
| `create_snapshot(context)` | 校验开局数据并创建领域快照 |
| `validate_snapshot(snapshot)` | 校验可恢复数据 |
| `sync_runtime(snapshot, runtime)` | 验证并合并本地活模型进度 |
| `apply_action(snapshot, kind, payload, call_context)` | 返回新快照、结果、表现数据和库存差值 |
| `settle_snapshot(snapshot, payload)` | 验证终局并计算领域奖励 |

成功结果以 `ok/snapshot/result/changes/inventory_delta` 表示；失败返回 `ok=false/error`，宿主不发布候选。可持久化值不能夹带 Node、Callable 或 Signal。

存储端口提供 `is_open()`、`revision()`、`snapshot()` 与 `commit(candidate, expected_revision)`。实际产品使用 `MeowdokuRoundSession.ProductPort`：它将工具事实、评分统计、复活次数、DDA/dirty、残局镜像与对局记录合并后提交。免费成功使用仍按 1.22 计当日工具次数和相关脏标志；`has_used_tool` 则沿用旧统计定义，只对真正付费的旧工具设置，不能混同这两个事实。

`MeowdokuRoundSession` 接收普通 Object 端口，不依赖 Node 生命周期。端口提供 `is_storage_ready/get_core_store/get_core_candidate/commit_core_candidate`；有选题计划时额外提供 `stage_round_selection(candidate, plan, checkpoint)`。此注入方法由 GameState 装配 LevelData 与内容版本，Session 不直接加载 ContentContext 或 LevelData。独立内存适配器因此可以测试动作事务。

产品结算通过 `MeowdokuRoundSettlement.stage()` 修改候选。1.22 进度、Elo 和新玩法结算由注入的 `progress_stager` 处理，通用幂等外壳继续保护主线推进、奖励、每日完成日期和残局清理。纯结算模块不静态加载整个 GameState。

请求顺序与恢复合同：

- `doku/main`、`doku/daily` 等命名空间各保存当前一局；同题重开仍有新业务局号，恢复才沿用保存局号。
- 动作序号递增；提交失败可以用原序号重试。同序号同动作同参数返回原回执，改参数或更旧序号被拒绝。
- 新局后旧局延迟请求失效；同一终局标识重复结算不会再次发奖励。
- `duplicate=true` 用于恢复已提交结果，不触发第二次计分、消费或整段动画。
- 页面隐藏、销毁或重新入场会使旧表现代次失效；付费结果已提交时仍然保留。输入临时锁、遮罩所有权和静音作用域必须随对应演出释放。

普通进度恢复到最后一次成功检查点；成功业务事务则保证其完整结果、消费与评分一起恢复。框架没有承诺任意普通手势动画帧都立即写盘。

## 5. 第二玩法能复用什么

Block Probe 位于 `scripts/examples/block/`，提供独立规则与可交互页面，验证放置、越界/重叠、消行列、计分、恢复和幂等奖励。它使用相同 RoundService 与 LocalCoreStore，不引用 Doku 棋盘、题库或提示引擎。

换成 Block 或三消时，可以保留事务存储、局号、重试、内容发布与适用的基础 UI；需要自己的状态、动作、快照校验、输入、棋盘视图、规则与产品装配。三消的掉落/连锁不应伪装为 Doku 格子状态，公共宿主也不应增加按具体游戏名称分支的逻辑。可复用边界已经可运行，但不等于仅换配置就获得另一款完整商业游戏。

## 6. 验证入口与限制

不要直接在主工程运行验证脚本，autoload 会访问日常存档。使用隔离运行器：

```bash
python3 tools/run_validation.py \
  --script res://tools/validation/test_doku_v122_contract.gd \
  --script res://tools/validation/test_doku_v122_selection_matrix.gd \
  --script res://tools/validation/test_game_v122_transaction.gd \
  --script res://tools/validation/test_game_input_lifecycle.gd \
  --script res://tools/validation/test_game_operation_lifecycle.gd \
  --script res://tools/validation/test_game_entry_transaction.gd
```

运行器复制工程和缓存，仅在临时副本中重定向用户数据并关闭真实业务网络。选题矩阵覆盖 112 个启用的 normal_level 值；纯规则、失败注入、真实页面的多触点/遮挡/重入/演出销毁分别验证不同边界。断言通过之外还要检查脚本错误、资源泄漏和正常退出；无界面验证不替代设备上对动画节奏、触感和视觉的人工验收。
