## 账号入口页：按渠道动态生成按钮，并将登录、登出、删除操作转交账号管理器。
## 界面监听流程状态更新可点击性，不直接调用原生登录 SDK。

extends UIFrameWindow

const _CHANNEL_ROW: PackedScene = preload("res://scripts/module/account/ui/other/channel_row.tscn")

const _TITLE_H: float = 130.0

const _TITLE_GAP: float = 70.0

const _DESIGN_LINE_RATIO: float = 1.33

const _MSG_LINES_LOGGED_OUT: int = 1

const _MSG_LINES_LOGGED_IN: int = 4

const _INFO_PAD_V: float = 30.0

const _INFO_TXT_W: float = 700.0

const _MSG_FS_LOGGED_OUT: int = 50

const _MSG_FS_LOGGED_IN: int = 60

const _INFO_GAP: float = 60.0

const _ROW_STEP: float = 200.0

const _ROW_H: float = 160.0

const _ROW_LEFT: float = 75.0

const _LINK_GAP: float = 70.0

const _LINK_H: float = 80.0

const _BOTTOM_SPACER: float = 90.0

const _DIALOG_W: float = 900.0

@onready var _dialog_root: Control = %DialogRoot

const _POPUP_LAYOUT := preload("res://scripts/module/account/view/other/account_popup_layout.gd")

@onready var _info_box: Panel = %InfoBox

@onready var _info_style_beige: StyleBox = _info_box.get_theme_stylebox(&"panel")

var _info_style_empty: StyleBoxEmpty = StyleBoxEmpty.new()

@onready var _msg_txt: Label = %InfoBox/MsgTxt

@onready var _title_txt: Label = %DialogRoot/TitleGroup/TitleTxt

@onready var _channel_list: Control = %ChannelList

@onready var _delete_link: Button = %DeleteLink

@onready var _delete_link_txt: RichTextLabel = %DeleteLink/LinkTxt

@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

var _logged_in: bool = false

var _signed_in_channel: String = ""


## 恢复页面内容并订阅账号流程信号，使按钮状态跟随实际登录/登出过程。
func on_show(params: Dictionary = {}) -> void:
	var channels: Array = params.get("channels", AccountDefine.available_channels())
	_signed_in_channel = str(params.get("signed_in_channel", ""))
	_logged_in = not _signed_in_channel.is_empty()
	_rebuild(channels)
	connect_managed(AccountManager.flow_state_changed, _on_flow_state_changed)
	connect_managed(AccountManager.login_flow_finished, _on_login_finished)

	connect_managed(AccountManager.logout_flow_finished, _on_logout_finished)

	set_channels_enabled(not AccountManager.is_busy())

	_delete_link_txt.text = "[center][u]%s[/u][/center]" % tr("DELETE_BTN_DELETE_ACCOUNT")


func on_hide() -> void:
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished


func get_dlg_name() -> String:
	return Tracker.Dlg.LOGIN


func _on_close_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	super._on_close_btn_pressed()


func set_channels_enabled(enabled: bool) -> void:
	var rows: Array[Node] = _channel_list.get_children()
	for row in rows:
		var btn: Button = row as Button
		if btn == null:
			continue
		btn.disabled = not enabled
		btn.modulate.a = 1.0 if enabled else 0.5


## 根据当前登录状态和可用渠道重新生成行组件；认证规则仍由管理器检查。
func _rebuild(channels: Array) -> void:
	_clear_rows()
	_apply_texts()
	var rows_to_draw: Array = [_signed_in_channel] if _logged_in else channels
	var rendered: Array[String] = []
	for i in rows_to_draw.size():
		var ch: String = str(rows_to_draw[i])
		var row: Button = _CHANNEL_ROW.instantiate()
		_channel_list.add_child(row)
		row.position = Vector2(_ROW_LEFT, i * _ROW_STEP)
		row.size = Vector2(750.0, _ROW_H)
		if _logged_in:
			row.setup(ch, tr("LOGOUT_BTN_SIGN_OUT"), true)
		else:
			row.setup(ch, tr("LOGIN_BTN_SIGN_IN_WITH") % AccountDefine.display_name(ch))
		row.pressed.connect(_on_channel_pressed.bind(ch, _logged_in))
		rendered.append("%s=%s" % [ch, "SignOut" if _logged_in else "SignIn"])
	print(
		(
			"[Account (LoginPage)] 重建渠道行 signed_in='%s' rows=[%s]"
			% [_signed_in_channel, ", ".join(rendered)]
		)
	)
	_relayout(rows_to_draw.size())


func _apply_texts() -> void:
	_msg_txt.add_theme_font_size_override(
		&"font_size", _MSG_FS_LOGGED_IN if _logged_in else _MSG_FS_LOGGED_OUT
	)
	_title_txt.text = "LOGIN_TITLE_SIGNED_IN" if _logged_in else "LOGIN_TITLE"
	if _logged_in:
		_msg_txt.text = tr("LOGIN_MSG_SIGNED_IN") % AccountDefine.display_name(_signed_in_channel)
	else:
		_msg_txt.text = "LOGIN_MSG"


func _clear_rows() -> void:
	var rows: Array[Node] = _channel_list.get_children()
	for row in rows:
		_channel_list.remove_child(row)
		row.queue_free()


func _relayout(row_count: int) -> void:
	var y: float = _TITLE_H
	y += _TITLE_GAP

	_info_box.visible = true
	_info_box.add_theme_stylebox_override(
		&"panel", _info_style_beige if _logged_in else _info_style_empty
	)
	var info_h: float = _info_height()
	_info_box.offset_top = y
	_info_box.offset_bottom = y + info_h

	_msg_txt.offset_top = _INFO_PAD_V
	_msg_txt.offset_bottom = info_h - _INFO_PAD_V
	y += info_h + _INFO_GAP

	_channel_list.offset_top = y
	var list_h: float = maxf(0.0, row_count * _ROW_STEP - (_ROW_STEP - _ROW_H))
	_channel_list.offset_bottom = y + list_h
	y += list_h

	_delete_link.visible = true
	y += _LINK_GAP
	_delete_link.offset_top = y
	_delete_link.offset_bottom = y + _LINK_H
	y += _LINK_H

	y += _BOTTOM_SPACER

	_dialog_root.offset_top = -y * 0.5
	_dialog_root.offset_bottom = y * 0.5
	_dialog_root.offset_left = -_DIALOG_W * 0.5
	_dialog_root.offset_right = _DIALOG_W * 0.5


func _info_height() -> float:
	var font_size: int = _msg_txt.get_theme_font_size(&"font_size")
	var lines: int = _MSG_LINES_LOGGED_IN if _logged_in else _MSG_LINES_LOGGED_OUT

	var design_h: float = float(lines) * float(font_size) * _DESIGN_LINE_RATIO

	var measured: float = _POPUP_LAYOUT.msg_height(_msg_txt, design_h)
	return maxf(design_h, measured) + 2.0 * _INFO_PAD_V


## 将用户选择的渠道交给管理器执行；页面只负责交互反馈。
func _on_channel_pressed(channel: String, is_sign_out: bool) -> void:
	print("[Account (LoginPage)] 渠道行按下 ch=%s → %s" % [channel, "登出确认弹窗" if is_sign_out else "发起登录"])
	if is_sign_out:
		Tracker.track_btn_click(Tracker.Btn.SIGN_OUT, self)
		UIManager.show_ui(UiName.SIGN_OUT_CONFIRM, {"channel": channel})
		return

	if AccountManager.is_busy():
		return
	Tracker.track_btn_click(Tracker.Btn.SIGN_IN, self, {"channel": channel})

	AccountManager.start_login(channel)


func _on_flow_state_changed(busy: bool) -> void:
	set_channels_enabled(not busy)


func _on_login_finished(ok: bool, channel: String, kind: String, _code: int) -> void:
	print(
		"[Account (LoginPage)] 登录流程结束 ok=%s ch=%s kind=%s code=%d" % [str(ok), channel, kind, _code]
	)
	UIManager.hide_ui(_ui_name)
	if ok:
		var conflict: ProgressConflict = AccountManager.get_progress_conflict()
		print(
			(
				"[Account (LoginPage)] 路由: %s"
				% ("进度选择弹窗(组2 有冲突)" if conflict != null else "本页让位,等 home 弹成功窗")
			)
		)
		if conflict != null:
			UIManager.show_ui(UiName.PROGRESS_SELECT, {"conflict": conflict})
		return
	if kind == AccountManager.KIND_NETWORK:
		print("[Account (LoginPage)] 路由: 无连接弹窗")
		UIManager.show_ui(UiName.NO_CONNECTION, {"retry": "login", "channel": channel})
		return
	print("[Account (LoginPage)] 路由: 登录失败弹窗")
	UIManager.show_ui(UiName.ACCOUNT_RESULT, {"type": "login_fail", "channel": channel})


func _on_logout_finished(ok: bool, kind: String, code: int) -> void:
	if ok:
		return
	print("[Account (LoginPage)] 登出失败 kind=%s code=%d" % [kind, code])
	if kind == AccountManager.KIND_NETWORK:
		UIManager.show_ui(UiName.NO_CONNECTION, {"retry": "logout"})
		return
	Toast.popup("LOGOUT_TOAST_FAILED", self)


func _on_delete_link_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.DELETE_ACCOUNT, self)
	UIManager.show_ui(UiName.DELETE_ACCOUNT_CONFIRM)
