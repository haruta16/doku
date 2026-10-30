# 恢复提示翻译

本目录只维护新增的六条故障恢复文案。原始 75 份 `OptimizedTranslation` 不修改，也不由 CSV 再生成。

每个 `.po` 是 Godot 原生 `Translation` 资源，由 `project.godot` 的 `locale/translations` 注册，随启动加载及资源导出。直接编辑 `msgstr` 即可，不需要生成脚本。`ConfirmDialog` 和 `Toast` 使用已有的 `tr()` 解析消息键。

62 份语言资源覆盖原来的 75 个 locale：`en_PH`、`fr_CA`、阿拉伯语各地区等沿用 Godot 的语言匹配；中文保留简繁两份。新增语言时同时注册资源并补充验证范围。

| 消息键 | 含义与约束 |
| --- | --- |
| `RECOVERY_RESULT_TITLE` | 本局结果尚未保存。 |
| `RECOVERY_RESULT_BODY` | 可重试保存；关闭会返回主页，未保存的结果可能丢失。不能暗示已成功保存。 |
| `RECOVERY_CHECKIN_TITLE` | 每日签到尚未保存。这里的签到指每日游戏进度，不是账号登录。 |
| `RECOVERY_CHECKIN_BODY` | 通关结果已经保存；可重试签到，也可关闭跳过本次签到。不能误称胜利丢失。 |
| `RECOVERY_CONTENT_ERROR` | 游戏内容无法读取，请重启游戏。 |
| `RECOVERY_SAVE_ERROR` | 本次操作无法保存，请重试。 |

操作按钮继续使用原始翻译表的 `FAIL_TRY_AGAIN`。这些新增译文未经各语言母语者审校；自动验证保证键的加载、地区回退和界面接入，不能替代语言质量与实际字体排版验收。

验证：`python3 tools/run_validation.py --script res://tools/validation/test_game_recovery_localization.gd --suite recovery`。该测试覆盖 75 个 locale 的六个键与原有重试按钮，另在英语、简体中文、繁体中文、法语、日语下触发真实保存失败、签到失败和两类提示。
