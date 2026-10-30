# 验证脚本约定

`run_validation.py --suite framework` 收集本目录顶层的自包含 `test_*.gd`，包括产品与页面回归。它不等于纯框架验证；统一报告的 `framework_boundary` 组在没有产品代码、资源与 Autoload 的临时工程中检查公共框架。签名、HTTP、Spine 等需要外部夹具的测试由内容专项运行器准备。

新增自包含测试时，复制 [最小模板](fixtures/test_template.gd) 为 `test_<name>.gd`，替换其中故意失败的检查及摘要名称。模板位于 `fixtures/`，不会被自动纳入 suite；不要靠恒真断言让空模板通过。

例如复制并实现为 `test_example.gd` 后，在仓库根目录运行；`ENGINE` 替换为匹配的 Spine-Godot 可执行文件：

```sh
python3 tools/run_validation.py --godot ENGINE --script res://tools/validation/test_example.gd
```

引擎选择顺序是显式 `--godot`、非空 `DOKU_GODOT`、PATH 中的 `godot`。PATH 命中只说明找到了程序，不能代替版本与 Spine 兼容验证。

不要直接执行 `godot --path . --script ...` 或在日常工程中按 F6。运行器先复制工程，在副本内重定向 `user://` 与 `OS.get_user_data_dir()`，每个测试进程重置隔离存档，并保留前一份临时数据供排查。测试不得自行拼接真实玩家目录、读取日常存档或删除隔离工程以外的文件；需要临时资源时使用副本的 `res://validation_artifacts/<test_name>/`。

每个测试进程只输出一条最终摘要，例如：

```text
EXAMPLE TESTS checks=3 failures=0
```

检查数必须来自实际执行且大于零；每条失败都累加失败数、输出具体标签，并最终 `quit(1)`。成功才 `quit(0)`；隔离条件不满足可用 `quit(2)`。空检查、缺失摘要、重复摘要、非零失败数或退出码都会失败。不要让辅助函数各打印一份完成摘要，也不要捕获失败后继续宣称成功。导入、恢复身份、固定帧启动检查和制作工具各有完成合同，不通过打印测试摘要冒充执行。

异步测试须等待待验证行为真正完成，再检查结果；至少保留正常成功路径，负向测试也要证明触发条件已经建立。结束前取消本测试拥有的任务、定时器和连接，释放节点并等待 `queue_free()` 等待处理的工作收尾，最后输出摘要和退出。不能仅加长固定等待来掩盖未完成回调或资源泄漏。

运行器保留环境诊断与退出资源诊断。当前验收对脚本异常、缺失动画轨道和任意退出资源／ObjectDB 泄漏判失败；历史台账仅提供脚本、消息、数量与运行环境的归因证据，不构成豁免。明确故障注入必须有对应断言，不能只凭完成摘要中的零失败判定通过。
