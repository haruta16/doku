# Hint Engine — 提示引擎

> 文件：[scripts/module/gameplay/core/hint_engine.gd](../../scripts/module/gameplay/core/hint_engine.gd)
>
> 这是 Meowdoku 的**解题引擎**——给定当前棋盘，自动推导下一步该放哪只猫或标哪些叉。它是 `QueendokuCore` 最大的消费者，也是「如果玩家点提示按钮，系统怎么算出答案」的全部逻辑。
>
> **前置阅读**：[核心玩法系统精读](02-core-gameplay-systems.md)

---

## 设计理念

提示引擎不是调 `_puzzle["solution"]` 查标准答案——**它是真的在解题**。

只认识四条规则（同行、同列、相邻、同色），全靠逻辑推导。这意味着提示引擎的输出**不依赖预先知道的答案**——即使在题库损坏、解法丢失的极端情况下，它也能独立算出正确结果。

引擎按策略复杂度分层：R1（最简单）→ R2 → R3 → R4 → R5（链式推导，最复杂）。每层都是「穷尽本层所有可能后，才上升到下一层」。

---

## 策略 R1：唯一候选格

`find_r1_hint(board, size, regions)` — 找「某行/某列/某区域只剩一个格子可以放猫」。

### 算法分三步

**第一步：统计已放的猫**

```gdscript
# 三个 bool 数组：row_piece[r]=true 表示第 r 行已经有猫了
var row_piece: Array[bool] = []  # size 个 false
var col_piece: Array[bool] = []  # size 个 false
var reg_piece: Array[bool] = []  # size 个 false
# 遍历棋盘，找到已放的猫 → 标记 row/col/reg
```

**第二步：全行同色的特殊情况**

```gdscript
for r in range(size):
    if row_piece[r]: continue                          # ← 这行已经有猫了，跳过
    # 检查整行是否都是同一个颜色
    var row_reg: int = regions[r][0]
    var row_uniform: bool = true
    for c in range(1, size):
        if regions[r][c] != row_reg:
            row_uniform = false; break
    if not row_uniform or reg_piece[row_reg]: continue # ← 不是全同色 / 该色已有猫

    # 这行全是颜色 A，且颜色 A 还没猫 → 这行的猫必须放在颜色 A 里
    # 但如果颜色 A 也在其他行 → 找到"全行同色 + 全列同色"的交点
```

这是 R1 中的优化：如果一整行都是一个颜色，且该色区域还没猫，那这行的猫必须在这个颜色里。如果再找到一个整列也是同色的交点——那个交点就是唯一解。

**第三步：行/列/区域只剩一个候选**

```gdscript
# 对每一行：如果没猫，找能放猫的格子，只有 1 个 → 找到了
for r in range(size):
    if row_piece[r]: continue
    var cands = []  # 遍历该行所有格子，_can_place(r,c) 的加入
    if cands.size() == 1:
        return { found: true, cell: cands[0], unit_type: "row", unit_index: r }

# 同理对每一列...
# 同理对每个颜色区域...
```

### `_can_place(r, c, ...)` — 这个格子能放猫吗？

```gdscript
static func _can_place(r, c, board, size, regions, row_piece, col_piece, reg_piece) -> bool:
    if board[r][c] != CellState.EMPTY:    return false  # ← 不是空格
    if row_piece[r]:                       return false  # ← 这行已经有猫了
    if col_piece[c]:                       return false  # ← 这列已经有猫了
    if reg_piece[regions[r][c]]:           return false  # ← 同色已有猫
    # 检查 3×3 邻域
    for dr in [-1, 0, 1]:
        for dc in [-1, 0, 1]:
            if board[r+dr][c+dc] == CellState.CAT:
                return false                            # ← 邻域有猫
    return true
```

这是**四条规则的完整检查**。和 `_classify_pair` 等价——只不过 `_can_place` 是针对「空格 vs 所有已存在的猫」的快速判断。`_classify_pair` 是针对两只具体猫的判断。场景不同，但规则完全一致。

---

## 策略 R1_mark：标叉推导

`find_mark_hint(board, size, regions)` — 找「因为已存在的猫，某些格子可以标叉」。

```gdscript
for r in range(size):
    for c in range(size):
        if board[r][c] != CellState.CAT: continue    # ← 找到一只猫

        # 同行所有空格 → 标叉
        # 同列所有空格 → 标叉
        # 3×3 邻域所有空格 → 标叉

        if to_mark.size() > 0:
            return { found: true, cat_cell: (r,c), unit_cells: to_mark }
```

更简单的逻辑：找到第一只猫 → 返回它排除的所有空格（同行、同列、相邻）。同色区域的标叉留给自动标叉系统（`_auto_mark_prefill_cats` 用 `QueendokuCore.cells_excluded_by_cat`）。

**为什么不用 `QueendokuCore.cells_excluded_by_cat`？** 因为 Hint Engine 用的是 `_can_place` 判断——只返回 EMPTY 的格子。`cells_excluded_by_cat` 返回所有冲突格子（包括已经有 MARK 的）。Hint 只需要告诉玩家「这些空格可以标叉」，不需要重复标。

---

## 策略 R2：候选格被限制在同行/同列

`find_r2_hint(board, size, regions)` — 两个方向的推断。

**方向 r2a**：「某颜色区域的所有候选格都在同一行」→ 该行其他颜色的格子可以标叉。

```
示例：颜色 3 还没放猫，颜色 3 的所有空格都在第 2 行
→ 第 2 行中颜色不是 3 的格子都不能放猫（因为颜色 3 必须占第 2 行）
```

**方向 r2b**：「某行的所有候选格都是同一颜色」→ 该颜色在其他行的格子可以标叉。

```
示例：第 4 行还没猫，第 4 行所有能放猫的格子都是颜色 5
→ 颜色 5 必须放在第 4 行 → 颜色 5 在其他行的格子都不能放猫
```

**实现**：先为每个颜色区域收集候选格（`reg_cands[reg]`），然后检查四个条件：

| 条件 | 检查 | 模式 |
|---|---|---|
| 某色候选格全在同一行 | `reg_cands[reg]` 的行号去重 = 1 | r2a_row |
| 某色候选格全在同一列 | `reg_cands[reg]` 的列号去重 = 1 | r2a_col |
| 某行候选格全是同一颜色 | 行候选格的颜色去重 = 1 | r2b_row |
| 某列候选格全是同一颜色 | 列候选格的颜色去重 = 1 | r2b_col |

额外检查 `has_new`：推导出的结论必须包含**新信息**（之前未知的格子可以标叉）。如果没有新信息，跳过这个提示——提示应该给玩家进展，不是重复已知事实。

---

## 策略 R3/R4：子集约束

`find_r3_r4_hint(board, size, regions)` —「k 个颜色区域的所有候选格全都在某 k 行/列里」。

**核心推理**：

```
如果 2 个颜色区域（A 和 B）的所有「能放猫的格子」都在第 3 行和第 5 行
→ 第 3 行和第 5 行的猫一定属于 A 或 B
→ 第 3 行和第 5 行中颜色不是 A 也不是 B 的格子 → 都标叉！
```

**算法**：把未放置的颜色区域按 k=2,3,4... 枚举子集。对每个子集，收集其候选格所在的所有行号。如果行号数量 == 子集大小（k 个区域刚好占了 k 行）→ 找到了 R3/R4 提示。

`k <= 3` 是 R3（简单约束），`k >= 4` 是 R4（复杂约束）。

`_gen_subsets` 是回溯法生成组合——标准算法（递归选或不选）。

**`max_k = min(unplaced.size() - 1, 6)`**：最多检查到 k=6。k 太大时组合数爆炸且实际价值不大（玩家自己也能看出来）。

---

## 策略 R5：链式推导（反证法）

`find_chain_hint(board, size, regions)` — 最复杂的提示：「如果在这里放猫，会导致矛盾，所以这里不能放猫」。

### `_chain_build_state` — 候选格建模

把棋盘转化为三个数组：
- `cands[r][c]`：第 r 行第 c 列能不能放猫（bool）
- `placed[r]`：第 r 行的猫在哪列（-1 = 还没放）
- `col_placed[c]` / `reg_placed[reg]`：该列/该区域是否已有猫

### `_chain_place(r, c)` — 模拟放猫

```gdscript
placed[r] = c                             # ← 标记已放
col_placed[c] = true
reg_placed[regions[r][c]] = true
# 同行所有其他列 → cands[r][*] = false （排除同行）
# 同列所有其他行 → cands[*][c] = false （排除同列）
# 3×3 邻域 → cands[邻域] = false（排除相邻）
# 同色区域 → cands[同色] = false  （排除同色）
```

### 核心算法：尝试 → 推导 → 矛盾？

```gdscript
for 每个空行 r:
    for 每个候选格 (r, c):
        # 1. 复制候选格数组
        # 2. 在 (r, c) 模拟放猫 → 排架大量格子
        # 3. 传播推导：如果某行只剩一个候选格 → 也放猫 → 再排除...
        # 4. 检查是否到矛盾：
        #    某行没有候选格了？→ 矛盾！
        #    某列没有候选格了？→ 矛盾！
        #    某颜色区域没有候选格了？→ 矛盾！
        #
        # 矛盾 → 「(r, c) 不能放猫」→ 返回提示
```

**这是反证法（Proof by Contradiction）**：假设在 (r, c) 放猫 → 逻辑推导 → 导致某行/列/区域无法放猫 → 结论：(r, c) 不能放猫。

**`best_depth`**：挑选「推导步数最少」的矛盾——矛盾越快出现，玩家越容易理解提示。

---

## `compute_r4_plus_cells` — 自动解题

```gdscript
static func compute_r4_plus_cells(board, size, regions, solution) -> Dictionary:
    # 循环执行：R1_mark → R1 → R2 → R3
    # 每次执行能推导出新信息就继续
    # 推导到无法进展为止

    # 最后：对比标准答案，找出「答案中有但推导不出的猫」
    # 这些就是 R4+（需要玩家自己推理的格子）
```

这个函数被用于题目的**难度评估**：一道题如果 `r4_plus` 为空，说明纯逻辑推导就能解出来（简单题）。如果有很多 R4+ 的格，说明需要更高级推理（困难题）。

---

## 完整策略层级

```
玩家点"提示"
    │
    ├─ R1     「第 3 行只剩一格能放猫」→ 直接告诉玩家放哪
    ├─ R1_mark「因为有这只猫，这些格子可以标叉」→ 高亮排除格子
    ├─ R2     「颜色 5 的候选格全在第二行」→ 高亮候选格 + 可标叉格
    ├─ R3     「2 个颜色区域刚好占 2 行」→ 高亮区域 + 排除格
    ├─ R4     「3-6 个颜色区域刚好占同等行数」→ 同上
    └─ R5     「假设放这里会导致矛盾」→ 显示推理链
```

## Helper 函数

| 函数 | 作用 |
|---|---|
| `_can_place(r, c, ...)` | 四条规则检查——这个空格能放猫吗？ |
| `_row_cells(r, size)` | 返回第 r 行的所有格子 |
| `_col_cells(c, size)` | 返回第 c 列的所有格子 |
| `_gen_subsets(arr, k)` | 生成 k 大小的所有子集（回溯法） |
| `_chain_build_state(board, ...)` | 构建候选格状态数组 |
| `_chain_place(r, c, ...)` | 模拟放猫，排除冲突候选格 |
| `_chain_try_contradiction(r, c, ...)` | 反证：假设在 (r,c) 放猫 → 推导 → 矛盾？ |
| `_apply_r2_marks(board, hint)` | 执行 R2 推导出的标叉 |
| `_apply_r3_marks(board, hint)` | 执行 R3 推导出的标叉 |

---

## 本篇学到的概念

| 概念 | 在哪 |
|---|---|
| 提示引擎不查答案——真正在解题 | 全文设计理念 |
| 唯一候选格：行/列/区域只剩 1 个空格 | `find_r1_hint` |
| 全行同色 + 全列同色 → 交点必放猫 | `find_r1_hint` Step 2 |
| `_can_place` = 四条规则的快速检查 | `_can_place` |
| 候选格约束：同色候选全在同一行 → 排除其他色 | `find_r2_hint` |
| 子集约束：k 个区域 = k 行 → 交集外可标叉 | `find_r3_r4_hint` |
| 回溯法生成组合 | `_gen_subsets` |
| 反证法：放猫 → 推导 → 矛盾 → 否证 | `find_chain_hint` |
| 传播推导：只剩一候选 → 强制放猫 → 继续推导 | `_chain_try_contradiction` |
| 最短矛盾链 = 最容易理解的提示 | `best_depth` |
| 自动解题循环：R1→R2→R3 穷尽推理 | `compute_r4_plus_cells` |
