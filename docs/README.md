# Meowdoku 恢复工程

以 Meowdoku 1.22.0（`2af1f49bd`）为产品基线、承接现有公共框架的学习恢复工程。迁移方法与待办见 [1.22 迁移计划](migration-1.22-plan.md)，范围、设计取舍和最终证据见 [1.22 迁移记录](migration-1.22-report.md)。

公共框架最初从 1.8.1 恢复基线拆分而来；本次把 1.22 的产品增量迁入该结构，继续保留内容交付与业务分离。框架背景参见 [实施与验收记录](framework-implementation.md)、[内容交付](content-delivery.md)、[本地业务](local-business.md)、[玩法模块](gameplay-modules.md) 和 [框架使用指南](framework-usage.md)。下文“恢复概况”和历史同一性报告描述原恢复阶段；本次主动重构后的源码不再声称与 APK 字节码相同。

迁移前对 `d89f94d` 的架构评估保留在 [当时的状态评估与暂缓事项](current-state-and-deferred-work.md)。它只评价迁移前版本；当前 1.22 的验证范围、剩余限制和维护事项以迁移记录为准，不能将旧结论解释为当前无 bug 或生产发布就绪。

## 当前目录与阅读顺序

如果目标是开发另一款独立产品，先读 [公共框架接入指南](framework-usage.md)，不要从复制本产品的 `app` 或整套 Doku 代码开始。目录内也有就近的所有权说明：[Meowdoku 产品](../products/meowdoku/README.md)、[公共框架](../scripts/framework/README.md)、[Meowdoku 应用](../products/meowdoku/app/README.md)、[Doku 实现](../products/meowdoku/gameplay/README.md)。

```text
scripts/
  framework/                    公共机制：存储、事务、窗口、内容交付
  examples/block/               独立接入示例；domain/ 是示例自己的规则
products/meowdoku/              Meowdoku 产品归属边界
  app/
    bootstrap/                  启动、内容装配与健康确认
    state/                      产品 schema、GameState、旧档迁移
    ui/                         产品页面注册、UIManager 与产品控件
    features/                   首页、设置、奖励、签到、语言和实验
    platform/                   当前产品的平台与 SDK 接入
    services/                   声音、会话和埋点
    diagnostics/                当前产品的调试页、API 与日志
  gameplay/
    domain/                     棋盘与纯规则，不读取产品单例、页面或文件
    application/                本产品的选题、策略、对局适配与结算
    content/                    本产品的配置、题库与发布语义校验
    presentation/               棋盘、输入、主线、每日、教程和结果表现
  editor/                       本产品的玩法编辑工具
  assets/                       本产品的美术、音频、翻译、预制体和内置数据
  launcher.tscn                 本产品的启动场景
addons/                         按 Godot 插件约定保留；不等同公共框架
tools/                          仓库验证与内容制作工具，包含产品专属校验
project.godot                   当前 Meowdoku 工程入口与 Autoload 配置
export_presets.cfg              当前 Meowdoku 的导出配置
```

学习先读 `docs/learning/00-gdscript-seven-abstractions.md`，再沿一条真实流程看：`products/meowdoku/app/bootstrap/launcher.gd` → `products/meowdoku/app/ui/ui_manager.gd` / `ui_registry.gd` → `products/meowdoku/gameplay/presentation/main/view/game_page.gd` → `products/meowdoku/gameplay/application/` → `scripts/framework/application/` / `storage/`。

`products/meowdoku/` 是明确的产品边界；其中的 `app`、`gameplay`、`assets` 都属于 Meowdoku。`gameplay/domain` 仍保持可单独验证的纯规则边界，但它的位置不意味着其他产品必须依赖它。公共框架与独立示例留在 `scripts/`，新产品自行装配所需的公共能力。

根 `project.godot` 和 `export_presets.cfg` 继续配置当前 Meowdoku 工程，不是通用产品注册表。`addons/` 保留插件安装位置，其中的产品适配插件归属见 [插件说明](../addons/README.md)。本仓库没有引入同进程切换多个产品的机制。

[历史同一性报告](RECOVERY_FIDELITY_AUDIT.md)、[原恢复过程](MEOWDOKU_逆向恢复全流程总结.md) 和 `docs/validation/` 中的既有验收证据保留当时路径，不把历史路径当作当前源码入口。

1.22 原始脚本证据位于 `.autoconverted/`，恢复证据位于 `docs/recovery/1.22.0/`，路径转换由 `tools/validation/fixtures/recovery_122_paths.json` 记录。旧恢复身份与旧验收报告保留历史含义；当前迁移源码不声称与原始字节码相同。

## 前置条件

项目使用了 Spine 4.2.43 骨骼动画资源。官方 Godot 编辑器无法识别 `SpineSprite`、`SpineAnimationTrack` 等类型，直接打开会报错。必须使用匹配的 Spine-Godot 编辑器。

从 Spine-Godot 发布页下载对应平台的编辑器：

<https://github.com/EsotericSoftware/spine-runtimes/releases>

放到工程目录外部，相对路径为：

```
../tools/spine-godot/4.2-4.6.1/godot-4.2-4.6.1-stable.exe
```

## 打开工程

在工程根目录执行：

**Windows:**
```powershell
& ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --editor --path .
```

**macOS / Linux:**
```bash
../tools/spine-godot/4.2-4.6.1/godot-4.2-4.6.1-stable --editor --path .
```

## 运行验收

完整的已实现自动验证统一由 `tools/verify.py` 编排。先指定匹配 Spine 的 Godot 可执行文件；所有引擎进程使用隔离工程，不读写日常玩家存档。

```sh
python3 tools/verify.py --suite all --godot /path/to/spine-godot
```

| 命令 | 覆盖范围 |
|---|---|
| `python3 tools/verify.py --suite quick` | Python 工具回归与资源依赖边界；引擎可用时也执行两项开发工具探针 |
| `python3 tools/verify.py --suite framework --godot ENGINE` | 上述检查，加全部自包含回归、启动检查、独立 framework/UI/业务/Block 与开发工具隔离 |
| `python3 tools/verify.py --suite all --godot ENGINE` | 上述检查，再加签名/HTTP 内容交付、产品发布、Spine 两进程和 PCK 导出证明 |
| `python3 tools/verify.py --suite all --list` | 只列计划，不执行、不生成验收结果 |
| `python3 tools/run_validation.py --suite storage --godot ENGINE` | 单独运行存储相关的自包含回归；还可选 recovery/gameplay/content/framework |

这里 `run_validation.py --suite framework` 的历史名称表示**全部自包含回归**：包含 Meowdoku 产品、页面和业务测试，不代表纯框架。统一报告中的 `framework_boundary` 才是只复制公共源码、没有产品代码、资源与 Autoload 的独立接入验证；可用 `python3 tools/run_framework_boundary_tests.py --godot ENGINE` 单独运行。

`ENGINE` 是实际引擎路径。引擎选择顺序为显式 `--godot`、非空环境变量 `DOKU_GODOT`、PATH 中的 `godot`；找到可执行文件不代表其版本或 Spine 支持已经通过验证，仍须使用匹配资源的 Spine-Godot。Python 工具用标准库；内容签名与相关 Python 回归要求 PATH 中有 `openssl`。HTTP 专项会启动本机临时服务器，需要允许 loopback 监听，不访问生产 CDN。不同平台的引擎/原生插件仍须分别验收。

默认完整入口会创建临时证据目录，并打印 `VERIFY_WORKSPACE`。其中保留逐组日志、子报告、输入指纹及总报告；`--output PATH` 可指定独立的空证据目录。摘要明确列出计划、执行、通过、排除和未执行的组；源码在验证期间发生变化会使总结果失败。`all` 指上述已实现自动检查，不包括移动 APK、原生 SDK、生产网络和人工视觉验收。

`VERIFY_ARCHIVE_SUMMARY` 指向便于归档的 `summary.json`，汇总实际环境、范围、组计数、诊断和已知告警。缺少分类证据的部分标为未知，不用零告警代替未验证；核查细节仍看原始 `report.json`、子报告和日志。归档时完整保留证据目录，可压缩保存；单独保存摘要不足以离线重建。可用 `python3 tools/validation_report.py EVIDENCE/report.json` 离线重建摘要，`EVIDENCE` 替换为证据目录；这不会重跑引擎，也不构成对新基线的批准。

`quick` 允许缺少引擎时跳过上述两项探针，并在 Python 完成结果中记录执行数与跳过数；它不能替代完整验收。`framework` 和 `all` 不接受 Python 测试跳过。

脚本测试必须输出一次包含正数检查数和零失败数的完成摘要；导入、恢复身份、启动检查及制作工具使用各自的完成合同。新增测试的运行方式、异步收尾与最小模板见 [验证脚本约定](../tools/validation/README.md)。脚本错误、缺失动画轨道、退出资源与 ObjectDB 泄漏均使当前验收失败。原 [退出诊断台账](../tools/validation/fixtures/shutdown_diagnostics.json) 保留历史日志指纹和环境归因，但不再豁免当前实现。明确注入的写盘失败与环境诊断另行分类，不能把真实错误归为测试成功。一次干净退出也不证明所有运行时路径永远无泄漏。

仅复查原恢复身份时，也可以继续使用下面的旧入口；它的默认范围是 `recovery`，不是全部套件：

```powershell
python tools/run_validation.py --godot ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe
```

`run_validation.py --suite framework --smoke` 覆盖全部自包含脚本与启动检查；需要签名、HTTP、Spine 夹具的专项由上表 `verify.py --suite all` 继续编排。不要直接在日常工程中执行会写盘的验证脚本。

预期输出：

```
VALIDATION_OK: 853 recovered scripts, 187 scenes, 75 translations, 59 level banks, 65915 records, and 45133 solution entries
```

## Android 构建

需要 Spine-Godot Android 导出模板和 Android SDK/NDK 环境。从上述 releases 页面下载匹配的导出模板，解压到：

```
../tools/spine-godot/4.2-4.6.1/templates/
```

配置 SDK 和 JDK 路径（只需一次）：

```powershell
& ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --editor --path . --script res://tools/setup_editor_settings.gd
```

导出 APK：

```powershell
& ..\tools\spine-godot\4.2-4.6.1\godot-4.2-4.6.1-stable.exe --headless --path . --export-debug Android ..\build\meowdoku-recovered.apk
```

恢复版使用独立包名 `com.oakever.meowdoku.recovered`，可与商店版共存。

## 恢复概况

- 257 个 GDScript 字节码文件全部反编译成功。
- 格式化前逐脚本重新编译并与 APK 字节码比较：255/257 字节完全一致；另 2 份仅有明确的非 Android/iOS 导出环境适配。没有发现合成变量名，也没有为了易读性重命名原标识符。
- 740/741 个导入资源完成转换。唯一失败项是 Rider 编辑器 GDExtension 描述文件，因 Android 导出包不含其平台二进制。
- 75 个运行时翻译资源全部保留。
- 26 个 XOR 混淆的关卡库文件已解码为可编辑 JSON（`products/meowdoku/assets/editor/levels/`），共 20,746 条关卡记录。`Level Bank Encryptor` 编辑器插件可将编辑后的明文重新加密到运行时目录 `products/meowdoku/assets/resources/levels/`。
- 专有的 UniKit 广告/统计 Android 插件在导出包中缺失，独立构建使用 GDScript 离线适配层。核心玩法、存档、本地化、音频、Spine 动画、教程、关卡推进、设置和调试 API 均正常可用。

完整的源码同一性、格式修复、未进入 APK 的代码边界和复核证据见 [`RECOVERY_FIDELITY_AUDIT.md`](RECOVERY_FIDELITY_AUDIT.md)。

## 参考资料

- Spine-Godot 运行时文档：<https://esotericsoftware.com/spine-godot>
- Godot Android 导出文档：<https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html>
- Godot MCP Pro 源码：<https://github.com/youichi-uda/godot-mcp-pro>
