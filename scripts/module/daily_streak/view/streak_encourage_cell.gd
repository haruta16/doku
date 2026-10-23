## 打卡鼓励文本单元：根据时段和猫图样式刷新文案布局。
extends UIChildWindow

enum Slot {
	DAWN = 1, MORNING = 2, MIDMORNING = 3, NOON = 4, LAZY = 5, DUSK = 6, NIGHT = 7, MIDNIGHT = 8
}

const _SLOT_COLOR: Array[Color] = [
	Color("763e43"),
	Color("834317"),
	Color("4d522d"),
	Color("834317"),
	Color("45492b"),
	Color("672e33"),
	Color("f7f2ee"),
	Color("f7f2ee"),
]

const _TEXT_X_WITH_CAT: float = 244.0
const _TEXT_X_NO_CAT: float = 152.0
const _TEXT_W: float = 656.0

const _TITLE_TOP: float = 20.0
const _TITLE_H_WITH_CAT: float = 80.0
const _TITLE_H_NO_CAT: float = 70.0

@export var bg_with_cat: Array[Texture2D] = []
@export var bg_no_cat: Array[Texture2D] = []

@onready var _bg: TextureRect = $Bg
@onready var _title: Label = $TitleTxt
@onready var _body: Label = $BodyTxt

var _slot: int = Slot.DAWN
var _with_cat: bool = true


func on_show(params: Dictionary = {}) -> void:
	set_slot(int(params.get("slot", _slot)), bool(params.get("with_cat", _with_cat)))


func set_slot(slot: int, with_cat: bool) -> void:
	_slot = clampi(slot, Slot.DAWN, Slot.MIDNIGHT)
	if slot < Slot.DAWN or slot > Slot.MIDNIGHT:
		push_error("StreakEncourageCell: slot=%d 越界(应为 1..8),已钳到 %d" % [slot, _slot])
	_with_cat = with_cat
	_apply_style()


func set_text(title: String, body: String) -> void:
	_title.text = title
	_body.text = body


func get_slot() -> int:
	return _slot


func is_with_cat() -> bool:
	return _with_cat


func _apply_style() -> void:
	var i: int = _slot - 1
	var pool: Array[Texture2D] = bg_with_cat if _with_cat else bg_no_cat
	if i < pool.size() and pool[i] != null:
		_bg.texture = pool[i]
	else:
		push_error(
			(
				"StreakEncourageCell: 底板缺失 slot=%d with_cat=%s(检查 .tscn 的 bg_* 数组)"
				% [_slot, str(_with_cat)]
			)
		)
	var col: Color = _SLOT_COLOR[i]
	_title.add_theme_color_override("font_color", col)
	_body.add_theme_color_override("font_color", col)
	var x: float = _TEXT_X_WITH_CAT if _with_cat else _TEXT_X_NO_CAT
	for lb: Label in [_title, _body]:
		lb.offset_left = x
		lb.offset_right = x + _TEXT_W

	_title.offset_top = _TITLE_TOP
	_title.offset_bottom = _TITLE_TOP + (_TITLE_H_WITH_CAT if _with_cat else _TITLE_H_NO_CAT)
