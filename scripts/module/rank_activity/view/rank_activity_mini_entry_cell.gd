## 紧凑版排行入口；同步活动名次和宝箱状态，并提供躲猫猫奖励抵达特效。

extends UIChildWindow

const _CHEST_SKIN_BY_RANK := {1: "RankBox3", 2: "RankBox2", 3: "RankBox1"}

const _CHEST_IDLE_ANIM := "Idle"
const _CHEST_IDLE_TRACK := 0

const _PEEKABOO_BURST_SCENE: PackedScene = preload("res://assets/prefab/effect_score_burst.tscn")

@onready var _state_open: Control = $StateOpen
@onready var _state_active: Control = $StateActive

@onready var _chest_sprite: SpineSprite = $StateOpen/ChestSwitch/SpineSprite
@onready var _rank_medal: Control = $StateActive/Rank
@onready var _rank_label: Label = $"StateActive/Rank/99"
@onready var _countdown_label: Label = $StateActive/Countdown/CountdownText
@onready var _click_btn: Button = $ClickBtn

var _offline_overlay: Control = null
var _offline_snapshot: bool = false


func on_create() -> void:
	RankActivityManager.state_changed.connect(_on_state_changed)
	RankActivityManager.ranking_changed.connect(_on_ranking_changed)

	_click_btn.button_down.connect(func() -> void: play_press_scale(self))
	_click_btn.button_up.connect(func() -> void: play_release_scale(self))
	_offline_overlay = RankOfflineOverlayHelper.attach(self, 100.0)


func on_show(_params: Dictionary = {}) -> void:
	if not ClockTicker.second_tick.is_connected(_on_tick):
		connect_managed(ClockTicker.second_tick, _on_tick)

	_offline_snapshot = RankOfflineOverlayHelper.is_offline_mode()
	_refresh()


func _on_state_changed(_state: int) -> void:
	_refresh()


func _on_ranking_changed() -> void:
	_update_rank()


func _on_tick() -> void:
	if _offline_snapshot:
		return
	if _state_active.visible:
		_countdown_label.text = _format_hms(RankActivityManager.get_remaining_sec())


func _refresh() -> void:
	var pending: Dictionary = RankActivityManager.get_pending_reward()
	var pending_reward: bool = not pending.is_empty()
	_state_open.visible = pending_reward
	_state_active.visible = not pending_reward
	if _state_open.visible:
		_apply_chest(int(pending.get("rank", 1)))
	if _state_active.visible:
		_update_rank()
		_countdown_label.text = _format_hms(RankActivityManager.get_remaining_sec())
		if _offline_snapshot:
			_countdown_label.text = "--"
			_rank_medal.visible = false
	RankOfflineOverlayHelper.refresh(_offline_overlay, _offline_snapshot)


func _apply_chest(rank: int) -> void:
	_chest_sprite.visible = true
	_apply_chest_skin(rank)


func _apply_chest_skin(rank: int) -> void:
	if _chest_sprite == null:
		return
	var skin: String = _CHEST_SKIN_BY_RANK.get(clampi(rank, 1, 3), "RankBox1")
	var sk = _chest_sprite.get_skeleton()
	if sk == null:
		return
	sk.set_skin_by_name(skin)
	sk.set_slots_to_setup_pose()
	_chest_sprite.update_skeleton(0.0)
	_play_chest_idle(_chest_sprite)


func _play_chest_idle(sprite: SpineSprite) -> void:
	if sprite == null:
		return
	var st = sprite.get_animation_state()
	if st == null:
		return
	st.set_animation(_CHEST_IDLE_ANIM, true, _CHEST_IDLE_TRACK)


func _update_rank() -> void:
	var has_rank: bool = (
		RankActivityManager.is_joined() and RankActivityManager.get_collect_total() > 0
	)
	_rank_medal.visible = has_rank
	if has_rank:
		_rank_label.text = str(RankActivityManager.get_player_rank())
	if not _offline_snapshot:
		RankActivityManager.record_seen_online_rank()


func _format_hms(sec: int) -> String:
	sec = maxi(0, sec)
	return "%02d:%02d:%02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]


func _on_click_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CHALLENGE_ENTRANCE, self)

	VibrateManager.play_at(VibrateManager.Pos.RANK_ENTRY_CLICK)

	_update_rank()

	RankActivityManager.open_home_entry()


func play_peekaboo_feedback(fish_count: int) -> void:
	var anim_name: String = "PeekabooFeedback2" if fish_count >= 3 else "PeekabooFeedback1"
	var player: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null and player.has_animation(anim_name):
		player.play(anim_name)
	else:
		push_warning("[%s] 缺动画 %s，跳过回弹反馈" % [name, anim_name])
	_spawn_peekaboo_burst()


func _spawn_peekaboo_burst() -> void:
	var burst: Node = _PEEKABOO_BURST_SCENE.instantiate()
	add_child(burst)
	if burst is CanvasItem:
		(burst as CanvasItem).z_index = 100
	if burst is Control:
		(burst as Control).position = size * 0.5
	for child_name: String in ["GlowAlp", "StarAlp", "StarAdd"]:
		var particles: Node = burst.get_node_or_null(child_name)
		if particles is CPUParticles2D:
			(particles as CPUParticles2D).emitting = true
	var burst_tween: Tween = burst.create_tween()
	burst_tween.tween_interval(1.5)
	burst_tween.tween_callback(burst.queue_free)
