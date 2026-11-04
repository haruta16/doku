## 流动网格背景：进入场景时调整尺寸以覆盖设计画布。
class_name GridFlowBg
extends Sprite2D

const _DESIGN_W: float = 1080.0 # 素材使用的设计画布宽度（逻辑像素）
const _OVERSCAN: float = 1.02 # 放大时额外留出 2% 宽度；背景流动/采样边界不易露出空隙


## 首次进树时按当前视口宽度对齐；本组件没有注册后续 resize 监听。
func _ready() -> void:
	_fit_to_canvas()


## 将背景横向居中；仅当视口比设计宽度更宽时等比放大，并留少量溢出防露边。
func _fit_to_canvas() -> void:
	var vp_w: float = get_viewport_rect().size.x
	position.x = vp_w * 0.5
	if vp_w > _DESIGN_W:
		var s: float = (vp_w / _DESIGN_W) * _OVERSCAN
		scale = Vector2(s, s)
