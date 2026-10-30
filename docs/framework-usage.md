# 使用与验证公共框架

这份文档首先面向**在独立 Godot 工程中使用公共能力**，然后介绍 Meowdoku 如何接入。公共组件可以按需使用，不要求新产品采用 Doku 的玩法、产品存档或整套服务。当前源码的资源路径约定是 `res://scripts/framework/`；这不是已发布的插件包或多产品生成器。

## 先确认所有权

| 位置 | 归属 | 新产品如何使用 |
|---|---|---|
| `scripts/framework/` | 公共机制：存储、事务、窗口、内容交付及通用显示辅助 | 按下面的依赖表接入；不能反向引用产品单例或产品资源 |
| `products/meowdoku/app/` | **Meowdoku 产品**：启动、存档结构、平台、首页、设置、奖励、路由等 | 阅读其装配方式，不作为公共框架整体复制 |
| `products/meowdoku/gameplay/application/` | **Meowdoku 的玩法用例与产品策略**：选题、难度、对局适配、结算 | 新产品写自己的规则，不继承这里的产品政策 |
| `products/meowdoku/gameplay/content/`、`presentation/` | **Meowdoku 的内容合同与表现** | 题库、配置、页面、输入和资源消费者随该产品维护 |
| `products/meowdoku/gameplay/domain/` | 可独立运行的 Meowdoku 棋盘规则 | 仅需要 Doku 时选择使用；它不是所有产品的框架依赖 |
| `scripts/examples/block/`（含 `domain/`） | 验证接入的 Block 规则与独立示例 | 可运行、可参考，但不是通用产品业务或完整 Block 产品 |
| `products/meowdoku/assets/` | Meowdoku 的产品资源 | 新产品使用自己的资源 |
| 根 `project.godot`、`export_presets.cfg`、已接入的 `addons/` | 当前 Meowdoku 工程入口、导出和插件集成 | 新产品使用自己的配置；插件按能力单独评估 |

`products/meowdoku/` 明确表示当前产品；其中 `app` 是产品装配，`gameplay/application` 是产品玩法用例，两者都不属于公共框架。产品内部允许依赖自己的状态、平台和页面；公共层不应通过产品名分支处理这些差异。少量产品代码相似时，可以各自维护，等职责确实稳定且相同再提取。

## 新产品的最小接入步骤

1. 建立自己的 Godot 工程，配置自己的主场景、应用标识和存档目录。不要从 Meowdoku 的 `project.godot` 继承全部 Autoload。
2. 将需要的公共源码及其 `.uid` 保留在新工程的 `scripts/framework/` 路径下。首次接入可以复制整个公共目录，减少遗漏内部依赖；无需复制 `products/`、`scripts/examples/`、当前产品的插件或 `.godot/` 缓存。这是源码接入约定，正式多产品维护时需记录来源版本，避免多份代码无记录地分叉。
3. 让 Godot 编辑器完成导入和全局类扫描，再编写产品入口。公共组件以普通对象或节点创建，不要求新增特定 Autoload；产品是否将自己的入口设为 Autoload，由产品决定。不要给产品类重复使用框架已有的 `class_name`。
4. 按下表提供配置和业务合同，先完成一条实际流程，再按需增加其他组件。保存失败、内容不可用、窗口创建取消都属于需要处理的结果。
5. 在新工程实际运行该流程。仓库的独立测试证明公共组件的已测边界，不能代替新产品自己的资源、SDK、导出和真机验收。

以下依赖是源码范围，不是必须同时开启的功能。保留目录内被 `preload`/全局类引用的文件；若需要更小子集，可参考现有独立运行器的显式文件清单。

| 需要的能力 | 公共源码范围 | 产品必须提供 | 不需要带入 |
|---|---|---|---|
| 存储事务 | `operation_result.gd`、`storage/` | 独立目录与槽路径、密码、schema 版本、初始状态、状态校验器 | 对局、奖励、UI、Doku、产品 GameState |
| 对局事务 | 上述存储或等价端口、`application/round_service.gd` | 模块 ID、模式 ID、五方法规则模块、请求身份；状态中的 `inventory` 与 `round_services` 字典 | Meowdoku 的难度、复活、选题与页面 |
| 库存与待领奖励 | 存储或等价端口、`application/economy_service.gd` | 已登记库存、领取资格、稳定 `claim_key`；奖励序号/待领列表/去重记录的产品 schema 与校验 | Meowdoku 奖励弹窗、广告 SDK、签到 |
| 窗口管理 | `ui/` 的窗口基类、管理器、层配置、事件、遮罩及辅助依赖 | 主场景、自己的 `UIFrameWindow` 场景、路由表；声音/场景准备回调可省略 | 产品 UIManager、UiName、UIRegistry、声音单例 |
| 内容交付 | `content/` | 产品与运行时标识、公钥、独立目录、渠道、内容校验、启动与确认时机 | DokuContentValidator、Meowdoku ContentRuntime |
| 场景资源替换 | `content/`、`presentation/content_scene_bindings.gd` | 自己的资源绑定表及内容；显式配置 `content/scene_bindings_path` | Meowdoku 的绑定表、纹理与 Spine 动画 |
| 显示辅助 | 所需的 `ui/extensions/` 或 `ui/common/` 脚本及其依赖 | 对应 Godot 节点及所需布局 | 产品主题与预制体；产品 Toast 和链接行为在 `products/meowdoku/app/ui` |

组件采用本工程已验证的 Godot 4.6.1 API。仓库验证使用带 Spine 的定制引擎；使用 Spine 资源需要匹配的运行时。没有使用 Spine 的产品不必引入其资源与产品配置，但不同引擎构建的兼容性仍应在目标环境验证。运行器接受 `--godot` 指定引擎，默认本机路径不是框架安装要求。

## 从一份产品存档开始

下面是完整的 `RefCounted` 产品存储适配脚本，可放进新产品自己的目录。它只使用公共存储，不需要 UI、对局或 Autoload。调用方先调用 `open(directory, password)` 并检查返回值，再调用 `set_score()`；目录应属于该产品，密码由产品传入。

```gdscript
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")
var _core: LocalCoreStore

func open(directory: String, password: String) -> Dictionary:
    var files := SaveStore.new(
        password, directory, true,
        directory.path_join("a.cfg"),
        directory.path_join("b.cfg"),
        directory.path_join("flag")
    )
    _core = LocalCoreStore.new(files, 1, _validate_state)
    return _core.open({"score": 0})

func set_score(score: int) -> Dictionary:
    if _core == null or not _core.is_open():
        return Result.failure("not_open")
    var expected: int = _core.revision()
    var candidate: Dictionary = _core.snapshot()
    candidate["score"] = score
    return _core.commit(candidate, expected)

func read_score() -> Dictionary:
    if _core == null or not _core.is_open():
        return Result.failure("not_open")
    return Result.success({"score": int(_core.snapshot().score)})

static func _validate_state(state: Dictionary) -> String:
    if typeof(state.get("score")) != TYPE_INT:
        return "score must be an integer"
    if state.score < 0:
        return "score must not be negative"
    return ""
```

`open()` 只在文件确实不存在时采用初始状态，默认不会立刻写盘。产品需要把首次创建或旧档迁移立即持久化时，调用 `open(initial_state, true)`：首次文件提交成功后才发布 opened、状态和 revision；失败仍保持关闭，可在同一实例重试，旧档不被修改。该选项不重写已有有效存档，默认模式仍不发首次提交通知。`corrupt`、`schema_mismatch` 或其他失败必须交给产品恢复流程，不能当作新用户清档。`set_score()` 返回 `ok=false` 时，活状态仍为上一次成功提交；页面不应显示为已保存。调用方可记录 `OperationResult.describe(result)`，向玩家展示产品自己的提示，不直接暴露诊断文字。

`LocalCoreStore.snapshot()` 返回副本。一次操作先读取 revision、构造候选，再提交；发生 `conflict` 时应重新读取并重新计算该业务动作，不能无条件覆盖新状态。提交成功会同步发出 `committed`，监听器可能重入；实际产品会话仍须拒绝旧回执覆盖新局。一个存档目录使用一个写入者，不将多个进程同时写盘当作受支持能力。

存储只保证数据可持久化及调用方提供的校验，不会猜测“分数、关卡或资格在业务上是否有效”。奖励的 `stage_*()` 方法同样只修改候选；任一步失败后丢弃整份候选，不能把部分变更继续提交。

## 独立使用窗口机制

`UIWindowManager` 不读取 `UiName`、`UIRegistry`、声音单例或产品资源。宿主在创建窗口之前配置注册表，再将管理器加入树；窗口挂到当前场景。每个窗口继承 `UIFrameWindow`，自行实现 `on_create/on_show/on_hide`。

以下代码可放入产品主场景脚本；先创建自己的 `res://my_game/settings.tscn`，其根节点脚本继承 `UIFrameWindow`。管理器创建后由按钮等产品入口调用 `open_settings()`，声音与资源替换均可不接入。

```gdscript
extends Node

var _windows: UIWindowManager

func _ready() -> void:
    _windows = UIWindowManager.new()
    _windows.configure({"settings": "res://my_game/settings.tscn"})
    add_child(_windows)

func open_settings() -> bool:
    var window: UIFrameWindow = _windows.show_ui("settings")
    return is_instance_valid(window) and window.is_showing()
```

`false` 表示本次调用未留下已打开窗口，包括创建失败或回调中取消。产品应保留原页面/入口，不能仅因调用了 `show_ui()` 就假定目标已经显示。需要异步加载时调用 `await _windows.show_ui_async("settings")`，返回后同样检查对象有效性和展示状态。

可选的第二、第三个参数分别为声音回调与场景准备回调；不传也能使用。声音回调接收窗口约定的 `button_click/window_open` 提示，场景准备回调接收新实例；子窗口继承相同接入。窗口的默认关闭按钮发出 `close_requested`，由创建该窗口的管理器处理，避免总是关到全局 UIManager。Meowdoku 在 `products/meowdoku/app/ui` 中把这些接入绑定到现有服务。

创建开始即登记占位，场景准备、`_ready()`、`on_create()` 中同步请求同名窗口会返回 `null`，不发布半初始化实例或再建一个实例。创建期间请求关闭会取消创建；每个可能重入的回调之后都重新检查有效性、归属和销毁状态。`window_created` 才表示可以正常查询或显示该实例，调用方应处理 `show_ui()` 返回 `null`。

逻辑层先排序，再统一分配绘制位置和节点顺序；节点顺序同时决定 GUI 输入优先级。每窗预留 128 个 z 位置，最多同时打开 32 窗；子控件的累计相对 z 应留在该窗口范围内，并为前后遮罩留出空间。独立 `CanvasLayer` 不属于这个窗口排序合同，跨窗口浮层应由宿主明确管理。窗口被全屏盖住与生命周期隐藏是两个状态，`hide_all()` 会关闭两者。

宿主释放窗口时立即清理缓存、栈与遮罩请求，窗口离树后再安全重排遮挡和遮罩；释放管理器则结束它拥有的窗口。管理器离树后不会由旧预热回调重新创建窗口。Godot 的线程资源加载没有取消接口，退出时会消费已发出的请求，必要时等待资源线程收尾；正常显示仍为异步加载，不承诺销毁时能立即中断资源解析。

一次逻辑显示以管理器的栈成员资格为准：关闭动画或 `visibility_changed` 收尾回调中重开同一窗口，沿用原遮罩请求与显示事件。关闭完成先出栈、恢复下层窗口，再选择实际可见的模态目标；被全屏盖住的窗口不等于已经关闭。回调打开另一窗口时，已经 HIDDEN 的旧窗口不会被遮挡重算重新显示。

`window_shown/window_hidden` 保持成对。首次显示在发布 `shown` 之前取消，管理器在退场结束或销毁后发布 `window_show_cancelled`。产品侧可选的 `UIPopupQueue` 在请求显示前监听这三种结果，取消不消耗 `once_per_session`，异步退场完成后才推进；外部销毁的通知来自 `tree_exiting` 时，延迟到回调结束再创建后继窗口，避免修改仍被引擎锁定的父节点。队列仍需要业务主动调用 `flush()`，当前产品没有接入点。

`is_showing()` 表示已打开的生命周期，遮挡时仍可为 true；`visible` 表示该节点的可见标记，`is_visible_in_tree()` 还考虑父节点。生命周期隐藏会暂停托管 Timer、断开托管连接；遮挡只调用页面的 `on_stack_bottom/on_stack_top`，是否暂停游戏计时由页面决定。`SceneTree.create_timer()` 不属于托管 Timer：页面自行创建的异步等待必须在返回后检查请求代次与生命周期。每日通关页的请求代次会在同窗刷新、隐藏和销毁时失效。

单个 `destroy_child()` 可以等待子窗口 `on_hide()`，重复关闭不会重复启动退场；等待期间重新显示会取消旧关闭。`destroy_all_children()` 和父窗口销毁采用同步清理，不等待动画，保证子窗口 `on_destroy()` 先于父窗口 `on_destroy()` 完成；节点内存随后在帧末释放。子窗口不独立参与管理器遮挡栈，父窗口需要时自行转发遮挡钩子。

`create_child()` 在场景准备、进树和生命周期回调之前登记所有权，所以子窗口可以在 `_ready/on_create/on_show` 内请求关闭自己。回调导致关闭、销毁或排队释放时返回 `null`，调用者不能假定创建一定成功；异步退场中的子窗口仍由父窗管理至收尾。切换 `visible` 也会触发同步信号，创建/显示流程会在信号后再次检查状态和展示代次。

同页刷新不会重新执行 `on_create()`。节点生命周期内固定的信号应在创建节点时连接一次；只在一次展示期间有效的监听才使用托管连接。语言页遵循前者，重复显示只更新文案和选择，不重复绑定按钮。`AutoFitLabelGroup` 合并响应本组及文字的布局变化，未取得真实宽度时不提前缩字号，布局完成和尺寸变化后重新测量。

产品安全区适配把屏幕像素通过实际 viewport 和父布局变换换算成 offset 单位，抵扣窗口位置及黑边。每次显示或刷新页面重新计算，零 inset 恢复初始基线。`_safe_top/_safe_bottom` 应挂在可自行布局的节点上，不挂在由 Container 排列的直接子控件上；如失败页两按钮的避让由外层 VBox 统一承担。当前页面沿竖轴布局，不承诺任意旋转界面或持续监听系统安全区变化。

公共窗口有不含产品 Autoload 的独立验证；另一个命令验证 Meowdoku 业务端口独立于页面：

```sh
python3 tools/run_ui_framework_tests.py
python3 tools/run_business_boundary_tests.py
python3 tools/check_architecture.py
```

架构守卫只检查显式资源路径，防止公共层引用产品、纯规则引用页面、玩法互相依赖；全局类与动态依赖由最小工程的真实 Godot 导入补充验证。这些检查不是全部代码依赖的形式化证明。

## 操作结果的统一约定

核心存储、库存、宿主和产品适配采用普通 Dictionary，`OperationResult` 只负责一致地构造结果，没有额外的 Result 继承体系。

```gdscript
return OperationResult.success({"snapshot": snapshot})
return OperationResult.failure("invalid_request", "诊断说明")
```

- `ok`：唯一的成功判断依据。
- `error`：失败的稳定机器码，成功时为空；用于程序分支和选择本地化提示。
- `detail`：可选诊断说明，不作为程序判断条件，也不直接显示给玩家。
- `cause`：需要包装失败时保留的原始结果，例如 `commit_failed` 内仍能看到 `write_failed`。
- `status`：存储或业务自己的状态，例如 `loaded`、`already_applied`。旧调用者仍可读取，不能仅凭它判断成功。

记录诊断用 `OperationResult.describe(result)`。纯查询仍返回值、布尔值或校验字符串；不为了形式统一而给每个 getter 包一层结果。玩法模块也可以直接返回遵守合同的字典，不强制导入辅助类。

## 运行可交互的 Block 示例

在仓库根目录执行：

```sh
python3 tools/run_block_example.py
```

启动器只复制 SaveStore、LocalCoreStore、RoundService、Block 模块与示例页面到临时工程。没有 Meowdoku 的 Autoload，也不会读取日常 Meowdoku 存档。默认示例存档放在系统临时目录的 `meowdoku-block-example-data` 下，启动时打印路径；再次执行同一命令会恢复同一份示例存档。

想为某次试验使用独立且明确的存档目录：

```sh
python3 tools/run_block_example.py --data-dir /private/tmp/my-block-example
```

通过鼠标悬停查看合法/非法放置预览，点击棋盘或从下方拖放方块。填满一行或一列会消除；固定队列用完或当前块无法放下时结束。领取星星、重新读取、新一局和退出都有真实保存语义。新一局替换当前棋盘，但保留已领取星星。

用上述启动器运行，不要为隔离验收直接从主工程 F6 启动场景；后者会同时启动主工程的 Autoload。示例是框架接入证明，尚不包含三格托盘、随机出块、运营活动和完整商业玩法。

对应代码：

- `scripts/examples/block/domain/block_probe_module.gd`：纯规则与只读放置预览，明确拒绝由页面覆盖权威棋盘。
- `scripts/examples/block/block_example_session.gd`：独立产品装配、存储路径、开局/放置/领取接口。
- `scripts/examples/block/block_example.gd`：页面；只有提交成功才刷新成新状态。
- `block_example_board.gd`、`block_example_piece.gd`：显示、预览和拖拽。拖拽携带对局与请求身份，旧拖拽不能落到下一块或新局。

## 给新玩法接入宿主

模块实现 `create_snapshot`、`validate_snapshot`、`sync_runtime`、`apply_action`、`settle_snapshot` 五个方法。它们接收/返回普通值；不要直接读节点、写文件或调用产品单例。`sync_runtime` 可以像 Block 一样明确拒绝外部盘面覆盖，它是旧玩法迁移的兼容接缝，不是必须开放的操作。

创建宿主时注入存储端口：`is_open()`、`revision()`、`snapshot()`、`commit(candidate, expected_revision)`。独立产品可以直接注入 LocalCoreStore；已有产品通过小适配器将附加业务字段纳入同一次提交。

以下是可放进产品会话脚本的请求函数，假设该模块定义了 `place` 动作。调用方先创建 `RoundService.new(core_store)`，且 core 已成功打开；`context` 由产品按模块合同提供。函数只返回结果，界面刷新与保存回执由调用方负责。

```gdscript
func start_or_resume(host: RoundService, module: RefCounted, context: Dictionary) -> Dictionary:
    if not host.register_module("my_game", module):
        return OperationResult.failure("module_registration_failed")
    var previous: Dictionary = host.resume("my_game", "main")
    if previous.get("ok", false):
        return previous
    if previous.get("error") != "missing":
        return previous
    return host.start("my_game", "main", 1, context)

func place_cell(host: RoundService, receipt: Dictionary, row: int, col: int) -> Dictionary:
    if not receipt.get("ok", false):
        return OperationResult.failure("round_not_ready")
    return host.action(
        "my_game", "main", str(receipt.round_id), int(receipt.next_sequence),
        "place", {"row": row, "col": col}
    )
```

只把成功的宿主回执传给 `place_cell()`。动作失败时保留上一份成功回执，重试同一请求不推进序号；成功时才接收新回执。`start_or_resume()` 不会自动重开已结束的局，产品需要检查返回的 `status`，由明确的新局操作使用上一局 `start_sequence + 1`。完整的回执顺序、重新打开与同步重入处理参考 `BlockExampleSession`，不要把示例函数误当成全部产品会话状态机。

成功模块结果必须有 `ok: true` 和字典 `snapshot`；可选 `result`、`inventory_delta` 必须是字典，`changes` 可以是数组或字典。失败结果必须有 `ok: false` 和字符串 `error`。宿主会验证成功开局、运行时同步和动作返回的快照，检查已保存记录的身份/序号/字段形状，再进入存储。错误的模块合同返回 `invalid_module_result`，错误的记录返回 `invalid_record`，不能把解析异常或部分候选当作成功。

`validate_snapshot` 必须先检查类型，再比较值或访问嵌套字段，并返回字符串；空字符串表示通过。GDScript 中不兼容类型的比较也可能触发运行时错误，不能假定任何 Variant 都能安全地与期望值比较。验证器拿到副本，不能通过别名改写实际候选。

页面只在 `ok=true` 后发布新状态。失败时保留原请求序号供重试；`duplicate=true` 表示已存在的回执，不能再播放发奖或统计副作用。普通 `action` 不接受 `__` 开头的宿主保留动作，结算使用专门的 `settle()`。

## 接入内容交付

`ContentStore` 的真实构造参数是 `ContentStore.new(root, product, runtime, public_key_pem, quota_bytes)`，最后一项有默认值。`root` 是产品自己的本地目录，`public_key_pem` 是公钥文件**内容**而不是路径；产品标识和运行时兼容标识必须与发布物一致。`ContentDownloader` 是节点，使用前加入场景树；`ContentContext` 是进程内的只读访问口，不是同时承载多个产品的隔离容器。

产品入口负责以下顺序：

1. 准备有效公钥、产品配置和 `ContentValidation.new(file_check, catalog_check, media_check)`。三个校验回调均返回含布尔 `ok` 的字典；省略回调只代表未检查该项业务语义，不代表内容天然可用。
2. 在消费者读取资源前调用 `begin_cold_start(validation)`。如需清理中断下载，在它之前、且没有下载任务时调用 `cleanup_interrupted()`。冷启动在同一个 store 上只能开始一次。
3. 检查启动结果。成功后把其 `catalog` 与 `resource_catalog`（可能为空）传给 `ContentContext.publish()`；无更新时消费者仍应有内置内容。`ok=false` 不能当成正常启动；若有 `restart_required=true`，当前进程不能假装已切回内置资源继续运行。
4. 只有实际使用了试运行版本、关键入口与资源消费者正常后，才调用 `confirm_healthy(release)`，并检查确认写入结果。不能把下载成功、挂载成功或进入 `_ready()` 直接等同于产品健康。未完成确认的试运行会在下次冷启动保守回退。
5. 自动更新优先用 `await downloader.download_from_channel(store, channel_url, channel, staging_root, validation)`。指定版本可用 `download_release(..., expected_release, expected_manifest_sha256)`，这两个尾参须同时提供或同时省略；提供时先绑定已验签清单的身份，再检查本地缓存和载荷。双空的直接地址入口把版本选择交给调用者，不具备频道的防旧入口重放保证。成功安装后再调用 `store.stage(release, validation)` 登记候选；下载和 stage 的结果都要检查。
6. 纯 JSON 候选可在产品认可的安全边界调用 `activate_data(validation)`；成功后发布返回的目录，同时保留当前媒体目录。包含 PCK 的候选会要求冷启动。当前对局应继续使用开局时冻结的数据，不在下载回调中自动替换规则。

如需替换已登记的场景资源，配置 `content/scene_bindings_path` 指向**本产品**的内置绑定表，再把 `ContentSceneBindings.apply` 接入窗口的场景准备回调。不配置则没有绑定，不会自动采用 Meowdoku 的资源。纹理尺寸、Spine 动画/皮肤等消费合同仍需产品校验；资源能解码不等于适合该页面。

`products/meowdoku/app/bootstrap/content_bootstrap.gd`（Meowdoku 的 Autoload 名为 `ContentRuntime`）是当前产品的启动装配参考，不属于公共目录，其他产品不要整体复制后依赖其中默认值。完整格式、PCK 限制和发布命令见 [内容交付文档](content-delivery.md)，其中产品示例需要替换为自己的标识和配置。

发布工具也要区分机制与产品验证：`tools/content/build_release.py` 支持其他 `--product` 标识，但目前只对 `meowdoku` 自动执行额外的产品语义/跨资源校验。其他标识签名成功，仅证明通过了通用发布格式与完整性检查；新产品必须在发布流程接入自己的内容校验，并在客户端验证，不能把“可签名”当成“业务可用”。不应通过改成其他产品标识来跳过 Meowdoku 的发布校验。

## 存档升级与性能边界

Meowdoku 当前核心 schema 为 1，已提供其旧存档到核心的迁移；其他产品自行定义版本和迁移，公共存储不要求沿用 Meowdoku 的字段或版本。没有实际 schema 变更时，不引入一个无人使用的通用迁移注册系统。以后升级字段时，应在产品层提供明确的旧版本转换：读取旧值、纯转换、校验、一次提交，失败保留旧档；未知未来版本继续拒绝覆盖。不能简单修改版本号并用默认状态重建玩家档。

核心提交使用同步双槽协议，包括校验、复制、读取已有槽、加密写入、回读和替换。不要把每一个动画格或拖动像素都变成磁盘事务。手势合并、检查点与关键奖励事务有不同的保存频率，需由业务边界决定。

当前 macOS 定制引擎的代表性测量，12 次有效样本/大小，另有 3 次预热：

| 编码后的状态大小 | 快照复制 p50 | 完整提交 p50 | 完整提交最大值 |
|---|---:|---:|---:|
| 14,320 bytes | 9 μs | 1.282 ms | 1.291 ms |
| 229,012 bytes | 134 μs | 14.895 ms | 15.105 ms |
| 918,364 bytes | 520 μs | 58.955 ms | 60.557 ms |

完整测量数据见 [性能产物](validation/storage-performance.json)。这是合成数据的桌面文件测量，不是移动端帧预算、真实玩家存档的性能保证或吞吐比较。它说明大核心档的同步提交可能占用多个帧；新增大量历史/活动记录时，应先测实际数据再选择合并保存、裁剪已可安全删除的数据或拆分独立数据域，不能破坏原有事务语义来追求数字。

宿主有界性测试执行 64 个真实 Block 动作，当前记录从 4,788 bytes 增至 5,212 bytes；只保留一条最后回执，不随动作数保存整个请求日志。它不代表其他产品集合（例如长期领取资格）可以不经业务证明随意裁剪。

## 阅读 Meowdoku 的具体接入

本节是当前产品的实现导览，不是新产品必须继承的结构。完整目录见 [工程说明](README.md#当前目录与阅读顺序)。

| 想理解或修改什么 | 先读哪里 | 归属 |
|---|---|---|
| 产品存档与兼容 | `products/meowdoku/app/state/` | MeowdokuStore 定义产品数据，GameState 保留页面门面 |
| 选题、策略与结算 | `products/meowdoku/gameplay/application/` | Meowdoku 的 Doku 产品规则 |
| 题库与发布验证 | `products/meowdoku/gameplay/content/` | 当前产品支持的数据与资源合同 |
| 产品页面装配 | `products/meowdoku/app/ui/ui_manager.gd` | 页面表、声音、资源绑定、安全区与埋点 |
| 启动内容 | `products/meowdoku/app/bootstrap/content_bootstrap.gd` | 当前产品渠道、启动确认与消费者接入 |

`GameState` 是已有页面的产品门面。阅读一次结算，从 `settle_main_round()` 进入，依次看产品结算的 `stage()`、`commit_core_candidate()` 和 `_publish_settlement()`：计算候选、保存、通知三个阶段不会混在同一个长函数里。它仍兼容旧 getter 和合并统计，不需要为了找一个奖励规则通读整个文件。

阅读页面开局，从 `GamePage.on_show()` 看调用顺序：恢复或选题、冻结策略、`_reset_round_for_entry()`、等待布局、`_setup_entry_board()`、`_commit_entry_selection()`、接检查点与入场。三个准备步骤都在同文件中同步完成，两次 `await` 和代次检查仍直接显示在入口。恢复决策留在 `_try_consume_endgame_snapshot()`，存档字段映射单独放在相邻的 `_build_endgame_restore_params()`。

每日页的 `on_show()` 同样保留策略冻结和异步入场，选池、过滤非法题、变换和构造题面由同文件的 `_prepare_daily_puzzle()` 完成。每日的 `CONTINUE` 是埋点状态，重新进入仍建立新局。基类顶部把本局冻结配置、产品会话和活棋盘状态分组列出；`_business_generation` 是页面异步代次，持久局号则由业务会话管理。

### Meowdoku 开发工具与正式运行边界

开发入口以 `OS.is_debug_build()` 为必要条件。作弊浮层、开发路由、策略按钮、棋盘保护区可视化和开发日志缓冲在正式构建中关闭；`CheatBus.issue()` 同样拒绝分发命令。产品侧保留旧 `rel` 标签作为 debug 构建中的额外关闭条件，不再依靠缺少该标签判断正式构建。

三个 MCP 运行时服务与截图快捷键在非 debug 构建中停止处理和输入。Autoload 与脚本引用保留完整，这属于运行时禁用，不是从发布包物理剥离资源；编辑器和 debug 构建的请求与快捷键继续可用。

确认弹窗的 Esc 与 Android 返回键复用右上角关闭按钮的取消逻辑，关闭动画期间重复返回不会重复执行回调。恢复提示使用本产品的翻译资源，重试按钮复用 `FAIL_TRY_AGAIN`；这些文案、翻译键和弹窗样式不属于公共存储的错误合同。新产品应将稳定错误码映射为自己的提示。

```sh
python3 tools/run_development_boundary_tests.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/validation -p 'test_*.py'
```

产品开发边界测试在独立副本运行真实启动器、路由及主线/每日页面；模拟 release 时只替换列出的构建谓词，断言脚本不变。Python 回归另测 MCP 请求、输入与快捷键的启用/禁用分支。当前没有匹配的 release 模板，这些检查不代表真实发布包或手机硬件验收。

## 按边界复核

公共目录的独立接入检查：

```sh
python3 tools/run_framework_boundary_tests.py
python3 tools/run_ui_framework_tests.py
python3 tools/run_block_example.py --headless --test
python3 tools/check_architecture.py
```

第一项只带公共目录进入无产品 Autoload、资源与玩法的临时工程，检查整个公共目录能独立导入及基础接入合同；UI 与 Block 项继续验证各自的实际行为和最小依赖。它们都不等于新产品的完整发布验收。

Meowdoku 产品及其适配的回归：

```sh
python3 tools/run_business_boundary_tests.py
python3 tools/run_validation.py --suite framework --smoke
```

`run_business_boundary_tests.py` 虽然没有 Autoload，仍包含 Meowdoku 存档及 Doku 用例，验证的是产品业务端口独立于页面，不是纯公共框架。

`framework` 自动收集自包含验证，包括恢复基线、存储、宿主合同、Doku 规则、产品页面、Block 场景与内容消费者。`--list` 只打印将要运行的脚本；也可选择 `recovery`、`storage`、`gameplay`、`content`，或多次指定 `--script`。

需要签名、HTTP 服务和真实 PCK 夹具的测试由其专用工具运行，不直接放进普通 suite。将 `ENGINE` 替换为匹配的 Spine-Godot 引擎路径；也可设置 `DOKU_GODOT` 后省略 `--godot`：

```sh
python3 tools/content/run_tests.py --godot ENGINE
python3 tools/content/run_spine_test.py --godot ENGINE
python3 tools/content/run_product_tests.py --godot ENGINE
python3 tools/content/verify_exported_resources.py --godot ENGINE
```

独立 Block 页面及截图检查：

```sh
python3 tools/run_block_example.py --headless --test
python3 tools/run_block_example.py --test --screenshot /private/tmp/block-example.png
```

普通运行器支持 `--rendered`，保持相同存档隔离但使用图形窗口。图形模式需要可用窗口服务；本轮环境的 macOS LaunchServices/XPC 连接限制使截图尝试超时，因此不能把 headless 测试当作人工视觉验收。真实页面测试已覆盖拖放目标、保存失败、销毁重建恢复、领取重试和重复回调。

运行器保留临时工程、逐项日志和 `report.json`，性能用例另产生 `project/validation_artifacts/storage-performance.json`。测试会故意注入坏数据和写失败，日志可能有预期诊断；通过依据包括退出码、脚本错误标记、断言、失败计数与未知引擎 `ERROR`。已知环境、明确故障注入和退出资源消息分别记录；不能把“通过”描述为日志完全无诊断。所有验证都在副本或独立工程中运行，不使用日常玩家存档。

验证工具本身的回归：

```sh
python3 -m unittest discover -s tools/validation -p 'test_*.py'
```

该组覆盖门禁与正式发布命令的拒绝行为，包括退出码0但有引擎错误时不能签出最终发布目录。
