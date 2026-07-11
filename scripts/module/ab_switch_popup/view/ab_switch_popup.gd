@tool
class_name AbSwitchPopup
extends UIFrameWindow

@export var cat_y_offset: float = -350:
	set(v):
		cat_y_offset = v
		_sync_cat()

@onready
var _popup_text_txt: Label = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Content/Panel/PopUpText
@onready var _title_txt: Label = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Title/Text
@onready var _btn: Control = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Btn
@onready var _bg: PanelContainer = $Content/CenterContainer/BgSizeBox/Bg
@onready var _cat_dialog: Control = $Content/CatDialog


func _ready() -> void:
	if not is_instance_valid(_bg):
		return
	_bg.item_rect_changed.connect(_sync_cat)
	if Engine.is_editor_hint():
		set_process(true)
	call_deferred("_sync_cat")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_cat()


func _sync_cat() -> void:
	if not is_node_ready():
		return
	if not is_instance_valid(_bg) or not is_instance_valid(_cat_dialog):
		return

	var bgsizebox: Control = _bg.get_parent() as Control
	var center_container: Control = bgsizebox.get_parent() as Control
	var bg_top: float = center_container.position.y + bgsizebox.position.y + _bg.position.y
	_cat_dialog.position.y = bg_top + cat_y_offset


func on_show(params: Dictionary = {}) -> void:
	var text: String = params.get("text", "")
	if not text.is_empty():
		_popup_text_txt.text = text

	var title: String = params.get("title", "")
	if not title.is_empty():
		_title_txt.text = title

	var btn_text: String = params.get("btn_text", "")
	if not btn_text.is_empty():
		_btn.set("btn_text", btn_text)


func _on_action_pressed() -> void:
	UIManager.hide_ui(get_ui_name())


func _on_close_pressed() -> void:
	UIManager.hide_ui(get_ui_name())
