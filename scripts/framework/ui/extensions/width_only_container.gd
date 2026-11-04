## 仅贡献宽度的容器：调整最小尺寸与子节点布局，避免高度参与父级尺寸计算。
class_name WidthOnlyContainer
extends Container


## 最小宽度取可见 Control 子节点中的最大值，高度固定为 0，让父容器不为这些子节点额外撑高。
func _get_minimum_size() -> Vector2:
	var width: float = 0.0
	for child in get_children():
		if child is Control and (child as Control).visible:
			width = maxf(width, (child as Control).get_combined_minimum_size().x)
	return Vector2(width, 0.0)


## 父容器安排重新排序时，把每个可见 Control 铺满本容器宽度；较高子节点居中溢出，不反向抬高最小高度。
func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	for child in get_children():
		if not (child is Control) or not (child as Control).visible:
			continue
		var control: Control = child
		var child_height: float = maxf(size.y, control.get_combined_minimum_size().y)
		fit_child_in_rect(control, Rect2(0.0, (size.y - child_height) * 0.5, size.x, child_height))
