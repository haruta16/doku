## 局内调试页签：集中展示影响当前盘面与玩法状态的命令。
class_name CheatTabGameplay
extends CheatTabBase


func title() -> String:
	return "局内"


func owned_tab() -> int:
	return CheatCommand.Tab.GAMEPLAY


func build(content: ScrollContainer, panel: CheatPanel) -> void:
	_build_flow_with_search(content, panel, "搜索局内命令(name / 名称)…")
