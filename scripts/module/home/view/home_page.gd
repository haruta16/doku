# 首页（HomePage）：开始游戏 / 每日挑战两个入口，负责转场动画与启动后的弹窗排队
# 入口状态与红点：每日挑战由 DailyEntryState 判定解锁（关卡数 < 21 锁定）；设置按钮上的红点由 Helpshift 未读数驱动（RedDotCenter 的「helpshift_unread」）
class_name HomePage
extends UIFrameWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _start_btn: Control = $Root/StartBtn  # 开始按钮（BtnWithTag 场景，用 Control 类型以便设置 show_difficult）
@onready var _daily_btn: Button = $Root/DailyBtn  # 每日挑战按钮外层，只用于绑按压缩放
@onready var _daily_bg: Button = $Root/DailyBtn/Bg  # 每日按钮可换肤的背景
@onready var _daily_shadow: NinePatchRect = $Root/DailyBtn/Shadow  # 按钮投影，锁定态隐藏
@onready var _daily_lock_icon: HBoxContainer = $Root/DailyBtn/LockIcon  # 锁定态：锁图标 + 文案
@onready var _daily_lock_label: Label = $Root/DailyBtn/LockIcon/LockLabel  # 锁定态文案
@onready var _daily_unlock_box: HBoxContainer = $Root/DailyBtn/UnlockBox  # 可玩 / 已完成态：猫爪 + 文案
@onready var _daily_unlock_label: Label = $Root/DailyBtn/UnlockBox/UnlockLabel  # 可玩 / 已完成态文案
@onready var _daily_done_tag: Panel = $Root/DailyBtn/DoneTag  # 已完成角标（用时）
@onready var _daily_done_time: Label = $Root/DailyBtn/DoneTag/DoneHBox/DoneTimeLabel  # 已完成用时文案
@onready var _daily_top_tag: Control = $Root/DailyBtn/TopTag  # 已完成右上角名次标签
@onready var _daily_top_label: Label = $Root/DailyBtn/TopTag/TopLabel  # 名次文案
@onready var _countdown_tag: Panel = $Root/DailyBtn/CountdownTag  # 倒计时角标（可玩态显示）
@onready var _daily_paw: TextureRect = $Root/DailyBtn/UnlockBox/Paw  # 猫爪图标（按 A/B 换亮 / 暗贴图）

# ---- 可调参数（Inspector 可改） ----
@export var _daily_paw_tex_lit: Texture2D  # 猫爪亮色贴图（已完成态）
@export var _daily_paw_tex_dim: Texture2D  # 猫爪暗色贴图（未完成态）

# ---- 每日按钮的原始样式缓存（首次显示时记下，换肤后靠它还原） ----
var _daily_sf_normal: StyleBox  # Bg 的 normal 原始样式
var _daily_sf_pressed: StyleBox  # Bg 的 pressed 原始样式
# ---- 倒计时与动画 ----
@onready var _countdown_label: Label = $Root/DailyBtn/CountdownTag/HBox/CountdownLabel  # 倒计时文案 HH:MM:SS
@onready var _countdown_timer: Timer = $Root/DailyBtn/CountdownTimer  # 每秒超时（Timer 未改 wait_time，默认 1 秒）
@onready var _anim: AnimationPlayer = $AnimationPlayer  # 首页主界面动画 MainInterface

# ---- 入口格子场景（daily_streak A/B 的新版首页布局用） ----
# 每日挑战入口格子，在新版布局里替代原来的 DailyBtn
const _DC_ENTRY_CELL: PackedScene = preload(
	"res://scripts/module/daily/ui/daily_challenge_entry_cell.tscn"
)
# 连续打卡入口格子
const _STREAK_ENTRY_CELL: PackedScene = preload(
	"res://scripts/module/daily_streak/ui/streak_entry_cell.tscn"
)

# ---- 新版布局的槽位（Root/DailyStreakLayout，A/B 关闭时整体隐藏） ----
@onready var _streak_layout: Control = $Root/DailyStreakLayout  # 新版布局整体容器
@onready var _dc_slot: Control = $Root/DailyStreakLayout/DcEntrySlot  # 每日挑战格子槽位
@onready var _streak_slot: Control = $Root/DailyStreakLayout/StreakEntrySlot  # 连续打卡格子槽位
@onready var _start_btn_slot: Control = $Root/DailyStreakLayout/StartBtnSlot  # 开始按钮槽位
@onready var _logo_slot: Control = $Root/DailyStreakLayout/LogoSlot  # Logo 槽位

# ---- Logo 与坐标备份 ----
@onready var _loge: Control = $Root/Loge  # 猫头 Logo 容器
var _dc_cell = null  # 动态创建的每日挑战格子（懒加载）
var _streak_cell = null  # 动态创建的连续打卡格子（懒加载）

# ---- 原始坐标备份（_ready 时记录，切回旧布局时还原） ----
var _start_btn_orig_off_l: float = 0.0  # 开始按钮原始 offset_left
var _start_btn_orig_off_r: float = 0.0  # 开始按钮原始 offset_right
var _loge_orig_pos: Vector2 = Vector2.ZERO  # Logo 原始位置

# ---- 开始按钮的两种纵向位置（像素，相对父节点） ----
const _START_BTN_SOLO_OFFSET_TOP: float = 366.0  # 只剩开始按钮时的上边距
const _START_BTN_SOLO_OFFSET_BOTTOM: float = 526.0  # 只剩开始按钮时的下边距

const _START_BTN_DUO_OFFSET_TOP: float = 222.0  # 两个入口并存时的上边距
const _START_BTN_DUO_OFFSET_BOTTOM: float = 382.0  # 两个入口并存时的下边距

# ---- 弹窗排队的延迟（秒） ----
const HOME_RATE_US_DELAY: float = 0.5  # 弹评分弹窗前的延迟（秒）

const HOME_RESTORE_DELAY: float = 0.4  # 漏奖补发判定前的延迟（秒）

# ---- 诊断状态 ----
static var last_restore_status: String = "尚未触发补发判定"  # 上次漏奖补发判定的结果，static 供 cheat 面板读取

# ---- 运行时状态 ----
var _is_exiting: bool = false  # 是否正在转场离开首页
var _auto_mark_switch_checked: bool = false  # 自动标记变更提示本次启动只判定一次

var _tap_diag_last_ms: int = 0  # 诊断用时间戳（除初始化外没有引用）
var _pending_page: String = ""  # 转场目标页名
var _pending_params: Dictionary = {}  # 转场目标页参数
var _new_page_node: Node = null  # 转场后打开的新页面节点


# ================= 生命周期 =================
# 初始化：备份原始坐标、绑按压缩放与按钮音效、按视口宽度摆放背景网格
func _ready() -> void:
	# 记住开始按钮原始左右偏移，切回旧布局时还原
	_start_btn_orig_off_l = _start_btn.offset_left
	_start_btn_orig_off_r = _start_btn.offset_right
	if _loge != null:
		_loge_orig_pos = _loge.position
	# 设置按钮与每日按钮按下时缩放反馈
	bind_press_release_scale($Root/VBoxContainer/Header/SettingsBtn)
	bind_press_release_scale($Root/DailyBtn)
	# 按视口宽度自适应每日按钮文案字号
	_fit_daily_btn_font()

	# 设置按钮的声音由自己播，避免与全局按钮音效叠加
	claim_button_sound($Root/VBoxContainer/Header/SettingsBtn)

	# 背景网格按视口宽度居中；宽屏（> 1080）时整体放大 1.02 倍
	var grid: Sprite2D = $Background/GridFlowLoop
	var vp_w: float = get_viewport_rect().size.x
	grid.position.x = vp_w / 2.0
	if vp_w > 1080.0:
		var s: float = (vp_w / 1080.0) * 1.02
		grid.scale = Vector2(s, s)


# 把设置按钮的屏幕中心 Y 广播给 HomeSettingAnchor，供其它页面（FollowHomeSettingBtnY）对齐
func _write_setting_anchor() -> void:
	var gb: Control = $Root/VBoxContainer/Header/SettingsBtn
	HomeSettingAnchor.set_settingbtn_y(gb.global_position.y + gb.size.y * 0.5)


# 语言切换通知：刷新随语言变化的文案与字号
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_dynamic_text()
		_fit_daily_btn_font()


# 刷新开始按钮文案：显示当前关卡号
func _refresh_dynamic_text() -> void:
	_start_btn.btn_text = tr("GAME_LEVEL_TITLE") % GameState.get_current_level()


# 每日按钮字号下限（像素）
const _DAILY_BTN_MIN_FONT_SIZE: int = 44


# 每日按钮文案自适应：锁定态与可玩态的可用宽度不同，各自从上限逐步缩小到放得下
func _fit_daily_btn_font() -> void:
	# 两种形态显示的是同一个文案 key
	var display_text: String = tr("HOME_DAILY_CHALLENGE")
	# 按钮实际宽度 = 左右 offset 之差
	var btn_w: float = _daily_btn.offset_right - _daily_btn.offset_left
	# 锁定态可用宽度：扣掉锁图标 56 与右侧留白 40
	var lock_avail: float = btn_w - 56.0 - 40.0
	var lock_font: Font = _daily_lock_label.get_theme_font("font")
	var lock_fs: int = 80
	# 从 80 号字起每轮 -2，直到放得下或触到下限
	while lock_fs > _DAILY_BTN_MIN_FONT_SIZE:
		if (
			lock_font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, lock_fs).x
			<= lock_avail
		):
			break
		lock_fs -= 2
	_daily_lock_label.add_theme_font_size_override("font_size", lock_fs)

	# 可玩态可用宽度：扣掉猫爪 100、间距 20、右侧留白 60
	var unlock_avail: float = btn_w - 100.0 - 20.0 - 60.0
	var unlock_font: Font = _daily_unlock_label.get_theme_font("font")
	# 从 66 号字起同样逐步缩小
	var unlock_fs: int = 66
	while unlock_fs > _DAILY_BTN_MIN_FONT_SIZE:
		if (
			unlock_font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, unlock_fs).x
			<= unlock_avail
		):
			break
		unlock_fs -= 2
	_daily_unlock_label.add_theme_font_size_override("font_size", unlock_fs)


# 每次被 UIManager 显示时调用：刷状态、摆布局，然后按顺序弹各种弹窗
func on_show(_params: Dictionary = {}) -> void:
	# 诊断日志：确认首页被重新显示
	print("[StreakSwitch] home.on_show 被调用")

	# 首页不展示 banner，进入即销毁
	UniKitManager.destroy_ad("banner")

	# 恢复 BGM（可能被游戏内暂停过）
	SoundManager.start_bgm()

	# 查 Helpshift 未读消息数，顺带刷新设置入口的红点
	HelpshiftManager.request_unread()
	# 复位转场标记，允许再次点入口
	_is_exiting = false
	_new_page_node = null
	# 设置按钮先透明，由 MainInterface 动画淡入
	$Root/VBoxContainer/Header/SettingsBtn.modulate.a = 0.0

	# 延后一帧上报锚点，等布局稳定后取到的 Y 才准
	_write_setting_anchor.call_deferred()
	# 开始 / 每日按钮也交给动画淡入
	$Root/StartBtn.modulate.a = 0.0
	$Root/DailyBtn.modulate.a = 0.0
	# 停掉上一次的动画再从头播，避免叠加
	_anim.stop()
	# 从开头播到 disappear 标记：入场段
	_anim.play_section_with_markers(&"MainInterface", &"", &"disappear")
	# 首次进入时缓存每日按钮的原始样式，换肤后靠它还原
	if _daily_sf_normal == null:
		_daily_sf_normal = _daily_bg.get_theme_stylebox("normal")
		_daily_sf_pressed = _daily_sf_normal
	# 当前关卡号：开始按钮文案与难度标记都用它
	var lv: int = GameState.get_current_level()
	_refresh_dynamic_text()
	# 难度标记按 A/B 分组取不同判定：J 组看「关卡号 %10 == 9」，其它组看「%10 == 0」
	_start_btn.show_difficult = (
		LevelData.is_hard_level_group_j(lv)
		if ABTestManager.rule_normal_rank.is_group_j()
		else LevelData.is_hard_level(lv)
	)
	# 每日按钮的显隐由 no_dc 决定
	var hide_dc: bool = ABTestManager.no_dc.is_daily_challenge_hidden()
	_daily_btn.visible = not hide_dc
	# 隐藏时开始按钮挪到「单人」位置，否则用「双人」位置
	if hide_dc:
		_start_btn.offset_top = _START_BTN_SOLO_OFFSET_TOP
		_start_btn.offset_bottom = _START_BTN_SOLO_OFFSET_BOTTOM
	else:
		_start_btn.offset_top = _START_BTN_DUO_OFFSET_TOP
		_start_btn.offset_bottom = _START_BTN_DUO_OFFSET_BOTTOM
	# 每日入口可见时才刷它的状态并起倒计时
	if not hide_dc:
		# 推进「历史最大可玩日期」，跨天时把完成态刷回可玩
		DailyEntryState.ensure_max_daily_advanced()
		_refresh_daily_btn_state()
		_fit_daily_btn_font()
		_update_countdown()
		_countdown_timer.start()

	# 应用首页布局（daily_streak A/B 走新版布局，否则还原旧布局）
	_apply_home_layout()

	# 记录本次的 A/B 分组，供下次启动判断是否「切组」
	StreakManager.notify_group_dyed()

	# 弹窗排队：跨组提示优先；没弹过才轮到自动标记变更提示
	if not await _maybe_show_streak_switch_popup():
		await _maybe_show_auto_mark_switch_popup()

	# 评分弹窗与漏奖补发放最后，避免盖住前面的弹窗
	await _maybe_show_rate_us_on_home()
	await _maybe_show_pending_rewards()


# ================= 启动后弹窗排队 =================
# 返回本次该弹的跨组提示页号（0 表示不弹）；弹过就消费掉标记，只弹一次
func _maybe_show_streak_switch_popup() -> bool:
	# StreakManager 内部有 eligible 标记：应用没重启时不会重复给出页号
	var page: int = StreakManager.get_pending_switch_page()
	print("[StreakSwitch] home._maybe_show_streak_switch_popup: pending=%d" % page)
	# 0 表示没有待弹的切组提示
	if page <= 0:
		return false
	# 先消费再弹，避免弹窗过程中被重复触发
	StreakManager.consume_pending_switch()
	# 页号 → UI 名：1 / 2 / 3 对应三个不同文案的切组弹窗
	var ui_name: StringName
	match page:
		1:
			ui_name = UiName.STREAK_SWITCH1
		2:
			ui_name = UiName.STREAK_SWITCH2
		3:
			ui_name = UiName.STREAK_SWITCH3
		_:
			return false

	# 等 0.1 秒，让首页入场动画先跑起来
	await get_tree().create_timer(0.1).timeout
	# 期间玩家已经离开首页就放弃弹窗
	if not visible or _is_exiting:
		return false
	var dlg: UIFrameWindow = UIManager.show_ui(ui_name)
	if dlg == null:
		return false
	# 等用户关掉弹窗再返回 true，后面的弹窗排在它后面
	while dlg.visible:
		await dlg.visibility_changed
	return true


# 自动标记（auto mark）功能变更提示：每次启动最多判定一次
func _maybe_show_auto_mark_switch_popup() -> void:
	# 本次启动已经判定过
	if _auto_mark_switch_checked:
		return
	_auto_mark_switch_checked = true

	# 存档里记录的旧 A/B 值（-1 表示从没记录过）
	var stored: int = GameState.get_saved_game_auto_mark()
	# 从没记录过就不提示
	if stored == -1:
		return

	# 当前生效的 A/B 值（peek_value 读本地缓存，不触发网络拉取）
	var current: int = ABTestManager.find_config("game_auto_mark").peek_value()
	if stored == current:
		return

	# text_key 留空表示不属于要提示的变更组合
	var text_key: String = ""
	# 旧值有功能、新值关闭 → 「功能已下线」文案
	if stored in [1, 2, 4, 5] and current == 0:
		text_key = "GAME_AUTO_MARK_SWITCH_ENDED_DESC"
	elif stored in [1, 2, 3, 4] and current in [1, 2, 3, 4]:
		# 新旧都开着但档位变了 → 「功能升级」文案
		text_key = "GAME_AUTO_MARK_SWITCH_UPGRADED_DESC"

	# 两种之外的组合不提示
	if text_key.is_empty():
		return

	# 等首页动画与上一个弹窗结束
	await get_tree().create_timer(0.1).timeout
	if not visible or _is_exiting:
		return

	# 通用 A/B 变更提示弹窗（标题 / 正文 / 按钮文案都由 key 指定）
	var dlg: UIFrameWindow = (
		UIManager
		. show_ui(
			UiName.AB_SWITCH_POPUP,
			{
				"title": "DAILY_STREAK_MAJOR_UPDATE",
				"text": text_key,
				"btn_text": "DAILY_STREAK_GET_IT",
			}
		)
	)
	if dlg == null:
		return
	while dlg.visible:
		await dlg.visibility_changed

	# 弹完（无论玩家看没看）都记下当前值，避免下次再弹
	GameState.set_saved_game_auto_mark(current)


# 漏奖补发：把玩家当时没领到的广告奖励延后补发，有每日次数上限
func _maybe_show_pending_rewards() -> void:
	# 等首页入场动画播完再判定
	await get_tree().create_timer(HOME_RESTORE_DELAY).timeout
	# 期间玩家离开首页就放弃
	if _is_exiting or not visible:
		last_restore_status = "延迟期间玩家已离开 home,放弃本次判定"
		return
	# 队列为空则无事可做
	if not GameState.has_pending_rewards():
		last_restore_status = "无待补发奖励(漏奖队列为空)"
		return

	# 逐条筛：只有「属于可补发广告位」的队列项才补
	var grantable: Array = []
	for pr in GameState.get_pending_rewards():
		# 广告位 → 补发道具列表；空列表表示这个位不是补发类
		var r_items: Array = UniKitManager.restore_items_for_position(str(pr.get("source", "")))
		if r_items.is_empty():
			# 不可补发的条目直接跳过
			continue
		grantable.append({"entry": pr, "items": r_items})
	# 一条都补不了：清空整个队列，免得每次进首页都判定一遍
	if grantable.is_empty():
		last_restore_status = "队列非空但无可补发道具(广告位非补发类)"
		GameState.pop_all_pending_rewards()
		return

	# 今日还能补发几次（含「近 3 天正常领奖不足 3 次」的防刷门槛）
	var now: int = int(Time.get_unix_time_from_system())
	var remaining: int = GameState.get_restore_remaining_today(now)
	if remaining <= 0:
		last_restore_status = "今日不补发(已达上限或防刷未过,今日已补发 %d 次)" % GameState.get_restored_today_count()
		return

	# 队列倒序 = 后进先出，优先补最近漏掉的
	grantable.reverse()
	# 最多补到今日剩余额度
	var to_grant: Array = grantable.slice(0, remaining)

	# 同种道具合并计数后一次性展示
	var by_kind: Dictionary = {}
	var granted_entries: Array = []
	for g in to_grant:
		for it in g.items:
			var gk: String = str(it.get("kind", ""))
			if gk == "":
				continue
			# 按 kind 累加数量
			by_kind[gk] = int(by_kind.get(gk, 0)) + int(it.get("count", 0))
		granted_entries.append(g.entry)
	var rewards: Array = []
	for k in by_kind:
		rewards.append({"kind": k, "count": int(by_kind[k])})
	# 把本次判定结果写进 static 字段，供 cheat 面板排查「为什么没补」
	last_restore_status = (
		"本批弹出 %d 次补发/%d 种道具(今日可发 %d 次, 队列可补 %d 次)"
		% [to_grant.size(), rewards.size(), remaining, grantable.size()]
	)
	# 补发领取弹窗；rewards 形如 [{kind, count}]
	var page := UIManager.show_ui(UiName.AD_REWARD_RESTORED, {"rewards": rewards})
	if page == null:
		return

	# 用字典等弹窗结束：collected 表示玩家真的点了领取
	var result := {"done": false, "collected": false, "rewards": []}
	# 领取回调（一次性）
	page.collected.connect(
		func(rewards_collected: Array) -> void:
			result.rewards = rewards_collected
			result.collected = true
			result.done = true,
		CONNECT_ONE_SHOT
	)
	# 玩家直接关掉弹窗也算结束（collected 保持 false）
	page.closed.connect(func() -> void: result.done = true, CONNECT_ONE_SHOT)
	# 轮询等结束：弹窗内部流程较多，用信号 await 不方便
	while not result.done:
		await get_tree().process_frame
	# 只有真领取了才计入今日已补发次数
	if result.collected:
		GameState.add_restored_today_count(to_grant.size())

	# 已补发的条目从队列移除（没领取的也算处理过）
	GameState.remove_pending_rewards(granted_entries)
	UIManager.hide_ui(UiName.AD_REWARD_RESTORED)


# 首页评分弹窗：A/B 指定「通关后回首页」且关卡 >= 8 时才可能弹
func _maybe_show_rate_us_on_home() -> void:
	# 当前关卡号，下面用它做门槛判定
	var lv: int = GameState.get_current_level()
	# 门槛：rate_us_pop 取值为「通关后回首页」且 lv >= 8
	if not ABTestManager.rate_us_pop.is_eligible_at_home(lv):
		return
	# 必须本次冷启动后赢过一局，且从未弹过
	if not GameState.has_won_since_cold_start() or GameState.has_shown_rate_us():
		return
	# 离线不弹（评分需要联网提交）
	if not UniKitManager.is_online():
		return
	# 先标记已弹，防止重复进首页时再弹
	GameState.mark_rate_us_shown()
	# 等首页入场动画
	await get_tree().create_timer(HOME_RATE_US_DELAY).timeout

	# 期间离开首页就作废
	if _is_exiting or not visible:
		return

	# 评分弹窗；await closed 拿回 {is_submitted, star_count}
	var rate_us := UIManager.show_ui(UiName.RATE_US)
	var data: Dictionary = await rate_us.closed
	UIManager.hide_ui(UiName.RATE_US)
	# 提交且 4 星以上 → 走系统内评分（InAppReview）
	if data.get("is_submitted") and data.get("star_count", 0) > 4:
		InAppReviewManager.request_review()
	# 提交但 4 星及以下 → 转成反馈弹窗收集意见
	elif data.get("is_submitted") and data.get("star_count", 0) <= 4:
		var feedback := UIManager.show_ui(UiName.FEEDBACK, {"as_dlg": true})
		await feedback.closed
		UIManager.hide_ui(UiName.FEEDBACK)


# ================= 显隐与刷新 =================
# 每次被 UIManager 隐藏时调用：停倒计时并隐藏自己
func on_hide() -> void:
	# 倒计时 Timer 是场景常驻节点，必须显式停
	_countdown_timer.stop()
	visible = false


# 倒计时每秒超时一次 → 刷新每日按钮
func _on_countdown_timer_timeout() -> void:
	_update_countdown()


# 刷新每日按钮状态与倒计时文案（跨天时会从已完成回到可玩）
func _update_countdown() -> void:
	# 先推进历史最大日期，再算状态
	DailyEntryState.ensure_max_daily_advanced()
	_refresh_daily_btn_state()
	# 倒计时到次日 0 点，格式 HH:MM:SS
	_countdown_label.text = DailyEntryState.countdown_text()


# ================= 输入与入口按钮 =================
# 返回键（Android 物理返回）→ 弹退出确认
func _on_back_request() -> void:
	# 已经在转场中就不再处理
	if _is_exiting:
		return
	_request_quit_confirm()


# 弹「确认退出」弹窗；设置页开着时不接管返回键
func _request_quit_confirm() -> void:
	# 设置页可见时，返回键该由它自己处理
	var setting: Node = UIManager.get_ui(UiName.SETTING)
	if setting != null and setting is CanvasItem and (setting as CanvasItem).visible:
		return
	# 确认后直接退出游戏
	UIManager.show_ui(UiName.CONFIRM, {"on_confirm": func(): get_tree().quit()})


# 打开设置页（先埋点按钮点击）
func _on_settings_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.SETTINGS, self)
	UIManager.show_ui(UiName.SETTING)


# 开始游戏：带当前关卡号进 game 页
func _on_start_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.NORMAL_PLAY, self)
	_exit_to_page("game", {"level_index": GameState.get_current_level()})


# 每日挑战入口：点击交给 DailyEntryState 判定
func _on_daily_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.DAILY_PLAY, self)

	# 锁定 / 已完成只弹 Toast，可玩才真的进 daily_game
	DailyEntryState.handle_click(self, _exit_to_page.bind("daily_game", {}))


# ================= 转场 =================
# 转场退出：先播首页退场动画，动画走到标记点时才打开目标页
func _exit_to_page(page_name: String, params: Dictionary) -> void:
	# 防重入：一次只允许一次转场
	if _is_exiting:
		return
	_is_exiting = true
	# 这里只记录目标，真正打开在 _on_entry_reached
	_pending_page = page_name
	_pending_params = params
	# 用动画里 Entry 与 disappear 两个标记的时间差当延迟（当前两者几乎重合，延迟≈0）
	var anim: Animation = _anim.get_animation(&"MainInterface")
	var entry_delay: float = maxf(
		0.0, anim.get_marker_time(&"Entry") - anim.get_marker_time(&"disappear")
	)
	# 只连一次；隐藏首页后会断开
	if not _anim.animation_finished.is_connected(_on_anim_finished):
		_anim.animation_finished.connect(_on_anim_finished)
	# 从 disappear 标记播到末尾（退场段）
	_anim.play_section_with_markers(&"MainInterface", &"disappear", &"")
	# 延迟到点后打开目标页
	get_tree().create_timer(entry_delay).timeout.connect(_on_entry_reached)


# 动画到点：打开目标页，并把首页抬到它上面，让退场动画盖住新页
func _on_entry_reached() -> void:
	# 已经开过或节点已出树就不重复处理
	if _new_page_node != null or not is_inside_tree():
		return

	# show_ui 会缓存复用页面，重复调用只是重新 on_show
	_new_page_node = UIManager.show_ui(_pending_page, _pending_params)
	if _new_page_node == null:
		return

	# z_index 比新页大 1：首页的退场动画画在新页之上
	if _new_page_node is CanvasItem:
		z_index = (_new_page_node as CanvasItem).z_index + 1


# 退场动画播完：先断开自己，再隐藏首页
func _on_anim_finished(_anim_name: StringName) -> void:
	if _anim.animation_finished.is_connected(_on_anim_finished):
		_anim.animation_finished.disconnect(_on_anim_finished)
	# 只有目标页真的开起来了才隐藏首页（否则会黑屏）
	if _new_page_node != null:
		UIManager.hide_ui(UiName.HOME)


# ================= 每日挑战按钮 =================
# 按 DailyEntryState 的三态刷新每日按钮外观
func _refresh_daily_btn_state() -> void:
	# LOCKED 关卡不够 / DONE 今日已完成（或已过日期） / 其它为可玩
	var s: int = DailyEntryState.compute_state()
	match s:
		# 锁定态：统一灰底圆角，隐藏阴影与所有角标，只留锁图标
		DailyEntryState.State.LOCKED:
			var sf := StyleBoxFlat.new()
			sf.bg_color = Color(0.667, 0.667, 0.667, 1)
			sf.set_corner_radius_all(200)
			_daily_bg.add_theme_stylebox_override("normal", sf)
			_daily_bg.add_theme_stylebox_override("pressed", sf)
			_daily_bg.add_theme_stylebox_override("hover", sf)
			_daily_shadow.visible = false
			_daily_lock_icon.visible = true
			_daily_unlock_box.visible = false
			_daily_done_tag.visible = false
			_daily_top_tag.visible = false
			_countdown_tag.visible = false
		# 已完成态：蓝色底 + 投影，显示完成角标、名次与猫爪
		DailyEntryState.State.DONE:
			var sf_n := StyleBoxFlat.new()
			sf_n.bg_color = Color(0.576, 0.651, 0.945, 1)
			sf_n.set_corner_radius_all(200)
			sf_n.shadow_color = Color(0.576, 0.651, 0.945, 0.15)
			# 投影参数（像素）：偏移 10、向下 4
			sf_n.shadow_size = 10
			sf_n.shadow_offset = Vector2(0, 4)
			var sf_p := StyleBoxFlat.new()
			sf_p.bg_color = Color(0.471, 0.537, 0.78, 1)
			sf_p.set_corner_radius_all(200)
			_daily_bg.add_theme_stylebox_override("normal", sf_n)
			_daily_bg.add_theme_stylebox_override("pressed", sf_p)
			_daily_bg.add_theme_stylebox_override("hover", sf_n)
			_daily_shadow.visible = true
			_daily_lock_icon.visible = false
			_daily_unlock_box.visible = true
			_daily_done_tag.visible = true
			_daily_top_tag.visible = true
			_countdown_tag.visible = false
			# 完成用时与名次文案由 DailyEntryState 生成
			_daily_done_time.text = DailyEntryState.done_time_text()
			_daily_top_label.text = DailyEntryState.done_rank_text()

			# 猫爪按 dc_tag_ui A/B 决定是否显示；已完成态用亮色贴图
			_daily_paw.visible = ABTestManager.dc_tag_ui.is_paw_enabled()
			if _daily_paw.visible:
				_daily_paw.texture = _daily_paw_tex_lit
			# 名次标签宽度随文案变化，延后一帧等排版完成再算
			call_deferred("_update_top_tag_layout")
		# 默认（可玩）：还原原始样式，显示倒计时；猫爪用暗色
		_:
			_daily_bg.add_theme_stylebox_override("normal", _daily_sf_normal)
			_daily_bg.add_theme_stylebox_override("pressed", _daily_sf_pressed)
			_daily_bg.add_theme_stylebox_override("hover", _daily_sf_normal)
			_daily_shadow.visible = true
			_daily_lock_icon.visible = false
			_daily_unlock_box.visible = true
			_daily_done_tag.visible = false
			_daily_top_tag.visible = false
			_countdown_tag.visible = true

			_daily_paw.visible = ABTestManager.dc_tag_ui.is_paw_enabled()
			if _daily_paw.visible:
				_daily_paw.texture = _daily_paw_tex_dim


# 重新摆放右上角名次标签：宽度随文字自适应并保持右边对齐
func _update_top_tag_layout() -> void:
	# 设计稿里标签的默认位置与尺寸（像素）
	const DEFAULT_TAG_X: float = 619.0
	const DEFAULT_TAG_Y: float = -31.0
	const DEFAULT_TAG_W: float = 202.0
	const DEFAULT_TAG_H: float = 70.0
	const DEFAULT_LBL_W: float = 151.0
	const LBL_OFFSET_L: float = 30.0
	const LBL_OFFSET_T: float = 0.0
	# 按当前字号量出文字的自然宽度
	var font: Font = _daily_top_label.get_theme_font("font")
	var fs: int = _daily_top_label.get_theme_font_size("font_size")
	var lbl_w_natural: float = ceilf(
		font.get_string_size(_daily_top_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	)

	# 宽度不小于设计值
	var lbl_w: float = max(lbl_w_natural, DEFAULT_LBL_W)
	# 标签宽度 = 2 × 文字宽 - 100，右边固定
	var tag_w: float = 2.0 * lbl_w - 100.0

	# 由右边固定点反推新的 X
	var tag_x: float = (DEFAULT_TAG_X + DEFAULT_TAG_W) - tag_w
	_daily_top_tag.position = Vector2(tag_x, DEFAULT_TAG_Y)
	_daily_top_tag.size = Vector2(tag_w, DEFAULT_TAG_H)
	_daily_top_label.position = Vector2(LBL_OFFSET_L, LBL_OFFSET_T)
	_daily_top_label.size = Vector2(lbl_w, DEFAULT_TAG_H)


# ================= 首页布局（daily_streak A/B） =================
# 应用首页布局：A/B 开启时切到带打卡入口的新版布局
func _apply_home_layout() -> void:
	# daily_streak A/B：取值非 0 即启用新版布局
	var use_l2: bool = ABTestManager.daily_streak.is_enabled()
	_streak_layout.visible = use_l2
	# A/B 关闭：还原开始按钮 offset 与 Logo 位置
	if not use_l2:
		_start_btn.offset_left = _start_btn_orig_off_l
		_start_btn.offset_right = _start_btn_orig_off_r
		if _loge != null:
			_loge.position = _loge_orig_pos
		return

	# A/B 开启：原来的每日按钮让位给新版格子
	_daily_btn.visible = false

	# 开始按钮与 Logo 对齐到槽位
	_start_btn.global_position = _start_btn_slot.global_position
	_start_btn.size = _start_btn_slot.size

	if _loge != null:
		var slot_center: Vector2 = _logo_slot.global_position + _logo_slot.size * 0.5
		_loge.global_position = slot_center - _loge.size * 0.5

	# 两个入口格子懒加载：只在第一次切到新版布局时创建
	if _dc_cell == null:
		# create_child 要求场景根节点继承 UIChildWindow，并且会立刻 _do_show
		_dc_cell = create_child(_DC_ENTRY_CELL, {})
		_mount_into_slot(_dc_cell, _dc_slot)
	if _streak_cell == null:
		_streak_cell = create_child(_STREAK_ENTRY_CELL, {})
		_mount_into_slot(_streak_cell, _streak_slot)
	# 再按打卡是否「凉了」微调一次
	_apply_streak_dead_layout()


# challenge_only 且每日挑战还锁着时，打卡入口没有意义：隐藏它并让每日入口居中
func _apply_streak_dead_layout() -> void:
	var streak_dead: bool = (
		ABTestManager.daily_streak.is_challenge_only()
		and DailyEntryState.compute_state() == DailyEntryState.State.LOCKED
	)
	# 打卡入口失去意义时隐藏它（见函数说明）
	if _streak_cell != null:
		_streak_cell.visible = not streak_dead
	if _dc_cell != null:
		if streak_dead:
			# 居中：把每日格子的 X 补到布局中点
			(_dc_cell as Control).position.x = (
				_streak_layout.size.x * 0.5 - _dc_slot.position.x - _dc_slot.size.x * 0.5
			)
		else:
			(_dc_cell as Control).position.x = 0.0


# 把格子从原父节点摘下、挂进槽位并归零位置
func _mount_into_slot(cell: Node, slot: Control) -> void:
	var p: Node = cell.get_parent()
	if p != null:
		p.remove_child(cell)
	slot.add_child(cell)
	if cell is Control:
		(cell as Control).position = Vector2.ZERO


# ================= 埋点与诊断 =================
# 首页的埋点页面名
func get_scr_name() -> String:
	return Tracker.Scr.HOMEPAGE


# 空的 _input 覆写：首页不直接处理输入，全部交给控件信号
func _input(event: InputEvent) -> void:
	pass


# 诊断函数：点击被别人拦截时 push_error 报出拦截者（当前没有调用点）
func _diag_tap(pos: Vector2) -> void:
	# 取当前鼠标悬停的控件
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var hovered_path: String = str(hovered.get_path()) if hovered != null else "null"
	# 命中首页自己（可能只是正在转场），不算异常
	var in_home: bool = hovered != null and (hovered == self or is_ancestor_of(hovered))
	if in_home:
		if _is_exiting:
			push_error(
				"HomePage tap blocked by _is_exiting: hovered=%s pos=%s" % [hovered_path, str(pos)]
			)
		return

	# 落在白名单弹窗上：正常
	if _is_normal_home_overlay(hovered):
		return
	push_error(
		(
			"HomePage tap intercepted: hovered=%s pos=%s is_exiting=%s"
			% [hovered_path, str(pos), str(_is_exiting)]
		)
	)


# 判断悬停控件是否属于「允许盖在首页上的弹窗」或 cheat 面板
func _is_normal_home_overlay(hovered: Control) -> bool:
	if hovered == null:
		return false

	# 白名单：首页会弹出的 9 个窗口
	var normal_ui: Array[StringName] = [
		UiName.SETTING,
		UiName.CONFIRM,
		UiName.RATE_US,
		UiName.FEEDBACK,
		UiName.AD_REWARD_RESTORED,
		UiName.STREAK_SWITCH1,
		UiName.STREAK_SWITCH2,
		UiName.STREAK_SWITCH3,
		UiName.AB_SWITCH_POPUP,
	]
	# 逐个检查这些窗口是否可见、且是悬停控件的祖先
	for ui_name in normal_ui:
		var win: UIFrameWindow = UIManager.get_ui(ui_name)
		if win != null and win.visible and (win == hovered or win.is_ancestor_of(hovered)):
			return true

	# 另外放行名字里含 cheat 的节点（调试面板）
	var node: Node = hovered
	while node != null:
		if node.name.to_lower().contains("cheat"):
			return true
		node = node.get_parent()
	return false
