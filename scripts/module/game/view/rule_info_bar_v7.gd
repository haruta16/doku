# 规则信息条（V7）：前 10 关显示三行固定规则，10 关之后换成可滑动的规则卡片
class_name RuleInfoBarV7
extends Control

# ---- 静态形态用到的子节点名（卡片形态下统一隐藏） ----
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

# ---- 子节点引用 ----
@onready var _control: Control = $Control # 内容容器
@onready var _swipe: RuleSwipeCard = $Control/SwipeCard # 滑动规则卡片


# ================= 形态切换 =================
# 按关卡号切换形态
func apply_level(level: int) -> void:
	# 关卡号决定形态
	var swipe_mode: bool = level > 10
	# 文字形态显示静态节点，卡片形态全部隐藏
	for n: String in _CONTROL_NODES:
		var node := _control.get_node_or_null(n) as CanvasItem
		if node != null:
			node.visible = not swipe_mode
	_swipe.visible = swipe_mode
	# 卡片形态把三条规则文案灌进滑动卡片
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


# 取某个标签的现有文案作为卡片文案（标签不存在时用 fallback 翻译 key）
func _label_text(node_name: String, fallback: String) -> String:
	var l := _control.get_node_or_null(node_name) as Label
	return l.text if l != null else fallback
