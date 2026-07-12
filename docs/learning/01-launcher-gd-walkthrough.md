# launcher.gd 精读 — 应用启动全流程

> 文件：[scripts/module/ui/panel/launcher.gd](../../scripts/module/ui/panel/launcher.gd)
>
> 这是整个 Meowdoku 应用的**大脑**。`_ready()` 是唯一入口，所有初始化逻辑从这里开始。
>
> **前置阅读**：[GDScript 七种根基抽象](00-gdscript-seven-abstractions.md) — 本文中所有「令・名・型・値・注・符・释」分类均基于此框架。

---

## 文件头：`extends` 和常量

```gdscript
extends Node
```

| 词 | 抽象 | 含义 |
|---|---|---|
| `extends` | 令（声明令） | 「我的基座是...」 |
| `Node` | 型（引擎节点型） | Godot 里最基本的节点类型 |

**为什么是 `Node`？** 因为 `launcher.tscn` 的根节点就是 `Node` 类型。`extends Node` 意思是「这个脚本只能挂在 Node 类型的节点上」。Node 是 Godot 所有节点的祖宗——它提供了 `_ready()`、`add_child()` 等所有节点都有的基础能力。

> 🧭 **新人关键认知**：在 Godot 里，脚本不是独立运行的。脚本必须**挂在节点上**。`extends` 告诉你这个脚本挂在哪种节点上。

---

```gdscript
const _CHEAT_COMMANDS: GDScript = preload("res://scripts/module/ui/panel/cheat_commands.gd")
const _CHEAT_OVERLAY: PackedScene = preload("res://addons/cheat_manager/cheat_overlay.tscn")
const _SPLASH_SCENE: PackedScene = preload("res://scripts/module/splash/ui/splash_page.tscn")
```

**`preload` vs `load`**：`preload` 在**编译时**加载（快，但路径必须写死），`load` 在**运行时**加载（灵活，但慢）。这里路径都是固定的，所以用 `preload`。

**`PackedScene` 是什么？** 场景文件的「压缩包」形态。`preload("xxx.tscn")` 返回一个 `PackedScene`，你可以调用 `.instantiate()` 来解压出一个真实的节点实例。类比：`.tscn` 是蓝图，`PackedScene` 是蓝图卷起来，`.instantiate()` 是按蓝图盖房子。

---

```gdscript
var _splash_page = null
var _startup_complete: bool = false
var _crashlytics_logger: LogUtil = null
var _in_game_log_buffer: InGameLogBuffer = null
var _perf_t0: int = 0
var _perf_last: int = 0
var _perf_emitted: Dictionary = {}
```

**`var` vs `const`**：`var` 盒子可以随时换内容，`const` 盒子装完就锁死了。

| 变量 | 类型 | 用途 |
|---|---|---|
| `_splash_page` | Node (隐式) | 持有闪屏页面引用，供 `_wait_splash_complete` 使用 |
| `_startup_complete` | bool | 启动完成后置 true，解锁快捷方式等回调 |
| `_crashlytics_logger` | LogUtil | 自定义日志器——捕获 `print()` 输出并上报崩溃系统 |
| `_in_game_log_buffer` | InGameLogBuffer | 游戏内日志缓冲区——用于游戏内 Debug 面板显示 |
| `_perf_t0` | int | 启动计时起点（毫秒） |
| `_perf_last` | int | 上一次打点时间（毫秒） |
| `_perf_emitted` | Dictionary | 防止同一阶段重复打点（`{"LOAD_SPLASH": true}`） |

---

## 完整 `_ready()` 逐段精读

### 阶段 1：日志 + 帧率 + 屏幕常亮（第 30-38 行）

```gdscript
_crashlytics_logger = LogUtil.new()
OS.add_logger(_crashlytics_logger)
_in_game_log_buffer = InGameLogBuffer.new()
InGameLogBuffer.instance = _in_game_log_buffer
OS.add_logger(_in_game_log_buffer)

Engine.max_fps = 60
DisplayServer.screen_set_keep_on(true)
```

**为什么第一个做**：这些是**纯基础设施**，不依赖任何 SDK、不依赖 AB 配置、不依赖网络。开机就能做，先做了让后续所有 `print()` 都能被日志系统捕获。

**`.new()` — 创建实例**：`LogUtil.new()` 是创建对象。类比：`LogUtil` 是蓝图，`.new()` 是按蓝图造一个对象。返回值是一个 LogUtil 实例的引用（自定义类是引用语义）。

**`Engine.max_fps = 60`**：锁 60 帧。手机游戏常规操作，省电防发热。

**`DisplayServer.screen_set_keep_on(true)`**：屏幕常亮，不让手机自动锁屏——玩游戏时必备。

---

### 阶段 2：语言 + 会话 + 持久化（第 40-47 行）

```gdscript
_perf_t0 = Time.get_ticks_msec()
_perf_last = _perf_t0

LanguageManager.apply_system_locale()

SessionManager.session_changed.connect(_on_session_changed)

GameState.consume_first_session_persist()
```

**打点计时起点**：`_perf_t0` 设在这里（不是文件头），因为前面几行是编译期常量、不计入运行耗时。

**`Time.get_ticks_msec()`**：引擎内置函数，返回从引擎启动到现在的毫秒数。跟 `Date.now()` 不一样——它不关心现实时间，只关心引擎跑了多久。

**`LanguageManager.apply_system_locale()`**：LanguageManager 是 autoload 单例，读取系统语言并应用对应的翻译文件。这个项目支持 60+ 种语言。

**信号连接**：

```gdscript
SessionManager.session_changed.connect(_on_session_changed)
```

| 词 | 抽象 | 含义 |
|---|---|---|
| `SessionManager` | 名（变量名，指向 autoload 单例） | 全局会话管理器 |
| `session_changed` | 名（信号名） | 一个事件频道：「会话变了」 |
| `.connect(...)` | 名（方法名） | 订阅这个频道 |
| `_on_session_changed` | 名（函数名） | 收到信号后执行的函数 |

**信号是什么？** 信号是**向上广播**的。SessionManager 不知道也不关心谁在听——它只管 emit。Launcher 选择订阅（connect），当会话变化时自动收到通知。

---

### 阶段 3：调试工具（第 49-51 行）

```gdscript
if not OS.has_feature("rel"):
    add_child(_CHEAT_COMMANDS.new())
    add_child(_CHEAT_OVERLAY.instantiate())
```

**`OS.has_feature("rel")`**：「rel」是 Godot 用 `export_release` 模板导出时自动添加的 feature tag。`not has_feature("rel")` = 不是在 release 构建 = 开发/调试模式。只有在调试模式下才加载作弊面板。

**场景树**：Launcher 节点调用 `add_child(cheat_panel)` → cheat_panel 成为 Launcher 的子节点 → 显示在屏幕上。Godot 的 UI 就是用节点树搭出来的。

---

### 阶段 4：Android 延迟 + 显示闪屏（第 53-58 行）

```gdscript
if OS.has_feature("android"):
    await get_tree().create_timer(1.0).timeout

_splash_page = UIManager.show_ui(UiName.SPLASH)

_hide_native_splash(500)
```

**Android 为什么等 1 秒？** Android 的原生闪屏需要一点时间来完成自己的过渡动画。不等的话 Godot 的闪屏会和原生闪屏重叠。

**原生闪屏 → Godot 闪屏的衔接**：先让 Godot 闪屏显示，再通知原生层「你可以退了，渐变 500ms」。两个闪屏短暂重叠 → 原生淡出 → 只剩 Godot 闪屏。视觉上是无缝过渡。

**`await`**：GDScript 的异步令。「停在这里，等后面的事情做完，再继续往下」。

**`get_tree()`**：获取当前场景树。场景树是整个应用的核心数据结构——所有节点都在树上。

---

### 阶段 5：等待 SDK 初始化 + 打点（第 60-78 行）

```gdscript
_emit_perf(Tracker.PerfStep.LOAD_SPLASH)

if UniKitManager.is_analyze_inited():
    _emit_perf(Tracker.PerfStep.INIT_GAME_MANAGER)
else:
    UniKitManager.analyze_init_completed.connect(
        _emit_perf.bind(Tracker.PerfStep.INIT_GAME_MANAGER), CONNECT_ONE_SHOT
    )
if UniKitManager.is_ad_inited():
    _emit_perf(Tracker.PerfStep.INIT_AD_MANAGER)
else:
    UniKitManager.ad_init_completed.connect(
        _emit_perf.bind(Tracker.PerfStep.INIT_AD_MANAGER), CONNECT_ONE_SHOT
    )

if UniKitManager.is_analyze_inited():
    _bind_crashlytics_user_id()
else:
    UniKitManager.analyze_init_completed.connect(_bind_crashlytics_user_id, CONNECT_ONE_SHOT)
```

**这段的节奏是**：闪屏已显示 → 打点 LOAD_SPLASH → SDK 可能还在后台初始化 → 已初始化的直接做，还没好的注册一次性回调。

**`CONNECT_ONE_SHOT` + `bind()`**：

| 概念 | 含义 |
|---|---|
| `.bind(参数)` | 给函数**预先绑定参数**。`_emit_perf.bind(X)` 返回一个新的 Callable——调用它时自动传 X |
| `CONNECT_ONE_SHOT` | 信号触发**一次后自动断开**，不会重复调用 |

**为什么用 `CONNECT_ONE_SHOT`？** `analyze_init_completed` 理论上只 emit 一次，但 `CONNECT_ONE_SHOT` 是双重保险——就算 SDK 异常 emit 了两次，打点也只发生一次。

---

### 阶段 6：快捷方式注册（第 80-82 行）

```gdscript
ShortcutManager.add_shortcuts(tr("SHORTCUT_FEEDBACK_TITLE"), tr("SHORTCUT_IMPORTANT_TITLE"))
ShortcutManager.connect_shortcut_received(_on_shortcut_received_pushed)
```

Android/iOS 桌面长按 App 图标会弹出快捷菜单（"反馈"、"重要提醒"）。这两行注册了菜单项，并连接了回调——当用户通过快捷方式进入时触发。

放在这里是因为 `ShortcutManager` 不依赖隐私、不依赖 ATT、不依赖 AB 配置——早注册早安全，不会错过任何快捷方式事件。

---

### 阶段 7：隐私弹窗 + ATT + 推送（第 84-100 行）

```gdscript
if UniKitManager.check_privacy_required():
    var privacy_dialog: Node = UIManager.show_ui(UiName.PRIVACY)
    await privacy_dialog.accepted
    UIManager.hide_ui(UiName.PRIVACY)
    UniKitManager.agree_privacy()

UniKitManager.init_att()

if (OS.has_feature("android") or OS.has_feature("ios")) and GameState.get_push_ask_count() < 2:
    UniKitManager.request_push_permission()
    await UniKitManager.push_permission_done
    GameState.inc_push_ask_count()

UniKitManager.set_push_enabled(true)
_clear_daily_pushes()
await get_tree().create_timer(0.5).timeout
_register_daily_pushes()
```

**执行顺序不是随意的**：

```
隐私弹窗 → 用户同意 → init_att() → 请求推送权限 → 注册每日推送
```

**隐私弹窗必须在 ATT 之前**。GDPR 要求先获得基础数据授权，再问追踪授权。

**`await privacy_dialog.accepted` 是全程唯一的阻塞点**。如果用户去泡杯咖啡回来才点同意，整个 `_ready()` 就停在这里。后续所有初始化（ATT、推送、AB 配置、预热）都要等用户点了同意才会继续。

**用户交互 = await 信号**：显示隐私弹窗后，代码「停住」（await）。用户点了同意 → 弹窗 emit `accepted` 信号 → `await` 结束 → 继续往下走。这是 Godot 处理异步用户交互的标准模式。

**推送注册前的 `await 0.5s`**：给原生推送系统一点喘息时间——`set_push_enabled(true)` 后系统可能需要几帧来初始化推送通道。

---

### 阶段 8：AB 配置 + 屏幕适配（第 102-108 行）

```gdscript
await get_tree().process_frame

await _wait_cmp_then_att_max_2s()

await ABTestManager.await_remote_ready(2.0)

ScreenManager.setup()
```

**`await process_frame`**：保证前面的 UI 操作（隐私弹窗关闭、推送注册）都在这一帧里完成了，下一帧再继续。

**CMP/ATT 等待**：对于需要弹 ATT 的 iOS 用户，这一行就是排队等用户同意/拒绝。

**AB 配置**：ATT 完成后（用户的选择可能影响 AB 分组），从服务器拉远程配置。最多等 2 秒——2 秒没回来就用本地默认值。

**`ScreenManager.setup()`**：此时 AB 配置已就位（有些 UI 变体依赖 AB 开关），屏幕尺寸也确定了，可以安全设置。

---

### 阶段 9：预热 + 音乐（第 110-112 行）

```gdscript
_prewarm_game()

_init_music_default_when_ab_loaded()
```

**预热必须放在 AB 配置之后**：`_prewarm_game()` 里用到了 `ABTestManager.rule_normal_rank.is_group_j()` 来决定棋盘大小算法。

**音乐初始化同理**：`_init_music_default_when_ab_loaded()` 用到了 `ABTestManager.bgm_test`。

---

### 阶段 10：等闪屏 + 最终路由（第 114-126 行）

```gdscript
await _wait_splash_complete()

_emit_perf(Tracker.PerfStep.END)

if _try_handle_shortcut():
    pass
elif GameState.is_tutorial_done():
    UIManager.show_ui(UiName.HOME)
else:
    UIManager.show_ui(UiName.TUTORIAL)

UIManager.hide_ui(UiName.SPLASH)
_startup_complete = true
```

**`await _wait_splash_complete()`**：这是 `_ready()` 里最后一个 `await`。前面所有初始化工作都做完了，最后保证闪屏至少展示了 2 秒。

**`_emit_perf(END)`**：启动完成。`perf_t0 → END` 的差值就是完整的冷启动耗时。

**路由决策**：

| 分支 | 条件 | 去向 |
|---|---|---|
| 1 | 从快捷方式进来 | `_try_handle_shortcut()` 内部处理 |
| 2 | 教程已完成 | 进首页 HOME |
| 3 | 教程未完成 | 进教程页 TUTORIAL |

**`_startup_complete = true`**：解锁所有被 `_startup_complete` 守卫的回调——之后 `_notification` 和 `_on_shortcut_received_pushed` 才会真正执行。

---

## 全流程时间线

```
t=0     日志 帧率 屏幕常亮
        │
t≈10ms  语言 会话 持久化
        │
t≈15ms  调试工具（仅 dev）
        │
t≈20ms  Android? → 等 1s
        │
t≈1s    显示 Godot 闪屏 ←── 从此刻起用户看到画面
        隐藏原生闪屏
        │
        注册 SDK 回调 快捷方式
        │
        ┌─ 隐私弹窗 ────────┐
        │  await 用户同意    │ ← 用户操作时间不可控
        └──────────────────┘
        │
        init_att()
        请求推送权限
        注册每日推送
        │
        CMP + ATT（iOS 可能弹系统弹窗）
        │
        拉取 AB 配置（最多等 2s）
        ScreenManager.setup()
        │
        _prewarm_game()        ← 后台偷偷准备
        _init_music()
        │
        _wait_splash_complete()← 保证闪屏≥2s
        │
        _emit_perf(END)        ← 启动计时结束
        │
        闪屏消失 → HOME/TUTORIAL
        _startup_complete = true  ← 启动完成 🔓
```

**核心设计原则**：每一个 `await` 的位置都代表对外部世界的依赖（用户、系统、网络）。不依赖的绝不阻塞，能并行的绝不串行。

---

## 所有函数的详解

以下按在 `_ready()` 中首次出现的顺序排列。

---

### `_emit_perf` — 性能打点

```gdscript
func _emit_perf(step: String) -> void:
    if _perf_emitted.has(step):
        return
    _perf_emitted[step] = true
    var now: int = Time.get_ticks_msec()
    Tracker.track_perf_monitor("app_start", step, now - _perf_last, now - _perf_t0)
    _perf_last = now
```

**做了什么事**：记录应用启动过程中每个阶段的耗时。

逐行拆解：

| 行 | 做了什么 | 新概念 |
|---|---|---|
| `if _perf_emitted.has(step): return` | 同一个阶段只记录一次，重复调用直接跳过 | `Dictionary.has()` — 判断 key 是否存在 |
| `_perf_emitted[step] = true` | 标记这个阶段「已经记录过了」 | `dict[key] = value` — 往字典里写 |
| `var now: int = Time.get_ticks_msec()` | 获取当前时间戳（毫秒） | 局部变量 `var` |
| `Tracker.track_perf_monitor(...)` | 上报给统计系统 | autoload 单例的方法调用 |
| `_perf_last = now` | 更新「上一次打点时间」，为下一次调用做准备 |  |

**`_perf_last` 和 `_perf_t0` 的区别**：
- `_perf_t0` — 起点，永远不动。`now - _perf_t0` = 「从启动到现在过了多久」
- `_perf_last` — 上一阶段的时间。`now - _perf_last` = 「上一阶段到这一阶段花了多久」

---

### `_hide_native_splash` — 隐藏原生闪屏

```gdscript
func _hide_native_splash(fade_ms: int) -> void:
    if OS.has_feature("ios"):
        if Engine.has_singleton("UniKitPlugin"):
            Engine.get_singleton("UniKitPlugin").hideSplash(fade_ms)
    elif OS.has_feature("android"):
        if Engine.has_singleton("SplashPlugin"):
            Engine.get_singleton("SplashPlugin").hideSplash(fade_ms)
```

**做了什么事**：App 启动时，iOS/Android 系统会先显示一个原生闪屏（静态图片）。等 Godot 引擎加载完、我们的闪屏页面显示后，就要把这个原生闪屏关掉。

**`Engine.has_singleton("X")` / `Engine.get_singleton("X")`**：检查/获取原生插件单例。Godot 通过 `Engine.get_singleton()` 桥接到原生代码。

---

### `_bind_crashlytics_user_id` — 绑定崩溃日志用户 ID

```gdscript
func _bind_crashlytics_user_id() -> void:
    var user_id: String = UniKitManager.get_uuid() if OS.has_feature("rel") else "debug"
    UniKitManager.set_crashlytics_user_id(user_id)
```

**做了什么事**：把用户 ID 告诉崩溃收集系统（Firebase Crashlytics）。这样线上崩溃时能知道是哪个用户触发的。

**三元表达式**：`A if 条件 else B` — 一行写完条件赋值。Release 用真实 UUID，开发模式用 "debug"。

---

### `_notification` — 系统通知回调

```gdscript
func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_IN and _startup_complete:
        _try_handle_shortcut.call_deferred()
```

**做了什么事**：当 App 从后台切回前台时，检查是否从快捷方式进来的。

**`_notification(what: int)`**：Godot 的**通知回调**。引擎发生特定事件时自动调用，`what` 是事件编号。

**`_startup_complete`**：守卫条件——启动还没完成时不处理（避免 _ready 中途被干扰）。

**`call_deferred()`**：**延迟调用**——等当前帧处理完再调用。避免在通知回调里直接做重操作导致引擎状态不一致。

**`_notification` vs `_ready`**：
- `_ready()` — 生命周期回调：只调用一次，节点进场景树时
- `_notification(what)` — 系统事件回调：调用多次，每次引擎发生特定事件时

---

### `_on_session_changed` — 会话变化回调

```gdscript
func _on_session_changed(new_session_id: String) -> void:
    print("[Launcher] SessionId change to %s" % new_session_id)
```

每当 SessionManager 检测到新会话（App 从后台回来超过一定时间），它 emit `session_changed` 信号，然后这个函数被调用。

**`%s` 字符串格式化**：GDScript 的字符串格式化。`%s` 是字符串占位符，`%d` 是整数占位符。类似 Python。

---

### `_clear_daily_pushes` — 清除旧推送

```gdscript
func _clear_daily_pushes() -> void:
    print("[xxztest]clear register daily push new pool")
    UniKitManager.remove_push("daily_noon")
    UniKitManager.remove_push("daily_evening")
```

**做了什么事**：先把之前可能注册过的推送全部删掉。每天两档——中午 (`daily_noon`) 和晚上 (`daily_evening`)。

**为什么要先删再加？** 如果 App 之前注册过推送，直接再注册会产生重复。先清再建保证干净。

---

### `_register_daily_pushes` — 推送的总调度

```gdscript
func _register_daily_pushes() -> void:
    if ABTestManager.push_local_text.is_new_pool():
        _register_new_pushes()
    else:
        _register_legacy_pushes()
```

**做了什么事**：根据 A/B 测试配置，走「新版推送文案」还是「旧版推送文案」。这是 A/B 测试的典型模式——**一个开关决定走哪条路**。

---

### `_register_legacy_pushes` — 旧版推送文案

```gdscript
func _register_legacy_pushes() -> void:
    var title: String = tr("PUSH_TITLE")
    var noon_contents: Array[Dictionary] = []
    for i: int in range(1, 5):
        noon_contents.append({"title": title, "content": tr("PUSH_CONTENT_%d" % i)})
    var evening_contents: Array[Dictionary] = []
    for i: int in range(5, 9):
        evening_contents.append({"title": title, "content": tr("PUSH_CONTENT_%d" % i)})
    UniKitManager.add_daily_push("daily_noon", 12, noon_contents)
    UniKitManager.add_daily_push("daily_evening", 20, evening_contents)
```

**做了什么事**：准备 4 条中午文案 + 4 条晚上文案，然后注册到系统。

**`tr("KEY")`**：Godot 的翻译函数。根据当前语言返回翻译后的文本。翻译内容在 `assets/localization/` 的 `.translation` 文件里。

**`range(1, 5)` 的陷阱**：`range(1, 5)` 是 `[1, 2, 3, 4]`，不包含 5。这和 Python 一样——左闭右开。

**`Array[Dictionary]`**：两个型嵌套。外层 `Array` 表示这是个数组，内层 `[Dictionary]` 表示数组里装的元素都是 Dictionary。

**Dictionary 字面量**：`{"title": title, "content": ...}` — 创建一个包含两个 key 的字典。

---

### `_register_new_pushes` — 新版推送文案

```gdscript
func _register_new_pushes() -> void:
    var noon_all: Array[Dictionary] = []
    for i: int in range(1, 101):
        noon_all.append(
            {"title": tr("PUSH_NOON_TITLE_%d" % i), "content": tr("PUSH_NOON_BODY_%d" % i)}
        )
    noon_all.shuffle()
    var evening_all: Array[Dictionary] = []
    for i: int in range(1, 101):
        evening_all.append(
            {"title": tr("PUSH_EVE_TITLE_%d" % i), "content": tr("PUSH_EVE_BODY_%d" % i)}
        )
    evening_all.shuffle()
    UniKitManager.add_daily_push("daily_noon", 12, noon_all.slice(0, 5))
    UniKitManager.add_daily_push("daily_evening", 20, evening_all.slice(0, 5))
```

**和旧版的区别**：

| | 旧版 | 新版 |
|---|---|---|
| 文案数量 | 4 条固定 | 100 条 |
| 选择策略 | 系统随机挑 | 先 `shuffle()` 打乱，再 `.slice(0, 5)` 取前 5 条 |

**新概念**：

| 方法 | 含义 |
|---|---|
| `.shuffle()` | 洗牌——把数组元素随机打乱 |
| `.slice(0, 5)` | 切片——取索引 0~4 的元素（不含 5） |

---

### `_prewarm_game` — 游戏预热

```gdscript
func _prewarm_game() -> void:
    await UIManager.warm_pool_async(UiName.GAME)
    var lv: int = GameState.get_current_level()
    var sz: int = (
        LevelData.get_size_group_j(lv)
        if ABTestManager.rule_normal_rank.is_group_j()
        else LevelData.get_size(lv)
    )
    var game: Node = UIManager.get_ui(UiName.GAME)
    if game != null and game.has_method("prewarm_board") and sz > 0:
        await game.prewarm_board(sz)
    if sz > 0:
        BankData.get_ranks(sz)
        BankData.get_lk_style_ranks(sz)
        BankData.get_gc_ranks(sz)
```

**做了什么事**：在玩家还看着闪屏时，偷偷把游戏页面、棋盘、关卡数据都准备好。等玩家点「开始」→ 游戏瞬间出现。

**为什么只预热游戏页面？** 因为游戏页面是唯一真正复杂的页面——它要创建 N×N 个 Cell 节点、初始化棋盘渲染、绑定输入手势。首页、设置页只是几个按钮和文字，`instantiate()` 几乎感知不到。

**对象池**：不每次都 `instantiate()` + `queue_free()`，而是提前创建好放池子里，用的时候拿，用完还回去。UIManager 的 `_cache` Dictionary 就是对象池。

**`has_method("prewarm_board")` — 鸭子类型**：GDScript 是动态语言，你可以不关心 `game` 的具体类型，只问「你有这个函数吗？」。

**题库预热**：`BankData.get_ranks(sz)` 首次调用时读磁盘文件（慢），之后走内存缓存（快）。预热 = 提前触发首次读取，把数据放进缓存。

**`lv` 的作用**：算出当前需要的棋盘 size，只精准预热这一个 size 的题库。不会去读其他 size 的文件——浪费内存。

---

### `_wait_cmp_then_att_max_2s` — 隐私合规等待

```gdscript
func _wait_cmp_then_att_max_2s() -> void:
    var emptyCallback: Callable = func() -> void: pass

    var is_android: bool = OS.has_feature("android")
    if is_android:
        UniKitManager.check_cmp(emptyCallback)
        return

    var shown_guide: bool = GameState.has_shown_att_guide()
    var att_status: int = UniKitManager.get_att_status()
    if (
        (shown_guide or att_status != UniKitManager.ATT_STATUS_NOT_DETERMINED)
        and not UniKitManager.debug_force_editor_test
    ):
        UniKitManager.check_cmp(AttGuideHelper.try_show_and_wait_dialog_close)
        return

    const CMP_MAX_WAIT_MS: int = 2000

    var state: Dictionary = {"cmp_done": false, "att_needed": false, "att_flow_done": false}
    UniKitManager.check_cmp(
        func() -> void:
            state.cmp_done = true
            if not UniKitManager.can_show_att():
                return
            state.att_needed = true
            await AttGuideHelper.try_show_and_wait_dialog_close()
            state.att_flow_done = true
    )

    var t0: int = Time.get_ticks_msec()
    while not state.cmp_done and Time.get_ticks_msec() - t0 < CMP_MAX_WAIT_MS:
        await get_tree().process_frame
    if not state.cmp_done:
        return
    if not state.att_needed:
        return

    while not state.att_flow_done:
        await get_tree().process_frame

    await get_tree().create_timer(1.0).timeout
```

**背景概念**：

| 缩写 | 全称 | 干什么的 |
|---|---|---|
| CMP | Consent Management Platform | 欧洲 GDPR — 弹窗问用户是否同意使用数据 |
| ATT | App Tracking Transparency | iOS — 弹窗问用户是否允许 App 追踪 |

**三个分支**：

| 平台 | 条件 | 处理方式 |
|---|---|---|
| Android | `OS.has_feature("android")` | `check_cmp(空回调)` 直接走人 |
| iOS fast path | ATT 不需要弹或已经选过 | `check_cmp(引导页)` 直接走人 |
| iOS 需要 ATT | ATT 还没确定 | 注册回调 → 轮询等 CMP（最多 2s）→ 等 ATT 引导页完成 |

**核心模式**：

- **`Callable` — 函数是第一公民**：`var cb: Callable = func(): pass`。在 GDScript 里可以把函数当成值一样传来传去——赋给变量、当参数传。
- **闭包捕获外部变量（引用语义）**：匿名函数内 `state.cmp_done = true` 修改的是外部的 Dictionary。Dictionary 是引用类型——闭包里改，外面也变。
- **`while ... await` 异步轮询**：每帧检查一次条件，不是死循环。
- **超时守卫**：`Time.get_ticks_msec() - t0 < 2000` 防止永远卡住。
- **Fast path 设计**：不需要 ATT 时直接 return 跳过复杂逻辑，减少不必要的等待。

**执行流图**：

```
_wait_cmp_then_att_max_2s()
│
├─ Android？ → check_cmp(空回调) → return ✅
│
└─ iOS：
    │
    ├─ 不需要 ATT 弹窗？ → check_cmp(引导页) → return ✅
    │
    └─ 需要 ATT 弹窗：
        │
        ├─ 注册回调（CMP 完成后自动执行 ATT 流程）
        │
        ├─ while 轮询等 CMP（最多 2 秒）:
        │   ├─ 超时 → return（放弃 ATT）
        │   └─ CMP 完成：
        │       ├─ 不需要 ATT → return
        │       └─ 需要 ATT：
        │           └─ while 等 ATT 引导页完成 → 再等 1s 缓冲 → return ✅
```

---

### `_init_music_default_when_ab_loaded` — 异步等 AB 配置加载音乐

```gdscript
func _init_music_default_when_ab_loaded() -> void:
    var cfg: BgmTestConfig = ABTestManager.bgm_test
    if not cfg.is_value_loaded():
        var timer: SceneTreeTimer = get_tree().create_timer(8.0)
        while not cfg.is_value_loaded() and timer.time_left > 0.0:
            await get_tree().process_frame
        if not cfg.is_value_loaded():
            return
    GameState.init_music_default(cfg.default_music_on())
```

**做了什么事**：等 AB 配置中的音乐开关加载完，然后决定默认音乐是开还是关。

**`SceneTreeTimer`**：Godot 对「等 N 秒」的官方封装。`timer.time_left` 返回剩余秒数。比手算 `now - t0` 更简洁。

**两种超时方式的对比**：

| 方式 | 适用场景 |
|---|---|
| `Time.get_ticks_msec()` 手算 | 超时逻辑复杂 |
| `create_timer()` | 单纯的「最多等 N 秒」，代码更简洁 |

**为什么音乐等 8 秒而 CMP 只等 2 秒？** 音乐是体验优化，错过不影响核心功能。CMP 是合规要求，必须尽快决定。

---

### `_wait_splash_complete` — 最少展示时间 + 强制完成

```gdscript
func _wait_splash_complete() -> void:
    if _splash_page == null or not is_instance_valid(_splash_page):
        return
    var elapsed_ms: int = Time.get_ticks_msec() - _perf_t0
    var wait_sec: float
    if elapsed_ms >= 2000:
        wait_sec = 0.5
    else:
        wait_sec = (2000 - elapsed_ms) / 1000.0 + 0.5
    await get_tree().create_timer(wait_sec).timeout
    if not is_instance_valid(_splash_page):
        return
    _splash_page.force_complete()
    await _splash_page.loading_complete
```

**核心设计：「最少展示 2 秒」**

```
如果启动花了 500ms  → 再等 (2000-500)/1000 + 0.5 = 2.0 秒 → 总共 2.5 秒
如果启动花了 2500ms → 再等 0.5 秒                                → 总共 3.0 秒
如果启动花了 5000ms → 再等 0.5 秒                                → 总共 5.5 秒
```

如果初始化逻辑很快（1 秒就全好了），闪屏也要撑到 2 秒——不然用户只会看到画面一闪而过。

**闪屏页面的 `_process(delta)`**：每帧更新进度条，使用缓出曲线渐进逼近 100%。进度条是纯装饰动画。

**`force_complete()` vs 直接关闭**：`force_complete()` 不直接结束闪屏——它设置标记，让进度条加速跑到 100% 后再结束。避免进度条在 70% 时突然消失。

**Launcher ↔ SplashPage 的交互模式**：

```
Launcher:  "你至少再活 1.5 秒"
           await timer...
Launcher:  "好了，可以结束了"
           _splash_page.force_complete()  →
                                              SplashPage: "收到，等我跑完进度条动画..."
                                              tween 跑完 → emit loading_complete →
           ← await loading_complete
Launcher:  "收到，你结束了"
```

---

### `_try_handle_shortcut` — 快捷方式处理

```gdscript
func _try_handle_shortcut() -> bool:
    var shortcut_key: String = ShortcutManager.get_shortcut_key()
    if shortcut_key == ShortcutManager.FEEDBACK_ACTION_ID:
        ShortcutManager.clear_shortcut_key()
        Tracker.track_remove_app_start()
        _open_feedback_from_shortcut()
        return true
    if shortcut_key == ShortcutManager.IMPORTANT_ACTION_ID:
        ShortcutManager.clear_shortcut_key()
        Tracker.track_remove_app_start()
        return false
    return false
```

**`return true/false` 的含义**：true = 我处理了，不用再跳首页/教程；false = 我没处理，继续正常流程。

**`clear_shortcut_key()`**：读完后立刻清掉——防止重复处理（比如 `_notification` 触发时再次读）。

---

### `_open_feedback_from_shortcut` — 从快捷方式打开反馈页

```gdscript
func _open_feedback_from_shortcut() -> void:
    var page := UIManager.show_ui(UiName.FEEDBACK)
    await page.closed
    UIManager.hide_ui(UiName.FEEDBACK)

    var game_node: Node = UIManager.get_ui(UiName.GAME)
    var daily_node: Node = UIManager.get_ui(UiName.DAILY_GAME)
    if (game_node != null and game_node.visible) or (daily_node != null and daily_node.visible):
        return
    if GameState.is_tutorial_done():
        var home_node: Node = UIManager.get_ui(UiName.HOME)
        if home_node == null or not home_node.visible:
            UIManager.show_ui(UiName.HOME)
    else:
        var tut_node: Node = UIManager.get_ui(UiName.TUTORIAL)
        if tut_node == null or not tut_node.visible:
            UIManager.show_ui(UiName.TUTORIAL)
```

**设计意图**：用户关了反馈页后，如果正在打游戏 → 回到游戏（不动）。否则 → 跳到首页/教程。

**`page.closed` 信号**：UIFrameWindow 基类上的信号。每个 UI 窗口关闭时 emit，让调用方知道「用户已经操作完了」。

**`node.visible` 检查**：判断某个场景是否正在显示中。`get_ui` 只是从缓存拿实例，不意味着它正在屏幕上。

---

### `_on_shortcut_received_pushed` — 快捷方式回调

```gdscript
func _on_shortcut_received_pushed(_type: String) -> void:
    if not _startup_complete:
        return
    _try_handle_shortcut.call_deferred()
```

**做了什么事**：当用户通过快捷方式进入 App 时（可能是 App 已经在后台运行），处理快捷方式事件。

**`_startup_complete` 守卫**：启动没完成时不处理——等 `_ready()` 末尾会统一处理。

**参数 `_type` 的下划线前缀**：GDScript 的约定——前缀 `_` 表示「这个参数我知道但我不用」。不加 `_` 的话编译器会警告 unused parameter。

---

## 本章学到的全部概念

| 概念类别 | 具体学到的 |
|---|---|
| Godot 生命周期 | `_ready()`, `_process(delta)`, `_notification()` |
| 信号通信 | `connect()`, `emit()`, `await signal`, `CONNECT_ONE_SHOT` |
| 异步模式 | `await`, `while...await` 轮询, `create_timer()` 超时, `SceneTreeTimer` |
| UI 管理 | 对象池, `show_ui/hide_ui`, `_cache`, `warm_pool_async` |
| 场景树 | `add_child()`, `get_tree()`, `instantiate()`, `call_deferred()` |
| 资源加载 | `preload()`（同步） vs `ResourceLoader`（异步） |
| 平台适配 | `OS.has_feature()`, `Engine.has_singleton()` |
| 数据类型 | `Callable`, `Dictionary`, `Array[Dictionary]`, 闭包, 匿名函数 |
| GDScript 语法 | `for...range`, `tr()`, `%s`/`%d` 格式化, 三元表达式, `bind()` |
| 设计模式 | 预热策略, 最少展示时间, fast path, 超时守卫, 条件编译 |
| A/B 测试 | 开关决定分支（新旧推送、棋盘大小算法、音乐默认值） |
