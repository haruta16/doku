## 排行结算礼包的演出单元；组合名次、头像、宝箱和累计获胜次数，收集按钮向外发出领取意图。

extends UIChildWindow

const _NUM_COLOR: String = "02BE52"

const _NUM_FONT: String = "res://assets/fonts/Roboto-bold-title.tres"

const _OPEN_NOTIFY_DELAY: float = 0.8834

const _BOX_APPEAR_SFX_DELAY: float = 2.5

const _BOX_APPEAR_VIBRATE_DELAY: float = 2.88

const _BTN_TEXT_COLLECT: String = "AD_REWARD_RESTORED_COLLECT"
const _BTN_TEXT_OK: String = "RANK_GIFT_OK"

const _PODIUM_Y_WITH_BOX: float = 500.0
const _PODIUM_Y_NO_BOX: float = 800.0

const _PODIUM_HEIGHT: float = 347.0

@onready var _box_spine: Control = $BoxSpine

@onready var _box_sprite_down: SpineSprite = $BoxSpine/box/SpineSprite3
@onready var _box_sprite_up: SpineSprite = $BoxSpine/box/SpineSprite4
@onready var _win_text: RichTextLabel = $WinText
@onready var _podium: Control = $Podium
@onready var _collect_btn: Control = $CollectBtn
@onready var _anim: AnimationPlayer = $AnimationPlayer

@onready
var _box_idle_down: AnimationPlayer = $"BoxSpine/box/SpineSprite3/SpineAnimationTrack/SpineSprite3 Track 0"
@onready
var _box_idle_up: AnimationPlayer = $"BoxSpine/box/SpineSprite4/SpineAnimationTrack/SpineSprite4 Track 0"

const _BOX_SKIN_BY_PLACE := {1: "RankBox3", 2: "RankBox2", 3: "RankBox1"}

signal collect_pressed

var _opening: bool = false

var _appeared: bool = false

var _has_box: bool = false


func setup(top3_infos: Array, place: int, win_count: int) -> void:
	set_win_count(place, win_count)
	if _podium != null:
		_podium.apply_top3(top3_infos)
	var has_box: bool = true
	set_has_box(has_box)

	if has_box:
		_apply_box_skin(place)

	if _collect_btn != null:
		_collect_btn.btn_text = _BTN_TEXT_COLLECT if has_box else _BTN_TEXT_OK

		var _sh: CanvasItem = _collect_btn.get_node_or_null("Root/Shadow") as CanvasItem
		if _sh != null:
			_sh.visible = false

	_play_enter_appear(has_box, &"Appear1")


func _play_enter_appear(has_box: bool, anim_name: StringName) -> void:
	_appeared = false
	if _anim != null and _anim.has_animation(anim_name):
		_anim.play(anim_name)
		if has_box:
			_play_box_appear_sfx_delayed()
			_play_box_appear_vibrate_delayed()
		await _anim.animation_finished
		if not is_instance_valid(self):
			return
		set_has_box(has_box)
		if has_box:
			_start_box_idle_loop()
	_appeared = true


func _play_box_appear_sfx_delayed() -> void:
	await get_tree().create_timer(_BOX_APPEAR_SFX_DELAY).timeout
	if is_instance_valid(self):
		SoundManager.play(SoundManager.Kind.RANK_BOX_APPEAR)


func _play_box_appear_vibrate_delayed() -> void:
	await get_tree().create_timer(_BOX_APPEAR_VIBRATE_DELAY).timeout
	if is_instance_valid(self):
		VibrateManager.play_at(VibrateManager.Pos.RANK_GIFT_BOX_APPEAR)


func _start_box_idle_loop() -> void:
	for tp: AnimationPlayer in [_box_idle_down, _box_idle_up]:
		if tp != null and tp.has_animation(&"Idle_looped"):
			tp.play(&"Idle_looped")


func _apply_box_skin(place: int) -> void:
	var skin: String = _BOX_SKIN_BY_PLACE.get(clampi(place, 1, 3), "RankBox1")
	for sp: SpineSprite in [_box_sprite_down, _box_sprite_up]:
		if sp == null:
			continue
		var sk = sp.get_skeleton()
		if sk == null:
			continue
		sk.set_skin_by_name(skin)
		sk.set_slots_to_setup_pose()
		sp.update_skeleton(0.0)


func set_has_box(has_box: bool) -> void:
	_has_box = has_box
	if _box_spine != null:
		_box_spine.visible = has_box
	if _podium != null:
		var podium_y: float = _PODIUM_Y_WITH_BOX if has_box else _PODIUM_Y_NO_BOX
		_podium.offset_top = podium_y
		_podium.offset_bottom = podium_y + _PODIUM_HEIGHT


func _on_collect_pressed() -> void:
	if not _appeared:
		return
	if _opening:
		return
	_opening = true
	if _has_box and _anim != null and _anim.has_animation(&"Open1"):
		SoundManager.play(SoundManager.Kind.RANK_BOX_OPEN)
		_anim.play(&"Open1")
		get_tree().create_timer(0.95).timeout.connect(
			func() -> void: VibrateManager.play_at(VibrateManager.Pos.RANK_GIFT_OPEN)
		)

		await get_tree().create_timer(_OPEN_NOTIFY_DELAY).timeout
		if not is_instance_valid(self):
			return
		collect_pressed.emit()

		if _anim.is_playing():
			await _anim.animation_finished
			if not is_instance_valid(self):
				return
	else:
		collect_pressed.emit()
	visible = false


func set_win_count(place: int, count: int) -> void:
	var key: String = "RANK_GIFT_WIN_TIMES_%d" % clampi(place, 1, 3)
	_win_text.text = tr(key) % [_NUM_COLOR, _NUM_FONT, count]
