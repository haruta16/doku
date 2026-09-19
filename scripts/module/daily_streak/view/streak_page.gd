# 连续打卡页：三种展示态（常规 / 首次点亮 / 打卡结算），7 天格子 + 第 7 天开宝箱
class_name StreakPage
extends UIFrameWindow

enum DisplayState { MAIN, LIT, SETTLE } # 展示状态：MAIN 常规 / LIT 首次点亮 / SETTLE 打卡结算

# 星期文案 key，下标 0 = 周日 … 6 = 周六（与 Time.weekday 对齐）
const _WEEKDAY_LABELS: Array[String] = [
	"WEEKDAY_SUN",
	"WEEKDAY_MON",
	"WEEKDAY_TUE",
	"WEEKDAY_WED",
	"WEEKDAY_THU",
	"WEEKDAY_FRI",
	"WEEKDAY_SAT"
]
const _PARAM_STATE: String = "state" # on_show 的参数名：指定要展示的状态
const _SETTLE_SLOT_DELAY: float = 20.0 / 60.0 # 直接以结算态打开时，等多久开始播格子动画（秒）
const _LIT_SLOT_DELAY: float = 62.0 / 60.0 # 从点亮态切结算态时，等多久开始播格子动画（秒，要等 LightUp 播完）


# ================= 打开入口 =================
# 以常规态打开（主页入口点击）
static func open_main() -> StreakPage:
	return UIManager.show_ui(UiName.STREAK, {_PARAM_STATE: DisplayState.MAIN}) as StreakPage


# 以首次点亮态打开（连续第 1 天打卡后）
static func open_lit() -> StreakPage:
	return UIManager.show_ui(UiName.STREAK, {_PARAM_STATE: DisplayState.LIT}) as StreakPage


# 以结算态打开（打卡成功的结算）
static func open_settle() -> StreakPage:
	return UIManager.show_ui(UiName.STREAK, {_PARAM_STATE: DisplayState.SETTLE}) as StreakPage


# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _slots: Array[Control] = [
	$StreakContent/StreakPanel/SlotWed,
	$StreakContent/StreakPanel/SlotThu,
	$StreakContent/StreakPanel/SlotFri,
	$StreakContent/StreakPanel/SlotSat,
	$StreakContent/StreakPanel/SlotSun,
	$StreakContent/StreakPanel/SlotMon,
	$StreakContent/StreakPanel/SlotTue,
]
@onready var _streak_num: Label = $"StreakContent/StreakPanel/2Txt" # 当前连续天数
@onready var _best_streak_group: Control = $StreakContent/StreakPanel/Group5 # 最佳记录整块（常规态与结算态显示）
@onready var _best_label: Label = $StreakContent/StreakPanel/Group5/BestStreak99Txt # 最佳记录文字
@onready var _claim_btn: Button = $StreakContent/ClaimBtn # 结算态的「继续」按钮
@onready var _back_btn: Button = $StreakContent/Top/BackBtnGroup # 常规态的返回按钮
@onready var _anim: AnimationPlayer = $AnimationPlayer # 页面动画播放器
@onready var _sun_btn: Button = $StreakContent/StreakPanel/IconSlot/SunImg/SunBtn # 点亮态的太阳按钮（点它进结算）

# ---- 运行时状态 ----
var _state: DisplayState = DisplayState.MAIN # 当前展示状态
var _lit_consumed: bool = false # 点亮态是否已被点击消费（防重复触发）
var _lit_enter_done: bool = false # 入场动画是否播完（播完之前的点击不算）


# ================= 生命周期 =================
# 给继续/返回按钮接上按下抬起缩放
func on_create() -> void:
	bind_press_release_scale(_claim_btn)
	bind_press_release_scale(_back_btn)


# 进页面：按参数切状态、播对应入场动画；结算态另外跑一遍结算流程
func on_show(params: Dictionary = {}) -> void:
	var requested: int = params.get(_PARAM_STATE, DisplayState.MAIN) # 默认常规态
	_lit_consumed = false
	_lit_enter_done = false
	_apply_state(requested)
	_play_enter_anim(requested)
	# 结算态：入场动画之外还要跑格子动画与开奖
	if requested == DisplayState.SETTLE:
		_run_settle_flow()


# 返回键：只有常规态才自己处理，其余状态交回给系统
func on_escape() -> bool:
	if _state != DisplayState.MAIN:
		return false
	_on_back_pressed()
	return true


# 埋点页面名：常规态算打卡页，结算态算游戏内打卡
func get_scr_name() -> String:
	match _state:
		DisplayState.MAIN:
			return Tracker.Scr.STREAK
		DisplayState.SETTLE:
			return Tracker.Scr.GAME_STREAK
		_:
			return ""


# ================= 展示状态切换 =================
# 播入场动画：点亮态 Appear、结算态 Appear3、常规态看今天还能不能打卡选 Appear2/3
func _play_enter_anim(s: int) -> void:
	var anim_name: StringName
	match s:
		DisplayState.LIT:
			anim_name = &"Appear"
		DisplayState.SETTLE:
			anim_name = &"Appear3"
		_:
			anim_name = &"Appear2" if StreakManager.can_checkin_today() else &"Appear3"
	if _anim.has_animation(anim_name):
		# 先归零再播，保证每次从第 0 帧开始
		if _anim.has_animation(&"RESET"):
			_anim.play(&"RESET")
			_anim.advance(0.0)
		_anim.play(anim_name)

		# 点亮态：等入场动画播完才允许点击
		if s == DisplayState.LIT:
			connect_managed_once(_anim.animation_finished, _on_lit_enter_anim_finished)


# 入场动画播完，点亮态开始接受点击
func _on_lit_enter_anim_finished(_finished_anim: StringName) -> void:
	_lit_enter_done = true


# 切状态并整页刷新
func _apply_state(s: int) -> void:
	_state = s
	_refresh()


# ================= 数据刷新 =================
# 刷新可见性与数据
func _refresh() -> void:
	_refresh_visibility()
	_refresh_data()


# 按状态决定返回键 / 最佳记录 / 继续按钮 / 太阳按钮的显隐
func _refresh_visibility() -> void:
	var is_main: bool = _state == DisplayState.MAIN
	var is_settle: bool = _state == DisplayState.SETTLE

	_back_btn.visible = is_main

	_best_streak_group.visible = is_main or is_settle
	_claim_btn.visible = is_settle

	_sun_btn.visible = _state == DisplayState.LIT


# 填连续天数、最佳记录，并刷 7 个格子
func _refresh_data() -> void:
	var data: StreakData = StreakManager.get_data()
	_streak_num.text = str(data.current_streak)
	_best_label.text = tr("DAILY_STREAK_BEST_FORMAT") % data.best_streak
	_refresh_slots()


# 按打卡数据刷 7 个格子的星期与点亮状态；结算态把「今天这格」留给动画
func _refresh_slots() -> void:
	var show_chest: bool = StreakManager.has_reward()
	var slots: Array[Dictionary] = StreakManager.get_week_slots()

	var anim_idx: int = _new_checkin_index() if _state == DisplayState.SETTLE else -1
	for i: int in range(_slots.size()):
		var s: Dictionary = slots[i]
		var slot: Control = _slots[i]
		# 最后一格是宝箱格（实验档允许奖励时）
		var slot_is_chest: bool = (i == _slots.size() - 1) and show_chest
		slot.weekday = _WEEKDAY_LABELS[int(s.weekday)]
		# 今天刚打卡的那格先画成未点亮，等结算动画来点亮
		if i == anim_idx:
			slot.apply_static(false, slot_is_chest)
		else:
			slot.apply_static(bool(s.checked), slot_is_chest)


# 找出这一轮里最后一个已点亮的格子下标（没有则 -1），就是今天刚打的那格
func _new_checkin_index() -> int:
	var slots: Array[Dictionary] = StreakManager.get_week_slots()
	var idx: int = -1
	for i: int in range(slots.size()):
		if bool(slots[i].checked):
			idx = i
	return idx


# ================= 结算流程 =================
# 结算：先锁住继续按钮，等一小段后播打卡动画；有宝箱就开奖并等奖励页关掉
func _run_settle_flow(slot_delay: float = _SETTLE_SLOT_DELAY) -> void:
	var idx: int = _new_checkin_index()
	if idx < 0:
		return
	var slot: Control = _slots[idx]
	# uid > 0 才代表真有奖励要展示（0 只表示「打过卡」）
	var has_award: bool = StreakManager.get_pending_show_uid() > 0
	_set_continue_enabled(not has_award)

	# 等入场/点亮动画播完再动格子；中途页面被关掉就直接退出
	await get_tree().create_timer(slot_delay).timeout
	if not is_showing():
		return

	# 没有奖励：只播打卡动画，然后清掉待展示标记
	if not has_award:
		slot.play_checkin(false)
		StreakManager.consume_pending_show()
		return

	# 有奖励：先播开奖动画并等它放完，再让 AwardManager 把奖励弹出来
	var dur: float = slot.play_checkin(true)
	await get_tree().create_timer(dur).timeout
	if not is_showing():
		return
	StreakManager.claim_reward(false)
	StreakManager.consume_pending_show()
	# 开完奖收起宝箱、退回未打卡点；等奖励页关掉再补播普通打卡动画并放开继续按钮
	slot.hide_chest()
	slot.show_unchecked_dot()
	await _await_reward_closed()
	if not is_showing():
		return
	slot.play_checkin(false)
	_set_continue_enabled(true)


# 等奖励页（UiName.AWARD）关掉再继续
func _await_reward_closed() -> void:
	var reward := UIManager.get_ui(UiName.AWARD)
	while is_instance_valid(reward) and reward.visible:
		await reward.visibility_changed


# 结算过程中锁住继续按钮，防止提前退出
func _set_continue_enabled(enabled: bool) -> void:
	if _claim_btn:
		_claim_btn.disabled = not enabled


# ================= 输入与按钮 =================
# 点亮态下点屏幕任意位置都进结算，并吞掉这次点击
func _input(event: InputEvent) -> void:
	if not is_showing() or _state != DisplayState.LIT or _lit_consumed or not _lit_enter_done:
		return
	var is_press: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if not is_press:
		return
	_lit_consumed = true
	get_viewport().set_input_as_handled()
	_light_up_to_settle()


# 太阳按钮：与点屏幕等价（同样防重复、要求入场动画已播完）
func _on_sun_pressed() -> void:
	if _state != DisplayState.LIT or _lit_consumed or not _lit_enter_done:
		return
	_lit_consumed = true
	_light_up_to_settle()


# 点亮 → 结算：播 LightUp、切状态、跑结算流程，并补一次页面埋点
func _light_up_to_settle() -> void:
	if _anim.has_animation(&"LightUp"):
		_anim.play(&"LightUp")
	_apply_state(DisplayState.SETTLE)
	_run_settle_flow(_LIT_SLOT_DELAY)

	Tracker.track_scr_show(Tracker.Scr.GAME_STREAK)


# 返回：埋点后关掉打卡页
func _on_back_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	UIManager.hide_ui(UiName.STREAK)


# 继续：埋点 + 震动后关掉打卡页
func _on_continue_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CONTINUE, self)
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
	UIManager.hide_ui(UiName.STREAK)
