## 题目调试页签：交给题目会话追踪器展示本次运行的选题记录。
class_name CheatTabPuzzle
extends CheatTabBase


func title() -> String:
	return "题库"


func build(content: ScrollContainer, _panel: CheatPanel) -> void:
	PuzzleSessionTracker.build_cheat_tab(content)
