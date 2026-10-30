## 通用调试页签：展示未归入局内或活动分类的可搜索命令。
class_name CheatTabCommand
extends CheatTabBase


func title() -> String:
	return "命令"


func owned_tab() -> int:
	return CheatCommand.Tab.COMMAND


func build(content: ScrollContainer, panel: CheatPanel) -> void:
	_build_flow_with_search(content, panel, "搜索命令(name / 名称)…")
