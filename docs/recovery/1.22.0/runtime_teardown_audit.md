# 1.22.0 退出清理与启动警告审计

已确认并修复原包自带的棋盘骨骼回收时序缺陷。修复后在同一 Godot 4.6.1 / Spine 4.2.43 / macOS Metal 环境中，打开主页、继续第 2 关存档、原生关闭窗口，进程正常退出；日志没有崩溃、RID 泄漏或 ObjectDB 泄漏。没有更换项目渲染后端。

## 原因和原包证据

`BoardView` 的猫骨骼池保存未挂在场景树上的 `SpineSprite`。正常运行时，`CellView.release_cat_spine()` 解除格子与骨骼、绘制回调的绑定，再调用棋盘的 `recycle_cat_spine()`，把骨骼从集中绘制层摘下并放入池中。

退出时，父棋盘先收到 `NOTIFICATION_PREDELETE` 并清空池。随后子格子收到同一通知，又把仍有效的骨骼回收到已经清空的池。新入池的骨骼不再有父节点，而棋盘不会再执行一次池清理，于是骨骼及其渲染资源留下来。预热路径先建立 `CatBatchLayer`，再添加格子，能触发这一过程。

以下逻辑直接存在于未经格式化、未经注释迁移的 `originals/upgrades/1.22.0/recovered/`：

| 原始文件 | 行 | 证据 |
| --- | ---: | --- |
| `scripts/module/gameplay/view/board_view.gd` | 734 | `recycle_cat_spine()` 无销毁状态判断，摘下骨骼后直接入池 |
| 同上 | 750 | `PREDELETE` 只释放通知当时池中已有的骨骼 |
| 同上 | 772、785 | 先建立集中层，后添加预热格子 |
| `scripts/module/gameplay/view/cell_view.gd` | 677 | 子格子的 `PREDELETE` 调用 `release_cat_spine()` |
| 同上 | 698 | 解除绘制连接、清除格子绑定，并把骨骼交回父棋盘 |

这两份原始恢复脚本都已回编译成与原包 GDC 完全相同的字节，见 [bytecode_roundtrip.json](bytecode_roundtrip.json)；本报告的 JSON 也摘录了对应哈希。因此，问题来自原包已有的对象生命周期逻辑，不能归因于换行格式化或教学注释。

## 最小修复及验证

修复只涉及 `BoardView`：增加 `_destroying` 标记，在 `PREDELETE` 开始时置为 `true`；销毁期间的 `recycle_cat_spine()` 立即 `free()` 传入骨骼。正常运行时的回收、复用和玩法逻辑不变。这个判断也覆盖尚未完整建立 `_cells` 的情况，不依赖遍历棋盘数据数组完成回收。

验证分三层：

1. 独立最小项目用普通 `Node` 模拟相同父子通知与池结构。先层后格的旧逻辑在 `board.free()` 后仍能观察到活跃节点有效；加入销毁标记后，活跃及闲置节点都失效。脚本和原始输出保存在本地忽略目录 `originals/upgrades/1.22.0/exit_audit/`。
2. [verify_board_teardown.gd](../../../tools/verify_board_teardown.gd) 使用当前真实 `BoardView`、`CellView`、`SpineSprite` 和猫骨骼资源，完成 17 条断言：正常回收和取出、取出后池为空、活跃与闲置实例均被释放，以及绘制回调断开；分别覆盖集中层位于格子之前和之后。组件保持离树，不启动棋盘页面。
3. 修复后的真实桌面程序在原 Metal 渲染后端继续第 2 关并退出，进程状态为 0，退出日志没有资源泄漏或崩溃。

生产组件测试还做了负向对照：临时派生 `BoardView`，仅以原始恢复文件中的 `recycle_cat_spine()` 原文覆盖修复后的方法。17 条断言全部执行，其中两条活跃骨骼释放断言失败，进程状态为 1；恢复当前实现后 17 条全部通过，进程状态为 0。该对照确认测试实际能捕获回收缺陷。临时覆盖脚本没有写入业务目录。

```sh
godot-4.6.1 --headless --path . --script tools/verify_board_teardown.gd
```

测试在 Autoload 建立后动态加载业务脚本，检查脚本可实例化和实例有效性，并强制要求完成恰好 17 条断言；中途运行错误不能以 `checks=0` 获得通过结果。

## 渲染后端及验证脚本的边界

修复前的 Metal 桌面退出日志记录了 136 个 CanvasItem、22 个 Mesh 及材质、纹理等泄漏，随后在渲染器销毁路径收到 signal 11。改用 GL 的对照运行虽然正常退出，仍留下同样规模的对象和渲染资源泄漏，因此切换后端没有解决回收缺陷。修复池的生命周期后，原 Metal 路径也正常退出。现有证据支持先修复应用层生命周期；不能据此宣称 Spine 或 Godot 所有退出路径均无问题。

资源全量验证、关卡回编译验证和此组件测试的短命 headless 进程仍可产生单条 `ObjectDB instances leaked at exit`。这些工具加载项目 Autoload 后迅速退出，未完成完整游戏生命周期；当前日志未包含 `--verbose` 的残留对象清单，不能准确归因到某个等待协程或静态引用。该现象与已经消失的桌面 RID 泄漏分别记录，不把通过断言等同于零退出警告，也不为消除警告盲改业务逻辑。

## Profile 默认档警告

`ProfileService: frame_form=0 与 wins=0 不匹配…clamp 到 0` 是原包已有的默认值误报警：

- `ProfileData.frame_form` 默认是 `0`，旧存档缺键时也读为 `0`。
- 冠军头像框的第一个形态要求至少获胜 `1` 次，因此 `is_form_unlocked(0, 0)` 返回 `false`。
- `form_for_wins(0)` 返回 `-1`，随后 `maxi(0, -1)` 又变成 `0`。
- `_clamp_frame_form()` 即使值没有改变，也打印“脏档”警告。

首次不存在 `profile.cfg` 时 `_load()` 直接返回；初始化会保存默认档，之后启动加载该档即可触发这一警告。因此，它本身不证明存档损坏或恢复错误。`ProfileService`、`ProfileData` 和 `ProfileCatalog` 的原始恢复源码回编译均与原 GDC 完全一致。本次保留其原有行为；如以后专门清理日志，应只在确实改变值时警告，并单独验证存档兼容性。

原始文件位置为 `profile_service.gd:918`、`profile_data.gd:18/125`、`profile_catalog.gd:43/92/101`，均相对于上述 `recovered/scripts/module/profile/`。当前源码和原始源码的行号会因教学注释而不同。

机器可读摘要、输入与日志哈希、测试结果见 [runtime_teardown_audit.json](runtime_teardown_audit.json)。日志只保留本地相对路径和必要结论，不复制用户目录、存档内容或完整运行日志。
