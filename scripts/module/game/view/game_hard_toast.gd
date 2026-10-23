## 难关提示卡：在通用开局卡基础上选择难关或超难关皮肤和文本节点。
class_name GameHardToast
extends BaseGameToast

# ---- 外观配置 ----
const APPEAR_ANIM: StringName = &"Beginning" # 场景里的入场动画


## 使用的入场动画名
func _appear_anim() -> StringName:
	return APPEAR_ANIM


## 埋点用的弹窗名
func _dlg_name() -> String:
	return Tracker.Dlg.GAME_HARD_TOAST


func _label_subpaths() -> Dictionary:
	return {
		"Card6": "PanelContainer/VBoxContainer/Label",
		"Card7": "PanelContainer/VBoxContainer/Label",
		"Card11": "PanelContainer/VBoxContainer/PanelContainer/Label",
	}


const _SUPER_HARD_FIRE_TEX: Texture2D = preload("res://assets/sprites/pop/icon_fire_super.png")

const _SUPER_HARD_TAG_COLOR: Color = Color(0.9529412, 0.30980393, 0.8862745, 1)
const _SUPER_HARD_TAG_KEY: String = "GAME_SUPER_HARD_TAG"

const _SKIN_SUBPATHS: Dictionary = {
	"Card6":
	[
		"PanelContainer/VBoxContainer/HBoxContainer/FireIcon",
		"PanelContainer/VBoxContainer/HBoxContainer/HardLabel"
	],
	"Card7":
	[
		"PanelContainer/VBoxContainer/HBoxContainer/FireIcon",
		"PanelContainer/VBoxContainer/HBoxContainer/HardLabel"
	],
	"Card11": ["", "PanelContainer/VBoxContainer/HBoxContainer/HardLabel"],
}

var _tag_base: Dictionary = {}


func _apply_text(params: Dictionary) -> void:
	super._apply_text(params)
	_apply_super_hard_skin(bool(params.get("super_hard", false)))


func _apply_super_hard_skin(is_super_hard: bool) -> void:
	var card_name: String = _active_card_name()
	var subpaths: Array = _SKIN_SUBPATHS.get(card_name, [])
	if subpaths.is_empty():
		return
	var card: Control = $Root/Card.get_node_or_null(card_name) as Control
	if card == null:
		return
	var fire: TextureRect = null
	if not String(subpaths[0]).is_empty():
		fire = card.get_node_or_null(String(subpaths[0])) as TextureRect
	var tag: Label = card.get_node_or_null(String(subpaths[1])) as Label
	if tag == null:
		return
	if not _tag_base.has(card_name):
		_tag_base[card_name] = {
			"tex": fire.texture if fire != null else null,
			"text": tag.text,
			"color": tag.get_theme_color(&"font_color"),
		}
	var base: Dictionary = _tag_base[card_name]
	if fire != null:
		fire.texture = _SUPER_HARD_FIRE_TEX if is_super_hard else base["tex"]
	tag.text = _SUPER_HARD_TAG_KEY if is_super_hard else String(base["text"])
	tag.add_theme_color_override(
		&"font_color", _SUPER_HARD_TAG_COLOR if is_super_hard else base["color"]
	)


func _active_card_name() -> String:
	return NormalStartToastConfig.CARD_BASELINE
