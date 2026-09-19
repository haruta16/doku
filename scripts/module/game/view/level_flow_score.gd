# 得分飘字：用图片字体拼出「+1234」，只有 4 个数字位，位数不够的槽位隐藏
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


# 设置要显示的分数（按十进制逐位贴图）
func set_score(gain: int) -> void:
	var digits: String = str(gain)
	var slots: Array[TextureRect] = [_digit1, _digit2, _digit3, _digit4]

	_plus.visible = true
	_plus.texture = load(PLUS_TEXTURE)

	# 第 i 位有数字就贴对应贴图，没有就把槽位藏起来
	for i in range(4):
		if i < digits.length():
			slots[i].visible = true
			var idx: int = digits.unicode_at(i) - "0".unicode_at(0)
			slots[i].texture = load(DIGIT_TEXTURES[idx])
		else:
			slots[i].visible = false

	_update_pivot()


# 等布局完成后按 HBox 实际尺寸居中（缩放动画以中心为轴）
func _update_pivot() -> void:
	await get_tree().process_frame # 等一帧让 HBox 完成布局
	size = $HBox.size
	pivot_offset = size * 0.5
