## 奖励展示单元：按道具或头像框类别设置图标和数量。
extends UIChildWindow

const _ICON_Y_BIAS: float = -55.21

const _AVATAR_CELL: PackedScene = preload("res://scripts/module/profile/ui/avatar_cell.tscn")

const _FRAME_CELL_POS: Vector2 = Vector2(5.5, 13.5)

const _ICON_BY_KIND: Dictionary = {
	"locate": [preload("res://assets/sprites/game/tool_cat_item.png"), Vector2(106, 106)],
	"hint": [preload("res://assets/sprites/game/icon_hint_lamp.png"), Vector2(106, 106)],
	"draft": [preload("res://assets/sprites/game/icon_draft_pencil.png"), Vector2(106, 106)],
	"mouse": [preload("res://assets/sprites/game/icon_mouse.png"), Vector2(106, 106)],
}

@onready var _bg: TextureRect = $Frame
# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _icon: TextureRect = $IconImg # 道具图标
@onready var _count_txt: Label = $CountTxt # 数量文字

var _avatar_cell: Control = null


func on_show(params: Dictionary = {}) -> void:
	var category: int = int(params.get("category", AwardItem.Category.TOOL))
	if category == AwardItem.Category.FRAME:
		set_frame_award(int(params.get("frame_id", 0)))
	else:
		set_award(str(params.get("kind", "")), int(params.get("count", 0)))


func set_award(kind: String, count: int) -> void:
	_set_tool_visual(true)
	if _count_txt != null:
		_count_txt.text = str(count)
	var entry: Variant = _ICON_BY_KIND.get(kind, null)
	if entry == null:
		push_warning("[AwardCell] unknown kind: %s" % kind)
		if _icon != null:
			_icon.texture = null
		return
	var tex: Texture2D = entry[0]
	var size: Vector2 = entry[1]
	if _icon == null:
		return
	_icon.texture = tex
	_icon.offset_left = -size.x * 0.5
	_icon.offset_top = _ICON_Y_BIAS - size.y * 0.5
	_icon.offset_right = size.x * 0.5
	_icon.offset_bottom = _ICON_Y_BIAS + size.y * 0.5


func set_frame_award(frame_id: int) -> void:
	_set_tool_visual(false)
	if _avatar_cell == null:
		_avatar_cell = _AVATAR_CELL.instantiate()
		add_child(_avatar_cell)
		_avatar_cell.position = _FRAME_CELL_POS
	_avatar_cell.set_base_visible(false)
	_avatar_cell.set_avatar_visible(false)
	_avatar_cell.set_frame(frame_id)


func _set_tool_visual(shown: bool) -> void:
	if _bg != null:
		_bg.visible = shown
	if _icon != null:
		_icon.visible = shown
	if _count_txt != null:
		_count_txt.visible = shown
