# Game Page 精读 — 三大系统的汇聚点

> 文件：
> - [scripts/module/game/view/game_page.gd](../../scripts/module/game/view/game_page.gd) — 正式关卡的 Game Page
> - [scripts/module/game/view/base_game_page.gd](../../scripts/module/game/view/base_game_page.gd) — 所有游戏页面的公共基类
>
> `GamePage extends BaseGamePage extends UIFrameWindow`。这两个文件是规则引擎（QueendokuCore）、输入系统（GestureRecognizer + CellAction）和棋盘渲染（BoardView）的**交汇点**。Game Page 不自己做判断——它负责**协调**：接收输入、调用规则引擎、更新渲染、管理状态。
>
> **前置阅读**：[核心玩法系统精读](02-core-gameplay-systems.md) → [输入系统精读](03-input-system.md)

---

## 文件定位

```
GamePage (2400+ 行)
  extends BaseGamePage (4000+ 行)
    extends UIFrameWindow
```

`BaseGamePage` 是所有游戏页面（Normal 正式关卡、Daily 每日挑战）的公共基类——共享输入系统、棋盘验证、撤销栈、提示引擎。`GamePage` 是正式关卡的具体实现——加了 Normal 特有的入場动画、Toast、每日首局降档、残局快照等逻辑。

本文不覆盖全部 6400+ 行，而是聚焦**架构胶水层**——怎么把输入系统、规则引擎、棋盘渲染连起来。

---

## 架构全景

```
                    ┌─────────────────────────────────┐
                    │          Game Page               │
                    │  ┌─ _consume_board_actions()     │
                    │  │  消费 CellAction[]            │
                    │  │  调 _board_view.set_cell_state│
                    │  │  执行震动/撤销记录              │
                    │  └─ _validate_board()            │
                    │     调 QueendokuCore.is_complete │
                    │  ┌─ 管理命数、撤销栈、连击         │
                    │  └─ 通关/失败流程                 │
                    └──────┬──────────┬────────────────┘
                           │          │
              ┌────────────┘          └──────────────┐
              ▼                                      ▼
  ┌─────────────────────┐              ┌──────────────────────┐
  │  输入系统             │              │  规则引擎              │
  │  GestureRecognizer   │              │  QueendokuCore        │
  │  + Scheme + Operation│              │  .classify_violation  │
  │  → CellAction[]      │              │  .find_conflicts      │
  └─────────┬────────────┘              │  .is_complete         │
            │                           │  .cells_excluded_by_cat│
            ▼                           └───────────┬────────────┘
  ┌─────────────────────┐                          │
  │  BoardView (渲染层)   │◄── _board_view.set_cell_state() ──┘
  │  存储棋盘状态         │── _board_view.get_board() ────────►
  │  发射触摸信号         │── _board_view.get_cell_state() ───►
  └─────────────────────┘
```

**棋盘状态的真源在 BoardView**。QueendokuCore 和 Game Page 都是无状态的——每次操作从 BoardView 读取最新状态、做计算、写回 BoardView。

---

# 第一篇：连接输入系统

## `_ready()` — 信号接线

```gdscript
_board_view.cell_drag_start.connect(_on_board_cell_drag_start)
_board_view.cell_drag_over.connect(_on_board_cell_drag_over)
_board_view.cell_drag_end.connect(_on_board_cell_drag_end)
```

BoardView 是棋盘渲染层——它捕获用户的触摸事件，emit 三个信号。Game Page 接收这三个信号，转发给 GestureRecognizer。

BoardView 不负责「手势怎么解释」——它只负责「触摸事件发生了，坐标在这里」。解释了「这个触摸是什么意思」是 GestureRecognizer 的工作。

## `_on_board_cell_drag_start(pos)` — 手指按下

```gdscript
func _on_board_cell_drag_start(pos: Vector2) -> void:
    _ensure_input_system()
    _reset_idle_hint()

    var sc: Vector2i = _board_view.pointer_to_cell(pos.x, pos.y)
    var sc_state: int = _board_view.get_cell_state(sc.y, sc.x)

    # 守卫条件：游戏已通关？错误动画中？按在 ERROR/LOCKED_MARK 上？
    if _is_complete or _wrong_guess_pending or (...):
        return

    _consume_board_actions(_gesture_recognizer.on_drag_start(pos))
```

**守卫条件（Guard Clauses）**：在做任何事之前先检查「现在能做操作吗？」。游戏已通关、正在播错误动画、按在锁定的格子上——直接 return，不产生任何 CellAction。

`_ensure_input_system()` — 懒初始化输入系统：

```gdscript
func _ensure_input_system() -> void:
    if _normal_scheme == null:                           # ← 只创建一次
        _normal_scheme = BoardInputScheme.create_normal(_board_view)
        _draft_scheme = BoardInputScheme.create_draft(_board_view)

    var want_guard: bool = ABTestManager.swipe_protect.is_enabled()
    # 根据 AB 配置决定用哪种 GestureRecognizer
    if want_guard:
        _gesture_recognizer = SwipeGuardRecognizer.new(_board_view)
    else:
        _gesture_recognizer = BoardGestureRecognizer.new(_board_view)
    _gesture_recognizer.active_scheme = _normal_scheme  # ← 初始是 Normal 模式
```

**`ensure` 命名约定**：保证某个东西存在——如果不存在就创建，存在就不动。

**`_normal_scheme` 和 `_draft_scheme` 是「模式」的两种预设**——切换模式只需要改 `_gesture_recognizer.active_scheme`：

```gdscript
# 进入草稿模式
_gesture_recognizer.active_scheme = _draft_scheme

# 退出草稿模式
_gesture_recognizer.active_scheme = _normal_scheme
```

---

## `_consume_board_actions(actions)` — CellAction 的消费者

这是**从输入到渲染的最后一公里**：

```gdscript
func _consume_board_actions(actions: Array[CellAction]) -> void:
    if actions.is_empty():
        return
    var applied: bool = false
    for a: CellAction in actions:
        if _board_view.is_cell_input_locked(a.row, a.col):   # ← 格子被锁了？
            continue

        if a.kind == CellAction.Kind.DOUBLE_TAP:
            _consume_double_tap(a.row, a.col)                # ← 双击：特殊处理
            applied = true
            continue

        if a.kind == CellAction.Kind.SET_DRAFT:
            _set_cell_draft(a.row, a.col, a.state)           # ← 草稿：写入草稿层
            continue

        if _board_view.get_cell_state(a.row, a.col) == CellState.DRAFT_CAT:
            continue                                         # ← DRAFT_CAT 不处理

        if a.record:
            _record_cell_change(a.row, a.col, a.before, a.state)  # ← 记入撤销栈

        _board_view.set_cell_state(                          # ← ★ 真正修改棋盘
            a.row, a.col, a.state,
            a.play_anim, a.show_cat_visual, a.source
        )
        if a.vibrate >= 0:
            VibrateManager.play_vibrate(a.vibrate)           # ← 执行震动

        applied = true

    if applied:
        _validate_board()        # ← 检查通关！
        _update_remaining()      # ← 更新"已放猫数/总数"
```

### CellAction 的每个属性最终都落在了什么地方

| CellAction 属性 | 消费方 |
|---|---|
| `kind` | 决定走哪个分支（DOUBLE_TAP / SET_DRAFT / SET_STATE） |
| `row`, `col` | `_board_view.set_cell_state(r, c, ...)` |
| `before` | `_record_cell_change(r, c, before, after)` — 记入撤销栈 |
| `state` | `_board_view.set_cell_state(..., state, ...)` |
| `play_anim` | `_board_view.set_cell_state(..., play_anim, ...)` |
| `vibrate` | `VibrateManager.play_vibrate(vibrate)` |
| `record` | 控制是否记入 `_record_cell_change` |
| `source` | `_board_view.set_cell_state(..., ..., ..., source)` — 追踪变更来源 |

**这正是命令模式的完整闭环**：Operation 生产 CellAction 命令 → Game Page 消费命令 → BoardView、VibrateManager、撤销栈响应。

---

# 第二篇：连接规则引擎

## `_validate_board()` — 每步后的通关检查

```gdscript
func _validate_board() -> void:
    if _is_complete or _puzzle.is_empty() or not _puzzle.has("regions"):
        return
    var sz: int = _level_config.get("size", 4)
    if QueendokuCore.is_complete(_board_view.get_board(), sz, _puzzle["regions"]):
        _on_game_complete()
        return

    # ... 草稿模式自动提交检查（略）...
```

每次棋盘状态改变后都调用。三个参数的来源：

| 参数 | 来源 | 含义 |
|---|---|---|
| `board` | `_board_view.get_board()` | 从渲染层读出当前棋盘状态 |
| `size` | `_level_config["size"]` | 关卡配置中的棋盘大小 |
| `regions` | `_puzzle["regions"]` | 题目的颜色区域图 |

注意：`QueendokuCore` 不存任何棋盘状态——它**每次**从 BoardView 读出最新数据再判断。这种无状态设计让撤销、重做、复盘都很容易实现——只需要操作 BoardView 的状态即可。

## `_try_emit_rule_violation(r, c)` — 违规检测

```gdscript
func _try_emit_rule_violation(r: int, c: int) -> void:
    var regions: Array = _puzzle["regions"]
    var sz: int = _level_config.get("size", 4)
    var placed: Array = []
    var board: Array = _board_view.get_board()

    # 收集所有已存在的猫
    for rr in range(sz):
        for cc in range(sz):
            if board[rr][cc] == CellState.CAT:
                placed.append(Vector2i(rr, cc))

    # 调用规则引擎
    var rule: int = QueendokuCore.classify_violation(r, c, placed, regions)
    if rule != QueendokuCore.Rule.NONE:
        _on_rule_violated(rule)
```

**调用链**：`do_wrong_guess_mark` → `_try_emit_rule_violation` → `QueendokuCore.classify_violation` → `_on_rule_violated` → `_play_rule_highlight(rule)`

`_play_rule_highlight` 在违规时高亮对应的规则图标（同行、同列、相邻、同色）——用 Tween 做闪烁动画。

## `_play_wrong_guess_cat_feedback(r, c)` — 冲突猫的沮丧动画

```gdscript
var bad: Array[Vector2i] = QueendokuCore.find_conflicting_cats(r, c, placed, regions)
if not bad.is_empty():
    _board_view.play_cat_frustrated_at(bad)
```

不是让所有猫都沮丧——只让**和新猫冲突的那几只**沮丧。`find_conflicting_cats` 精准找出谁和谁冲突了。

## `_auto_mark_prefill_cats()` — 预填猫的自动标叉

```gdscript
for pos in _level_config.get("prefill_positions", []):
    var cat := Vector2i(pos[0], pos[1])
    if _board_view.get_cell_state(cat.x, cat.y) == CellState.CAT:
        _spread_auto_cross(
            cat, 0.0, QueendokuCore.cells_excluded_by_cat(cat, sz, _puzzle["regions"])
        )
```

预填的猫出现后，调 `QueendokuCore.cells_excluded_by_cat` 算出「因为这只猫的存在，哪些格子不能再放猫」，然后逐个标 `LOCKED_MARK`——玩家看到这些格子被锁定就知道「这些地方不用想了」。

---

# 第三篇：双击和错误操作

## `_consume_double_tap(r, c)` — 双击的执行

```gdscript
func _consume_double_tap(r: int, c: int) -> void:
    var cur: int = _board_view.get_cell_state(r, c)
    if cur == CellState.CAT:
        return                              # ← 猫上双击，忽略

    var original_before: int = consume_prior_tap_before(r, c, cur)
    var is_cat: bool = _is_solution_cell(r, c)    # ← ★ 查标准答案

    if is_cat:
        do_place_cat(r, c, original_before)       # ← 放猫
    else:
        do_wrong_guess_mark(r, c, original_before) # ← 标叉 + 扣命
```

**`_is_solution_cell(r, c)`** — 判断一个格子是不是正确答案：

```gdscript
func _is_solution_cell(r: int, c: int) -> bool:
    var sol: Array = _puzzle.get("solution", [])
    return bool(sol[r][c])
```

`_puzzle["solution"]` 是二維布尔数组——`solution[r][c] == true` = 这一格是猫的正确位置。

**关键**：`_puzzle["solution"]` 在 `on_show()` 时从题库中取出（见 `_setup_entry_normal`），存在 `_level_config` 和 `_puzzle` 两个字典里。这个数据贯穿整个游戏——所有「正确/错误」的判断都依赖它。

## `do_wrong_guess_mark(r, c, ...)` — 错误操作的处理

```gdscript
func do_wrong_guess_mark(r: int, c: int, original_before: int) -> void:
    _record_cell_change(r, c, original_before, CellState.MARK)
    _board_view.set_cell_state(r, c, CellState.MARK)
    VibrateManager.play_vibrate(LEVEL3)          # ← 错误震动（比正确弱）
    _try_emit_rule_violation(r, c)              # ← 检查违了什么规则
    _on_wrong_guess(r, c)                       # ← 扣命 + 动画
```

## `_on_wrong_guess(r, c)` — 错误的完整响应

```gdscript
func _on_wrong_guess(r: int, c: int) -> void:
    _mistake_count += 1
    _wrong_guess_pending = true                   # ← 锁住后续输入
    _combo_count = 0                              # ← 连击中断

    _lives = maxi(_lives - 1, 0)                  # ← 扣一条命

    _board_view.play_error_feedback(r, c)         # ← 错误动画

    if _lives <= 0:
        _board_view.play_cat_cry_loop_all()       # ← 所有猫哭
        UIManager.block_input_briefly(self, 2.0)  # ← 冻结输入 2 秒

        get_tree().create_timer(0.6).timeout.connect(
            func() -> void: _on_game_over()       # ← 游戏结束
        )
    else:
        _play_wrong_guess_cat_feedback(r, c)      # ← 冲突猫沮丧动画

    _animate_heart_lost(lost_index)               # ← 红心破碎动画

    # 0.4 秒后解除锁
    get_tree().create_timer(0.4).timeout.connect(
        func() -> void:
            _update_remaining()
            _wrong_guess_pending = false
    )
```

**时间线**：

```
t=0     错误的猫被放置
         → _wrong_guess_pending = true（输入锁住）
         → 棋盘播错误动画
         → 红心破碎动画
         → 如果还有命：冲突猫播沮丧动画

t=0.4s  _wrong_guess_pending = false（解锁输入）

t=0.6s  如果 _lives == 0：_on_game_over()
```

---

# 第四篇：通关流程

## `_on_game_complete()`

```gdscript
func _on_game_complete() -> void:
    _is_complete = true
    _clock_timer.stop()
    _exit_draft_mode_and_clear()
    _destroy_banner()

    Tracker.track_game_end(_build_game_end_params(GameResult.WIN))

    SoundManager.stop(SoundManager.Kind.MARK_CAT)
    _board_view.replay_all_cat_appear()        # ← 所有猫重播入场动画
    VibrateManager.play_vibrate(LEVEL5)        # ← 最强震动

    _cleanup_hint()
    await get_tree().process_frame

    var lv: int = _level_config.get("level", 0)
    GameState.on_level_won(lv)                 # ← 持久化：记录通关

    await _play_win_toast_and_wait()           # ← Toast："猫咪们都在正确的位置！"
    UIManager.show_ui(UiName.WIN, ...)         # ← 显示胜利页面
```

---

# 完整数据流

```
用户手指触摸
    │
    ▼
BoardView 发射 cell_drag_start 信号
    │
    ▼
Game Page._on_board_cell_drag_start(pos)
    │  ├─ _ensure_input_system() → 创建/复用 GestureRecognizer
    │  └─ 守卫条件（已通关？动画中？...）
    │
    ▼
_gesture_recognizer.on_drag_start(pos)
    │  ├─ _resolve_cell(pos) → 屏幕坐标 → (r, c)
    │  ├─ 双击检测
    │  └─ active_scheme.tap_op.on_tap(r, c, stroke)
    │      → 返回 CellAction[] 或 []
    │
    ▼
_consume_board_actions(cell_actions)
    │  ├─ [DOUBLE_TAP]  → _consume_double_tap()
    │  │    ├─ _is_solution_cell() → 查标准答案
    │  │    ├─ do_place_cat() or do_wrong_guess_mark()
    │  │    └─ → _on_wrong_guess() [如果错了]
    │  │
    │  ├─ [SET_DRAFT]   → _set_cell_draft()
    │  │
    │  └─ [SET_STATE]   → _board_view.set_cell_state()
    │       ├─ VibrateManager.play_vibrate()
    │       └─ _record_cell_change() [记入撤销栈]
    │
    ├─ _validate_board()
    │    └─ QueendokuCore.is_complete() → _on_game_complete() [如果通关]
    │
    └─ _update_remaining() → 更新"已放猫数/总数" UI
```

---

# 设计精华

| 设计决策 | 为什么 |
|---|---|
| BoardView 是棋盘状态的唯一真源 | QueendokuCore 和 Game Page 都不存棋盘状态——只从 BoardView 读写 |
| `_consume_board_actions` 是 CellAction 的唯一消费入口 | 所有操作（无论来源）都经过同一条管道——震动、撤销、验证统一执行 |
| `_validate_board` 在每次操作后无条件调用 | 每步都检查是否通关——不漏判 |
| `_wrong_guess_pending` 锁住输入 | 错误动画播放期间不让玩家操作——防止连点导致状态混乱 |
| `_puzzle["solution"]` 是二維布尔数组 | 对错判断的最终依据——O(1) 查表 |
| `_ensure_input_system` 懒初始化 | 输入系统只在第一次触摸时创建——不是 `_ready` 时 |
| GestureRecognizer 通过 `active_scheme` 切换模式 | Normal ↔ Draft 切换只改一行赋值 |
| `_record_cell_change` + 撤销栈 | 每一步操作都有 before/after——撤销就是反向执行 |

---

# 本篇学到的全部概念

| 概念类别 | 具体学到的 |
|---|---|
| 架构模式 | Game Page 作为协调者——不自己做判断，调规则引擎和渲染层 |
| 数据流 | 触摸 → BoardView 信号 → GestureRecognizer → CellAction[] → _consume_board_actions → BoardView + Vibrate + 撤销栈 |
| 守卫条件 | `_is_complete` / `_wrong_guess_pending` — 状态锁防止重复操作 |
| 懒初始化 | `_ensure_input_system()` — 只创建一次，首次触摸时才初始化 |
| 状态管理 | BoardView 是真源——QueendokuCore 和 Game Page 都是无状态的 |
| 异步流 | `_on_wrong_guess` 中的定时器链——0.4s 解锁、0.6s Game Over |
| 撤销栈 | `_record_cell_change(before, after)` + `_commit_current_step()` |
| 二維布尔数组 | `_puzzle["solution"][r][c]` — O(1) 查表判对错 |
| Tween 动画 | `_animate_heart_lost` / `_play_rule_highlight` — 属性动画 |
