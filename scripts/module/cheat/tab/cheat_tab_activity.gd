## 活动调试页签：按分类收集活动命令，以可搜索按钮列表呈现。
class_name CheatTabActivity
extends CheatTabBase


func title() -> String:
	return "活动"


func owned_tab() -> int:
	return CheatCommand.Tab.ACTIVITY


func build(content: ScrollContainer, panel: CheatPanel) -> void:
	_build_flow_with_search(content, panel, "搜索活动命令(name / 名称)…")
