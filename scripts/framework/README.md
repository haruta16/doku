# 公共框架：其他独立产品可以按需使用

本目录拥有通用机制，不拥有 Meowdoku 的业务、资产或 Autoload。新产品目前保留 `res://scripts/framework/` 路径接入；这不是已经发布的可任意改路径的插件包。

- `storage/`：文件保存与候选提交。产品提供路径、初始数据、schema 和校验器。
- `application/`：可选的对局与库存事务。产品提供玩法模块、动作含义、奖励资格和库存种类。
- `ui/`：窗口机制与不依赖产品场景的显示辅助。产品提供场景、路由与可选回调。
- `content/`：内容验证、交付和读取机制。产品提供身份、公钥、内容语义和启用时机。
- `presentation/`：可选的场景资源绑定。绑定表与原始资源由产品提供。

公共代码不直接引用 `products/`、`scripts/examples/` 或产品插件。Meowdoku 的应用、玩法和资源归属见 [产品目录](../../products/meowdoku/README.md)。新功能若需要知道某产品的关卡、道具、SDK 单例或固定场景结构，应先留在产品侧；不为了复用而堆叠产品分支。

这些组件有自己的合同，并不要求所有游戏采用全部组件。`ContentContext` 是单进程的活动内容上下文；这里支持多个独立产品工程复用源码，不承诺同一进程并行运行多个产品。

从仓库根目录执行：

```sh
python3 tools/check_architecture.py
python3 tools/run_framework_boundary_tests.py
```

前者检查显式资源路径，后者只复制本目录，在没有产品脚本、资源、插件和 Autoload 的独立工程中导入所有公共脚本并验证基本接入。动态分支与平台能力仍需相应专项验证。

实际初始化、依赖选择、错误处理和示例见 [新产品接入指南](../../docs/framework-usage.md)。
