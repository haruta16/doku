## 流动网格背景：进入场景时调整尺寸以覆盖设计画布。
class_name GridFlowBg
extends Sprite2D

const _DESIGN_W: float = 1080.0
const _OVERSCAN: float = 1.02


func _ready() -> void:
	_fit_to_canvas()


func _fit_to_canvas() -> void:
	var vp_w: float = get_viewport_rect().size.x
	position.x = vp_w * 0.5
	if vp_w > _DESIGN_W:
		var s: float = (vp_w / _DESIGN_W) * _OVERSCAN
		scale = Vector2(s, s)
