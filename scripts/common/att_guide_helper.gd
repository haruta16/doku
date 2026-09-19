# ATT（iOS 广告跟踪授权）引导流程：先播自定义引导页，再调系统 ATT 弹窗，并等它关闭
class_name AttGuideHelper
extends Object

# ---- 常量 ----
# 上报弹窗来源用的场景标识（启动闪屏）
const _SOURCE: String = "splash_scr"


# ================= 对外入口 =================
# ATT 引导主流程：按 AB 分组决定要不要先播自定义引导页，最后调系统弹窗并等玩家关闭；协程，调用方必须 await
static func try_show_and_wait_dialog_close() -> void:
	# 编辑器强制测试开关：为 true 时本次不写存档，流程结束时自动复位
	var is_test: bool = UniKitManager.debug_force_editor_test
	# 当前系统 ATT 授权状态（由 UniKit 原生侧返回）
	var att_status: int = UniKitManager.get_att_status()
	# 只有「尚未询问」才允许调起系统弹窗；已授权或已拒绝都不能再弹
	var can_request_att: bool = att_status == UniKitManager.ATT_STATUS_NOT_DETERMINED

	# AB 分组一：跳过自定义引导页，直接弹系统 ATT
	if ABTestManager.att_dlg_logic.should_skip_custom_guide():
		# 能弹就弹，并阻塞到玩家做出选择（await 原生弹窗关闭信号）
		if can_request_att:
			UniKitManager.show_att_alert(_SOURCE)
			await UniKitManager.att_dismissed
		# 统一收尾：测试态把开关复位
		_reset_debug_flag_if_test(is_test)
		return

	# 自定义引导页只播一次，是否播过记在存档里
	if not GameState.has_shown_att_guide():
		# 按 AB 分组挑引导页样式：v2 是新版视觉
		var guide_page: String = (
			"pre_att_guide_v2"
			if ABTestManager.att_dlg_logic.is_custom_guide_restyled()
			else "pre_att_guide"
		)
		# 拉起引导页；返回 null 表示这页没起来（存档/配置缺失等）
		var page: Node = UIManager.show_ui(guide_page)
		# 兜底分支：引导页起不来也当它已展示，不能卡住启动流程
		if page == null:
			# 测试态不写存档，方便反复验证
			if not is_test:
				GameState.mark_att_guide_shown()
			# 仍然尝试调起系统弹窗
			if can_request_att:
				UniKitManager.show_att_alert(_SOURCE)
				await UniKitManager.att_dismissed
			_reset_debug_flag_if_test(is_test)
			return
		# 等玩家点掉引导页（continued 由引导页自己发出）
		await page.continued
		# 关掉引导页再往下走
		UIManager.hide_ui(guide_page)

		# 正常流程把「已展示引导」写进存档；测试态跳过
		if not is_test:
			GameState.mark_att_guide_shown()

	# 最后一步：弹系统 ATT 弹窗并等它关闭
	if can_request_att:
		UniKitManager.show_att_alert(_SOURCE)
		await UniKitManager.att_dismissed
	_reset_debug_flag_if_test(is_test)


# ================= 内部工具 =================
# 测试收尾：关掉编辑器强制测试开关，避免下次启动又被强制走一遍引导
static func _reset_debug_flag_if_test(is_test: bool) -> void:
	# 只在测试态动这个开关
	if is_test:
		UniKitManager.debug_force_editor_test = false
