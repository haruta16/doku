extends Control
class_name LevelFlowScore

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
const PLUS_TEXTURE: String = "res://assets/sprites/game/score_font/ui_mao_sz_pic_10.png"

@onready var _plus: TextureRect = $HBox/Plus
@onready var _digit1: TextureRect = $HBox/Digit1
@onready var _digit2: TextureRect = $HBox/Digit2
@onready var _digit3: TextureRect = $HBox/Digit3
@onready var _digit4: TextureRect = $HBox/Digit4


func set_score(gain: int) -> void:
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


func _update_pivot() -> void:
	await get_tree().process_frame
	size = $HBox.size
	pivot_offset = size * 0.5
