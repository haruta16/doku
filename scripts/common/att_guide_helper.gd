## 启动权限引导：按实验配置串起自定义说明页和 iOS ATT 弹窗。
class_name AttGuideHelper
extends Object

# ---- 常量 ----
## 上报弹窗来源用的场景标识（启动闪屏）
const _SOURCE: String = "splash_scr"


## 根据实验与存档决定是否显示说明页，等待系统弹窗关闭并记录已展示状态。
static func try_show_and_wait_dialog_close() -> void:
	var is_test: bool = UniKitManager.debug_force_editor_test
	var att_status: int = UniKitManager.get_att_status()
	var can_request_att: bool = att_status == UniKitManager.ATT_STATUS_NOT_DETERMINED

	if ABTestManager.att_dlg_logic.should_skip_custom_guide():
		if can_request_att:
			await _show_att_alert_and_wait()
		_reset_debug_flag_if_test(is_test)
		return

	if not GameState.has_shown_att_guide():
		var guide_page: String = (
			"pre_att_guide_v2"
			if ABTestManager.att_dlg_logic.is_custom_guide_restyled()
			else "pre_att_guide"
		)
		var page: Node = UIManager.show_ui(guide_page)
		if page == null:
			if not is_test:
				GameState.mark_att_guide_shown()
			if can_request_att:
				await _show_att_alert_and_wait()
			_reset_debug_flag_if_test(is_test)
			return

		GameState.mark_startup_permission_prompt_shown()
		await page.continued
		UIManager.hide_ui(guide_page)

		if not is_test:
			GameState.mark_att_guide_shown()

	if can_request_att:
		await _show_att_alert_and_wait()
	_reset_debug_flag_if_test(is_test)


## 标记本次启动已弹权限提示，发起 ATT 请求并等待关闭信号。
static func _show_att_alert_and_wait() -> void:
	GameState.mark_startup_permission_prompt_shown()
	UniKitManager.show_att_alert(_SOURCE)
	await UniKitManager.att_dismissed


# ================= 内部工具 =================
## 测试收尾：关掉编辑器强制测试开关，避免下次启动又被强制走一遍引导
static func _reset_debug_flag_if_test(is_test: bool) -> void:
	# 只在测试态动这个开关
	if is_test:
		UniKitManager.debug_force_editor_test = false
