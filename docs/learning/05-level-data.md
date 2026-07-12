# Level Data — 难度曲线与关卡分配

> 文件：[scripts/module/gameplay/model/level_data.gd](../../scripts/module/gameplay/model/level_data.gd)
>
> 这是 Meowdoku 的**关卡系统**——棋盘大小怎么随关卡增长、哪些是特殊关卡、怎么从题库里取题。它连接了 `QueendokuCore`（题库验证）和 `BankData`（题库读取），也是 `GamePage._setup_entry_normal` 的核心依赖。
>
> **前置阅读**：[核心玩法系统精读](02-core-gameplay-systems.md) → [Game Page 精读](04-game-page.md)

---

## 阅读范围

`level_data.gd` 共 944 行，本文聚焦最能体现**难度曲线设计**的 5 个核心函数和 3 个辅助函数。题库选择逻辑（`get_next_entry` / `get_next_entry_main`）仅概述其设计思路。

---

## 核心一：`get_size(level_num)` — 难度曲线 = 查询表

```gdscript
const SIZES: Array[int] = [
    4, 4, 5, 5, 6,  5, 5, 6, 6, 7,    # 关卡 1-10
    6, 6, 6, 6, 7,  6, 7, 6, 7, 8,    # 关卡 11-20
    6, 7, 6, 7, 8,  6, 7, 8, 7, 8,    # 关卡 21-30
    ...共 100 个值...
]

static func get_size(level_num: int) -> int:
    if level_num <= 100:
        return SIZES[level_num - 1]
    return _SIZES_101_PLUS[(level_num - 101) % 10]   # ← 101 关后 10 关一循环
```

### 为什么是查询表而不是公式？

你可能会想：「为什么不用 `size = 4 + floor(sqrt(level))` 之类的公式？」

**因为难度曲线需要精确的手工控制**。4×4 出现在第 1 关，6×6 出现在第 5 关，7×7 出现在第 10 关——不是线性增长，而是锯齿状来回跳：

```
关卡:  1   2   3   4   5   6   7   8   9   10
大小:  4   4   5   5   6   5   5   6   6   7
              ↗        ↘
           增长       回退！让玩家喘口气
```

**锯齿式难度**：上一个大棋盘后面通常跟一个小棋盘当「休息关」。如果 7×7 后面直接来 8×8，玩家连续受挫会流失。6×6 作为缓冲，用户打完觉得「这关简单」→ 继续玩。

### 101 关后的循环

```gdscript
const _SIZES_101_PLUS: Array[int] = [7, 8, 7, 9, 10, 7, 8, 9, 8, 10]

return _SIZES_101_PLUS[(level_num - 101) % 10]
```

101 关之后不再逐关设计（太费人力），而是 10 关一个循环组。`% 10` 做取模：第 101 关 = `[0]` = 7，第 102 关 = `[1]` = 8，…，第 110 关 = `[9]` = 10，第 111 关 = `[0]` = 7 重新开始。

### `get_size_group_j` — A/B 测试的不同曲线

```gdscript
static func get_size_group_j(level_num: int) -> int:
    if level_num < 21:                         # ← 前 20 关和默认一样
        return SIZES[level_num - 1]
    if level_num <= 50:
        return _SIZES_GROUP_J_21_50[(level_num - 21) % 10]    # ← 21-50 用 J 组公式
    if level_num <= 100:
        return _SIZES_GROUP_J_51_100[(level_num - 51) % 10]   # ← 51-100 用 J 组公式
    return _SIZES_GROUP_J_101_PLUS[(level_num - 101) % 10]
```

**前 20 关两组完全一样**（对照组）。21 关之后开始分叉——J 组走不同的棋盘大小曲线。A/B 测试对比两组玩家的留存和付费，看哪个曲线更好。

---

## 核心二：`is_hard_level(level_num)` — 硬核关

```gdscript
static func is_hard_level(level_num: int) -> bool:
    return level_num >= 21 and level_num % 10 == 0
```

Hard 关 = 从第 20 关开始，每 10 关一次的「Boss 关」：20、30、40、50…

**两个条件**：
- `>= 21`：前 20 关没有 Hard 关（新手保护期）
- `% 10 == 0`：每 10 的倍数

```gdscript
static func is_hard_level_group_j(level_num: int) -> bool:
    return level_num >= 29 and level_num % 10 == 9
```

J 组的 Hard 关是 29、39、49… —— 延迟了 9 关入场（新手保护更长）。

**Hard 关和普通关的区别**：Hard 关给更难的题目（rank 更高或 tier = "H"），有火焰特效和 "HARD" 标题。Game Page 里 `_is_hard_level` 这个 flag 控制了很多行为。

---

## 核心三：`compute_prefill` — 新手引导的预填

```gdscript
static func compute_prefill(level_num: int, region_map: Array, solution: Array, sz: int) -> Array:
    if level_num < 1 or level_num > 10:
        return []                              # ← 只有前 10 关才预填

    var want_size_one: bool = level_num >= 7   # ← 第 7 关策略切换

    # 统计每个颜色区域的大小
    var region_area: Dictionary = {}
    for r in range(sz):
        for c in range(sz):
            var rid: int = region_map[r][c]
            region_area[rid] = region_area.get(rid, 0) + 1

    # 找合适的预填位置
    for r in range(sz):
        var c: int = solution[r]
        var rid: int = region_map[r][c]
        var area: int = region_area.get(rid, 0)
        if want_size_one and area == 1:        # ← 关卡 7-10：预填面积=1 的区域
            return [r, c]
        elif not want_size_one and area > 1:   # ← 关卡 1-6：预填面积>1 的区域
            return [r, c]

    return [0, solution[0]]                    # ← 兜底
```

**预填 = 进关卡时就已经有一只猫在棋盘上**。减少玩家的初始选择空间，降低难度。

**策略随关卡变化**：

| 关卡 | 预填策略 | 教育目的 |
|---|---|---|
| 1-6 | 预填面积 > 1 的颜色区域 | 教「同色区域只能有一只猫」 |
| 7-10 | 预填面积 = 1 的孤立格 | 教「面积 1 的区域必须放猫」 |
| 11+ | 不预填 | 玩家已经会了 |

---

## 核心四：`compute_puzzle_id` — 题目去重的「指纹」

```gdscript
static func compute_puzzle_id(sz: int, region_map: Array) -> String:
    # 1. 归一化区域编号（把 [5,7,7,5] 变成 [0,1,1,0]）
    var input_norm_str = _serialize_region_map(_normalize_region_map(region_map, sz))

    # 2. 生成 8 种变换（旋转×4 × 镜像×2），取字典序最小的作为「规范形」
    var canonical_str = 所有变换中最小的字符串

    # 3. 算 SHA256 的前 16 位 hex
    var hash16 = canonical_str.sha256_text().substr(0, 16)

    return "%d_%s" % [sz, hash16]  # 如 "5_a1b2c3d4e5f6a7b8"
```

**为什么需要这个？** 同一道题经过旋转/镜像会变成不同的 `regionMap`。如果玩家连续两关遇到旋转后的同一道题，会觉得「重复了」。`compute_puzzle_id` 把旋转/镜像等价类映射到同一个 ID——记录玩家见过的 ID，就能跳过重复。

Game Page 的 `_setup_entry_normal` 调了这个函数并做了去重逻辑（`record_puzzle` → 发现重复 → 跳过取下一题）。

---

## 核心五：`get_next_entry` — 从题库取题

```gdscript
static func get_next_entry(sz, rank, tier, remaining_attempts = -1) -> Dictionary:
    # 1. 从三个题库来源拿数据
    var regular = BankData.get_levels_by_tier(sz, rank, tier)
    var lkstyle = BankData.get_lk_style_levels_by_tier(sz, rank, tier)
    var gc = BankData.get_gc_levels(sz, rank)   # 仅特定 size 有

    # 2. 按索引轮询（idx % total），循环取题不重复
    var idx = GameState.get_bank_index(sz, rank, tier)
    var real_idx = idx % total

    # 3. 单区域过滤（A/B 测试：禁止超过 2 个面积为 1 的区域）
    if 过滤条件不满足:
        GameState.advance_bank_index(...)
        return get_next_entry(sz, rank, tier, remaining_attempts - 1)  # ← 递归重试

    # 4. 验证题目合法性
    if not QueendokuCore.validate_solution_entry(entry, sz):
        push_error("题库内题不合法，跳过")
        GameState.advance_bank_index(...)
        return get_next_entry(sz, rank, tier, remaining_attempts - 1)  # ← 递归重试

    # 5. 推进进度指针
    advance_for_entry(entry, sz)
    return entry
```

### 设计要点

**索引轮询**：`idx % total` 确保题库里的每道题都会被用到。不是在题库里随机挑——那样有的题永远用不到，有的题反复出现。

**递归重试 + `remaining_attempts` 上限**：如果当前这道题不合法（被过滤规则毙掉），`advance_bank_index` 跳过它，递归再取下一道。`remaining_attempts` 递减——防止无限递归。跌到 1 时直接返回当前题（不管合不合法），避免死循环。

**三个题库来源**：

| 来源 | 含义 |
|---|---|
| `regular` | 标准题库（`bankDataN×N.json`） |
| `lkstyle` | LK 风格题库（更难的变体） |
| `gc` | GC 题库（仅特定 size/rank 组合） |

三个来源的题目被拼成一个虚拟的大数组，`idx` 按顺序轮询——用户无感，但题库池大了三倍。

---

## 辅助函数

### `strategy_to_rank(strategy)` — 玩家实力 → 题目难度

```gdscript
static func strategy_to_rank(strategy: int) -> int:
    match strategy:
        5: return 4
        6: return 5
        7: return 5
        _: return strategy   # strategy 1-4 → rank 1-4 直接映射
```

**strategy** 是系统对玩家实力的评估（1-7），**rank** 是题目难度等级（1-5）。不是线性映射：strategy 5→rank 4（给偏高难度但不到顶），strategy 6-7→rank 5（顶格难度）。

### `strategy_to_tier(strategy)` — 普通还是困难

```gdscript
static func strategy_to_tier(strategy: int) -> String:
    match strategy:
        5: return "H"
        7: return "H"
        _: return "N"
```

tier "H" 的题目用了更难的算法（更少的提示步骤），tier "N" 是标准难度。

### `get_strategy(level_num)` — 获取当前策略

```gdscript
static func get_strategy(level_num: int) -> int:
    if level_num <= 5:
        return 1                         # ← 前 5 关永远最低难度
    var strategy = GameState.get_current_strategy()
    if level_num >= 51 and strategy < 2:
        strategy = 2                     # ← 51 关后保底难度
    return strategy
```

策略存在 `GameState` 里（跨关卡持久化）。前 5 关锁在 strategy=1（最简单的题），51 关后锁在 ≥2（不给太简单的题，玩到 51 关的玩家不需要 baby mode）。

---

## 全貌：`get_level_entry(level_num)` — 取一关的完整数据

这个函数是 GamePage 在 `on_show` 时调的主入口。流程：

```
get_level_entry(level_num)
  │
  ├─ 特殊关卡？（10, 20, 30...）→ 从 SP/LK 题库取固定题目
  │
  ├─ 计算 sz = get_size(level_num) 或 get_size_group_j
  │
  ├─ 计算 strategy → rank + tier
  │     ├─ Hard 关？→ rank 固定为 4/5
  │     └─ 普通关？→ strategy → rank + tier（受 AB 测试 rnr 参数影响）
  │
  ├─ get_next_entry(sz, rank, tier) → entry
  │
  └─ 返回 entry { regionMap, solution, size, rank, ... }
```

Game Page 拿到 entry 后，`regionMap` → `_puzzle["regions"]`（棋盘渲染用），`solution` → `_puzzle["solution"]`（判对错用）。

---

## 本篇学到的概念

| 概念 | 在哪 |
|---|---|
| 难度曲线 = 手工查询表（不是公式） | `SIZES` 数组 + `get_size()` |
| 锯齿式难度：增长 + 回退 = 保持心流 | `SIZES` 数组中 7→6 的回退 |
| 循环组设计（101 关后 10 关一轮） | `% 10` 取模 |
| A/B 测试的难度分叉 | `get_size_group_j` vs `get_size` |
| 新手保护：前 5 关 strategy=1、前 20 关无 Hard | `get_strategy` / `is_hard_level` |
| 预填的教学设计：1-6 关教同色、7-10 关教孤立格 | `compute_prefill` |
| 题目去重：规范形 + SHA256 | `compute_puzzle_id` |
| 索引轮询取题 + 递归重试 + 上限防止死循环 | `get_next_entry` |
| 三题库拼合 | regular + lkstyle + gc |
| `match` 语法 | `strategy_to_rank` / `strategy_to_tier` |
| `%` 取模运算的循环用途 | 多处 `% 10` |
