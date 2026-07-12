# 输入系统精读 — 触摸 → 棋盘操作

> 文件：
> - [scripts/module/game/input/cell_action.gd](../../scripts/module/game/input/cell_action.gd) — 操作数据包（3 种 Kind + 3 个工厂方法）
> - [scripts/module/game/input/board_stroke_context.gd](../../scripts/module/game/input/board_stroke_context.gd) — 一次手势的状态
> - [scripts/module/game/input/board_gesture_recognizer.gd](../../scripts/module/game/input/board_gesture_recognizer.gd) — 手势 → 操作的协调者
> - [scripts/module/game/input/swipe_guard_recognizer.gd](../../scripts/module/game/input/swipe_guard_recognizer.gd) — 防误触层（继承 BoardGestureRecognizer）
> - [scripts/module/game/input/board_input_scheme.gd](../../scripts/module/game/input/board_input_scheme.gd) — 模式切换（Normal / Draft）
> - [scripts/module/game/input/operations/base_tap_operation.gd](../../scripts/module/game/input/operations/base_tap_operation.gd) — 点击操作基类
> - [scripts/module/game/input/operations/normal_tap_operation.gd](../../scripts/module/game/input/operations/normal_tap_operation.gd) — 正式模式点击
> - [scripts/module/game/input/operations/normal_swipe_operation.gd](../../scripts/module/game/input/operations/normal_swipe_operation.gd) — 正式模式滑动
> - [scripts/module/game/input/operations/normal_double_tap_operation.gd](../../scripts/module/game/input/operations/normal_double_tap_operation.gd) — 正式模式双击
> - [scripts/module/game/input/operations/draft_tap_operation.gd](../../scripts/module/game/input/operations/draft_tap_operation.gd) — 草稿模式点击
> - [scripts/module/game/input/operations/draft_swipe_operation.gd](../../scripts/module/game/input/operations/draft_swipe_operation.gd) — 草稿模式滑动
>
> 这 11 个文件构成了 Meowdoku 的**输入系统**——把用户的触摸手势翻译成棋盘操作意图。它不碰棋盘渲染、不碰状态存储，只负责「判断玩家想干什么」。
>
> **前置阅读**：[GDScript 七种根基抽象](00-gdscript-seven-abstractions.md) → [launcher.gd 精读](01-launcher-gd-walkthrough.md) → [核心玩法系统精读](02-core-gameplay-systems.md)

---

## 架构全景

```
用户手指触摸屏幕 (Vector2: 屏幕像素坐标)
       │
       ▼
┌─────────────────────────────────────────────┐
│  BoardGestureRecognizer                     │
│  ├─ _resolve_cell(pos)  → 像素坐标 → (r,c)  │
│  ├─ 双击检测（0.35s 内在同一格再按）         │
│  └─ 插值：手指快速滑动时填充中间跳过的格子    │
│                                             │
│  SwipeGuardRecognizer（子类）               │
│  └─ 覆盖 _resolve_cell → 防误触锁定         │
└─────────────────────────────────────────────┘
       │  委托给
       ▼
┌─────────────────────────────────────────────┐
│  BoardInputScheme（模式切换）                │
│  ├─ create_normal(board) → Normal*Operation  │
│  └─ create_draft(board) → Draft*Operation    │
└─────────────────────────────────────────────┘
       │  委托给
       ▼
┌─────────────────────────────────────────────┐
│  TapOperation / SwipeOperation /             │
│  DoubleTapOperation                          │
│  └─ 读取 board 当前状态，输出 CellAction[]    │
└─────────────────────────────────────────────┘
       │  返回
       ▼
 CellAction[]  ─── 交给 Game Page 执行
 （纯数据包：改变哪个格子的什么状态）
```

这是**策略模式 + 命令模式**的经典组合：
- **策略模式**：模式切换（Normal ↔ Draft）时只换 `BoardInputScheme` 里的三个 Operation 对象，手势识别逻辑完全不变
- **命令模式**：`CellAction` 是操作意图的数据包——输入系统只生产命令，不执行命令

---

# 第一篇：CellAction — 「对格子做什么」的数据包

## 全文

```gdscript
class_name CellAction
extends RefCounted

enum Kind {
    SET_STATE,
    DOUBLE_TAP,
    SET_DRAFT,
}

var kind: int = Kind.SET_STATE
var row: int = -1
var col: int = -1
var state: int = CellState.EMPTY
var before: int = CellState.EMPTY
var play_anim: bool = true
var show_cat_visual: bool = true
var record: bool = true
var vibrate: int = -1
var source: int = BoardView.ChangeSource.USER_ACTION


static func set_cell(
    r: int,
    c: int,
    before_state: int,
    target: int,
    vib: int = -1,
    do_record: bool = true,
    src: int = BoardView.ChangeSource.USER_ACTION
) -> CellAction:
    var a := CellAction.new()
    a.kind = Kind.SET_STATE
    a.row = r
    a.col = c
    a.before = before_state
    a.state = target
    a.vibrate = vib
    a.record = do_record
    a.source = src
    return a


static func double_tap(r: int, c: int) -> CellAction:
    var a := CellAction.new()
    a.kind = Kind.DOUBLE_TAP
    a.row = r
    a.col = c
    return a


static func set_draft(r: int, c: int, mark: int) -> CellAction:
    var a := CellAction.new()
    a.kind = Kind.SET_DRAFT
    a.row = r
    a.col = c
    a.state = mark
    return a
```

---

## 设计理念：为什么包一层？

这不是执行操作——它只是一个**数据包**。

```
CellAction.set_cell(3, 4, MARK, EMPTY, LEVEL2)

意思：「我要把第 3 行第 4 列从 MARK 改成 EMPTY，震动强度 2」
```

Game Page 拿到这个包之后自己去执行（包括动画、音效、撤销历史记录）。

**为什么不直接在 Operation 里改棋盘状态？** 解耦。输入系统不需要知道：
- 棋盘怎么渲染动画
- 状态变更怎么记入撤销历史
- 音效怎么播放

输入系统只负责「判断玩家想干什么」，输出一个意图包。Game Page 负责消费。

---

## 三个 Kind

```gdscript
enum Kind { SET_STATE, DOUBLE_TAP, SET_DRAFT }
```

| Kind | 值 | 含义 | 由哪个工厂方法创建 |
|---|---|---|---|
| `SET_STATE` | 0 | 改变格子状态（放猫/标叉/清空） | `set_cell()` |
| `DOUBLE_TAP` | 1 | 双击（快速填满一行） | `double_tap()` |
| `SET_DRAFT` | 2 | 草稿模式操作 | `set_draft()` |

---

## 属性详解

| 属性 | 类型 | 默认值 | 含义 |
|---|---|---|---|
| `kind` | int | `SET_STATE` | 操作类型 |
| `row` | int | -1 | 目标行号 |
| `col` | int | -1 | 目标列号 |
| `state` | int | `EMPTY` | 目标状态（要变成什么） |
| `before` | int | `EMPTY` | 操作前的状态（用于撤销） |
| `play_anim` | bool | true | 是否播放动画 |
| `show_cat_visual` | bool | true | 是否显示猫的视觉 |
| `record` | bool | true | 是否记入撤销历史 |
| `vibrate` | int | -1 | 震动强度（-1 = 不震动） |
| `source` | int | `USER_ACTION` | 变更来源（用户操作 / 系统 / 撤销 / 提示） |

`before` 是用来支持撤销的——撤销时需要用 `before` 恢复之前的状态。

`record` 控制这条操作是否进撤销栈。提示系统（Hint）做出的变更 `record = false`——不让玩家撤销提示。

`source` 追踪变更来源，用于统计和调试。`ChangeSource` 枚举定义在 `BoardView` 里：

| ChangeSource | 含义 |
|---|---|
| `USER_ACTION` | 玩家自己操作的 |
| `SYSTEM` | 系统自动（如预填） |
| `UNDO` | 撤销操作 |
| `HINT` | 提示系统 |

---

## 三个工厂方法

### `set_cell(r, c, before_state, target, vib, do_record, src)`

创建一个 SET_STATE 操作。参数最多（7 个），因为它是最常用的操作。

**默认参数**：

```gdscript
static func set_cell(r, c, before_state, target, vib = -1, do_record = true, src = USER_ACTION)
```

| 参数 | 默认值 | 何时覆盖 |
|---|---|---|
| `vib` | -1（不震动） | 手指当前所在的格子 → LEVEL2 |
| `do_record` | true | Hint 操作 → false |
| `src` | USER_ACTION | Undo → ChangeSource.UNDO |

调用方只需要关心前 4 个必填参数，后面 3 个有合理默认值。

### `double_tap(r, c)`

创建一个 DOUBLE_TAP 操作。只设 `kind`、`row`、`col`，其他属性保持默认值。Game Page 收到后自行决定「双击这一格意味着什么」。

### `set_draft(r, c, mark)`

创建一个 SET_DRAFT 操作。和 `set_cell` 的区别：不设 `before`、不设 `vibrate`——草稿模式不震动、不记入撤销历史（草稿是临时的）。

---

# 第二篇：BoardStrokeContext — 一次手势的状态

## 全文

```gdscript
class_name BoardStrokeContext
extends RefCounted

var start_cell: Vector2i = Vector2i(-1, -1)
var last_cell: Vector2i = Vector2i(-1, -1)
var target_state: int = 0
var target_pending: bool = false
var had_move: bool = false
var changed: bool = false
var wants_double_tap_window: bool = false


func reset() -> void:
    start_cell = Vector2i(-1, -1)
    last_cell = Vector2i(-1, -1)
    target_state = 0
    target_pending = false
    had_move = false
    changed = false
    wants_double_tap_window = false


func is_active() -> bool:
    return start_cell != Vector2i(-1, -1)
```

---

## 设计理念：状态对象跟一次手势走

`BoardGestureRecognizer` 在 `on_drag_start` 时 `_stroke.reset()`，在 `on_drag_end` 时再次 `_stroke.reset()`。一次手指从按下到抬起的完整生命周期。

**`(-1, -1)` 是哨兵值**：表示「还没有有效的起始格」。因为棋盘的合法坐标范围是 `(0,0)` 到 `(size-1, size-1)`，`(-1, -1)` 永远不合法。

---

## 属性详解

### `target_state` / `target_pending` — 一笔画的意图

这是整个输入系统最巧妙的设计。

```
玩家在 Normal 模式下滑动标叉：
  手指按下 (2,3) — 这一格是空格
    → target_pending = false（意图已确定）
    → target_state = MARK（这一笔是"标叉模式"）

  手指滑到 (2,4) — 这一格是空格
    → target_state = MARK，当前是 EMPTY → 改为 MARK ✅

  手指滑到 (2,5) — 这一格是猫
    → 猫不能滑动覆盖 → 返回 null，跳过

  手指滑到 (2,6) — 这一格已经是 MARK
    → 已经是目标状态 → 跳过（避免重复操作）
```

**`target_pending` 的场景**——手指按在猫上：

```
玩家在 (3,4) 按下 — 这一格是猫：
  NormalTapOperation.on_tap:
    → target_pending = true（意图还没最终确定！）
    → target_state = EMPTY（暂定"清除模式"）
    → 返回 []（不立即操作）
    → 开启双击窗口

玩家滑动到 (3,5)：
  NormalSwipeOperation.on_paint:
    → target_pending == true → 正式确定意图
    → target_state = MARK (因为 (3,5) 是空格，应该标叉)
    → target_pending = false
```

**为什么要有 `target_pending`？** 防误触。玩家可能在试着滑动时不小心先碰到了猫。如果第一格是猫就立即清除，玩家会感到沮丧。延迟意图确定给了玩家一个「缓冲」——第一格不是猫时不延迟，第一格是猫时才进入 pending。

### `had_move` — 手指移动过吗？

区分「单击」和「滑动」。如果 `had_move = false`，说明手指按下后没动就抬起了——是单击。`on_drag_over` 中设为 true。

### `changed` — 这一笔画改变了任何格子吗？

用于决定滑动结束时是否需要额外的 UI 更新（如刷新冲突显示）。

### `wants_double_tap_window` — 需要开启双击检测窗口吗？

由 `NormalTapOperation.on_tap` 在按到猫时设置。GestureRecognizer 读取它来决定是否启动 0.35 秒双击定时器。

---

## `is_active()` — 判断手势是否在进行中

```gdscript
func is_active() -> bool:
    return start_cell != Vector2i(-1, -1)
```

`on_drag_over` 中用这个判断：如果手势还没开始（手指从棋盘外滑入），忽略。

---

# 第三篇：三种操作

## 基类

### BaseTapOperation

```gdscript
class_name BaseTapOperation
extends RefCounted

var board: BoardView

func _init(p_board: BoardView) -> void:
    board = p_board

func on_tap(_r: int, _c: int, _stroke: BoardStrokeContext) -> Array[CellAction]:
    return []
```

持有 `board: BoardView` 引用——Operation 需要读取棋盘当前状态来决定返回什么 CellAction。

`_` 前缀的参数 = 「我知道有这个参数但不用」。基类默认什么都不做——返回空数组。

`-> Array[CellAction]`：返回类型是 CellAction 数组。大多数时候只有一个元素，但可能为空（什么都不做）或多个（比如双击填满一行返回多个操作）。

### BaseSwipeOperation

```gdscript
class_name BaseSwipeOperation
extends RefCounted

var board: BoardView

func _init(p_board: BoardView) -> void:
    board = p_board

func on_paint(_r: int, _c: int, _stroke: BoardStrokeContext, _is_current: bool) -> CellAction:
    return null

func on_end(_stroke: BoardStrokeContext) -> void:
    pass
```

| 方法 | 何时调用 | 返回值 |
|---|---|---|
| `on_paint(r, c, stroke, is_current)` | 手指经过每个格子 | `CellAction` 或 `null`（null = 跳过这个格子） |
| `on_end(stroke)` | 手指抬起 | 无返回值——做清理工作 |

**`on_paint` 返回单个 CellAction 而不是数组**：滑动时每帧经过一个格子，一次只操作一个格子。Tap 返回数组是因为双击可能一次操作多个格子。

**`is_current`**：手指当前所在的格子（true）还是插值生成的中间格子（false）。用于震动控制——只有手指真正碰到的格子才触发震动，插值格子不震动。

---

## 正式模式

### NormalTapOperation

```gdscript
func on_tap(r: int, c: int, stroke: BoardStrokeContext) -> Array[CellAction]:
    var out: Array[CellAction] = []
    var cur: int = board.get_cell_state(r, c)

    if cur == CellState.CAT or cur == CellState.ERROR or cur == CellState.LOCKED_MARK:
        stroke.target_pending = true
        stroke.target_state = CellState.EMPTY
        return out

    stroke.target_pending = false
    stroke.target_state = CellState.MARK if CellState.is_blank(cur) else CellState.EMPTY

    if CellState.is_blank(cur):
        out.append(CellAction.set_cell(r, c, CellState.EMPTY, CellState.MARK, LEVEL2))
    elif cur == CellState.MARK:
        out.append(CellAction.set_cell(r, c, CellState.MARK, CellState.EMPTY, LEVEL2))
    return out
```

**状态机**：

```
点击时的格子状态      → 操作                  → 滑动意图
─────────────────────────────────────────────────────
EMPTY / DRAFT_*      → 标叉 (MARK)           → 这一笔都是标叉
MARK                 → 清空 (EMPTY)           → 这一笔都是清空
CAT / ERROR / LOCKED → 不动（target_pending） → 等滑动到第一格再定
```

### NormalSwipeOperation

```gdscript
func on_paint(r: int, c: int, stroke: BoardStrokeContext, is_current: bool) -> CellAction:
    var state: int = board.get_cell_state(r, c)

    if state == CellState.CAT or state == CellState.ERROR or state == CellState.LOCKED_MARK:
        return null

    if stroke.target_pending:
        stroke.target_state = CellState.MARK if CellState.is_blank(state) else CellState.EMPTY
        stroke.target_pending = false

    if state == stroke.target_state:
        return null

    var vib: int = LEVEL2 if is_current else -1
    return CellAction.set_cell(r, c, state, stroke.target_state, vib)
```

**三个跳过条件**：

| 条件 | 原因 |
|---|---|
| 猫/ERROR/LOCKED_MARK | 这些格子不能被滑动覆盖 |
| `state == target_state` | 已经是目标状态了，不需要再操作 |
| 返回 `null` | GestureRecognizer 看到 null 就跳过（不追加到 actions 里） |

**`target_pending` 在这里被消费**：第一格延迟确定的意图在这里正式落地。`target_state` 根据第一个碰到的非猫格子来定——如果是空格就是 MARK（标叉），如果已经是叉就是 EMPTY（清除）。

### NormalDoubleTapOperation

```gdscript
func on_double_tap(r: int, c: int) -> Array[CellAction]:
    if board.get_cell_state(r, c) == CellState.CAT:
        return []
    return [CellAction.double_tap(r, c)]
```

双击不直接操作棋盘——返回 `DOUBLE_TAP` 类型的 CellAction，由 Game Page 决定具体行为。典型实现：双击某个空格 → 自动填满该行/列的所有剩余空格。

---

## 草稿模式

### DraftTapOperation

```gdscript
func on_tap(r: int, c: int, stroke: BoardStrokeContext) -> Array[CellAction]:
    var cur: int = board.get_cell_state(r, c)
    if not CellState.is_blank(cur):
        return []

    if cur == CellState.EMPTY:
        stroke.target_state = CellState.DRAFT_CROSS
        return [CellAction.set_draft(r, c, CellState.DRAFT_CROSS)]
    else:
        stroke.target_state = CellState.EMPTY
        return [CellAction.set_draft(r, c, CellState.EMPTY)]
```

**和 NormalTapOperation 的关键区别**：

| | Normal | Draft |
|---|---|---|
| 目标状态 | MARK / EMPTY | DRAFT_CROSS / EMPTY |
| 按在猫上 | target_pending | 忽略（什么都不做） |
| 震动 | ✅ LEVEL2 | ❌ 不震动 |
| 撤销历史 | record = true | 不进撤销（草稿可一键清除） |
| 创建方式 | `CellAction.set_cell()` | `CellAction.set_draft()` |

### DraftSwipeOperation

```gdscript
func on_paint(r: int, c: int, stroke: BoardStrokeContext, _is_current: bool) -> CellAction:
    var cur: int = board.get_cell_state(r, c)
    if not CellState.is_blank(cur):
        return null
    if cur == CellState.DRAFT_CAT:
        return null
    if cur == stroke.target_state:
        return null
    return CellAction.set_draft(r, c, stroke.target_state)
```

**和 NormalSwipeOperation 的关键区别**：

| | Normal Swipe | Draft Swipe |
|---|---|---|
| 跳过猫 | ✅ 跳过 CAT/ERROR/LOCKED_MARK | ✅ 跳过所有非 blank |
| 额外保护 | — | 额外跳过 DRAFT_CAT（草稿猫不能用滑动覆盖） |
| `_is_current` | 用于震动控制 | 不关心——草稿不震动，用 `_` 忽略参数 |
| target_pending | 有（第一格可能是猫） | 无（第一格不是 blank 就直接跳过） |

---

# 第四篇：BoardInputScheme — 模式切换

## 全文

```gdscript
class_name BoardInputScheme
extends RefCounted

var tap_op: BaseTapOperation
var double_tap_op: BaseDoubleTapOperation
var swipe_op: BaseSwipeOperation


func _init(p_tap, p_double_tap, p_swipe) -> void:
    tap_op = p_tap
    double_tap_op = p_double_tap
    swipe_op = p_swipe


static func create_normal(board: BoardView) -> BoardInputScheme:
    return BoardInputScheme.new(
        NormalTapOperation.new(board),
        NormalDoubleTapOperation.new(board),
        NormalSwipeOperation.new(board),
    )


static func create_draft(board: BoardView) -> BoardInputScheme:
    return BoardInputScheme.new(
        DraftTapOperation.new(board),
        DraftDoubleTapOperation.new(board),
        DraftSwipeOperation.new(board),
    )
```

---

## 策略模式

这是策略模式的标准实现：

```
模式切换 = 换三个 Operation 对象
手势识别 = 完全不变
```

Game Page 在用户切换 Normal ↔ Draft 时：

```gdscript
# 切换到草稿模式
recognizer.active_scheme = BoardInputScheme.create_draft(board)

# 切回正式模式
recognizer.active_scheme = BoardInputScheme.create_normal(board)
```

`BoardGestureRecognizer` 不需要知道当前是哪种模式——它只调 `active_scheme.tap_op.on_tap(...)`。哪个 Operation 被注入，就执行哪种逻辑。

**对比不用策略模式的写法**：

```gdscript
# 不推荐：到处都是 if/else
func on_tap(r, c):
    if mode == NORMAL:
        # Normal 逻辑
    else:
        # Draft 逻辑
```

策略模式的版本只改一行赋值，所有 `if mode ==` 都消失了。

---

# 第五篇：BoardGestureRecognizer — 核心协调者

## 全文

```gdscript
class_name BoardGestureRecognizer
extends RefCounted

var board: BoardView
var active_scheme: BoardInputScheme
var _stroke := BoardStrokeContext.new()
var _last_tap_cell: Vector2i = Vector2i(-1, -1)


func _init(p_board: BoardView) -> void:
    board = p_board
```

---

## `on_drag_start(pos)` — 手指按下

```gdscript
func on_drag_start(pos: Vector2) -> Array[CellAction]:
    var cell: Vector2i = _resolve_cell(pos)
    var r: int = cell.y
    var c: int = cell.x

    if _last_tap_cell == Vector2i(r, c):
        _last_tap_cell = Vector2i(-1, -1)
        _stroke.reset()
        return active_scheme.double_tap_op.on_double_tap(r, c)

    _stroke.reset()
    _stroke.start_cell = Vector2i(r, c)
    _stroke.last_cell = Vector2i(r, c)
    var actions: Array[CellAction] = active_scheme.tap_op.on_tap(r, c, _stroke)

    if not actions.is_empty():
        _open_double_tap_window(r, c)
    return actions
```

### 双击检测机制

```
时间线：
  第 1 次按下 (3,4)：
    _last_tap_cell = (-1, -1)  →  不等于 (3,4)  →  不是双击
    → 执行 tap_op.on_tap(3,4)
    → 如果有返回操作 → _open_double_tap_window(3,4)
      → _last_tap_cell = (3,4)
      → 启动 0.35s 定时器
        → 0.35s 后回调：如果 _last_tap_cell 仍是 (3,4) → 清空为 (-1,-1)

  0.35 秒内第 2 次按下 (3,4)：
    _last_tap_cell == (3,4)  →  是双击！
    → _last_tap_cell 清空
    → 不执行 tap（跳过 _open_double_tap_window）
    → 执行 double_tap_op.on_double_tap(3,4)

  0.35 秒后：
    定时器触发 → _last_tap_cell = (-1,-1)
    下一次按下 (3,4) → 又是普通 tap
```

**为什么双击检测在 GestureRecognizer 层而不是 Operation 层？** Operation 不需要知道时间概念——只响应 `on_double_tap` 调用。时间窗口逻辑和业务逻辑分离。

**`_open_double_tap_window` 的条件**：只有 tap 返回了非空操作时才开启（`not actions.is_empty()`）。按在猫上时 tap 返回 `[]`——不开双击窗口。这意味着「按在猫上 → 0.35 秒内再按同一格」不会触发双击——这是合理的，因为按在猫上通常是想滑动清除。

---

## `on_drag_over(pos)` — 手指滑动

```gdscript
func on_drag_over(pos: Vector2) -> Array[CellAction]:
    var out: Array[CellAction] = []
    if not _stroke.is_active():
        return out
    var cell: Vector2i = _resolve_cell(pos)
    if cell.x < 0:
        return out
    var r: int = cell.y
    var c: int = cell.x
    if Vector2i(r, c) == _stroke.last_cell:
        return out

    var last: Vector2i = _stroke.last_cell
    var dr: int = r - last.x
    var dc: int = c - last.y
    var steps: int = maxi(absi(dr), absi(dc))
    for i in range(1, steps):
        var ir: int = last.x + int(roundi(float(dr) * i / steps))
        var ic: int = last.y + int(roundi(float(dc) * i / steps))
        var mid: CellAction = active_scheme.swipe_op.on_paint(ir, ic, _stroke, false)
        if mid != null:
            out.append(mid)
    _stroke.last_cell = Vector2i(r, c)
    _stroke.had_move = true
    var cur: CellAction = active_scheme.swipe_op.on_paint(r, c, _stroke, true)
    if cur != null:
        out.append(cur)
    return out
```

### 提前退出条件

| 条件 | 含义 |
|---|---|
| `not _stroke.is_active()` | 手势还没开始——忽略 |
| `cell.x < 0` | 手指在棋盘外——忽略 |
| `cell == _stroke.last_cell` | 还在同一个格子里——忽略 |

### 插值算法 — 为什么需要它

手指快速滑动时，两帧之间的位置可能跳过中间格子：

```
帧 N： 手指在 (2,3)，_stroke.last_cell = (2,3)
帧 N+1：手指在 (2,6)
        → dr = 6-3 = 3
        → steps = max(3, 0) = 3
        → 插值：
          i=1: ir=2, ic=3+round(3*1/3)=4 → (2,4) 调 on_paint
          i=2: ir=2, ic=3+round(3*2/3)=5 → (2,5) 调 on_paint
        → 最后：_stroke.last_cell = (2,6)，调 on_paint(2,6)
```

不用插值的话，`(2,4)` 和 `(2,5)` 会被跳过——玩家清楚地滑过了这两个格子，但它们的状态没变。这会让滑动标叉体验很差。

插值算法沿直线方向填充每一个被跳过的格子。`steps = max(abs(dr), abs(dc))` 保证了即使是对角线滑动也能正确插值。

### `is_current` 参数的作用

```gdscript
# 插值中间格子 — is_current = false（不震动）
on_paint(ir, ic, _stroke, false)

# 手指当前真正所在的格子 — is_current = true（震动）
on_paint(r, c, _stroke, true)
```

只有手指真正碰到的最后一格才触发震动——如果每个插值格都震动，连续滑动会变成连续震动。

---

## `on_drag_end()` — 手指抬起

```gdscript
func on_drag_end() -> void:
    active_scheme.swipe_op.on_end(_stroke)
    _stroke.reset()
```

清理工作：通知 SwipeOperation 这一笔结束了，然后重置 `_stroke` 为初始状态。

---

## `_resolve_cell(pos)` — 屏幕坐标 → 格子坐标

```gdscript
func _resolve_cell(pos: Vector2) -> Vector2i:
    return board.pointer_to_cell(pos.x, pos.y)
```

委托给 `BoardView.pointer_to_cell(x, y)`——只有 BoardView 知道棋盘在屏幕上的位置和格子大小。GestureRecognizer 不需要关心棋盘怎么布局的。

---

# 第六篇：SwipeGuardRecognizer — 防误触

## 全文

```gdscript
class_name SwipeGuardRecognizer
extends BoardGestureRecognizer

var _guard := SwipeAxisGuard.new()


func on_drag_start(pos: Vector2) -> Array[CellAction]:
    _guard.begin(board.get_puzzle_size(), SLOT_PX, BOARD_PADDING, CELL_PX,
                  board.pointer_to_cell(pos.x, pos.y))
    var actions: Array[CellAction] = super(pos)
    _configure_guard()
    _push_zone()
    return actions


func on_drag_over(pos: Vector2) -> Array[CellAction]:
    var was_pending: bool = _stroke.target_pending
    var actions: Array[CellAction] = super(pos)
    if was_pending and not _stroke.target_pending:
        _guard.set_active(_guard_active_now())
    _push_zone()
    return actions


func on_drag_end() -> void:
    super()
    _guard.end()
    board.update_swipe_protection_zone({})


func _resolve_cell(pos: Vector2) -> Vector2i:
    return _guard.process(pos.x, pos.y)
```

---

## 继承 — 只覆盖需要改的部分

`SwipeGuardRecognizer` 继承了 `BoardGestureRecognizer` 的全部手势识别逻辑，只覆盖了四个地方：

| 覆盖的方法 | 父类做的 | 子类加的 |
|---|---|---|
| `_resolve_cell` | 直接返回棋盘坐标 | 先过 SwipeAxisGuard 过滤 |
| `on_drag_start` | 手势开始 | 初始化 Guard + 配置防护参数 + 推送调试区域 |
| `on_drag_over` | 滑动处理 | 检测 pending→确定 的转折点并更新 Guard + 推送区域 |
| `on_drag_end` | 手势结束 | Guard.end() + 清除调试区域 |

**`super(pos)` 调用父类**：子类先做自己的事（初始化 Guard），然后调 `super(pos)` 让父类的手势识别逻辑照常运行，拿到结果后再做自己的事（推送区域）。这是模板方法模式的扩展——不重写父类，只加钩子。

---

## 防误触原理

在竖屏手机上，玩家从屏幕边缘向内滑动可能被系统误认为「返回手势」。在棋盘上，手指竖直滑动（不同行之间）比水平滑动（同行内标叉）更容易触发系统手势。

`SwipeAxisGuard` 检测手指滑动的轴偏差：

```
允许的滑动（水平标叉）：
  (3,2) → (3,3) → (3,4) → (3,5)
  行号始终是 3，列号递增 → 纯水平滑动 ✅

被拦截的滑动（偏移超标）：
  (3,2) → (3,3) → (2,4) → (3,5)
                        ↑ 行号从 3 变成了 2
  Guard 检测到偏移超过阈值 → 锁定行号为 3，忽略列号的变化
```

`_guard.process(x, y)` 返回「修正后的」坐标——如果偏移在容忍范围内，返回真实坐标；如果偏移超标，锁定到主轴上。

---

## AB 测试开关

```gdscript
func _swipe_guard_enabled_for_level() -> bool:
    var cfg: SwipeProtectConfig = ABTestManager.swipe_protect
    return cfg.is_enabled() and board.get_puzzle_size() >= cfg.min_size()
```

滑动保护不是全局开启的——它受 A/B 测试配置控制，且只在棋盘大于等于某个最小尺寸时才启用（小棋盘不需要保护——格子大，不容易误触）。

---

# 完整数据流

```
触摸事件 (屏幕坐标 x, y)
       │
       ▼
BoardGestureRecognizer.on_drag_start(pos)
       │
       ├─ _resolve_cell(pos)  → 像素 → (r, c)
       │    └─ [SwipeGuard] _guard.process(x, y) → 修正后的坐标
       │
       ├─ 双击？→ active_scheme.double_tap_op.on_double_tap(r, c)
       │          → CellAction(Kind.DOUBLE_TAP, r, c)
       │
       └─ 单击 → active_scheme.tap_op.on_tap(r, c, stroke)
                  → 设 stroke.target_state / target_pending
                  → [CellAction(Kind.SET_STATE, ...)] or []

触摸移动
       ▼
BoardGestureRecognizer.on_drag_over(pos)
       │
       ├─ _resolve_cell(pos) → (r, c)
       ├─ 插值中间跳过的格子
       └─ active_scheme.swipe_op.on_paint(r, c, stroke, is_current)
          → CellAction(Kind.SET_STATE, ...) or null

触摸抬起
       ▼
BoardGestureRecognizer.on_drag_end()
       └─ active_scheme.swipe_op.on_end(stroke)
          └─ _stroke.reset()
```

---

# 设计精华总结

| 设计决策 | 为什么 | 对应模式 |
|---|---|---|
| CellAction 是纯数据包 | 输入系统和执行系统解耦——输入不碰棋盘状态 | 命令模式 (Command) |
| StrokeContext 跟一次手势 | 状态局部化——手势之间互不干扰 | 上下文对象 (Context) |
| Operation 分 Normal/Draft 两套 | 手势识别代码不变，只换操作对象 | 策略模式 (Strategy) |
| Scheme 打包三个 Operation | 模式切换 = 一行赋值 | 抽象工厂 (Factory Method) |
| 双击检测在手势层非操作层 | Operation 不需要知道时间 | 关注点分离 |
| SwipeGuard 用继承不修改父类 | 父类不改，新功能加在子类 | 模板方法 (Template Method) |
| `_resolve_cell` 可被子类覆盖 | 父类定流程，子类改细节 | 模板方法 (Template Method) |
| `target_pending` 延迟意图确定 | 防误触——按在猫上不立即清猫 | 二段确认 (Two-phase commit) |
| `is_current` 区分当前格和插值格 | 只在手指真正碰到的格子震动 |  |

---

# 本篇学到的全部概念

| 概念类别 | 具体学到的 |
|---|---|
| 设计模式 | 命令模式 (CellAction)、策略模式 (Operation)、模板方法 (继承)、工厂方法 (create_normal/draft) |
| 继承 | `extends BoardGestureRecognizer` — 只覆盖需要改的方法，`super()` 调父类 |
| 解耦 | 输入系统和执行系统完全分离——输入产出 CellAction，Game Page 消费 |
| 状态管理 | StrokeContext — 局部状态对象跟一次手势走 |
| 防误触 | target_pending（二段确认）、SwipeGuard（轴锁定） |
| 插值算法 | 快速滑动时填充中间跳过的格子 |
| 双击检测 | 0.35 秒时间窗口 + 同一格判断 |
| A/B 测试 | swipe_protect 配置控制防误触开关 |
| 类型系统 | `Array[CellAction]` 泛型数组、`CellAction \| null` 可空返回 |
| 哨兵值 | `Vector2i(-1, -1)` 表示「无效坐标」 |
| 默认参数 | `vib: int = -1` — 合理的默认值减少调用方负担 |
| `_` 前缀 | 参数不用时的约定（`_is_current`） |
