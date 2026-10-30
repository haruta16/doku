# 内容交付：当前实现、发布方法与边界

本实现把**配置 JSON**和**表现资源 PCK**分开激活。题库、关卡表只是配置的具体消费者；通用交付层按逻辑 ID 管理文件，产品校验器解释具体结构。默认使用随客户端发布的内容；配置公钥和地址以后才下载签名发布物。稳定签名频道负责发现与选择版本，发布物负责交付内容。本文描述现有题库、规则、声音和登记场景资源的读取合同。

## 1. 代码与数据流

| 位置 | 职责 |
| --- | --- |
| `scripts/framework/content/content_manifest.gd` | 严格清单合同、RSA/SHA-256 签名、逐文件大小与 SHA-256 |
| `content_channel.gd` | 签名频道、运行时选择、不可变清单哈希绑定 |
| `content_downloader.gd` | HTTPS、缓存命中、有限重试、进度与取消，校验后交给安装器 |
| `content_store.gd` | 不可变版本目录、候选/活动/回退指针、试启动、清理 |
| `content_catalog.gd` | 单个版本的只读 JSON 副本与媒体读取 |
| `content_raw_pack.gd` | 挂载前检查 PCK 目录、受限 Spine 导入闭包；每进程最多一代动态包 |
| `content_media_map.gd` | 逻辑媒体槽位与包内相对路径合同 |
| `products/meowdoku/app/bootstrap/content_bootstrap.gd` | `ContentRuntime` 首个 Autoload，选择缓存内容、冷启动挂包、下载候选 |
| `scripts/framework/content/content_context.gd` | 业务读取口、数据代数、独立媒体目录、资源缓存、可观测内容错误 |
| `products/meowdoku/gameplay/content/` | Doku 专属规则和内容校验，不放进通用框架 |
| `products/meowdoku/gameplay/content/level_bank_io.gd` | 远端题库覆盖与内置题库读取，标记实际题目来源 |

完整路径是：**发布工具 → 签名频道选版 → 签名发布目录 → 下载临时目录 → 验签/哈希/合同校验 → 不可变安装目录 → pending → 合适时机激活 → 产品逻辑读取**。下载完成不会直接改变正在玩的棋盘。

## 2. 什么可以更新

### JSON：题库与选题策略

业务通过逻辑 ID 读取内容，不直接拼 CDN 地址。Meowdoku 的 ID 和容器必须匹配现有消费者：

| ID | JSON 顶层形状 |
| --- | --- |
| `doku/levels/bankdata4x4` 等常规尺寸题库 | `{"1": [题目], "2": [题目], ...}`；难度键限 1–5 |
| `doku/levels/bankdatagc6x6` 等 GC 题库 | `{"levels": [题目, ...]}`；每题 `r` 为 1–5，消费者据此筛选难度 |
| `doku/levels/bankdatalkstyle7x7` 等 LKStyle 题库 | `{"1": [题目], "2": [题目], ...}`；与常规题库相同，难度键限 1–5 |
| `doku/levels/bankdatalk` | `[题目, ...]` |
| `doku/levels/bankdatalkmodified`、`doku/levels/bankdatasp` | `{"levels": [题目, ...]}` |
| `doku/policy` | `schema=1`，可覆盖 `size_cycles`、`special_levels`、`draft_unlock_level` |
| `doku/level_catalog` | `schema=1` 与 `levels` 字典，精确关卡定义与依赖引用 |
| `media` | 下文的媒体槽位表；必须与资源包一起发布 |

题目验证包括尺寸 4–12、矩阵形状、区域/答案范围、解合法性和**文件名声明尺寸与题目尺寸相等**。常规题库的 Array 或 `{levels:...}` 会被拒绝；即使题目本身合法，消费者不支持的容器也不能发布。

每个数据版本是相对于客户端内置内容的一份覆盖快照，**不会自动叠加上一份远端 JSON 版本**。如果 r1 更新了题库 A，r2 只包含策略，则 r2 的题库 A 回到内置版。希望保留的远端 JSON 应一并放入 r2。`size_cycles` 是特例：按分组合并内置策略；`special_levels` 整表替换。规则细节见 `DokuPolicy._refresh()`。

产品 validator 除逐文件格式外，还检查候选目录与内置题库组合后的跨表引用。实际生效的 `special_levels`（包括继承的内置策略）及已有 SP57 变体必须指向存在且合法的题；固定关卡覆盖的旧引用不再参与校验。`doku/level_catalog` 可以精确声明关卡的题库/难度/索引、预置猫、初始生命、草稿门槛、资源槽位覆盖及奖励。明确声明的题或资源不存在时拒绝发布/安装，不悄悄换题。未声明关卡继续使用既有选题。校验只读取候选与内置数据，不拿另一份活动版本来补引用。

每日挑战还要求现有控制组与实验组实际使用的难度/tier 题池非空，不能仅凭题库总题数大于零判定可用。候选完整替换一个题库文件，缺少的难度不会从旧远端版本或内置同文件中逐组补齐；没有覆盖的题库才使用内置版本。LK 的 `date/label` 等直接消费字段也校验类型。题库格式错误返回 `logical_id`、零起算 JSON `path` 和诊断 `detail`，方便定位具体题目；这些诊断用于制作工具和日志，不直接展示给玩家。

普通主线也按实际消费合同检查：候选与内置策略合并后，结合固定/特殊关覆盖、尺寸实验组、难度组、每日降档、联合题源准入和 tier 回退，确保每种可达选择至少有一个合法的可循环题池。有限 LK 补充题可能已被玩家耗尽，不能充当永久兜底。检查按策略分段、尺寸周期和关卡尾数的共同周期取代表，不靠模拟前几百关猜测后续可用性；失败返回 `main_pool_missing` 及关卡、尺寸、难度和策略位置。运行时与校验共享 `DokuMainSelectionRules`，避免两套难度曲线漂移。

共享规则另有 `test_doku_main_selection_rules.gd` 的32条独立固定期望，覆盖困难档随机、连续顶档限制、每日降档及随机数消耗顺序，期望不从当前规则反向生成。随机序列取自重构前实现运行于 Godot 4.6.1 的记录；升级引擎时需明确审阅随机序列兼容性。规则输入 `previous_was_max` 是上一局标志，内部 `tracked_max_strategy` 是比较用的原始顶档，输出 `next_previous_was_max` 是下一标志或表示不更新的 null；是否命中顶档在每日降档之前判断，存档字段不变。

policy、固定关定义和媒体映射的格式错误也提供具体字段路径与原因；布尔 `validate()` 委托同一份详细校验，不另维护一套宽松规则。

公共交付层接收 `ContentValidation`，明确携带逐文件、整目录、挂载媒体三个校验回调，各自返回含布尔 `ok` 的 Dictionary。Meowdoku 通过 `DokuContentValidator.validation()` 一次装配，发布、安装和激活沿用同一合同。通用层不再反射查找 Callable 所属对象的方法；包装逐文件回调不会隐式取消目录或媒体校验。`DokuContentValidator.validate()` 的布尔入口仅用于局部查询或旧测试，不替代完整发布验证。

JSON 在**新局入口**激活。已开始的局使用自己的题面、规则和来源快照；恢复旧局不依赖仍保留整份历史内容目录。BankData 在内容代数变化后清除各类题库缓存，包括失败缓存。

题库中的 `prefill_positions` 与关卡表的 `prefill` 是不同字段，但都必须是唯一、界内、与答案一致的整数坐标数组。发布和客户端 validator 校验该合同；实际 SP 预览入口还检查当前记录与传入题面一致，拒绝非法缓存或切代前的旧参数，避免半初始化开局。普通与主线选题采用有界循环，连续筛选大量候选不会增加调用栈；筛选偏好耗尽时保留原有合法末题降级，无合法题则由入口拒绝。

新手教程是固定客户端流程：4×4 题面、配色、答案与七步提示共同定义在 `TutorialPage`，不从可替换 SP 的 `guide` 标签取题。替换 SP 不要求保留该标签，但仍必须满足普通主线的实际引用合同。教程搭盘失败时不启动步骤，启动器也不确认试运行版本健康；失败版本按现有冷启动协议回退。

### 固定关卡表：逐关指定题目、规则、表现与奖励

在发布 source 中添加 `doku/level_catalog.json`，构建后逻辑 ID 就是 `doku/level_catalog`。例如下面定义第 21 关；引用的内置 4×4 题库第 1 难度、第 1 题，其第 0 行答案列为 2：

```json
{
  "schema": 1,
  "levels": {
    "21": {
      "puzzle": {"bank": "doku/levels/bankdata4x4", "rank": 1, "index": 1},
      "prefill": [[0, 2]],
      "rules": {"initial_lives": 3, "draft_unlock_level": 21},
      "media": {"game/mark": "theme/tutorial/mark"},
      "reward": {"hint": 1}
    }
  }
}
```

字段合同由 [DokuLevelCatalog](../products/meowdoku/gameplay/content/doku_level_catalog.gd) 定义；[DokuContentValidator](../products/meowdoku/gameplay/content/doku_content_validator.gd) 校验完整候选发布的跨表和媒体依赖。

| 字段 | 含义与边界 |
| --- | --- |
| `schema`、`levels` | 顶层只接受这两项；schema 必须为整数 1。最多 10,000 条定义，关卡键是正整数字符串，例如 `"21"`，不接受 `"021"`。 |
| `puzzle` | 每关必填。`bank` 是题库逻辑 ID；`index` 从 **1** 开始。按难度分组的题库还需整数 `rank=1..5`；数组或 `levels` 容器的题库省略 rank。题库优先取本次发布，未覆盖时取客户端内置版。 |
| `prefill` | 可选的预置猫坐标 `[行, 列]`，坐标从 **0** 开始；最多 12 个、不重复，必须在棋盘内且与题目答案一致。显式 `[]` 表示不预置；省略时保留原有预置计算。 |
| `rules` | 可选。`initial_lives` 为整数 1–3；`draft_unlock_level` 为整数 1–10,000，表示开启草稿的关卡门槛。缺省项沿用正常规则。 |
| `media` | 可选的**棋盘槽位别名覆盖**：左侧限 `game/mark`、`game/mark_alt`、`game/mark_lock`、`game/hint_cat`、`game/cat`，右侧是本次 `media.json` 中同类型的目标槽位。首页槽位不能放在逐关定义里。例中只为这关把 `game/mark` 指向 `theme/tutorial/mark`，不是文件路径。 |
| `reward` | 可选的关卡结算道具奖励；可用键为 `hint`、`locate`、`undo`，每项数量为整数 1–10,000。奖励经现有业务结算链发放，随本局定义保存。 |

这个示例声明了媒体别名，因此同一发布还必须带资源包和以下 `media.json`；将原 `products/meowdoku/assets/sprites/game/icon_mark_white_2.png` 拷贝为 raw-assets 目录的 `mark.png` 即可跑通示例。原图尺寸为 **32×168**，替换图需保持这一尺寸，原因见下一节固定槽位合同。

```json
{"textures":{"theme/tutorial/mark":"mark.png"}}
```

如果只调整题目、预置、规则或奖励，移除定义中的 `media` 字段即可作为 JSON-only 发布。**JSON-only 可以继续使用已经激活的媒体，但不能新声明对某个历史媒体版本的槽位依赖。** 构建时不读取玩家机器的活动内容，也无法证明每位玩家都装有那个旧包；这样的别名会以 `level_media_missing` 拒绝。需要新的逐关资源组合时，把关卡表、完整媒体映射和资源包放在同一份发布中。

发布表只影响其中明确列出的关卡，未声明关卡继续走现有选题。每份 JSON 是完整覆盖快照：下一版要保留这些固定关卡定义，需继续携带它们。关卡表能组合客户端已有能力；新增玩法机制、场景结构或新的字段消费者仍需更新客户端。

### PCK：图片、音频与受限 Spine

`raw_pck` 支持原始 PNG/JPEG/WebP 与 OGG/WAV/MP3 等文件。图片与声音通过运行时解码器读取，不依赖编辑器 `.import`。JSON 可以作为原始包内文件，但玩法 JSON 仍应使用独立清单条目，才能经过产品校验并按局切换。

`spine_pck` 支持当前定制引擎的 Spine `.atlas + .skel + PNG`。发布工具在独立工程重新导入，生成固定的 `SpineSkeletonDataResource` `.tres`，真实执行 `--export-pack`，再移除全局配置、UID 缓存和其他非内容文件。运行时只接受这一固定资源模板及其核验后的导入闭包。它不是任意 `.tres/.tscn` 加载器。

包内自有目录为 `res://content/<product>/<release>/...`。Spine 另允许由该目录源路径推导出来的 `.godot/imported/*.(ctex|spatlas|spskel)`。拒绝脚本、场景、原生扩展、全局 UID 缓存、项目配置、删除条目、任意 core 覆盖和其他包格式。

**目录不同并不能隔离 UID。** `ResourceUID` 是全局注册表；真导出验证复现了动态包让原来的依赖指向另一版本的情况。因此这里同时约束 UID 缓存、资源引用方式、导入映射和已有路径冲突，不能仅靠“每进程一代”声称安全。PCK 的作用和 UID 的全局性质可查 [Godot PCK 文档](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_pcks.html) 与 [ResourceUID 文档](https://docs.godotengine.org/en/4.6/classes/class_resourceuid.html)。

资源包只在冷启动、其他 Autoload 使用内容之前挂载；当前进程不能卸载并改挂下一代。`load_resource_pack` 本身不是内容校验器，缓存中的旧 Resource 也不会因挂包自然变成新实例。见 [ProjectSettings.load_resource_pack](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-method-load-resource-pack)。

### 较大配置的读取与发布约定

JSON 交付不依赖关卡概念。`ContentCatalog.read_json(logical_id)` 校验文件、解析并缓存，返回深拷贝，调用方不能通过修改嵌套数据污染共享缓存。Meowdoku 的产品校验器仍只接受已经接入的配置 ID 和结构，未知用途不能靠上传文件绕过产品检查。

专项验证使用独立产品的 `presentation/themes`，包含 12,000 条记录、超过 1 MiB 的 JSON，覆盖签名、注入校验器、安装激活、完整读取及副本隔离。这验证通用配置链路，不代表 Meowdoku 新增了主题功能，也不代表移动端性能预算。当前单文件上限 128 MiB、整份发布 256 MiB 是拒绝异常输入的硬上限；不是建议的配置规模。解析和深拷贝仍为同步操作，调用方应按版本读取后在业务侧缓存所需值，避免每帧读取整表。

## 3. 媒体槽位和独立版本

`media.json` 示例：

```json
{
  "textures": {
    "ui/home/daily_paw_dim": "ui/paw.png",
    "ui/home/daily_paw_lit": "ui/paw_lit.png"
  },
  "audio": {
    "sfx/mark_cat": "audio/cat.ogg",
    "bgm/default": "audio/music.ogg"
  },
  "spine": {
    "game/cat": "maomi_fuor.tres"
  }
}
```

三个字段均可省略；槽位名称和相对路径使用小写安全路径。未配置的槽位继续使用调用方提供的内置资源。声明的路径必须属于本次包，启动时必须能解码。提供 `media` 却没有 PCK 的 JSON 版本会被拒绝。

已接入的消费者：SoundManager 的 `sfx/<Kind 枚举小写名>`、`voice/combo_male_3` 至 `8`、female 对应槽位及 `bgm/default`；HomePage 每日入口亮/暗猫爪纹理。既有 BGM A/B 开关仍决定是否播放。`ContentSceneBindings` 按内置 `products/meowdoku/assets/config/scene_bindings.json` 将登记的原纹理/Spine 资源映射到逻辑槽位，保留原资源作为回退；它不替换场景结构或脚本。Spine 替换必须保留原消费者使用的动画/皮肤名称，发布前和挂载后都会校验。未登记资源不自动成为可热更资源。

两类消费方式的合同不同：

| 消费方式 | 例子 | 发布要求 |
| --- | --- | --- |
| 固定场景绑定 | `game/mark`、`ui/home/logo`、`game/cat` | 原资源→槽位登记在随客户端发布的 [scene_bindings.json](../products/meowdoku/assets/config/scene_bindings.json)。纹理必须与原资源像素尺寸完全相同，以保持 NinePatch 裁剪、边距和布局；Spine 必须保留原资源的全部动画和皮肤名。逐关别名目标也遵守原槽位的相同合同。 |
| 代码显式读取的动态槽位 | `ui/home/daily_paw_dim`、`sfx/mark_cat` | 消费者通过 ContentContext 读取，并提供内置回退。通用层校验路径、类型和解码；额外尺寸、播放方式等条件由该消费者负责，没有一律强加固定场景的像素尺寸要求。 |

只在 `media.json` 增加一个名字不会创建消费者。新增固定绑定要更新客户端登记表；新增动态用途要有客户端调用代码。能被 Godot 正常解码只是基础条件：例如 `ui_logo` Spine 本身合法，放进 `game/cat` 仍会因缺少猫动画/皮肤而被产品验证拒绝。

数据和媒体有独立活动指针。例如先启动 `art-r1`，再在局间激活只有 JSON 的 `data-r2`，最终是 `data=data-r2, media=art-r1`。退出并重新进入仍保持这对来源，清理不会删掉被媒体指针引用的版本。下一份含 PCK 的发布物冷启动成功后，才替换媒体代。

含 PCK 的新版本拥有自己的完整媒体槽位表；未声明的槽位回到内置，而不是叠加旧包。要清除某个远端槽位，在下一份资源发布中删除该槽位即可。JSON-only 发布不承担媒体重置。

## 4. 实际发布命令

需要 Python 3、OpenSSL，以及项目匹配的 Spine-Godot。以下 macOS shell 示例中的 `/opt/homebrew/bin/godot-4.6.1` 是本机路径，应替换为实际引擎路径，或设置 `DOKU_GODOT` 后省略 `--godot`。当前验证版本为 `4.6.1.stable.custom_build.14d19694e`，带 Spine。普通 Godot 发行版不能替代这个 Spine 工具链。

以下是可在仓库根目录运行的本地示例，发布和密钥都放在临时目录；私钥不进入仓库，也不进入发布物。生产环境应由受控的构建环境保管私钥，只把公钥打进客户端。

```sh
CONTENT_WORK=$(mktemp -d /private/tmp/meowdoku-content.XXXXXX)
mkdir -p "$CONTENT_WORK/source/doku"
cat > "$CONTENT_WORK/source/doku/policy.json" <<'JSON'
{"schema":1,"draft_unlock_level":21}
JSON
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$CONTENT_WORK/private.pem"
openssl pkey -in "$CONTENT_WORK/private.pem" -pubout -out "$CONTENT_WORK/public.pem"

python3 tools/content/build_release.py \
  --source "$CONTENT_WORK/source" --output "$CONTENT_WORK/releases/data-r1" \
  --product meowdoku --release data-r1 \
  --runtime godot-4.6.1-spine-4.2-data-v1 --key "$CONTENT_WORK/private.pem" \
  --godot /opt/homebrew/bin/godot-4.6.1
```

输入目录结构决定逻辑 ID：`doku/levels/bankdata4x4.json` 变成 `doku/levels/bankdata4x4`。不要直接把整个 `products/meowdoku/assets/editor/levels` 当作 source；它既缺逻辑前缀，也包含未接入的研究/样例文件。文件名会归一为小写，重名会拒绝。

原始媒体示例，追加到上面的 source：

```sh
mkdir -p "$CONTENT_WORK/media/ui" "$CONTENT_WORK/media/audio"
cp products/meowdoku/assets/audio/sfx/mark_cat.ogg "$CONTENT_WORK/media/audio/cat.ogg"
cp products/meowdoku/assets/icons/project_icon.png "$CONTENT_WORK/media/ui/paw.png"
cat > "$CONTENT_WORK/source/media.json" <<'JSON'
{"textures":{"ui/home/daily_paw_dim":"ui/paw.png"},"audio":{"sfx/mark_cat":"audio/cat.ogg"}}
JSON

python3 tools/content/build_release.py \
  --source "$CONTENT_WORK/source" --output "$CONTENT_WORK/releases/art-r2" \
  --product meowdoku --release art-r2 \
  --runtime godot-4.6.1-spine-4.2-data-v1 --key "$CONTENT_WORK/private.pem" \
  --raw-assets "$CONTENT_WORK/media" --godot /opt/homebrew/bin/godot-4.6.1
```

Spine 发布可同时包含前述原始媒体；生成的 wrapper 名称是 atlas/skel 的共同文件名加 `.tres`：

```sh
cat > "$CONTENT_WORK/source/media.json" <<'JSON'
{"textures":{"ui/home/daily_paw_dim":"ui/paw.png"},"audio":{"sfx/mark_cat":"audio/cat.ogg"},"spine":{"game/cat":"maomi_fuor.tres"}}
JSON

python3 tools/content/build_release.py \
  --source "$CONTENT_WORK/source" --output "$CONTENT_WORK/releases/art-r3" \
  --product meowdoku --release art-r3 \
  --runtime godot-4.6.1-spine-4.2-data-v1 --key "$CONTENT_WORK/private.pem" \
  --raw-assets "$CONTENT_WORK/media" \
  --spine-assets products/meowdoku/assets/effect/spine/ui_cat_icon \
  --godot /opt/homebrew/bin/godot-4.6.1
```

输出包含 `manifest.json`、二进制 `manifest.sig`、`data/...`，有媒体时再包含 `assets.pck`。发布目录/版本 ID 不可原地修改；修正内容要创建新 ID。签名覆盖清单的**原始字节**，重新格式化 JSON 也需要重新签名。清单每项包含 `id/path/kind/bytes/sha256`，签名证明发布方身份，哈希核对下载内容完整性。

`build_release.py` 对 `product=meowdoku` 在签名前强制调用 `tools/validate_content_product.py`，在无 Autoload 的独立工程检查产品格式、跨表引用、实际挂包和媒体消费者合同。JSON-only 发布也需要匹配引擎，可通过 `--godot` 或 `DOKU_GODOT` 指定。验证失败不会创建最终发布目录，也没有跳过产品验证的正式发布开关。其它产品应接入自己的 validator。客户端安装、启动和激活仍重新校验，不能把构建校验代替运行时验证。

创建稳定频道的发布材料：

```sh
python3 tools/content/build_channel.py \
  --product meowdoku --channel stable --revision 1 \
  --target "$CONTENT_WORK/releases/art-r3" https://your-content-host.example/releases/art-r3 \
  --key "$CONTENT_WORK/private.pem" --output "$CONTENT_WORK/channel-r1"
```

将不可变发布目录上传到对应 URL，再将 `channel-r1/channel.json` 与 `channel.sig` 成对部署到稳定目录，例如 `/channels/stable/`。工具只产出本地文件，不会上传或覆盖已部署目录。每个 `--target` 从现有签名 manifest 推导 runtime/release/manifest_sha256，并验证发布签名及载荷大小/哈希；可重复指定以给不同运行时各分配一个兼容版本。客户端精确匹配 runtime，不做模糊降级。

## 5. 客户端配置与调用

`project.godot` 的 `[content]` 当前默认公钥路径和地址为空，因此正常运行不会访问远端。启用时配置：

```ini
[content]
product="meowdoku"
runtime_id="godot-4.6.1-spine-4.2-data-v1"
validator_script="res://products/meowdoku/gameplay/content/doku_content_validator.gd"
scene_bindings_path="res://products/meowdoku/assets/config/scene_bindings.json"
public_key_path="res://products/meowdoku/assets/config/content-public.pem"
channel="stable"
channel_url="https://your-content-host.example/channels/stable"
release_url=""
release_id=""
release_manifest_sha256=""
allow_local_http=false
```

这是配置示意域名；仓库没有真实线上地址。公钥文件需要随客户端导出，现有 preset 的 include_filter 为 `products/meowdoku/assets/config/*.json,products/meowdoku/assets/config/content-public.pem`；更改公钥文件名时也需同步该过滤规则。**绝不把私钥放在该目录**。`runtime_id` 是客户端认可的兼容合同字符串，必须随引擎、Spine 或导入配置不兼容变更而调整，它不是自动计算的平台指纹。

启动时读取频道；正在试运行的版本先由 Launcher 确认健康，再开始后台更新查询。可显式调用 `await ContentRuntime.check_for_updates()`。`channel_url` 优先；留空而使用固定 `release_url` 自动更新时，必须同时配置 `release_id` 与原始 `manifest.json` 字节的 SHA-256（`release_manifest_sha256`）。缺少或格式错误时在网络请求前拒绝；验签后还要求清单身份完全一致，CDN 返回另一份合法旧签名内容也不会安装。身份必须来自随客户端发布的配置或其他可信渠道，不能从同一未经身份绑定的下载响应临时取得。该固定模式锁定一份发布，不提供自动发现新版本的能力。

旧配置迁移：如果原来只配置了 `release_url`，现在会停止该入口的自动更新，返回 `release_identity_required`；这不会阻止使用有效本地内容或内置内容启动。继续使用固定入口需补齐 `release_id` 与 `release_manifest_sha256`，或者改用签名频道 `channel_url`。已有内容损坏、挂载失败等启动故障仍按原有恢复合同处理，不能与更新配置缺失混为一谈。

显式调用 `download_and_stage(url, expected_release, expected_manifest_sha256)` 采用相同身份绑定；为了保留人工指定版本的用途，两个身份参数都省略仍允许 `download_and_stage(url)`。双空模式只检查签名、兼容性与内容完整性，没有频道的版本新鲜度保证；调用者承担版本选择与 HTTPS 源可信性。半配置不允许。成功仅登记 pending；`activate_for_new_round()` 负责局间 JSON 激活，含 PCK 返回 `pack_requires_cold_start`；冷启动成功后 `confirm_boot_healthy()` 才确认新版本。

频道清单包含 `format/product/channel/revision/targets`，每个 target 包含 `runtime/release/url/manifest_sha256`。签名绑定原始字节，发布清单必须同时匹配目标 release 与哈希。每个客户端缓存保留当前频道的已接受 revision/sha256：拒绝更旧的 revision，以及同一 revision 改内容。下载失败可重试同一签名频道。计划回退时发布更高 revision 指向旧的不可变发布；自动检查不会反复启用已经试启动失败的 rejected 发布，修复包使用新 release ID。该水位不等于可信时间、跨设备权限或防本地篡改机制。

自动版本发现已经接入；用户分群、远端 A/B 分配和运营可视化页面未实现，也不是该交付器的职责。可以由已有服务为客户端提供频道地址，不需要让通用资源层理解用户画像。

发布工具与客户端共用同组 URL 回归，空端口、凭证和不符合本机调试地址合同的 URL 在签名前拒绝。HTTP 默认只接受 HTTPS，不跟随重定向，不接受 URL query/fragment/凭证；每次请求默认超时 20 秒。连接中断、超时、408、429 和 5xx 默认最多尝试 3 次，短暂指数退避；404、签名、结构、哈希和磁盘错误不盲目重试。调试构建且 `allow_local_http=true` 时可访问本机 loopback HTTP。集成测试使用该开关，正常客户端配置不因此改变。

已经安装同一清单时会重新验证本地文件，再返回 `already_installed=true`，不重复传输发布载荷；频道与 manifest 元数据仍会查询。`ContentRuntime.update_progress` 提供 phase、release、file、completed_bytes、total_bytes、file_bytes 和 attempt。`cancel_update()` 可取消传输与重试等待，返回 `download_cancelled`，清理半包且不登记 pending。安装/验签属于同步步骤，不能在步骤中途抢占；取消也不会卸载已挂载的 PCK。

### 当前产品的更新交互

现有产品采用静默后台检查。失败保留当前有效内容；JSON 在新局边界启用，PCK 在下一次冷启动启用。进度和取消保留为程序接口与诊断能力，不要求玩家操作更新页面；本项目没有宣称已经提供下载进度、取消或手动重试界面。正常后台失败不弹窗打断对局，阻止正常启动的内容故障继续走启动器已有错误提示。

固定发布地址和频道入口都拒绝已经试启动失败的不可变版本。局间激活发现候选损坏时，将其隔离并清除 pending，当前活动版本保持不变；如果隔离状态本身写入失败，诚实返回状态错误，保留原指针供重试。发布方修复使用新的 release ID。

实际页面以选题计划中已验证的尺寸创建棋盘，合法省略 `size` 的题库仍可使用。主线、每日和教程要求 `BoardView.setup()` 明确成功，主线还核对完整题面形状；搭盘失败不提交本次入场、不开放道具操作，也不能拿缓存旧棋盘冒充本次成功。

固定关卡目录按 `ContentContext.generation()` 缓存一份独立、已验证的目录。该缓存仅由 `DokuLevelCatalog` 持有，查询只复制所选题目及定义；通用 `read_json()` 仍返回副本。发布、撤销和新代次的非法目录都会触发失效，不沿用旧代次结果。首次读取仍包含整表解析与校验成本，缓存只消除同一代次的重复工作。

## 6. 激活、故障与清理

`user://content/` 与玩家业务存档分离。`releases/<id>` 是不可变内容目录；`activation_0.json` 与 `activation_1.json` 为带校验和的双槽元数据。提交成功后才发布内存状态，写失败不会先更新活动指针。文件 flush/rename 不等于对所有操作系统突然断电场景的形式化持久性保证。

指针：`pending` 是候选，`active/last_good` 是数据与上份数据，`media_active/media_last_good` 是媒体与上份媒体，`trial` 是当前待确认启动。资源挂载/解码前先写 trial；挂载以后失败就返回 `restart_required` 并阻止进入业务，不能在同一进程声称重新使用了干净基包。下一进程发现未完成 trial 后回退。这个标记表示“未完成启动”，并不能断言是新内容导致了崩溃。

启动时重验签名、哈希、合同；活动数据损坏会修复持久化指针并使用上份可用数据或内置。媒体独立验证与回退。JSON-only 版本继承的媒体目录也必须重新验签。

运行中第一次读某个已声明文件却发现损坏时，`ContentContext.content_error()` 记录 logical_id/release/error，题库不静默改用另一份题，策略不静默伪装成内置；新局入口据此阻止开始。若清单根本没声明此 ID，则正常回到内置。目录已解析进内存的 JSON 快照无需因后续磁盘改动而改变；下一次冷启动会重验磁盘。

题库 entry 上的 `_content_provenance={logical_id,release,fallback_error}` 记录实际来源；`DokuPolicy.provenance()` 记录策略来源。`ContentRuntime.diagnostics()` 提供 data/media 版本、运行时合同、是否配置、trial、内容错误、当前进度、是否正在更新、维护结果和最近交付结果。追查失败时先读 error，不要仅看 pending 或目录是否存在。

常见错误：`signature_invalid` 是签名不匹配；`runtime_mismatch` 是运行时合同不兼容；`content_schema:<id>` 是产品数据不合法；`media_requires_pack`/`media_dependency` 是媒体合同错误；`pack_existing_path`/`import_uid_collision` 是命名或 UID 冲突；`cache_quota` 是缓存配额不足；`pack_requires_cold_start` 表示继续等待下次进程。

启动器在冷启动前清理自有 `incoming_*` 与 `downloads/download_*` 中断目录；已有进程不能调用这项启动清理去删除正在下载的任务。启动选版、更新前、登记候选、JSON 激活及试启动确认后都会调用 `prune_unreferenced()`，保护 active/pending/last_good/trial/media 指针及当前已挂载 PCK。失败记录在 diagnostics，不删除玩家存档。

默认配额 768 MiB，频道上限 64 KiB、清单上限 1 MiB、单文件 128 MiB、单发布 256 MiB、文件数 2048。下载与安装会暂存副本，实际峰值空间会更高；当前没有增量包、多任务优先级或断点续传，取消后重新检查会重传尚未安装的载荷。

人工回退可以再次指定此前的已签名发布地址，按正常校验和激活流程执行。紧急恢复到完全内置内容时，在进程退出后移走整个 `user://content` 缓存目录；不要移走其他存档目录，也不要在已挂包进程内删包并期待立即卸载。

## 7. 验证与尚未覆盖的环境

统一入口见 [运行验收](README.md#运行验收)。内容专项需要 Python、PATH 中的 OpenSSL、匹配资源的 Spine-Godot，以及本机 loopback 监听权限。工具使用系统临时目录并保留隔离标记，不依赖 `/private/tmp`。引擎按显式 `--godot`、非空 `DOKU_GODOT`、PATH 中的 `godot` 依次选择；命中 PATH 不等于已验证版本或 Spine 支持。非 Meowdoku 的纯 JSON 发布不需要引擎。下面的 `ENGINE` 替换为实际引擎路径，`REPORT` 和 `SPINE_REPORT` 替换为用于保留结构化证据的文件路径。

所有下列命令的业务文件都在临时工程/目录，避免主工程 Autoload 接触日常存档：

```sh
python3 tools/content/run_tests.py --godot ENGINE --report REPORT
python3 tools/content/run_product_tests.py --godot ENGINE --report REPORT
python3 tools/content/verify_exported_resources.py --godot ENGINE
python3 tools/content/run_spine_test.py --godot ENGINE --report SPINE_REPORT
python3 tools/run_validation.py --godot ENGINE \
  --script res://tools/validation/test_content_provenance.gd \
  --script res://tools/validation/test_content_media_consumers.gd \
  --script res://tools/validation/test_content_integration.gd
```

`run_tests.py` 必须完成 8 个已计划步骤，包括发布器负向校验、基础交付、频道/下载/维护、损坏资源两进程恢复，以及真实启动器导入与两进程恢复；每个测试输出实际检查数。必需夹具缺失会在执行前明确报错，此时不生成 JSON 报告；执行后的结构化报告记录预期与实际步骤数，步骤不足或任何步骤失败均不会通过。该专项及其他内容/集成工具覆盖了 OpenSSL/Godot 签名互通、频道 revision 与目标匹配、缓存命中不重传、503 有限重试、404 不重试、下载/公开入口取消、localhost HTTP、文件破坏与错误清单、不可变安装、激活写失败、trial 未确认回退、实际图片/音频解码、真实声音与主页消费者、题源元数据、声明损坏和未覆盖的区别、尺寸合同、2700 次既有选题尺寸决策、Spine 真导出/加载及跨进程 JSON 与媒体版本继承。`run_tests.py` 还故意签发不可解码 PNG，验证“挂载以后失败要求重启 → 下一进程才回退”；该用例中的图片解码原生报错是预期故障。UID 导出实验是用于证明风险的故意碰撞包，不能作为生产发布物。

`run_product_tests.py` 使用正式 `product=meowdoku` 构建命令执行22个实际发布用例，覆盖固定关卡、主线/每日必需题池、实际尺寸AB覆盖、合法联合题源、LK字段类型、继承媒体别名、SP教程归属与预填合同、原始图片尺寸和别名，以及真实Spine动画/皮肤合同。失败用例同时要求最终发布目录不存在；正确用例必须完成产品验证和签名。该命令传入 `--report` 时将证据追加为 `product_publication_checks`，密钥、打包工程与发布物均为临时文件。

通用交付、Spine、产品签名前校验和原始PCK打包共用未知引擎 `ERROR` 门禁；退出码0或成功摘要不能覆盖原生错误。故意损坏PNG仅在指定故障进程允许其两条解码诊断，恢复进程不享有例外。Python回归会实际调用发布命令，验证模拟引擎返回0但输出ERROR时，不能生成最终签名发布目录。

发布用例重跑到同一报告时，替换旧发布检查，并根据保留的交付步骤和本次发布结果重新计算总状态。已修复的旧发布失败不会残留为总失败；仍然失败的交付步骤也不会被新发布成功覆盖。

已验证环境为 macOS 上的上述 Godot 4.6.1 Spine 定制构建；导出证明使用 Linux PCK preset，但由这个 macOS 引擎进程实际加载，**不等于 Linux 或移动设备验收**。Android/iOS 真机网络、后台终止、平台纹理导入、TLS、低磁盘及商店发行流程仍需目标平台验证。更换引擎/Spine/导入配置要重新运行导出证明；不要把一次桌面验证推断成所有平台通用。

通用层只理解 JSON、媒体和激活状态。以后换成交换三消或拖放消行，保留交付层，换产品逻辑 ID、validator、策略解析和具体媒体消费者即可；新玩法的规则/执行代码仍随客户端发布。
