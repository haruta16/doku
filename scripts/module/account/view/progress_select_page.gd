## 进度冲突选择页；展示本地与云端快照，收集玩家选择后交给 AccountManager 应用。
## 选中一行只改变界面状态，点击继续才会触发存档合并和后续页面重载。

extends UIFrameWindow

const _OPTION_ROW: PackedScene = preload(
	"res://scripts/module/account/ui/other/progress_option_row.tscn"
)

const KIND_LOCAL: String = "local"

const KIND_CLOUD: String = "cloud"

const _CARD_X: float = 50.0

const _CARD_W: float = 800.0

const _CARD_H: float = 200.0

const _CARD_STEP: float = 240.0

const _DIALOG_W: float = 900.0

const _TITLE_H: float = 130.0

const _TITLE_GAP: float = 70.0

const _TXT_PAD_V: float = 30.0

const _MSG_H_BASE: float = 160.0

const _CARD_GAP_TOP: float = 40.0

const _BTN_GAP_TOP: float = 60.0

const _BTN_H: float = 160.0

const _BOTTOM: float = 90.0

const _BTN_PAD_TOP: float = 68.0

const _BTN_INST_H: float = 258.0

@onready var _card_host: Control = %CardHost

const _POPUP_LAYOUT := preload("res://scripts/module/account/view/other/account_popup_layout.gd")

@onready var _dialog_root: Control = $Root/Content/DialogRoot

@onready var _info_box: Panel = $Root/Content/DialogRoot/InfoBox

@onready var _msg_txt: Label = $Root/Content/DialogRoot/InfoBox/MsgTxt

@onready var _action_btn: Control = %ActionBtn

var _rows: Dictionary = {}

var _selected: String = ""


func _ready() -> void:
	_action_btn.tag_pressed.connect(_on_continue_pressed)


## 读取当前冲突快照并生成两组选项；展示前刷新数据，减少页面停留期间的过期状态。
func on_show(params: Dictionary = {}) -> void:
	_clear_rows()
	var conflict: ProgressConflict = params.get("conflict")
	if conflict == null:
		push_error("[Account (ProgressSelectPage)] 缺 conflict 参数，无法渲染卡片")
		return
	print(
		(
			"[Account (ProgressSelectPage)] 展示 local=%d/%d cloud=%d/%d suggested=%s"
			% [
				conflict.local.level,
				conflict.local.items,
				conflict.cloud.level,
				conflict.cloud.items,
				conflict.suggested
			]
		)
	)
	_build_row(KIND_LOCAL, 0, tr("PROGRESS_KEEP_LOCAL"), conflict.local)
	_build_row(KIND_CLOUD, 1, tr("PROGRESS_RESTORE_CLOUD"), conflict.cloud)
	_select(conflict.suggested)

	_relayout()


func _relayout() -> void:
	var y: float = _TITLE_H + _TITLE_GAP
	var msg_h: float = _msg_height()
	_info_box.offset_top = y
	_info_box.offset_bottom = y + _TXT_PAD_V + msg_h + _TXT_PAD_V

	_msg_txt.offset_top = _TXT_PAD_V
	_msg_txt.offset_bottom = _TXT_PAD_V + msg_h
	y = _info_box.offset_bottom + _CARD_GAP_TOP
	var rows: Array[Node] = _card_host.get_children()
	for row in rows:
		var c: Control = row as Control
		if c == null:
			continue
		c.position.y = y + float(int(c.get_meta(&"row_index", 0))) * _CARD_STEP
	var last_card_bottom: float = y + float(maxi(rows.size() - 1, 0)) * _CARD_STEP + _CARD_H

	_action_btn.offset_top = last_card_bottom + _BTN_GAP_TOP - _BTN_PAD_TOP
	_action_btn.offset_bottom = _action_btn.offset_top + _BTN_INST_H
	var total: float = last_card_bottom + _BTN_GAP_TOP + _BTN_H + _BOTTOM
	_dialog_root.offset_top = -total * 0.5
	_dialog_root.offset_bottom = total * 0.5
	_dialog_root.offset_left = -_DIALOG_W * 0.5
	_dialog_root.offset_right = _DIALOG_W * 0.5


func _msg_height() -> float:
	return _POPUP_LAYOUT.msg_height(_msg_txt, _MSG_H_BASE)


func _build_row(kind: String, index: int, title: String, info: ProgressSnapshot) -> void:
	var row: Button = _OPTION_ROW.instantiate()
	_card_host.add_child(row)

	row.position = Vector2(_CARD_X, 0.0)
	row.size = Vector2(_CARD_W, _CARD_H)
	row.set_meta(&"row_index", index)
	row.setup(kind, title, tr("PROGRESS_LEVEL") % info.level, tr("PROGRESS_ITEMS") % info.items)
	row.pressed.connect(_select.bind(kind))
	_rows[kind] = row


func _clear_rows() -> void:
	var children: Array[Node] = _card_host.get_children()
	for c in children:
		_card_host.remove_child(c)
		c.queue_free()
	_rows.clear()
	_selected = ""


## 更新当前选择及行高亮；此步骤尚未覆盖任何进度。
func _select(kind: String) -> void:
	if _selected == kind:
		return
	_selected = kind
	var kinds: Array = _rows.keys()
	for k in kinds:
		var row: Button = _rows[k]
		row.set_selected(k == kind)


func get_dlg_name() -> String:
	return Tracker.Dlg.PROGRESS_SELECT


func on_escape() -> bool:
	print("[Account (ProgressSelectPage)] 返回键被吞掉:必须先选一个进度")
	return true


## 把已选项提交给 AccountManager，随后由账号流程决定同步与页面重载。
func _on_continue_pressed() -> void:
	if AccountManager.is_busy():
		print("[Account (ProgressSelectPage)] Continue 重复触发(流程进行中),忽略")
		return
	if _selected.is_empty():
		print("[Account (ProgressSelectPage)] Continue 但未选任何一项,忽略")
		return
	print("[Account (ProgressSelectPage)] 玩家选择=%s" % _selected)
	Tracker.track_btn_click(Tracker.Btn.CONTINUE, self, {"progress_choice": _selected})

	if not AccountManager.apply_progress_choice(_selected):
		print("[Account (ProgressSelectPage)] 选择未被受理(选云端但无网),本页留在屏上等玩家改选或联网")
		UIManager.show_ui(UiName.NO_CONNECTION, {"retry": "progress"})
		return

	UIManager.hide_ui(_ui_name)
