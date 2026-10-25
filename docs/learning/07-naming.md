# 命名 — 怎么给变量和函数起名

> 这篇不讲「要用 camelCase 还是 snake_case」这种格式问题。格式由 GDScript 官方风格指南一句话规定完，真正难的是：
>
> **面对一个空白的 `var ` ，第一个字母该敲什么。**
>
> 本文所有例子都来自本项目 `scripts/`——这些标识符是从 APK 里原样恢复的原始名字，没有做过易读化重命名。也就是说，你看到的是**一位真实开发者的一手命名样本**，包括他起得好的和起得糟的。

---

## 一、先建立正确的心智模型

### 1.1 命名不是「起个好听的标签」，是「写下一条对自己成立的约束」

编译器只需要名字**唯一**，不需要它**有意义**。所以名字是纯为人写的。

它约束的对象有三个，按重要程度排序：

| 读者 | 什么时候读 | 名字坏了会怎样 |
|---|---|---|
| 三个月后的你自己 | 改这个 bug 时 | 你相信自己记得，结果记错了，改出新 bug |
| 现在读代码的你 | 想知道这行在干嘛 | 必须跳进函数体里反推 |
| 未来的接手者 / AI | 想复用这段逻辑 | 全局搜错关键词，漏掉一半调用点 |

所以判断一个名字好坏的唯一硬标准只有一条：

> **这个名字有没有说谎。**
>
> 名字是「一个格子当前的状态」→ 就不能在里面塞坐标。
> 名字是「点击」→ 就不能在双击时也发它。

名字难看但不撒谎，只是难看；名字好看但撒谎，是缺陷。

### 1.2 名字长度的判据不是字符数，是「歧义半径」

初学者常纠结「名字多长才合适」。正确的问题不是长度，是**这个词在这段代码里唯一指向什么**。

```gdscript
# scripts/module/gameplay/core/queendoku_core.gd:12
static func find_conflicts(board: Array, size: int, regions: Array) -> Dictionary:
```

`board` / `size` / `regions` 都只有 5 个字母左右，但没有任何歧义——这个文件只有这一块棋盘，`size` 只可能是边长，`regions` 只可能是色块图。**短名字在天生没有歧义时是优点。**

```gdscript
# scripts/module/gameplay/core/swipe_axis_guard.gd:10
var _slot: int = 0 # 相邻格子的像素步长（格宽 + 间隙）
```

同一个文件里有 `_n`（边长）/ `_slot`（步长）/ `_padding`（偏移）/ `_cell`（单格内容区）四个几何量，都跟棋盘尺寸沾边。这里必须区分，于是名字变长。**歧义大的地方，名字就必须长。**

所以：**短不是省事，短是特权的授予——只有当这个词在你这段作用域里天然唯一时才配得上。**

### 1.3 缩写只有两种合法情形

本项目里 `sz`（尺寸）出现 80 次，`idx` 36 次，`lv`（关卡号）26 次，`pos` 19 次。看起来项目喜欢缩写，但真正合法的缩写只有两类：

1. **通用到字典里都查得到的**：`idx`、`pos`、`btn`、`cfg`、`params`、`tmp`。
2. **本项目自己定义过、且处处一致的**：`sz` = 棋盘边长，`lv` = 关卡号，`CAT` / `MARK` / `DRAFT` = 猫 / 叉 / 草稿（各自 40 处以上，无一处例外）。

不合法的是第三类——**你自己临时发明的缩写**：

```gdscript
# scripts/module/bank/view/bank_page.gd:305,310（这两个名字在本文件里各出现 15 次以上）
var sf_p := StyleBoxFlat.new()   # p = pressed
var sf_f := StyleBoxFlat.new()   # f = focus
```

`sf_f` 这行旁边就写着 `StyleBoxFlat`——你会以为 `f` 是 flat，实际它指的是 focus。这就是「发明的缩写」的典型代价：**它比不缩写更慢读懂，因为它先误导你再纠正你。**

> **实用规则**：想缩写时先问「这个缩写在本文件出现过第二次吗，还是只此一处？」
> 只此一处 → 写全拼，字符数是免费的。
> 出现多次 → 才值得为「一致」付缩写这个代价。

### 1.4 格式约定（这部分唯一、机械、可背）

| 对象 | 写法 | 本项目实例 |
|---|---|---|
| 局部变量 / 参数 | `snake_case` | `start_cell`、`end_params` |
| 私有成员 / 内部函数 | 前置单下划线 | `_active_id`、`_load_size`、`_row_cells` |
| 类名 / `class_name` | `PascalCase` | `SwipeAxisGuard`、`BoardInputScheme` |
| 常量 / 枚举成员 | `UPPER_SNAKE_CASE` | `_DEDUP_WINDOW_MS`、`CellState.DRAFT_CROSS` |
| 文件名 | 与 `class_name` 对应的 `snake_case` | `swipe_axis_guard.gd` ↔ `SwipeAxisGuard` |
| 信号 | `snake_case`，**过去时** | `window_shown`、`anchor_changed` |
| 布尔 | `is_` / `has_` / `should_` 开头 | `is_draft`、`has_score`、`should_skip_shake` |

一条容易忽略的红线：**GDScript 的下划线私有性只是约定，不是语言强制**——外部照样能调 `_load_size`。所以下划线传递的信息是「这是我内部的事，别碰」，而不是「你碰不到」。

---

## 二、拿到一个空白名字时，从哪里下手

### 2.1 先用一句中文写下职责，再翻译成标识符

**先写句子，再起名字。** 句子里的每个成分都有固定去处：

```
「这个函数为【谁】，把【什么】变成【什么】，在【什么条件下】」
        ↓ 动词    ↓ 宾语   ↓ 结果    ↓ 条件（放最后当限定）
```

真实例子，逐级长大：

```gdscript
# scripts/module/game/level_ops.gd:7
static func confirm_level_failed_main(end_params: Dictionary, lv: int) -> void:
#              ↑动词      ↑宾语  ↑结果    ↑ 限定（主线；区别于 daily）
```

```gdscript
# scripts/module/abtest/abtest_manager.gd:289
func _finalize_app_start_dye() -> void:
#     ↑动词      ↑ 时机限定       ↑ 动作
```

```gdscript
# scripts/module/gameplay/core/hint_engine.gd:185
static func _row_cells(r: int, size: int) -> Array[Vector2i]:
#            ↑ 宾语     ← 动词被省略：私有 + 纯函数 + 只为内部服务（见下面 2.3）
```

反过来推：**如果你无法用一句中文说清这个函数干什么，那它很可能确实在干两件事，应该拆开。** 起不出名字，往往是设计问题的症状，不是语文问题。

### 2.2 七大功能前缀（照抄本项目，不是照抄教科书）

本项目 2456 个函数里，最高频的首词就是这套「动词前缀协议」：

| 前缀 | 说话内容 | 数量 | 本项目实例 |
|---|---|---|---|
| `on_` | 我是个回调 / 事件处理，**由外部时机触发** | 351 | `on_show`、`on_tap`、`on_restart_click` |
| `get_` | 我只读，**不改任何状态** | 225 | `get_cell_state`、`get_sizes` |
| `is_` / `has_` / `should_` | 我回答一个是非问题，返回 `bool` | 194 / 27 / 28 | `is_active`、`has_daily_fixed_slogan` |
| `set_` | 我写入（通常配合通知） | 103 | `set_zone` |
| `init_` / `setup_` / `_ready` | 我只在开局跑一次 | 82 | `init_done` |
| `apply_` | 我把一份数据真正落到界面上 | 57 | `apply_hint` |
| `try_` | **我可能失败**，请检查返回值 | 5 | `try_acquire` |

这张表最值钱的不是前缀本身，而是**它们对读者的承诺**：

- `get_xxx()` → 我保证没有副作用，你可以放心在循环里调、放心调两次。（反例：如果 `get` 里偷偷写存档，调用者会踩雷。）
- `try_xxx()` → 我明确告诉你可能失败，你有义务看返回值。

```gdscript
# scripts/module/game/view/hint_mutex.gd:9-10
# 尝试占用；已被别的提示占用则返回 false 并打日志
func try_acquire(hint_id: String) -> bool:
```

叫 `try_` 而不是 `acquire_`，就把「可能失败」从函数体里提到了名字上——调用者不用读实现就知道要判返回值。

### 2.3 动词怎么选：一个真实动词比三个形容词有用

中文习惯说「处理一下」「搞一下」，英文里对应的 `handle` / `process` / `do` 是**零信息动词**。它们只说明「有事情发生」，不说明发生什么。

对比同一件事的两种叫法：

| 弱 | 强 | 差别 |
|---|---|---|
| `process_board_data()` | `find_conflicts()` | 前者要读代码才知道在处理什么 |
| `handle_level_end()` | `confirm_level_failed_main()` | 后者直接告诉你「确认失败」这个决定 |

最大的收益不在改成信号，而在于**把一件事按出口拆开**——同一个「提示浮层」的三个出口，各有一个名字（出自同一个文件 `scripts/module/game/view/hint_overlay.gd:22-24`）：

```gdscript
# 弱：一个函数吞下三种意图
func do_hint() / func process_hint()

# 强：三个出口，三个名字
signal hint_applied            # 应用：让页面执行提示
signal hint_dismissed          # 忽略/取消/关闭：只关浮层
signal hint_detail_requested   # 请求更多说明
```

**名词短语拆得越干净，函数名就越不可能退化成 `handle_hint()`。**

一个查错技巧：**把你函数里的 `handle_` / `process_` / `_do_` 全部标红。** 它们不一定都错，但每一个都值得重新问一次「我到底做了什么」。

**别怕长**。本项目函数名平均 3 个词（2456 个函数的词数分布：3 词 848 个、4 词 547 个、2 词 570 个），最长的一批到 5~6 个词：

```gdscript
play_r2_preview_cell_delayed()   # board_view.gd:1002 → 播放 R2 预览格的延时版本
_hide_iq_bar_after_fireworks()   # tutorial_page.gd:614 → 烟花放完后收起 IQ 条
```

后者 6 个词讲了一个完整因果故事（谁 + 什么时机 + 做什么）。**名字长是因为事情本身有那么多信息，不是因为啰嗦。**

### 2.4 变量：按「活多久」分三档，各用不同标准

| 档位 | 寿命 | 命名标准 | 实例 |
|---|---|---|---|
| 循环变量 / 极短局部 | 3~5 行 | 允许单字母，**因为上下文就在眼皮底下** | `r` / `c`（行列）、`i` / `j`（配对下标） |
| 函数内普通局部 | 5~30 行 | 一个名词短语，能自解释 | `var errors: Dictionary`、`var pieces: Array[Vector2i]` |
| 成员变量 / 字段 | 整个对象生命周期 | 必须带**单位或语义限定** | `_slot`（像素步长）、`_tol_px`（越界像素）、`_run_count` |

单字母并非原罪，看它有没有被就地消歧：

```gdscript
# scripts/module/gameplay/core/queendoku_core.gd:13-19
for r in range(size):
    for c in range(size):
        if board[r][c] == CellState.CAT:
            pieces.append(Vector2i(r, c))
```

`r` / `c` 紧挨着 `board[r][c]`，`range(size)` 就在旁边——歧义半径是零。这里写 `row_index` / `column_index` 反而让三行变噪音。

但**字段不行**。字段离定义很远、离使用也很远，必须自带语境：

```gdscript
# scripts/module/gameplay/core/swipe_axis_guard.gd:16-17
var _tol_px: float = 0.0      # 锁定后允许的垂直越界像素
var _threshold: int = 4       # 判定锁定所需的连滑格数
var _run_count: int = 0       # 连滑区间覆盖的格数（区间长度，不是步数）
```

`_run_count` 的注释专门澄清「不是步数」——**当名字天然会和别的量混淆时，注释是对的补充；但更好的做法是让名字自己说清**（这里换成 `_run_span` 或 `_covered_cell_count` 就不需要澄清了）。

### 2.5 单位写进名字，不写进注释

本项目在这点上做得很好，值得整条抄走：

```gdscript
const _DEDUP_WINDOW_MS: int = 5000        # log_util.gd:21
var _total_active_sec: int                # 活跃总时长（秒）
var _active_seg_start_ms: int             # 当前活跃段的起点（毫秒）
var _tol_px: float = 0.0                  # 像素
var slot_px: int                          # 步长（像素）
```

为什么单位必须进名字：因为**注释会被改代码的人忘掉，名字会被编译器逼着一起改**。

反面教材同样真实存在：

```gdscript
var _threshold: int = 4    # 4 个什么？格数？秒？像素？
```

它靠行尾注释「连滑格数」兜住了。但如果哪天有人把注释删了，这个名字就彻底空转。

**规则**：名字里出现数字量却看不出单位时，加后缀 `_px` / `_sec` / `_ms` / `_count` / `_ratio`。

### 2.6 布尔与函数：句型和它的返回值必须同构

这是最省力也最容易出错的一类。**问句型 → bool；命令型 → void；名词型 → 值。**

```gdscript
# ✅ 问句，返回 bool：读起来就是一句英文
static func is_draft(s: int) -> bool:                    # cell_state.gd:12
func is_active() -> bool:                                # hint_mutex.gd:26
func has_daily_fixed_slogan() -> bool                    # splash_slogan_config.gd:29
func should_free_revive() -> bool                        # revive_free_logic_config.gd:19
func should_skip_shake() -> bool                         # wrong_cat_effect_config.gd:22

# ✅ 命令句，返回 void 或返回值
static func find_conflicts(...) -> Dictionary
func apply_hint(...) -> void
func release(hint_id: String) -> void

# ❌ 句型与返回值错位
func check_draft(s: int) -> bool     # check 是命令型，读起来像「去检查」
func draft(s: int) -> bool           # 名词型，像在问「这是草稿的编号吗」
```

布尔字段额外一条：**别用否定式命名**。

```gdscript
var not_ready: bool = false      # ❌ 调用处出现 if not not_ready: 直接晕
var is_active: bool = false      # ✅ 肯定式，取反只发生在调用处一次
```

### 2.7 信号：名字是「已经发生的事」，不是「请你做的事」

信号名描述**广播者身上已经发生的事实**；订阅者要做什么是订阅者的事。所以它用过去时 / 状态描述，绝不用祈使句。

本项目 59 个信号名，**一个祈使句都没有**：

```gdscript
# scripts/module/ui/ui_events.gd
signal window_created(ui_name: String, win: UIFrameWindow)
signal window_shown(ui_name: String, win: UIFrameWindow)
signal window_hidden(ui_name: String, win: UIFrameWindow)

signal anchor_changed(y: float)   # 过去分词：已经变了
signal _step_completed            # 过去分词：已经完成
signal hint_applied               # 过去分词：已经应用
signal hint_dismissed             # 过去分词：已经关掉
signal init_done                  # 状态定格：已经就绪
```

这份清单里 `created` / `shown` / `hidden` / `changed` / `completed` / `applied` / `dismissed` 全是过去分词。这不是巧合——**用过去时，语法本身就在替你保证"这不是一条命令"**。

反过来，如果信号叫 `show_window` / `apply_hint`，读者会瞬间分不清它是信号还是要调的函数，甚至写出「在订阅回调里直接调用另一个对象的 `show_window`」这种反向依赖。

**信号名与 GDScript 内置信号撞名时，改名要顺手把信息补上。** 本项目有个漂亮的范例：

```gdscript
# scripts/module/game/ui/compont/auto_mark_btn.gd:5
# 点击信号；不叫 pressed 是为了不和内置信号重名
signal pressed_with_state(is_marked_before: bool)
```

内置 `BaseButton` 已经有 `pressed`。作者没有敷衍成 `pressed2`，而是改成 `pressed_with_state`——**被逼改名时，是补信息的最佳时机**：新名字不仅避开了冲突，还额外说明了「这个信号比内置的多带一个状态」。

再看一个把「时序语义」写进名字的例子：

```gdscript
# scripts/module/game/view/hint_mutex.gd:9-16
# 尝试占用；已被别的提示占用则返回 false 并打日志
func try_acquire(hint_id: String) -> bool:
```

`try_acquire`（可能失败的**动作**）与 `hint_applied`（已成立的**事实**）在语法上是两类词。**同一件事的「尝试」和「结果」用不同的语法形状命名**，读者一眼能分出哪个是要调的、哪个是要等的。

还有一条几乎零成本、收益极高的约定——**订阅者的处理函数固定叫 `_on_<信号名>`**：

```gdscript
signal hint_applied                              # hint_overlay.gd:22
func _on_hint_applied() -> void:                 # base_game_page.gd:5233
```

本项目有 **257 个** `_on_` 开头的函数，全部遵守这个对应关系。好处是：**你只看函数名就能反查到它在监听哪个信号**，不用去搜 `connect()`。这条约定在 Godot 编辑器里还有加成——`.tscn` 里写连接时，编辑器会自动建议这个函数名。

### 2.8 类名：说不清它是什么，就是没设计完

```gdscript
class_name SwipeAxisGuard   # 滑动轴（Guard=守卫）→ 一个能挡东西的东西
class_name HintMutex        # 提示互斥锁 → 一个管互斥的东西
class_name CellState        # 格子状态表
class_name LevelOps         # 关卡收尾操作集合
class_name BoardInputScheme # 输入方案（一套打包好的策略）
```

这五个名字都同时回答了两个问题：**它是什么东西（名词），它负责什么（后半截）**。

一个可靠的练习：**给这个类起名时，先不看代码，只看它暴露的公开函数列表**。如果你能从函数列表反推出一个准确的名词，说明这个类职责是清楚的；如果你推出来是「Manager」「Helper」「Util」这种万金油——那说明它里面装了两件不相关的事。

本项目确实有 `LogUtil`、`UIHelper` 这类名字，但它们各自只装一类东西（`LogUtil` 全是日志出口，`UIHelper` 全是界面小工具），所以成立。**`Manager` 不是错名，它是一个警报**：看到它，就回头数数这个文件里服务了几个不同的对象。

### 2.9 枚举：让名字承担「顺序」和「关系」

```gdscript
# scripts/module/gameplay/core/queendoku_core.gd:7-8
# 违规类型：数字越小优先级越高，提示文案按这个顺序挑最该说的那条
enum Rule { NONE = 0, SAME_COLOR = 1, SAME_LINE = 2, NO_TOUCH = 3 }
```

注意显式写了 `= 0/1/2/3`，并在注释里说明了「数字越小优先级越高」——**枚举的数值本身是一份被名字承载的契约**。如果谁重排了顺序，提示文案的挑选逻辑就静默坏了。

对照反面：

```gdscript
# scripts/module/sound/sound_manager.gd:7-9
# 音效编号：每个 Kind 对应 _SOUND_PATHS 里的一条 ogg；顺序即枚举值，插到中间会挪动后面的映射
enum Kind { BOARD_ENTER, MARK_X, ... }
```

这里的名字写明了「插到中间会出事」，但枚举本身**没有显式赋值**。这属于可接受的取舍（枚举名确实自解释），但它把风险留在了注释里——**能用显式值消除的风险，不要留给注释。**

枚举成员名的写法：**不要重复枚举名**。

```gdscript
CellState.EMPTY          # ✅ 读作 CellState.EMPTY
CellState.CELL_STATE_EMPTY  # ❌ 冗余
```

### 2.10 字典字段名：最容易失控的一类名字

字典的键没有编译期检查，所以键名一旦起错，错误只会在运行时以 `null` 的形式出现。本项目有 1000+ 处字符串键访问，最高频的键是 `regions`(22) / `size`(13) / `pos`(12) / `label`(11) / `solution`(11)。

真实存在的混用（同一份代码里两种风格并存）：

```gdscript
"regionMap"   # ← camelCase，来自外部 JSON 文件的字段名
"regions"     # ← snake_case，来自 GDScript 内部约定
```

**这里没有绝对的对错，但有一条纪律**：

- 键来自**外部文件**（JSON、存档）时，键名不是你的名字，**必须原样照抄外部格式**——`regionMap` 不能为了好看改成 `region_map`，否则读不到数据。
- 键是**你自己在代码里造的**时，统一 `snake_case`，并且**成对出现**：谁写入这个键、谁读取这个键，必须是同一个字符串。

判断依据是**这个键的"作者"是谁**。而这也给出了这类名字的可用技巧：**当你有 5 个以上的键描述同一个对象（比如一关的 `size` / `solution` / `regions` / `rank` / `lv`），就该给它一个 `class_name`，而不是继续用字典。** 字典用在这个数量以下是效率，以上是隐患。

### 2.11 参数名：`p_` 前缀，以及"约定的作用域"

先看本项目里**全部**用到 `p_` 参数的地方——只有 6 个文件：

```gdscript
# scripts/module/game/input/operations/base_tap_operation.gd:10
func _init(p_board: BoardView) -> void:
    board = p_board       # ← p_board（参数）与 board（字段）同时存在，一眼看出谁赋给谁

# scripts/module/game/input/board_input_scheme.gd:12-13
func _init(
    p_tap: BaseTapOperation, p_double_tap: BaseDoubleTapOperation, p_swipe: BaseSwipeOperation
) -> void:
    tap_op = p_tap

# 唯一的模块外例子
# scripts/module/award/model/award_item.gd:11
static func make(p_kind: String, p_count: int) -> AwardItem:
```

六个文件全在 `scripts/module/game/input/` 里（外加 `award_item.gd`）。**而同一个项目里，另一个构造函数完全不这么写**：

```gdscript
# scripts/module/game_state/save_store.gd:28-38
func _init(
    password: String, dir: String, dual_slot: bool,
    path_a: String, path_b: String = "", ...
) -> void:
    _password = password       # ← 没有 p_，靠字段的下划线前缀来区分
    _dir = dir
```

`_password = password` 和 `tap_op = p_tap` 解决的是同一个问题——**参数名和字段名撞车，赋值语句读不出方向**——但用了两种手段：

| 手段 | 写法 | 有效条件 |
|---|---|---|
| 参数加前缀 | `tap_op = p_tap` | 字段是公开的（没有下划线） |
| 字段加前缀 | `_password = password` | 字段是私有的（有下划线）——**本项目的主流做法** |

**这是本节最有价值的一课**：`p_` 不是"这个项目的规矩"，它是**输入系统模块的局部习惯**——因为那个模块的字段恰好是公开的（`board` / `tap_op` 无下划线），参数就必须自己带标记。作用域正好覆盖它有用武之地的地方。

> **遇到任何命名约定，先问三件事**：
> 1. 它是**语言逼的**吗？（早期 GDScript 的参数/字段消歧，现代可直接 `self.board = board`）
> 2. 它是**项目级**的吗？（像"信号一律过去时"——59 个信号无一例外）
> 3. 还是只是**某个模块的局部习惯**？（像 `p_`，6 个文件）
>
> 只有第 2 种值得你无条件跟随；第 3 种要跟着它所在的模块走，出了模块就按模块外的写法；第 1 种可能已经过期，值得查一下当前语言版本。

引数多于 3 个、且类型相同的函数，还有个更好的处理——直接看本项目的反面案例：

```gdscript
# scripts/module/gameplay/core/swipe_axis_guard.gd:32-34
func begin(
    puzzle_size: int, slot_px: int, padding: int, cell_px: int, start_cell: Vector2i
) -> void:
```

五个参数全是数字，调用处 `begin(9, 120, 0, 90, cell)` 根本读不出谁是谁。**类型相同 + 超过 3 个 = 应该收进一个带具名字段的字典或小类。** 这里的 `puzzle_size` / `slot_px` 之所以还必须叫得这么全，正是因为它们在调用处失去了语境——名字在替签名还债。

---

## 三、命名自检：14 个问题

每次写完一个名字，扫一眼这张表。**前 6 条是硬缺陷，后 8 条是坏味道。**

| # | 自检问题 | 不合格示例 | 改法 |
|---|---|---|---|
| 1 | 这个名字会出现在哪条错误日志里？看到它我能定位吗？ | `process_data()` | `find_conflicts()` |
| 2 | 名字说的类型和实际类型一致吗？ | `var list: Dictionary` | `var label_by_id: Dictionary` |
| 3 | 名字承诺"读"，实际有没有写？ | `get_level()` 里偷偷改存档 | 改叫 `ensure_level()` 或拆成两个函数 |
| 4 | 名字承诺"已经发生"，实际是"请你去做"？ | 信号叫 `window_shown`，却在订阅里主动显示窗口 | 信号只描述事实，动作另起函数名 |
| 5 | 有没有数字量缺单位？ | `_threshold = 4` | `_threshold_cells = 4` |
| 6 | 布尔是不是否定式？ | `not_ready` | `is_ready` |
| 7 | 缩写是本项目已有约定吗？ | 自创 `sf_f`(=focus) | 写 `focus_box` |
| 8 | 动词有信息量吗？ | `handle_*` / `process_*` / `do_*` | 换成真实动作 |
| 9 | 这名字离开本文件还成立吗？ | 全局唯一的 `data` / `info` / `obj` | 加限定词 |
| 10 | 同一概念在本项目里有几个名字？ | `size` / `sz` / `n` / `count` 混用 | 挑一个，全项目照抄 |
| 11 | 函数名是名词吗？ | `func _row_cells()` | 改成动词，或明确它是 getter |
| 12 | 名字比返回值说的多一点吗？ | `get_size() -> int`，其实返回格数 | `get_cell_count()` |
| 13 | 参数超过 3 个且类型相同时，调用处读得出来吗？ | `begin(9,120,0,90,cell)` | 收进具名结构 |
| 14 | 我改了这个变量的含义，名字跟着改了吗？ | 名字还叫 `pos`，值已经变成索引 | **改名是重构的一部分** |

第 14 条最重要，因为它是唯一一条**在代码写完之后才有机会犯的错**。前面 13 条在起名时防，这条只能在改代码时防。

---

## 四、三个立刻能用的生成技巧

### 技巧 1：先写调用处

不知道函数叫什么时，**先在调用它的地方写一行「你觉得最自然的中文句子」，然后把中文换成标识符**。

```gdscript
# 想： 「提示引擎要生成整行的格子列表」
# 先写： var 整行的格子列表 = ???
# 再换： var row_cells = hint_engine.row_cells(r, size)
```

本项目 `hint_engine.gd` 里私有函数写成 `_row_cells` / `_col_cells`，正是这个思路的产物——**调用处读得通，名字就及格了**。

### 技巧 2：为「同一件事的不同阶段」建命名家族

命名最怕孤立地起。真正高效的做法是**成组地起**——先想清楚这件事分几个阶段，再给每个阶段一个名字。

本项目的输入系统就是一组完美示范（见 `docs/learning/03-input-system.md`）：

```
BoardStrokeContext   ← 手势的「状态」
CellAction           ← 手势产出的「数据包」
BaseTapOperation     ← 的「操作基类」
NormalTapOperation   ← 正常模式的「具体操作」
DraftTapOperation    ← 草稿模式的「具体操作」
BoardInputScheme     ← 把三个操作「打包成一套方案」
```

从 `Base*` 到 `Normal*/Draft*` 到 `*Scheme`，**名字本身就画出了类图**。你不需要看代码就知道继承关系和多态点在哪。

技巧：**当你写了第三遍 `xxx_normal` / `xxx_draft` 时，抽象基类的名字应该自动浮现为 `BaseXxx`。**

### 技巧 3：为项目建一份术语表，让名字可复用

命名的真正瓶颈不是「想不出词」，是**同一个概念第十次出现时想不起上次用的哪个词**。

本项目事实上已经形成了一份术语表（本文档末尾附有完整版）。养成习惯：**新造一个领域名词时，先全局搜一次它有没有已经存在的叫法。** 搜到了就照抄，搜不到才新增——然后把新增的记进术语表。

一个反例：`dye`（染色）在本项目专指 AB 测试分组（`dye_ab`、`_app_start_dyed`、`get_ab_dyeing_tag`）。这是个领域行话，第一次读到会懵，但它**在项目内 40 处完全一致**，所以它是好名字——只要它一致。**行话的一致性价值高于易懂性**：一个始终一致的怪词，比三个各自易懂的近义词好得多。

---

## 五、命名的反馈回路：什么时候必须改名

名字不会一次起对。下面这些信号出现时，**改名不是洁癖，是修复**：

| 信号 | 含义 | 处理 |
|---|---|---|
| 你需要写注释解释名字的意思 | 名字没完成任务 | 把注释的内容塞进名字 |
| 你读到自己三个月前的代码，读了 3 秒才想起它干嘛 | 歧义半径超标 | 加限定词 |
| 你在代码里看到 `# TODO 这个其实不是 xxx` | 名字在说谎 | 立刻改名 |
| 同一个变量在不同分支里代表不同东西 | 一个名字担了两件事 | 拆成两个变量 |
| 你发现自己在心里叫它别的名字 | 你的直觉已经给出了更好的名字 | 用那个 |

最后一条最有用。**如果你每次读到 `raw` 都在心里翻译成「还没解析的原始返回」，那它就该叫 `unparsed_response`。** 心译本身就是成本。

---

## 六、本项目术语表（起名时的"官方译名"）

用错术语比用错格式伤害大得多。以下是从 `scripts/` 里实际用法定下来的：

### 6.1 游戏领域

| 术语 | 含义 | 出处 |
|---|---|---|
| `board` | 棋盘（二维状态数组） | `queendoku_core.gd` |
| `cell` | 格子 | `cell_state.gd` |
| `CAT` | 猫 = 正式落子 | `CellState` |
| `MARK` | 叉 = 玩家手打的否决标记 | `CellState` |
| `ERROR` | 冲突错标 | `CellState` |
| `DRAFT_CROSS` / `DRAFT_CAT` | 草稿叉 / 草稿猫（临时推演，不算落子） | `CellState` |
| `LOCKED_MARK` | 锁定叉（不可再改） | `CellState` |
| `region` | 同色区域 | `queendoku_core.gd` |
| `lv` | 关卡号 | `level_ops.gd` |
| `rank` | 难度档（1~5） | `bank_data.gd` |
| `sz` | 棋盘边长（4~12） | `bank_data.gd` |
| `slot` / `padding` / `tol` | 格步长 / 左上偏移 / 容差（均带 `_px`） | `swipe_axis_guard.gd` |
| `bank` | 题库 | `bank_data.gd`、`level_bank_io.gd` |
| `hint` / `R1`~`R5` | 提示策略的五个层级 | `hint_engine.gd` |
| `stroke` | 一次完整拖拽手势 | `board_stroke_context.gd` |
| `scheme` | 一套打包好的输入策略 | `board_input_scheme.gd` |

### 6.2 UI 与流程

| 术语 | 含义 | 出处 |
|---|---|---|
| `page` | 整页（一级界面） | `game/view/game_page.gd`、`home/view/home_page.gd` |
| `frame` / `window` | 可弹的窗口/浮层 | `ui/base/ui_frame_window.gd` |
| `child_window` | 依附于 frame 的子窗口 | `ui/base/ui_child_window.gd` |
| `overlay` | 覆盖层 | `cheat_overlay.gd` |
| `toast` | 轻提示 | `game/view/game_normal_toast.gd` |
| `widget` | 可复用小组件 | `ui/widget/red_dot.gd`、`btn_with_tag.gd` |
| `red_dot` / `dot_id` | 红点 / 红点标识 | `ui/red_dot_center.gd` |
| `on_show` / `on_hide` | 窗口生命周期回调（框架调用，子类覆写） | `ui/base/ui_base_window.gd:74` |
| `on_stack_top` / `on_stack_bottom` | 窗口被压栈 / 出栈时的回调 | `ui/base/ui_frame_window.gd:26,31` |
| `ensure_xxx` | 保证存在——不存在则创建，存在则不动 | `game_state.gd:683`、`undo_highlight_executor.gd:40` |
| `create_and_cache` | 实例化并进缓存 | `ui_manager.gd:655` |

### 6.3 数据与埋点

| 术语 | 含义 | 出处 |
|---|---|---|
| `dye` | AB 测试分组（染色） | `abtest_manager.gd` |
| `dda` | 动态难度调整 | `dda_rank_config.gd` |
| `att` | App Tracking Transparency（iOS 隐私授权） | `att_guide_helper.gd` |
| `reload` vs `load` | 重刷 vs 首次加载 | `bank_data.gd`（只有 SP 题库有 reload） |
| `snapshot` | 结算快照 | `game_state.clear_endgame_snapshot()` |
| `sec` / `ms` | 秒 / 毫秒（**必须带在名字里**） | `_total_active_sec`、`_mark_entered_time_ms` |
| `sf` | StyleBox | `sf_f`、`sf_p`（见 1.3 的反面案例） |
| `_C` / `_CL` / `_CB` | 主色 / 淡底 / 描边（`bank_page.gd:293-295`） | `bank_page.gd` |

---

## 七、四句话总结

1. **名字是约束，不是标签** —— 唯一的硬标准是它有没有说谎。
2. **长度的判据是歧义半径，不是字符数** —— 天然唯一时短就是好，有兄弟变量时就必须长。
3. **先写中文句子，再翻译成标识符** —— 起不出名字，说明你还没想清这个函数到底做什么。
4. **改名是重构的一部分** —— 名字一旦说谎，它比没有名字更危险。

> 最后一句给自己的耐心：命名能力**只能靠读别人的代码长**，不能靠背规则。你手边这 2456 个函数名就是最好的教材——**读到一个让你瞬间明白的名字就抄下来，读到一个让你卡住的名字就问"换我会怎么叫"**。这两件事做够 100 次，命名就不再是问题。
