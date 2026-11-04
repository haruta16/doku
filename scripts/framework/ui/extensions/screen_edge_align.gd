## 屏幕边缘对齐组件：进入场景后把目标节点布局到所需屏幕边界。
class_name ScreenEdgeAlign
extends Control

const SIDE_LEFT := 0 # 左边缘对齐，和 Inspector 枚举顺序一致
const SIDE_RIGHT := 1 # 右边缘对齐

@export_enum("LEFT", "RIGHT") var side: int = SIDE_LEFT # 选择向哪一侧补偿参照容器与视口的空隙

@export var container: NodePath = NodePath("") # 参照 Control 的相对节点路径；空值使用父节点


## 等待两帧布局后，将本控件水平平移到参照容器外侧的屏幕边缘；只做一次，不跟踪后续 resize。
## container 未指定时以父 Control 为参照；只平移左右偏移，不改变本控件宽度。
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
	# 用参照控件的左右位置计算屏幕边距；小于半像素或已越界时不再补偿。
	var canvas_w: float = get_viewport().get_visible_rect().size.x
	var left_margin: float = ref.global_position.x
	var right_margin: float = canvas_w - (ref.global_position.x + ref.size.x)
	if side == SIDE_LEFT and left_margin > 0.5:
		offset_left -= left_margin
		offset_right -= left_margin
	elif side == SIDE_RIGHT and right_margin > 0.5:
		offset_left += right_margin
		offset_right += right_margin
