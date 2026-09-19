# 每日挑战「自动标叉」道具弹窗：免费额度或看激励视频二选一，开通后今天自动标叉
class_name DailyAutoMarkPopup
extends UIFrameWindow

const _AD_POS: String = Tracker.AdPos.AUTOX_REWARD # 广告位：自动标叉的激励视频

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _primary_btn: Button = $Root/Content/Label/VBoxContainer/DualBtnArea/PrimaryBtn # 主按钮：免费领取 / 看广告
@onready var _secondary_btn: Button = $Root/Content/Label/VBoxContainer/DualBtnArea/SecondaryBtn # 次按钮：不用了
# 主按钮上的角标（免费 / AD 文案）
@onready
var _primary_badge: GameAdBadge = $Root/Content/Label/VBoxContainer/DualBtnArea/PrimaryBtn/Badge
# 主按钮上的广告图标，与角标二选一显示
@onready
var _ad_icon_box: Control = $Root/Content/Label/VBoxContainer/DualBtnArea/PrimaryBtn/BtnGroup/AdIconBox
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer # 弹窗出现/关闭动画
@onready var _label: Control = $Root/Content/Label # 文案块，猫要按它的位置来定位
@onready var _cat_popup: Control = $Root/Content/CatPopup # 探头看成绩的猫
# 历史最佳成绩行（有记录才显示）
@onready
var _best_record_top_txt: RichTextLabel = $Root/Content/Label/VBoxContainer/LabelArea/BestRecordTopTxt
@onready var _almost_there: Control = $Root/Content/Label/VBoxContainer/LabelArea/AlmostThere # 「就差一点」提示块

# ---- 布局常量（像素）：提示块按有无历史最佳摆两套位置 ----
const _ALMOST_THERE_TOP_WITH_BEST: float = 211.0 # 有历史最佳时：提示块上边距
const _ALMOST_THERE_BOTTOM_WITH_BEST: float = 361.0 # 有历史最佳时：提示块下边距
const _ALMOST_THERE_TOP_NO_BEST: float = 130.0 # 无历史最佳时：提示块上边距
const _ALMOST_THERE_BOTTOM_NO_BEST: float = 280.0 # 无历史最佳时：提示块下边距

const _CAT_OVERHANG_ABOVE_LABEL: float = 339.0 # 猫头高出文案顶部的像素
const _CAT_OVERLAP_INTO_LABEL: float = 68.0 # 猫身压进文案区的像素

# ---- 运行时状态 ----
var _closing: bool = false # 是否正在播关闭动画（防重入）

var _ad_requested: bool = false # 本次显示是否已发起广告请求（防连点）

var _is_free_mode: bool = false # true = 走免费额度，false = 要看广告


# ================= 生命周期 =================
# 接按钮按下/抬起缩放，并让猫跟随文案块位置
func _ready() -> void:
	bind_press_release_scale(_primary_btn)
	bind_press_release_scale(_secondary_btn)

	_label.resized.connect(_sync_cat_to_label)


# 每次弹出重置状态：判定免费/广告模式、刷按钮与成绩显示、播出现动画
func on_show(_params: Dictionary = {}) -> void:
	_closing = false
	_ad_requested = false
	_is_free_mode = not GameState.is_daily_auto_mark_free_consumed()
	_apply_mode_visibility()
	_apply_best_record_visibility()
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")
	_anim.advance(0.0)


# 关闭时播退场动画；_closing 已置位说明正在关，直接返回避免重入
func on_hide() -> void:
	if _closing:
		return
	_closing = true
	_disconnect_self_reward_callbacks()
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished


# 弹窗埋点名
func get_dlg_name() -> String:
	return Tracker.Dlg.DAILY_AUTO_MARK_POPUP


# ================= 显示模式 =================
# 按免费/广告模式决定角标、广告图标、次按钮的显示组合
func _apply_mode_visibility() -> void:
	if _is_free_mode:
		_ad_icon_box.visible = false
		_primary_badge.visible = true
		_primary_badge.show_free()
		_primary_badge.scale = Vector2.ONE * 1.4
		_secondary_btn.visible = false
	else:
		var ad_tag: bool = ABTestManager.ad_compliance_ui.should_show_ad_tag()
		if ad_tag:
			_ad_icon_box.visible = false
			_primary_badge.visible = true
			_primary_badge.show_icon_with_ad()
			_primary_badge.scale = Vector2.ONE
		else:
			_ad_icon_box.visible = true
			_primary_badge.visible = false
		_secondary_btn.visible = true


# 有历史最佳就显示成绩行并把提示块下移，没有则隐藏并上移
func _apply_best_record_visibility() -> void:
	var best: float = GameState.get_daily_best_beat_percent()
	if best <= 0.0:
		_best_record_top_txt.visible = false
		_almost_there.offset_top = _ALMOST_THERE_TOP_NO_BEST
		_almost_there.offset_bottom = _ALMOST_THERE_BOTTOM_NO_BEST
		return
	_best_record_top_txt.visible = true
	_almost_there.offset_top = _ALMOST_THERE_TOP_WITH_BEST
	_almost_there.offset_bottom = _ALMOST_THERE_BOTTOM_WITH_BEST
	var top_pct: float = 100.0 - best
	var pct_text: String = I18nFormat.percent(top_pct, 1)
	_best_record_top_txt.text = ""
	_best_record_top_txt.append_text(tr("DAILY_AUTO_MARK_BEST_RECORD") % pct_text)


# ================= 按钮回调 =================
# 主按钮：免费模式直接激活；否则校验广告就绪后拉激励视频
func _on_primary_btn_pressed() -> void:
	if _closing:
		return
	if _is_free_mode:
		_consume_free_and_activate()
		return
	if _ad_requested:
		return

	var show_id := UniKitManager.gen_show_id()
	if not UniKitManager.is_reward_ready("reward", _AD_POS, show_id):
		Toast.popup("AD_TOAST_NOT_READY", self)
		return
	_ad_requested = true

	var on_rewarded := func(placement_id: String) -> void:
		if placement_id != "reward":
			return
		GameState.mark_daily_auto_mark_enabled_today()

		Tracker.track_prop_get(Tracker.Prop.AUTOX, Tracker.PropSource.AUTOX_REWARD_AD, 1, 0)
		Tracker.track_prop_use(Tracker.Prop.AUTOX, Tracker.Scr.DAILY_GAME, 1, 0)
		if not _closing:
			UIManager.hide_ui(get_ui_name())
	var on_closed := func(placement_id: String) -> void:
		if placement_id != "reward":
			return

		if not _closing:
			UIManager.hide_ui(get_ui_name())
	_disconnect_self_reward_callbacks()
	UniKitManager.ad_rewarded.connect(on_rewarded, CONNECT_ONE_SHOT)
	UniKitManager.ad_closed.connect(on_closed, CONNECT_ONE_SHOT)
	UniKitManager.show_reward("reward", _AD_POS, show_id)


# 次按钮：不领了，直接关
func _on_secondary_btn_pressed() -> void:
	UIManager.hide_ui(get_ui_name())


# 消耗免费额度并开启今天的自动标叉（写存档），然后关弹窗
func _consume_free_and_activate() -> void:
	GameState.mark_daily_auto_mark_free_consumed()
	GameState.mark_daily_auto_mark_enabled_today()
	UIManager.hide_ui(get_ui_name())


# 把猫按文案块的实际位置重新摆好（文案尺寸变化时也会回调到这里）
func _sync_cat_to_label() -> void:
	if not is_instance_valid(_label) or not is_instance_valid(_cat_popup):
		return
	var label_top_y: float = _label.position.y
	var anchor_ref_y: float = _cat_popup.get_parent().size.y * _cat_popup.anchor_top
	_cat_popup.offset_top = label_top_y - _CAT_OVERHANG_ABOVE_LABEL - anchor_ref_y
	_cat_popup.offset_bottom = label_top_y + _CAT_OVERLAP_INTO_LABEL - anchor_ref_y


# 断开本节点挂在广告信号上的回调，避免重复触发
func _disconnect_self_reward_callbacks() -> void:
	for c: Dictionary in UniKitManager.ad_rewarded.get_connections():
		var cb: Callable = c.get("callable", Callable())
		if cb.is_valid() and cb.get_object() == self:
			UniKitManager.ad_rewarded.disconnect(cb)
	for c: Dictionary in UniKitManager.ad_closed.get_connections():
		var cb: Callable = c.get("callable", Callable())
		if cb.is_valid() and cb.get_object() == self:
			UniKitManager.ad_closed.disconnect(cb)
