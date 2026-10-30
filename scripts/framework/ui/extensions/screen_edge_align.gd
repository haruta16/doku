## 屏幕边缘对齐组件：进入场景后把目标节点布局到所需屏幕边界。
class_name ScreenEdgeAlign
extends Control

const SIDE_LEFT := 0
const SIDE_RIGHT := 1

@export_enum("LEFT", "RIGHT") var side: int = SIDE_LEFT

@export var container: NodePath = NodePath("")


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ref: Control
	if container != NodePath(""):
		ref = get_node_or_null(container) as Control
	else:
		ref = get_parent() as Control
	if ref == null:
		push_error("ScreenEdgeAlign: 无法确定参照容器，请通过 container 属性手动指定")
		return
	var canvas_w: float = get_viewport().get_visible_rect().size.x
	var left_margin: float = ref.global_position.x
	var right_margin: float = canvas_w - (ref.global_position.x + ref.size.x)
	if side == SIDE_LEFT and left_margin > 0.5:
		offset_left -= left_margin
		offset_right -= left_margin
	elif side == SIDE_RIGHT and right_margin > 0.5:
		offset_left += right_margin
		offset_right += right_margin
