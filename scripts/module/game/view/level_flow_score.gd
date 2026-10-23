## 关卡分数表现控件：设置分数并播放倍增过渡，按内容尺寸更新缩放支点。
extends Control
class_name LevelFlowScore

# ---- 图片字体资源（0~9 与加号） ----
const DIGIT_TEXTURES: Array[String] = [
	"res://assets/sprites/game/score_font/ui_mao_sz_pic_00.png",
	"res://assets/sprites/game/score_font/ui_mao_sz_pic_01.png",
	"res://assets/sprites/game/score_font/ui_mao_sz_pic_02.png",
	"res://assets/sprites/game/score_font/ui_mao_sz_pic_03.png",
	"res://assets/sprites/game/score_font/ui_mao_sz_pic_04.png",
	"res://assets/sprites/game/score_font/ui_mao_sz_pic_05.png",
	"res://assets/sprites/game/score_font/ui_mao_sz_pic_06.png",
	"res://assets/sprites/game/score_font/ui_mao_sz_pic_07.png",
	"res://assets/sprites/game/score_font/ui_mao_sz_pic_08.png",
	"res://assets/sprites/game/score_font/ui_mao_sz_pic_09.png",
]
const PLUS_TEXTURE: String = "res://assets/sprites/game/score_font/ui_mao_sz_pic_10.png" # 加号图片

# ---- 子节点引用（@onready） ----
@onready var _plus: TextureRect = $HBox/Plus # 加号
@onready var _digit1: TextureRect = $HBox/Digit1 # 第 1 位（最高位）
@onready var _digit2: TextureRect = $HBox/Digit2 # 第 2 位
@onready var _digit3: TextureRect = $HBox/Digit3 # 第 3 位
@onready var _digit4: TextureRect = $HBox/Digit4 # 第 4 位

var _current_gain: int = 0


func set_score(gain: int) -> void:
	_current_gain = gain
	var digits: String = str(gain)
	var slots: Array[TextureRect] = [_digit1, _digit2, _digit3, _digit4]

	_plus.visible = true
	_plus.texture = load(PLUS_TEXTURE)

	for i in range(4):
		if i < digits.length():
			slots[i].visible = true
			var idx: int = digits.unicode_at(i) - "0".unicode_at(0)
			slots[i].texture = load(DIGIT_TEXTURES[idx])
		else:
			slots[i].visible = false

	_update_pivot()


func animate_to_multiplied(multiplier: float, delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(
		func() -> void:
			if not is_instance_valid(self):
				return
			var from_val: float = float(_current_gain)
			var to_val: float = from_val * multiplier
			var tw: Tween = create_tween()
			tw.tween_method(func(v: float) -> void: set_score(int(v)), from_val, to_val, 0.25),
		CONNECT_ONE_SHOT
	)


func get_content_width() -> float:
	var w: float = 0.0
	var sep: int = $HBox.get_theme_constant("separation")
	var first := true
	for child: Control in $HBox.get_children():
		if child.visible:
			if not first:
				w += sep
			w += child.get_combined_minimum_size().x
			first = false
	return w


## 等布局完成后按 HBox 实际尺寸居中（缩放动画以中心为轴）
func _update_pivot() -> void:
	await get_tree().process_frame # 等一帧让 HBox 完成布局
	size = $HBox.size
	pivot_offset = size * 0.5
