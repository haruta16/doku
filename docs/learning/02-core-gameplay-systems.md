# 核心玩法系统精读 — 数据模型 & 规则引擎

> 文件：
> - [scripts/module/gameplay/model/cell_state.gd](../../scripts/module/gameplay/model/cell_state.gd) — 棋盘格子状态枚举（7 种状态 + 3 个判断函数）
> - [scripts/module/gameplay/core/queendoku_core.gd](../../scripts/module/gameplay/core/queendoku_core.gd) — 游戏规则引擎（9 个 static 函数）
>
> 这两个文件构成了 Meowdoku 的**纯数据层**——不依赖 UI、不依赖节点树、不依赖场景。纯数据进、纯数据出。理解它们等于理解了整个游戏的规则。
>
> **前置阅读**：[GDScript 七种根基抽象](00-gdscript-seven-abstractions.md) → [launcher.gd 精读](01-launcher-gd-walkthrough.md)

---

# 第一篇：cell_state.gd — 棋盘格子的 7 种状态

## 全文

```gdscript
class_name CellState
extends Object

enum { EMPTY, CAT, MARK, ERROR, DRAFT_CROSS, DRAFT_CAT, LOCKED_MARK }


static func is_draft(s: int) -> bool:
    return s == DRAFT_CROSS or s == DRAFT_CAT


static func is_blank(s: int) -> bool:
    return s == EMPTY or s == DRAFT_CROSS or s == DRAFT_CAT


static func is_cross(s: int) -> bool:
    return s == MARK or s == ERROR or s == LOCKED_MARK
```

---

## 文件头

### `class_name` — 给蓝图起名字

```gdscript
class_name CellState
```

| 词 | 抽象 | 含义 |
|---|---|---|
| `class_name` | 令（声明令） | 「给这个脚本的蓝图起名字」 |
| `CellState` | 名（类型名） | 以后整个项目里都可以用 `CellState` 这个类型名 |

没有 `class_name` 的脚本只能用文件路径引用（`load("res://...")`）。有了 `class_name`，你在任何地方写 `CellState` 就能直接用——Godot 在编译时自动注册这个类型名，所有脚本都能看到它。

### `extends Object` — 不挂节点

```gdscript
extends Object
```

| 基类 | 场景树能力 | 生命周期回调 | 内存管理 | 何时用 |
|---|---|---|---|---|
| `Node` | ✅ 可 `add_child` | `_ready()`, `_process()` 等 | 手动 `queue_free()` | 挂场景树上的东西 |
| `Object` | ❌ | 无 | 手动 `free()` | 纯数据/工具类 |
| `RefCounted` | ❌ | 无 | 自动（无人引用时释放） | 纯数据/工具类（现代选择） |

`CellState` 用 `Object` 是因为所有成员都是 `static`——永远不需要创建实例。即使创建，`Object` 也够了（比 `RefCounted` 更底层，没有引用计数的开销）。

但 `QueendokuCore` 用了 `RefCounted`（见第二篇）——这是更现代的选择。如果重写，`CellState` 也应该 `extends RefCounted`。

---

## `enum { EMPTY, CAT, MARK, ERROR, DRAFT_CROSS, DRAFT_CAT, LOCKED_MARK }`

### 语法

```gdscript
enum { EMPTY, CAT, MARK, ERROR, DRAFT_CROSS, DRAFT_CAT, LOCKED_MARK }
```

| 词 | 抽象 | 含义 |
|---|---|---|
| `enum` | 令（声明令） | 「定义一组有关联的固定值」 |
| `EMPTY, CAT, ...` | 値（枚举成员） | 有名字的整数常量 |

### 自动编号规则

没有显式赋值时，GDScript 从 0 开始自动编号：

```gdscript
enum { A, B, C }      →  A=0, B=1, C=2
enum { A=5, B, C }    →  A=5, B=6, C=7
enum { A, B=10, C }   →  A=0, B=10, C=11
```

本项目没有显式赋值，所以：

| 枚举成员 | 自动值 | 在棋盘上意味着 |
|---|---|---|
| `EMPTY` | 0 | 空格子——可以放猫或标叉 |
| `CAT` | 1 | 已放置的猫（皇后） |
| `MARK` | 2 | 玩家手动标的叉（确定这格不能放猫） |
| `ERROR` | 3 | 冲突高亮——两只猫冲突时标红 |
| `DRAFT_CROSS` | 4 | 草稿叉——铅笔模式下临时标记 |
| `DRAFT_CAT` | 5 | 草稿猫——铅笔模式下临时放猫 |
| `LOCKED_MARK` | 6 | 锁定的叉——系统预填的（新手引导/低难度），玩家不能改 |

### 7 种状态的设计分组

```
                ┌── 可放猫的状态 ──┐     ┌── 不可放猫的状态 ──┐
                │                  │     │                      │
              EMPTY          DRAFT_CROSS   MARK    LOCKED_MARK
              DRAFT_CAT                    ERROR

                └── 草稿状态 ──┘
              （铅笔模式临时标记）
```

---

## `is_draft(s)` — 是草稿吗？

```gdscript
static func is_draft(s: int) -> bool:
    return s == DRAFT_CROSS or s == DRAFT_CAT
```

| DRAFT_CROSS | DRAFT_CAT | 其他 |
|---|---|---|
| `true` | `true` | `false` |

**语义**：「这是铅笔模式下的临时标记吗？」

草稿状态的格子有一个特殊行为：切换到正式模式时，所有草稿标记会被清除。`is_draft()` 就是用来筛选这些「待清除」的格子的。

---

## `is_blank(s)` — 是空白吗？

```gdscript
static func is_blank(s: int) -> bool:
    return s == EMPTY or s == DRAFT_CROSS or s == DRAFT_CAT
```

| EMPTY | DRAFT_CROSS | DRAFT_CAT | MARK | ERROR | LOCKED_MARK |
|---|---|---|---|---|---|
| `true` | `true` | `true` | `false` | `false` | `false` |

**语义**：「这个格子还能放猫吗？」——只要不是永久标记（MARK / ERROR / LOCKED_MARK），就是 blank。

**和 `is_draft` 的关系**：

```
is_draft(DRAFT_CROSS) = true     is_blank(DRAFT_CROSS) = true
is_draft(EMPTY) = false          is_blank(EMPTY) = true
is_draft(MARK) = false           is_blank(MARK) = false
```

DRAFT 状态是两者的交集。但 `is_draft` 问的是「这是铅笔标记吗？」，`is_blank` 问的是「还能放猫吗？」——问题不同，答案不同。

---

## `is_cross(s)` — 是叉吗？

```gdscript
static func is_cross(s: int) -> bool:
    return s == MARK or s == ERROR or s == LOCKED_MARK
```

| MARK | ERROR | LOCKED_MARK | 其他 |
|---|---|---|---|
| `true` | `true` | `true` | `false` |

**语义**：「这个格子被标记为不能放猫了吗？」——涵盖任何形式的叉标记。

三种叉的区别在于来源：

| 叉类型 | 由谁放置 | 能手动改吗？ |
|---|---|---|
| MARK | 玩家 | ✅ |
| ERROR | 系统（冲突检测） | ❌ 随冲突消失而消失 |
| LOCKED_MARK | 系统（关卡预设/引导） | ❌ 不可撤销 |

但从「还能放猫吗？」的角度看，三种叉等价——都不能。

---

# 第二篇：queendoku_core.gd — 游戏规则引擎

## 全文

```gdscript
class_name QueendokuCore
extends RefCounted

enum Rule { NONE = 0, SAME_COLOR = 1, SAME_LINE = 2, NO_TOUCH = 3 }


static func find_conflicts(board: Array, size: int, regions: Array) -> Dictionary:
    var errors: Dictionary = {}

    var pieces: Array[Vector2i] = []
    for r in range(size):
        for c in range(size):
            if board[r][c] == CellState.CAT:
                pieces.append(Vector2i(r, c))

    for i in range(pieces.size()):
        for j in range(i + 1, pieces.size()):
            var a: Vector2i = pieces[i]
            var b: Vector2i = pieces[j]
            var conflict := false

            if a.x == b.x:
                conflict = true
            elif a.y == b.y:
                conflict = true
            elif abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1:
                conflict = true
            elif regions[a.x][a.y] == regions[b.x][b.y]:
                conflict = true

            if conflict:
                errors["%d,%d" % [a.x, a.y]] = true
                errors["%d,%d" % [b.x, b.y]] = true

    return errors


static func _classify_pair(a: Vector2i, b: Vector2i, regions: Array) -> int:
    if regions[a.x][a.y] == regions[b.x][b.y]:
        return Rule.SAME_COLOR
    if a.x == b.x or a.y == b.y:
        return Rule.SAME_LINE
    if abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1:
        return Rule.NO_TOUCH
    return Rule.NONE


static func classify_violation(r: int, c: int, placed_cats: Array, regions: Array) -> int:
    var here := Vector2i(r, c)
    var best: int = Rule.NONE
    for cat: Vector2i in placed_cats:
        var k: int = _classify_pair(here, cat, regions)

        if k != Rule.NONE and (best == Rule.NONE or k < best):
            best = k

            if best == Rule.SAME_COLOR:
                return best
    return best


static func find_conflicting_cats(r: int, c: int, placed_cats: Array, regions: Array) -> Array[Vector2i]:
    var here := Vector2i(r, c)
    var result: Array[Vector2i] = []
    for cat: Vector2i in placed_cats:
        if _classify_pair(here, cat, regions) != Rule.NONE:
            result.append(cat)
    return result


static func cells_excluded_by_cat(cat: Vector2i, size: int, regions: Array) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for r in range(size):
        for c in range(size):
            if r == cat.x and c == cat.y:
                continue
            if _classify_pair(Vector2i(r, c), cat, regions) != Rule.NONE:
                out.append(Vector2i(r, c))
    return out


static func constraint_cells_for_cat(cat: Vector2i, size: int, regions: Array) -> Array:
    var row_cells: Array[Vector2i] = []
    var col_cells: Array[Vector2i] = []
    var nbr_cells: Array[Vector2i] = []
    var reg_cells: Array[Vector2i] = []
    var cat_region: int = int(regions[cat.x][cat.y])
    for r in range(size):
        for c in range(size):
            if r == cat.x and c == cat.y:
                continue
            var p := Vector2i(r, c)
            if r == cat.x:
                row_cells.append(p)
            if c == cat.y:
                col_cells.append(p)
            if abs(r - cat.x) <= 1 and abs(c - cat.y) <= 1:
                nbr_cells.append(p)
            if int(regions[r][c]) == cat_region:
                reg_cells.append(p)
    return [row_cells, col_cells, nbr_cells, reg_cells]


static func cells_excluded_by_cat_no_region(cat: Vector2i, size: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for r in range(size):
        for c in range(size):
            if r == cat.x and c == cat.y:
                continue
            if r == cat.x or c == cat.y or (abs(r - cat.x) <= 1 and abs(c - cat.y) <= 1):
                out.append(Vector2i(r, c))
    return out


static func is_complete(board: Array, size: int, regions: Array) -> bool:
    var piece_count := 0
    for r in range(size):
        for c in range(size):
            if board[r][c] == CellState.CAT:
                piece_count += 1
    if piece_count != size:
        return false
    return find_conflicts(board, size, regions).is_empty()


static func validate_solution_entry(entry: Dictionary, size: int) -> bool:
    var regions: Array = entry.get("regionMap", [])
    var solution: Array = entry.get("solution", [])
    if regions.size() != size or solution.size() != size:
        return false

    var board: Array = []
    for r: int in range(size):
        var row: Array = []
        row.resize(size)
        row.fill(CellState.EMPTY)
        board.append(row)
    for r: int in range(size):
        var c: int = int(solution[r])
        if c < 0 or c >= size:
            return false
        board[r][c] = CellState.CAT
    return is_complete(board, size, regions)
```

---

## 文件头

### `extends RefCounted` — 引用计数自动回收

```gdscript
class_name QueendokuCore
extends RefCounted
```

| 基类 | 何时用 | 内存管理 |
|---|---|---|
| `Node` | 挂在场景树上 | 手动 `queue_free()` |
| `Object` | 纯数据/工具类 | 手动 `free()` |
| **`RefCounted`** | 纯数据/工具类 | **自动释放——无人引用时回收** |

`QueendokuCore` 所有函数都是 `static`——永远不需要创建实例。选择 `RefCounted` 意味着即使有人创建了实例，不用时也会被 Godot 自动回收，不会内存泄漏。这是比 `Object` 更安全的选择。

### `enum Rule` — 四种冲突类型

```gdscript
enum Rule { NONE = 0, SAME_COLOR = 1, SAME_LINE = 2, NO_TOUCH = 3 }
```

| 枚举成员 | 值 | 违规行为 | 优先级 |
|---|---|---|---|
| `NONE` | 0 | 没有冲突 | — |
| `SAME_COLOR` | 1 | 两只猫在同一颜色区域 | 🔴 最高（最严重） |
| `SAME_LINE` | 2 | 两只猫同行或同列 | 🟡 中 |
| `NO_TOUCH` | 3 | 两只猫相邻（含对角线） | 🟢 低 |

**值是刻意排的**：1 < 2 < 3，数字越小 = 越严重。多个函数利用 `k < best` 来取「最严重的冲突类型」，不需要额外写优先级映射表。

---

## 游戏规则速览

Meowdoku 的玩法是「皇后谜题」（Queens Puzzle / Queen Doku）。在 N×N 的棋盘上放置 N 只猫（皇后），规则：

```
✅ 每行恰好一只猫    (SAME_LINE — 同行)
✅ 每列恰好一只猫    (SAME_LINE — 同列)
✅ 每个颜色区域最多一只猫  (SAME_COLOR)
✅ 猫之间不能相邻（含对角）(NO_TOUCH)
```

一只猫排除了哪些格子：

```
  0 1 2 3 4          🐱 在 (2,2)
0 · · × · ·          × 的行被排除（同行）
1 · × × × ·          × 的列被排除（同列）
2 × × 🐱 × ×         × 的 3×3 邻域被排除（NO_TOUCH）
3 · × × × ·          × 的同色区域被排除（SAME_COLOR）
4 · · × · ·
```

---

## 核心数据类型：棋盘的三种表示

整篇代码涉及棋盘的三套坐标系，理解它们的区别至关重要：

### `board: Array` — 二维数组，存每个格子的状态

```gdscript
board = [
    [0, 1, 0, 0, 2],   # board[r][c] = CellState 枚举值
    [0, 0, 2, 0, 0],
    [2, 0, 0, 1, 0],
    [0, 2, 0, 0, 2],
    [1, 0, 0, 2, 0],
]
```

`board[r][c]`：第 r 行第 c 列的格子状态。r 是行号（纵轴），c 是列号（横轴）。

### `regions: Array` — 二维数组，存每个格子属于哪个颜色区域

```gdscript
regions = [
    [1, 1, 2, 2, 3],
    [1, 2, 2, 3, 3],
    [1, 2, 3, 3, 4],
    [2, 2, 3, 4, 4],
    [2, 3, 3, 4, 4],
]
```

`regions[r][c]`：第 r 行第 c 列属于第几号颜色区域。同一数字的所有格子是同一颜色。

### `Vector2i` — 一个格子的坐标

```gdscript
Vector2i(r, c)
#        │  └─ y 分量：列号（横轴）
#        └─ x 分量：行号（纵轴）
```

**重要记忆**：`Vector2i.x` = 行号，`Vector2i.y` = 列号。虽然名字叫 x/y，但它们在这里的语义是「二维数组的索引」——x 是第一维（行），y 是第二维（列）。这和屏幕坐标（x=水平，y=垂直）不一致，是这个小项目特有的约定。

### `solution: Array` — 一维数组，存每行猫在哪一列

```gdscript
solution = [2, 0, 4, 1, 3]
#           │  │  │  │  └─ 第 4 行的猫在第 3 列
#           │  │  │  └─ 第 3 行的猫在第 1 列
#           │  │  └─ 第 2 行的猫在第 4 列
#           │  └─ 第 1 行的猫在第 0 列
#           └─ 第 0 行的猫在第 2 列
```

**巧妙之处**：因为每行恰好一只猫，所以行号天然就是数组索引。不需要存 `{row: 0, col: 2}`，一个一维数组就能表示完整的解。

---

## 基础函数：`_classify_pair` — 两只猫犯了哪条规则

```gdscript
static func _classify_pair(a: Vector2i, b: Vector2i, regions: Array) -> int:
    if regions[a.x][a.y] == regions[b.x][b.y]:
        return Rule.SAME_COLOR
    if a.x == b.x or a.y == b.y:
        return Rule.SAME_LINE
    if abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1:
        return Rule.NO_TOUCH
    return Rule.NONE
```

### 逐个拆解

#### 参数

| 参数 | 类型 | 含义 |
|---|---|---|
| `a` | `Vector2i` | 第一只猫的位置（`.x` = 行号，`.y` = 列号） |
| `b` | `Vector2i` | 第二只猫的位置 |
| `regions` | `Array` | 二维数组——颜色区域图 |

#### `regions[a.x][a.y]` — 二维数组的二次索引

```
regions[2][3]
   │     └─ 第 2 行里的第 3 个元素（列号）
   └─ 取第 2 行（行号）

等效于：取第 2 行第 3 列的颜色区域编号
```

`regions` 是一个 Array，每个元素又是一个 Array。所以 `regions[2]` 返回一个 Array（第 2 行），`regions[2][3]` 再取这个 Array 的第 3 个元素。

#### `abs()` — 绝对值

```gdscript
abs(3 - 5)  →  2
abs(5 - 3)  →  2
abs(-2)     →  2
```

不管谁减谁，结果都是正的距离。

#### 判断逻辑为什么是这个顺序？

```
1. SAME_COLOR  同一颜色区域 → 最严重
2. SAME_LINE   同行/同列     → 次严重
3. NO_TOUCH    相邻          → 较轻微
4. NONE        都没违反      → 没问题
```

**判断顺序 = 优先级顺序**。一行只执行一条 return——匹配到就返回，不往下看。

**为什么 SAME_COLOR 最严重？** 从用户体验角度：同行同列是玩家最容易发现的错误（视觉线索强），同色区域次之。但对于提示系统，同色区域的违规更需要被优先指出——因为同行同列玩家自己能看到，同色区域（形状不规则）不容易看出来。

### `_` 前缀 — GDScript 的「私有」约定

GDScript 没有 `private` 关键字。程序员约定：函数名以 `_` 开头 = 「这是内部实现细节，外部不应该直接调用」。

你技术上可以写 `QueendokuCore._classify_pair(a, b, regions)`——但这违反了约定。正确的用法是调用 `classify_violation()` 或 `find_conflicting_cats()`，它们内部会调 `_classify_pair`。

---

## `find_conflicts` — 找出棋盘上所有冲突的猫

```gdscript
static func find_conflicts(board: Array, size: int, regions: Array) -> Dictionary:
    var errors: Dictionary = {}

    var pieces: Array[Vector2i] = []
    for r in range(size):
        for c in range(size):
            if board[r][c] == CellState.CAT:
                pieces.append(Vector2i(r, c))

    for i in range(pieces.size()):
        for j in range(i + 1, pieces.size()):
            var a: Vector2i = pieces[i]
            var b: Vector2i = pieces[j]
            var conflict := false

            if a.x == b.x:
                conflict = true
            elif a.y == b.y:
                conflict = true
            elif abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1:
                conflict = true
            elif regions[a.x][a.y] == regions[b.x][b.y]:
                conflict = true

            if conflict:
                errors["%d,%d" % [a.x, a.y]] = true
                errors["%d,%d" % [b.x, b.y]] = true

    return errors
```

### 第一步：收集所有猫的位置

```gdscript
var pieces: Array[Vector2i] = []
for r in range(size):
    for c in range(size):
        if board[r][c] == CellState.CAT:
            pieces.append(Vector2i(r, c))
```

双重 `for r...for c...` 遍历棋盘每一个格子。遇到 `CellState.CAT`（值为 1）就记录下位置。

### 第二步：逐对检查

```gdscript
for i in range(pieces.size()):
    for j in range(i + 1, pieces.size()):
```

**这是「不重复配对」的标准写法**。如果棋盘上有 5 只猫（索引 0~4），检查：

```
i=0: j=1,2,3,4    →  0 vs 1, 0 vs 2, 0 vs 3, 0 vs 4
i=1: j=2,3,4      →  1 vs 2, 1 vs 3, 1 vs 4
i=2: j=3,4        →  2 vs 3, 2 vs 4
i=3: j=4          →  3 vs 4
i=4: j 从 5 开始 →  range(5, 5) 为空，不执行
```

**关键**：`j` 从 `i+1` 开始——不回头检查。`A vs B` 和 `B vs A` 是同一对，只查一次。配对总数 = `n*(n-1)/2`。

### 第三步：判断冲突（为什么用 `elif` 而不是 `if`？）

```gdscript
if a.x == b.x:
    conflict = true
elif a.y == b.y:
    conflict = true
elif abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1:
    conflict = true
elif regions[a.x][a.y] == regions[b.x][b.y]:
    conflict = true
```

**用 `elif` 而不是 `if`**：只要满足任意一条规则，就是冲突。不需要继续检查其他规则。`elif` = 「如果上面的不成立，再试这个」= 短路求值。

这里用 `elif` 而不是调 `_classify_pair` 的原因是**性能**：`_classify_pair` 是 static 函数调用，每次调用有开销。`find_conflicts` 在最坏情况下要检查 `size² × (size² - 1) / 2` 对猫（5×5 棋盘上有 25 格，最多 25 只猫 = 300 对）。inline 展开避免了函数调用开销。

**判断逻辑和 `_classify_pair` 是一致的**——只是写法和返回值不同。

### 返回 Dictionary 而不是 bool

```gdscript
errors["%d,%d" % [a.x, a.y]] = true
errors["%d,%d" % [b.x, b.y]] = true
```

**为什么返回 Dictionary？** 调用方不只想知道「有没有冲突」，还想知道「哪些猫在冲突」——UI 需要给冲突的猫标红。

```gdscript
errors = {
    "2,3": true,   # 第 2 行第 3 列的猫冲突了
    "4,1": true,   # 第 4 行第 1 列的猫冲突了
}
```

**为什么用 Dictionary 而不是 `Array[Vector2i]`？**

```gdscript
# Dictionary 方式 — O(1) 查重
errors["2,3"] = true     # 插入
"2,3" in errors          # 查询 → O(1)

# Array 方式 — O(n) 查重
errors.append(Vector2i(2, 3))   # 插入
Vector2i(2, 3) in errors         # 查询 → O(n)，需要遍历整个数组
```

用 Dictionary 是为了**自动去重 + O(1) 查询**。如果猫 A 和猫 B 冲突、猫 A 和猫 C 也冲突，`errors["行A,列A"]` 会被写两次——但因为 key 相同，最终只有一条记录。不需要手动 `if not exists then add`。

---

## `classify_violation` — 在 `(r,c)` 放猫会触犯什么规则

```gdscript
static func classify_violation(r: int, c: int, placed_cats: Array, regions: Array) -> int:
    var here := Vector2i(r, c)
    var best: int = Rule.NONE
    for cat: Vector2i in placed_cats:
        var k: int = _classify_pair(here, cat, regions)

        if k != Rule.NONE and (best == Rule.NONE or k < best):
            best = k

            if best == Rule.SAME_COLOR:
                return best
    return best
```

### 新语法：`for...in` 遍历数组

```gdscript
for cat: Vector2i in placed_cats:
```

| | `for i in range(n)` | `for item in array` |
|---|---|---|
| 循环变量 | 索引（整数） | 元素本身 |
| 取元素 | `array[i]` | 直接用 `item` |
| 适用场景 | 需要索引时 | 只关心元素内容时 |

这里只需要每只猫的位置、不关心它是第几只——用 `for...in` 更简洁。

### `:=` — 类型推断赋值

```gdscript
var here := Vector2i(r, c)
```

等价于：

```gdscript
var here: Vector2i = Vector2i(r, c)
```

`:=` 让编译器从右边的表达式推断类型。当右边已经明确写了 `Vector2i(...)` 时，左边再写一遍 `: Vector2i` 就是重复。`:=` 消除这个冗余。

**何时用 `:` vs `:=`**：

```gdscript
var x: int = 5           # 右边是数字字面量→类型不明显→显式写 :
var x := 5               # 可以，但可读性不如上面
var x := Vector2i(1, 2)  # 右边已经写了类型→用 := 简洁
var x := get_something() # 返回类型不明显→建议显式写 :
```

### 核心算法：找最严重的冲突

```
best = Rule.NONE（初始：还没找到冲突）
遍历每只已存在的猫：
    k = 和这只猫的冲突类型
    如果是 NONE → 跳过（没冲突）
    如果 k < best（更严重）→ best = k
    如果 best == SAME_COLOR（已经是最高级了）→ 直接返回，不用看了
遍历完 → 返回 best
```

```
示例：在 (3, 4) 放猫，已有 3 只猫在 (0,2) (3,1) (5,4)

(0,2): 同列？NO_TOUCH？→ SAME_COLOR → best = SAME_COLOR (1)
       → best == SAME_COLOR → return 1 ✅（不用再看 (3,1) 和 (5,4) 了）
```

一旦发现 SAME_COLOR（最严重），立刻返回——不需要继续检查。这是提前终止优化。

---

## `find_conflicting_cats` — 找出和 `(r,c)` 冲突的所有猫

```gdscript
static func find_conflicting_cats(r: int, c: int, placed_cats: Array, regions: Array) -> Array[Vector2i]:
    var here := Vector2i(r, c)
    var result: Array[Vector2i] = []
    for cat: Vector2i in placed_cats:
        if _classify_pair(here, cat, regions) != Rule.NONE:
            result.append(cat)
    return result
```

### 和 `classify_violation` 的对比

| | `classify_violation` | `find_conflicting_cats` |
|---|---|---|
| 返回 | 一个 `int`（最严重的冲突类型） | `Array[Vector2i]`（所有冲突猫的列表） |
| 提前结束 | ✅ SAME_COLOR 时 return | ❌ 检查所有猫后才返回 |
| 用途 | 显示冲突原因文字 | 高亮所有冲突的猫（标红） |
| 给谁用 | 提示/错误信息 UI | 棋盘渲染（把冲突猫标成 ERROR 状态） |

**两者通常成对调用**：UI 拿到冲突列表来标红猫，同时拿冲突类型来显示提示文字（"同色区域不能放哦~"）。

---

## `cells_excluded_by_cat` — 一只猫排除了哪些格子

```gdscript
static func cells_excluded_by_cat(cat: Vector2i, size: int, regions: Array) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for r in range(size):
        for c in range(size):
            if r == cat.x and c == cat.y:
                continue
            if _classify_pair(Vector2i(r, c), cat, regions) != Rule.NONE:
                out.append(Vector2i(r, c))
    return out
```

### `continue` — 跳过本次循环

```gdscript
if r == cat.x and c == cat.y:
    continue
```

| 令 | 含义 | 对比 |
|---|---|---|
| `continue` | 跳过本次循环剩余代码，直接进入下一次循环 | 猫自己和猫自己不算冲突 |
| `break` | 直接退出整个循环 | 提前终止 |

### 用途：提示系统

当用户点「提示」按钮时，系统调用 `cells_excluded_by_cat` 获取「因为这只猫的存在，哪些格子不能再放猫了」，然后高亮这些格子——帮助玩家理解为什么某些格子不能点。

---

## `constraint_cells_for_cat` — 按规则类型分组

```gdscript
static func constraint_cells_for_cat(cat: Vector2i, size: int, regions: Array) -> Array:
    var row_cells: Array[Vector2i] = []
    var col_cells: Array[Vector2i] = []
    var nbr_cells: Array[Vector2i] = []
    var reg_cells: Array[Vector2i] = []
    var cat_region: int = int(regions[cat.x][cat.y])
    for r in range(size):
        for c in range(size):
            if r == cat.x and c == cat.y:
                continue
            var p := Vector2i(r, c)
            if r == cat.x:
                row_cells.append(p)
            if c == cat.y:
                col_cells.append(p)
            if abs(r - cat.x) <= 1 and abs(c - cat.y) <= 1:
                nbr_cells.append(p)
            if int(regions[r][c]) == cat_region:
                reg_cells.append(p)
    return [row_cells, col_cells, nbr_cells, reg_cells]
```

### 和 `cells_excluded_by_cat` 的区别

| | `cells_excluded_by_cat` | `constraint_cells_for_cat` |
|---|---|---|
| 返回 | 一个 `Array[Vector2i]`（所有排除的格子混在一起） | 4 个 `Array[Vector2i]` 的数组（按规则类型分组） |
| 用途 | 简单高亮所有不可放格子 | 按颜色分组高亮（同行红色、同色区域蓝色...） |

### `if...if...if` — 不排他的条件

```gdscript
if r == cat.x:        # 同行？→ 放进 row_cells
    row_cells.append(p)
if c == cat.y:        # 同列？→ 放进 col_cells（可能同时满足！）
    col_cells.append(p)
```

**关键**：用 `if...if` 而不是 `if...elif`。一个格子可能**同时**满足多个条件——比如同行又同色。如果用了 `elif`，它就只会进第一个匹配的组，丢失其他分组信息。

### `return [a, b, c, d]` — 多值返回的模式

GDScript 的函数只能返回一个值。当你需要返回多个东西时，把它们装进一个 Array：

```gdscript
var groups = QueendokuCore.constraint_cells_for_cat(cat, size, regions)
var same_row = groups[0]     # Array[Vector2i] — 同行格子
var same_col = groups[1]     # Array[Vector2i] — 同列格子
var adjacent = groups[2]     # Array[Vector2i] — 相邻格子
var same_region = groups[3]  # Array[Vector2i] — 同色区域格子
```

这和 Go 的 `return a, b, c, d` 不同——GDScript 返回的是一个 Array，调用方用索引取值。没有显式返回类型标注（`-> Array` 而非 `-> Array[Array]`），因为数组包含不同类型时类型系统不够表达。

### 用途：高级提示系统

提示系统可以按规则类型对排除格子做**不同颜色**的高亮：
- 🔴 红色 = 同行的排除
- 🔵 蓝色 = 同列的排除
- 🟡 黄色 = 相邻的排除
- 🟢 绿色 = 同色区域的排除

玩家一眼就能看懂「为什么这个格子不能放」——每种颜色对应一条规则。

---

## `cells_excluded_by_cat_no_region` — 无区域约束版本

```gdscript
static func cells_excluded_by_cat_no_region(cat: Vector2i, size: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for r in range(size):
        for c in range(size):
            if r == cat.x and c == cat.y:
                continue
            if r == cat.x or c == cat.y or (abs(r - cat.x) <= 1 and abs(c - cat.y) <= 1):
                out.append(Vector2i(r, c))
    return out
```

### 和 `cells_excluded_by_cat` 的两处不同

| | `cells_excluded_by_cat` | `cells_excluded_by_cat_no_region` |
|---|---|---|
| `regions` 参数 | ✅ 有 | ❌ 没有 |
| 排除规则 | 同行 + 同列 + 相邻 + 同色 | 同行 + 同列 + 相邻（去掉同色） |

`cells_excluded_by_cat` 用 `_classify_pair(...) != Rule.NONE` 统一判断；这个函数直接 inline 写三条规则，跳过了区域检查。

### 用途

用于**没有颜色区域的场景**——比如新手教程的前几关、或者早期版本的简单模式。那些关卡只有行/列/相邻约束，没有同色区域。

---

## `is_complete` — 通关判断

```gdscript
static func is_complete(board: Array, size: int, regions: Array) -> bool:
    var piece_count := 0
    for r in range(size):
        for c in range(size):
            if board[r][c] == CellState.CAT:
                piece_count += 1
    if piece_count != size:
        return false
    return find_conflicts(board, size, regions).is_empty()
```

### 通关的两个条件

| 条件 | 检查方式 | 不满足时 |
|---|---|---|
| 1. 恰好 N 只猫 | `piece_count == size` | 直接 `return false` |
| 2. 没有冲突 | `find_conflicts(...).is_empty()` | 返回 `false` |

### `.is_empty()` 方法

Dictionary 和 Array 都有的方法——返回 true 表示容器里没有任何元素。

```gdscript
{}.is_empty()       → true
{"a": 1}.is_empty() → false
[].is_empty()       → true
[1, 2].is_empty()   → false
```

这里 `find_conflicts()` 返回一个 Dictionary。`.is_empty()` = 没有任何冲突格子 = 通关！

### 短路求值

为什么先检查数量？

`find_conflicts` 的时间复杂度是 O(p²)（p = 棋盘上的猫数量）。如果猫的数量都不对，根本没必要求冲突——直接返回 false。这是一个小的性能优化——不过在这个规模（最多 12×12）并不关键。更重要的是**语义清晰**：先确保猫的数量对了，再检查位置对不对。

---

## `validate_solution_entry` — 验证关卡数据的合法性

```gdscript
static func validate_solution_entry(entry: Dictionary, size: int) -> bool:
    var regions: Array = entry.get("regionMap", [])
    var solution: Array = entry.get("solution", [])
    if regions.size() != size or solution.size() != size:
        return false

    var board: Array = []
    for r: int in range(size):
        var row: Array = []
        row.resize(size)
        row.fill(CellState.EMPTY)
        board.append(row)
    for r: int in range(size):
        var c: int = int(solution[r])
        if c < 0 or c >= size:
            return false
        board[r][c] = CellState.CAT
    return is_complete(board, size, regions)
```

### 入参 `entry` 的结构

```gdscript
entry = {
    "regionMap": [     # 颜色区域图（二维数组）
        [1, 1, 2, 2, 3],
        [1, 2, 2, 3, 3],
        [1, 2, 3, 3, 4],
        [2, 2, 3, 4, 4],
        [2, 3, 3, 4, 4],
    ],
    "solution": [2, 0, 4, 1, 3],  # 解法：每行猫在哪一列
    "r": 3,                          # difficulty rank
    "tier": "N",                     # tier (Normal/Hard)
    ...
}
```

### `.get(key, default)` — 安全取值

```gdscript
var regions: Array = entry.get("regionMap", [])
```

如果 `entry` 里有 `"regionMap"` → 返回它的值。如果没有 → 返回默认值 `[]`（空数组）。

对比：

```gdscript
var x = entry["regionMap"]          # key 不存在 → 运行时错误！
var x = entry.get("regionMap", [])  # key 不存在 → 返回 []，安全
```

### `row.resize(size)` + `row.fill(value)` — 构建全空棋盘

```gdscript
var row: Array = []        # row = []
row.resize(size)           # row = [null, null, null, null, null]
row.fill(CellState.EMPTY)  # row = [0, 0, 0, 0, 0]
```

| 方法 | 做了什么 |
|---|---|
| `.resize(n)` | 把数组扩展到 n 个元素。新增的位置用 `null` 填充 |
| `.fill(v)` | 把数组所有元素替换为 v |

两步合起来：创建一条全 EMPTY 的行。循环 `size` 次 = 创建 size × size 的全空棋盘。

### `int()` — 类型转换

```gdscript
var c: int = int(solution[r])
```

`solution` 是从 JSON 文件读出来的。JSON 标准没有区分整数和浮点数——数字就是数字。Godot 的 JSON 解析器可能把 `2` 解析为 `float`。`int()` 强制转为整数，确保后续 `board[r][c]` 的索引是正确的类型。

### 三步验证流水线

```
1. 基本检查：regionMap 和 solution 都有 size 行？
   ↓ 通过
2. 构建棋盘：创建全 EMPTY 的 size×size 棋盘
   ↓
3. 按 solution 放猫：逐行在 solution[r] 列放 CAT
   ↓
4. 规则检查：is_complete() — 猫数量 = size？没冲突？
   ↓ 通过 → return true ✅
```

这个函数被 `LevelData.get_next_entry()` 调用。题库取出的每道题都要通过这个验证——如果验证失败，说明题库数据有问题，`LevelData` 会跳过这道题取下一道。

---

## 全部 9 个函数的关系全景

```
                    _classify_pair         ←── 原子操作：判断两只猫的关系
                   ╱    ｜    ＼    ＼
                  ╱     ｜     ＼    ＼
    find_conflicts  classify  find_     cells_
    (全局冲突检查)   _violation conflicting excluded
        ｜          (放猫前预判) _cats    _by_cat
        ｜              ｜     (找出冲突猫)(获取排除格子)
        ｜              ｜                    ｜
    is_complete     UI层：        UI层：    constraint_
    (通关判断)      显示错误文字   高亮冲突猫  cells_for_cat
        ｜                                  (分组排除)
        ｜
    validate_solution_entry        cells_excluded_by_cat_no_region
    (验证题库数据)                 (无区域约束版)

图例：
  ──  函数调用关系
  ｜  使用场景
```

---

## 本篇学到的全部概念

### cell_state.gd

| 概念 | 在哪 |
|---|---|
| `class_name` — 全局注册类型名 | 文件头 |
| `extends Object` — 不挂场景树的数据类 | 文件头 |
| `enum` — 枚举：有名字的整数常量 | 第 4 行 |
| `static func` — 类级函数，不用实例即可调用 | 所有三个函数 |
| `is_draft` vs `is_blank` vs `is_cross` — 三种不同语义的筛选 | 三个函数 |

### queendoku_core.gd

| 概念类别 | 具体学到的 |
|---|---|
| 基类选择 | `extends RefCounted` — 引用计数自动回收（vs `Object` vs `Node`） |
| 枚举技巧 | 值排成优先级顺序（1<2<3），利用 `<` 取最严重冲突 |
| 数据结构 | `Vector2i`（二维坐标）、二维数组 `arr[r][c]`、一维 solution 数组 |
| 二维数组访问 | `regions[a.x][a.y]` — 行号和列号都是动态的 |
| 配对循环 | `for i...for j in range(i+1, n)` — 不重复配对 |
| 遍历循环 | `for item in array` — 不关心索引时更简洁 |
| 类型推断 | `:=` — 编译器从右边表达式自动推断类型 |
| 私有约定 | `_` 前缀函数名 = 「外部别调」 |
| 流程控制 | `continue`（跳过本次循环）、`elif`（短路求值） |
| 安全取值 | `dict.get(key, default)` — key 不存在时返回默认值 |
| 数组操作 | `.resize(n)`、`.fill(v)`、`.is_empty()` |
| 类型转换 | `int()` — 强制转为整数 |
| 多值返回 | `return [a, b, c, d]` — 用 Array 封装多个返回值 |
| 排他 vs 并行 | `if...elif`（只进第一个）vs `if...if`（可能同时进多个） |
| 短路优化 | 猫数量检查在前（`is_complete`）、SAME_COLOR 提前 return（`classify_violation`） |
| Dictionary 去重 | key 唯一——重复写同一个 key 自动覆盖，O(1) 查询 |
| 纯函数设计 | 所有函数 `static`——不依赖实例状态，纯数据进纯数据出 |
| UI 与逻辑分离 | 规则引擎不碰 UI——返回纯数据，UI 层消费数据 |
