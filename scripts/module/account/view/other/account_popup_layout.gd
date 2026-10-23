## 账号弹窗共用的排版计算；按文本实际高度安排消息、按钮和背景，适应多语言长度。

class_name AccountPopupLayout
extends RefCounted

const DIALOG_W: float = 900.0

const TITLE_H: float = 130.0

const TITLE_GAP: float = 70.0

const PAD_BOTTOM: float = 30.0

const INFO_GAP: float = 60.0

const BTN_H: float = 160.0

const BOTTOM: float = 90.0

const BTN_PAD_TOP: float = 68.0

const BTN_INST_H: float = 258.0


static func msg_height(msg: Label, fallback_h: float) -> float:
	if msg == null:
		push_error(
			(
				"AccountPopupLayout.msg_height: msg 为 null（常见原因：.tscn 漏 unique_name_in_owner），退回设计基线 %.0f"
				% fallback_h
			)
		)
		return fallback_h
	msg.update_minimum_size()
	var h: float = msg.get_minimum_size().y
	return h if h > 0.0 else fallback_h


## 按照消息测量高度重新排布背景和按钮；文本变长时增高弹窗，而非依赖固定行数。
static func apply(
	dialog_root: Control, info_box: Control, msg: Label, action_btn: Control, msg_fallback_h: float
) -> void:
	var msg_top: float = msg.offset_top
	var msg_h: float = msg_height(msg, msg_fallback_h)
	info_box.offset_top = TITLE_H + TITLE_GAP
	info_box.offset_bottom = info_box.offset_top + msg_top + msg_h + PAD_BOTTOM

	msg.offset_bottom = msg_top + msg_h
	var btn_top: float = info_box.offset_bottom + INFO_GAP

	action_btn.offset_top = btn_top - BTN_PAD_TOP
	action_btn.offset_bottom = action_btn.offset_top + BTN_INST_H
	var total: float = btn_top + BTN_H + BOTTOM
	dialog_root.offset_top = -total * 0.5
	dialog_root.offset_bottom = total * 0.5
	dialog_root.offset_left = -DIALOG_W * 0.5
	dialog_root.offset_right = DIALOG_W * 0.5
