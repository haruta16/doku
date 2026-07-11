class_name RuleInfoBarV7
extends Control

const _CONTROL_NODES: Array = [
	"RulesBg",
	"RulePill1",
	"RulePill2",
	"RulePill3",
	"RuleHighlight1",
	"RuleHighlight2",
	"RuleHighlight3",
	"RuleLabel1",
	"RuleLabel2",
	"RuleLabel3",
]

@onready var _control: Control = $Control
@onready var _swipe: RuleSwipeCard = $Control/SwipeCard


func apply_level(level: int) -> void:
	var swipe_mode: bool = level > 10
	for n: String in _CONTROL_NODES:
		var node := _control.get_node_or_null(n) as CanvasItem
		if node != null:
			node.visible = not swipe_mode
	_swipe.visible = swipe_mode
	if swipe_mode:
		(
			_swipe
			. setup(
				[
					_label_text("RuleLabel1", "GAME_RULE_ONE_PER_COLOR"),
					_label_text("RuleLabel2", "GAME_RULE_ONE_PER_LINE"),
					_label_text("RuleLabel3", "GAME_RULE_NO_TOUCH"),
				]
			)
		)


func _label_text(node_name: String, fallback: String) -> String:
	var l := _control.get_node_or_null(node_name) as Label
	return l.text if l != null else fallback
