## 声音管理器：统一音效播放器、播放节流与背景音乐，合并多个暂停原因后决定是否恢复。
extends Node

enum Kind {
	BOARD_ENTER,
	MARK_X,
	UNMARK_X,
	MARK_CAT,
	MARK_WRONG,
	USE_HINT,
	ALL_CLEARED,
	LEVEL_WIN,
	LEVEL_FAIL,
	BTN_CLICK,
	DLG_OPEN,
	CLAP,
	BLOW_TRUMPET,
	COMBO,
	COMBO_VOICE,
	MARK_WRONG_LOW,
	LEVEL_FAIL_LOW,
	MARK_X_SOFT_1,
	MARK_X_SOFT_2,
	RANK_CAT_COLLECT,
	RANK_FISH_COLLECT_1,
	RANK_FISH_COLLECT_2,
	RANK_FISH_COLLECT_3,
	RANK_SCORE_COUNT,
	RANK_RISE_UP,
	RANK_RISE_DOWN,
	RANK_BOX_OPEN,
	RANK_BOX_APPEAR,
	PASS_PAGE_SETTLE,
	AUTO_X_MARK,
	AUTO_X_BANNER_APPEAR,
	VOICE_NICE_S6,
	VOICE_GREAT_S6,
	VOICE_PERFECT_S6,
	VOICE_EXCELLENT_S6,
	VOICE_AMAZING_S6,
	VOICE_UNBELIEVABLE_S6,
	VOICE_INCREDIBLE_S9,
	VOICE_PHENOMENAL_S9,
	VOICE_SPECTACULAR_S9,
	VOICE_LEGENDARY_S9,
	VOICE_UNREAL_S10,
	VOICE_INSANE_S10,
	VOICE_EPIC_S10,
	VOICE_BREATHTAKING_S10,
	VOICE_NICE_MEOW_S11,
	VOICE_GREAT_KITTY_S11,
	VOICE_PURR_FECT_S11,
	VOICE_EXCELLENT_KITTEN_S11,
	VOICE_AMAZING_MEW_S11,
	VOICE_PAW_SOME_S11,
	VOICE_INCREDIBLE_WHISKERS_S11,
	VOICE_CATNIP_LEVEL_S11,
	VOICE_EPIC_POUNCE_S11,
	VOICE_LEGENDARY_FURBALL_S11,
	MEOW_SINGLE,
	MEOW_CRESC_1,
	MEOW_CRESC_2,
	MEOW_CRESC_3,
	MEOW_CRESC_4,
	MEOW_CRESC_5,
	MEOW_CRESC_6,
	MEOW_CRESC_7,
	MEOW_RAND_1,
	MEOW_RAND_2,
	MEOW_RAND_3,
	MEOW_RAND_4,
	MEOW_RAND_5,
	MEOW_RAND_6,
	MEOW_RAND_7,
	PASS_ANIM_CAT_WIN_1,
	PASS_ANIM_CAT_WIN_2,
	PASS_ANIM_CAT_WIN_3,
	VOICE_COMBO_03_JP,
	VOICE_COMBO_04_JP,
	VOICE_COMBO_05_JP,
	VOICE_COMBO_06_JP,
	VOICE_COMBO_07_JP,
	VOICE_COMBO_08_JP,
	VOICE_COMBO_09_JP,
	VOICE_COMBO_10_JP,
	VOICE_COMBO_11_JP,
	VOICE_COMBO_12_JP,
	VOICE_COMBO_03_EN_AI_CAT,
	VOICE_COMBO_04_EN_AI_CAT,
	VOICE_COMBO_05_EN_AI_CAT,
	VOICE_COMBO_06_EN_AI_CAT,
	VOICE_COMBO_07_EN_AI_CAT,
	VOICE_COMBO_08_EN_AI_CAT,
	VOICE_COMBO_09_EN_AI_CAT,
	VOICE_COMBO_10_EN_AI_CAT,
	VOICE_COMBO_11_EN_AI_CAT,
	VOICE_COMBO_12_EN_AI_CAT,
	COMPANION_WAVE,
	COMPANION_SURPRISE,
	COMPANION_EAT,
	COMPANION_HUNGRY,
	COMPANION_IDLE,
}

const _SOUND_PATHS: Dictionary = {
	Kind.VOICE_COMBO_03_JP: "res://assets/audio/sfx/combo_03_jp.ogg",
	Kind.VOICE_COMBO_04_JP: "res://assets/audio/sfx/combo_04_jp.ogg",
	Kind.VOICE_COMBO_05_JP: "res://assets/audio/sfx/combo_05_jp.ogg",
	Kind.VOICE_COMBO_06_JP: "res://assets/audio/sfx/combo_06_jp.ogg",
	Kind.VOICE_COMBO_07_JP: "res://assets/audio/sfx/combo_07_jp.ogg",
	Kind.VOICE_COMBO_08_JP: "res://assets/audio/sfx/combo_08_jp.ogg",
	Kind.VOICE_COMBO_09_JP: "res://assets/audio/sfx/combo_09_jp.ogg",
	Kind.VOICE_COMBO_10_JP: "res://assets/audio/sfx/combo_10_jp.ogg",
	Kind.VOICE_COMBO_11_JP: "res://assets/audio/sfx/combo_11_jp.ogg",
	Kind.VOICE_COMBO_12_JP: "res://assets/audio/sfx/combo_12_jp.ogg",
	Kind.VOICE_COMBO_03_EN_AI_CAT: "res://assets/audio/sfx/combo_03_en_ai_cat.ogg",
	Kind.VOICE_COMBO_04_EN_AI_CAT: "res://assets/audio/sfx/combo_04_en_ai_cat.ogg",
	Kind.VOICE_COMBO_05_EN_AI_CAT: "res://assets/audio/sfx/combo_05_en_ai_cat.ogg",
	Kind.VOICE_COMBO_06_EN_AI_CAT: "res://assets/audio/sfx/combo_06_en_ai_cat.ogg",
	Kind.VOICE_COMBO_07_EN_AI_CAT: "res://assets/audio/sfx/combo_07_en_ai_cat.ogg",
	Kind.VOICE_COMBO_08_EN_AI_CAT: "res://assets/audio/sfx/combo_08_en_ai_cat.ogg",
	Kind.VOICE_COMBO_09_EN_AI_CAT: "res://assets/audio/sfx/combo_09_en_ai_cat.ogg",
	Kind.VOICE_COMBO_10_EN_AI_CAT: "res://assets/audio/sfx/combo_10_en_ai_cat.ogg",
	Kind.VOICE_COMBO_11_EN_AI_CAT: "res://assets/audio/sfx/combo_11_en_ai_cat.ogg",
	Kind.VOICE_COMBO_12_EN_AI_CAT: "res://assets/audio/sfx/combo_12_en_ai_cat.ogg",
	Kind.BOARD_ENTER: "res://assets/audio/sfx/board_enter_1.ogg",
	Kind.MARK_X: "res://assets/audio/sfx/mark_x_2.ogg",
	Kind.UNMARK_X: "res://assets/audio/sfx/unmark_x_2.ogg",
	Kind.MARK_CAT: "res://assets/audio/sfx/mark_cat.ogg",
	Kind.MARK_WRONG: "res://assets/audio/sfx/mark_wrong_1.ogg",
	Kind.USE_HINT: "res://assets/audio/sfx/use_hint.ogg",
	Kind.ALL_CLEARED: "res://assets/audio/sfx/all_cleared.ogg",
	Kind.LEVEL_WIN: "res://assets/audio/sfx/level_win.ogg",
	Kind.LEVEL_FAIL: "res://assets/audio/sfx/level_fail.ogg",
	Kind.BTN_CLICK: "res://assets/audio/sfx/btn_click_2.ogg",
	Kind.DLG_OPEN: "res://assets/audio/sfx/dlg_open_1.ogg",
	Kind.CLAP: "res://assets/audio/sfx/tile_handlike_clip.ogg",
	Kind.BLOW_TRUMPET: "res://assets/audio/sfx/tile_handlike_genius.ogg",
	Kind.COMBO: "res://assets/audio/sfx/combo_encourage.ogg",
	Kind.COMBO_VOICE: "res://assets/audio/sfx/combo_voice.ogg",
	Kind.RANK_FISH_COLLECT_1: "res://assets/audio/sfx/rank_fish_collect_1.ogg",
	Kind.RANK_FISH_COLLECT_2: "res://assets/audio/sfx/rank_fish_collect_2.ogg",
	Kind.RANK_FISH_COLLECT_3: "res://assets/audio/sfx/rank_fish_collect_3.ogg",
	Kind.RANK_SCORE_COUNT: "res://assets/audio/sfx/rank_score_count.ogg",
	Kind.RANK_RISE_UP: "res://assets/audio/sfx/rank_rise_up.ogg",
	Kind.RANK_RISE_DOWN: "res://assets/audio/sfx/rank_rise_down.ogg",
	Kind.RANK_BOX_OPEN: "res://assets/audio/sfx/rank_box_open.ogg",
	Kind.RANK_BOX_APPEAR: "res://assets/audio/sfx/rank_box_appear.ogg",
	Kind.PASS_PAGE_SETTLE: "res://assets/audio/sfx/pass_page_settle.ogg",
	Kind.AUTO_X_MARK: "res://assets/audio/sfx/auto_x_mark.ogg",
	Kind.AUTO_X_BANNER_APPEAR: "res://assets/audio/sfx/auto_x_banner_appear.ogg",
	Kind.VOICE_NICE_S6: "res://assets/audio/sfx/combo_nice_s6.ogg",
	Kind.VOICE_GREAT_S6: "res://assets/audio/sfx/combo_great_s6.ogg",
	Kind.VOICE_PERFECT_S6: "res://assets/audio/sfx/combo_perfect_s6.ogg",
	Kind.VOICE_EXCELLENT_S6: "res://assets/audio/sfx/combo_excellent_s6.ogg",
	Kind.VOICE_AMAZING_S6: "res://assets/audio/sfx/combo_amazing_s6.ogg",
	Kind.VOICE_UNBELIEVABLE_S6: "res://assets/audio/sfx/combo_unbelievable_s6.ogg",
	Kind.VOICE_UNREAL_S10: "res://assets/audio/sfx/combo_unreal_s10.ogg",
	Kind.VOICE_INSANE_S10: "res://assets/audio/sfx/combo_insane_s10.ogg",
	Kind.VOICE_EPIC_S10: "res://assets/audio/sfx/combo_epic_s10.ogg",
	Kind.VOICE_BREATHTAKING_S10: "res://assets/audio/sfx/combo_breathtaking_s10.ogg",
	Kind.PASS_ANIM_CAT_WIN_1: "res://assets/audio/sfx/pass_anim_cat_win_1.ogg",
	Kind.PASS_ANIM_CAT_WIN_2: "res://assets/audio/sfx/pass_anim_cat_win_2.ogg",
	Kind.PASS_ANIM_CAT_WIN_3: "res://assets/audio/sfx/pass_anim_cat_win_3.ogg",
	Kind.COMPANION_WAVE: "res://assets/audio/sfx/companion_wave.ogg",
	Kind.COMPANION_SURPRISE: "res://assets/audio/sfx/companion_surprise.ogg",
	Kind.COMPANION_EAT: "res://assets/audio/sfx/companion_eat.ogg",
	Kind.COMPANION_HUNGRY: "res://assets/audio/sfx/companion_hungry.ogg",
	Kind.COMPANION_IDLE: "res://assets/audio/sfx/companion_idle.ogg",
}

const _POLYPHONY: Dictionary = {
	Kind.MARK_X: 4,
	Kind.UNMARK_X: 4,
	Kind.MARK_CAT: 3,
	Kind.MARK_WRONG: 2,
	Kind.BTN_CLICK: 4,
	Kind.CLAP: 2,
	Kind.BLOW_TRUMPET: 2,
	Kind.COMBO: 2,
	Kind.COMBO_VOICE: 2,
}

# ---- 音效播放器（_ready 里一次建好，常驻复用） ----
## Kind → AudioStreamPlayer；播放就是 play() 复用同一个节点
var _players: Dictionary = {}
## 临时静音：教学演示等场景压制音效，不写存档、也不影响 BGM
var _silent: bool = false

var _last_play_usec: Dictionary = {}

const _WARMUP_KINDS: Array = [
	Kind.MARK_X,
	Kind.MARK_CAT,
]

const _WARMUP_VOLUME_DB: float = -80.0

# ---- BGM 播放器与状态 ----
## 唯一的 BGM 播放器，stream 懒加载（见 _ensure_bgm_stream）
var _bgm_player: AudioStreamPlayer
## 是否已由 start_bgm() 打开总闸；false 时 _apply_bgm_playback 一律停播
var _bgm_started: bool = false
## 当前已加载的 BGM 路径，用来判断要不要重新 load
var _bgm_stream_path: String = ""

var _bgm_pause_reasons: Dictionary = {}

var _bgm_sfx_pause_pending: Dictionary = {}

const _BGM_PAUSE_SFX_KINDS: Array = [
	Kind.BOARD_ENTER,
	Kind.LEVEL_WIN,
	Kind.PASS_ANIM_CAT_WIN_1,
	Kind.PASS_ANIM_CAT_WIN_2,
	Kind.PASS_ANIM_CAT_WIN_3,
]


func _ready() -> void:
	for kind in _SOUND_PATHS.keys():
		var path: String = _SOUND_PATHS[kind]
		var stream: AudioStream = load(path) as AudioStream
		if stream == null:
			push_error("SoundManager: failed to load %s" % path)
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = "Master"
		player.max_polyphony = _POLYPHONY.get(kind, 1)
		add_child(player)
		_players[kind] = player

	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	add_child(_bgm_player)

	_connect_ad_signals.call_deferred()

	var bgm_log_timer := Timer.new()
	bgm_log_timer.wait_time = 1.0
	bgm_log_timer.one_shot = false
	bgm_log_timer.timeout.connect(_log_bgm_status)
	add_child(bgm_log_timer)
	bgm_log_timer.start()


func _log_bgm_status() -> void:
	if _bgm_player == null or _bgm_player.stream == null:
		return
	if not _bgm_player.playing or _bgm_player.stream_paused:
		return
	var total: float = _bgm_player.stream.get_length()
	var pos: float = _bgm_player.get_playback_position()
	var group: int = (
		int(ABTestManager.bgm_test.value())
		if ABTestManager != null and ABTestManager.bgm_test != null
		else -1
	)
	print(
		(
			"[BGM] 组=%d 曲目=%s 时长=%.1fs 当前=%.1fs (第 %d 秒)"
			% [group, _bgm_stream_path, total, pos, int(pos)]
		)
	)


## 检查静音与音效开关，按微秒时钟限制同类音效频率，特殊音效播放时暂时持有 BGM 暂停原因。
func play(kind: int, min_interval_sec: float = 0.0) -> void:
	if _silent:
		return
	if not GameState.is_sound_on():
		return
	var player: AudioStreamPlayer = _players.get(kind, null)
	if player == null:
		_emit_sound(kind, "", "no_player")
		return
	var now: int = Time.get_ticks_usec()
	if min_interval_sec > 0.0:
		var last: int = _last_play_usec.get(kind, -1)
		if last >= 0 and now - last < int(min_interval_sec * 1000000.0):
			return

	_last_play_usec[kind] = now

	if kind in _BGM_PAUSE_SFX_KINDS:
		_pause_bgm_during(kind, player)
	player.play()
	_emit_sound(kind, "", "")


func warmup_sfx() -> void:
	for kind: int in _WARMUP_KINDS:
		var player: AudioStreamPlayer = _players.get(kind, null)
		if player == null:
			continue
		var original_db: float = player.volume_db
		player.volume_db = _WARMUP_VOLUME_DB
		player.play()
		await get_tree().process_frame

		player.stop()
		player.volume_db = original_db


func get_sound_length(kind: int) -> float:
	var player: AudioStreamPlayer = _players.get(kind, null)
	if player == null or player.stream == null:
		return 0.0
	return player.stream.get_length()


func play_people_voice(kind: int) -> void:
	if _silent:
		return
	if not GameState.is_people_on():
		return
	var player: AudioStreamPlayer = _players.get(kind, null)
	if player == null:
		_emit_sound(kind, "voice", "no_player")
		return
	player.play()
	_emit_sound(kind, "voice", "")


func set_silent(value: bool) -> void:
	var changed: bool = _silent != value
	_silent = value
	if changed and is_instance_valid(EventBus):
		EventBus.emit_event(EventName.SOUND_SILENT, {"on": value})


func stop(kind: int) -> void:
	var player: AudioStreamPlayer = _players.get(kind, null)
	if player != null:
		player.stop()
		if is_instance_valid(EventBus):
			EventBus.emit_event(EventName.SOUND_STOP, {"kind": _kind_name(kind)})


func start_bgm() -> void:
	_bgm_started = true

	if (
		ABTestManager != null
		and ABTestManager.bgm_test != null
		and ABTestManager.bgm_test.has_music_switch()
	):
		GameState.apply_music_switch(ABTestManager.bgm_test.default_music_on())
	_apply_bgm_playback()


## 按来源键增删暂停原因；某一来源解除暂停不代表其他来源也已结束。
func set_bgm_paused(paused: bool, key: String) -> void:
	if paused:
		_bgm_pause_reasons[key] = true
	else:
		_bgm_pause_reasons.erase(key)
	if is_instance_valid(EventBus):
		(
			EventBus
			. emit_event(
				EventName.SOUND_BGM,
				{
					"action": "pause" if paused else "resume",
					"key": key,
					"reasons": _bgm_pause_reasons.size(),
				}
			)
		)
	_apply_bgm_playback()


## 按当前设置重新应用 BGM：设置页切换「音乐」开关后调用
func refresh_bgm() -> void:
	_apply_bgm_playback()


# ================= 广告联动 =================
## 连接 UniKit 的广告信号，广告展示期间自动暂停 BGM
func _connect_ad_signals() -> void:
	# 广告开始播放 → 暂停 BGM
	if UniKitManager.ad_shown.connect(_on_ad_shown_pause_bgm) != OK:
		push_error("SoundManager: failed to connect UniKitManager.ad_shown")
	# 广告关闭 → 恢复 BGM
	if UniKitManager.ad_closed.connect(_on_ad_closed_resume_bgm) != OK:
		push_error("SoundManager: failed to connect UniKitManager.ad_closed")


func _on_ad_shown_pause_bgm(placement_id: String) -> void:
	if placement_id == AdPlacement.BANNER:
		return
	set_bgm_paused(true, BgmPauseReason.AD)


func _on_ad_closed_resume_bgm(placement_id: String) -> void:
	if placement_id == AdPlacement.BANNER:
		return
	set_bgm_paused(false, BgmPauseReason.AD)


func _sfx_pause_key(kind: int) -> String:
	var kind_name: Variant = Kind.find_key(kind)
	return BgmPauseReason.SFX_PREFIX + (str(kind_name) if kind_name != null else str(kind))


func _pause_bgm_during(kind: int, sfx_player: AudioStreamPlayer) -> void:
	if not _bgm_started:
		return
	set_bgm_paused(true, _sfx_pause_key(kind))

	if _bgm_sfx_pause_pending.has(kind):
		return
	_bgm_sfx_pause_pending[kind] = true
	sfx_player.finished.connect(_on_pause_sfx_finished.bind(kind), CONNECT_ONE_SHOT)


func _on_pause_sfx_finished(kind: int) -> void:
	_bgm_sfx_pause_pending.erase(kind)
	set_bgm_paused(false, _sfx_pause_key(kind))


func _apply_bgm_playback() -> void:
	if not _should_play_bgm():
		_bgm_player.stop()
		return

	var path: String = (
		ABTestManager.bgm_test.get_music_path()
		if ABTestManager != null and ABTestManager.bgm_test != null
		else ""
	)
	if path == "" or not _ensure_bgm_stream(path):
		return

	_resume_or_start_bgm()

	_bgm_player.stream_paused = not _bgm_pause_reasons.is_empty()


func _should_play_bgm() -> bool:
	if not _bgm_started:
		return false
	if ABTestManager == null or ABTestManager.bgm_test == null:
		return false
	if not ABTestManager.bgm_test.has_music_switch():
		return false
	return GameState.is_music_on()


## 续播：只有在既没在播、也没被暂停时才 play()，避免暂停中被重置播放进度
func _resume_or_start_bgm() -> void:
	if not _bgm_player.playing and not _bgm_player.stream_paused:
		_bgm_player.play()


## 确保 BGM 流就位：路径没变且已加载就直接复用，否则重新 load 并强制循环
func _ensure_bgm_stream(path: String) -> bool:
	if _bgm_stream_path == path and _bgm_player.stream != null:
		return true
	if not ResourceLoader.exists(path):
		return false
	var stream: AudioStream = ResourceLoader.load(path) as AudioStream
	if stream == null:
		return false

	# BGM 必须无缝循环
	if "loop" in stream:
		stream.set("loop", true)
	_bgm_player.stream = stream
	_bgm_stream_path = path
	return true


func _emit_sound(kind: int, channel: String, miss: String) -> void:
	if not is_instance_valid(EventBus):
		return
	var payload: Dictionary = {"kind": _kind_name(kind)}
	if not channel.is_empty():
		payload["ch"] = channel
	if not miss.is_empty():
		payload["miss"] = miss
	EventBus.emit_event(EventName.SOUND_PLAY, payload)


func _kind_name(kind: int) -> String:
	var keys: Array = Kind.keys()
	if kind >= 0 and kind < keys.size():
		return String(keys[kind])
	return "unknown(%d)" % kind
