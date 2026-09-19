# 音频总控（autoload 名 SoundManager）：启动时预加载全部音效、各建一个常驻播放器，并统一管理 BGM 的播放/暂停
extends Node

# ---- 音效种类 ----
# 音效编号：每个 Kind 对应 _SOUND_PATHS 里的一条 ogg；顺序即枚举值，插到中间会挪动后面的映射
# 大致分四类：棋盘与按钮音、结算胜负音、CLAP/BLOW_TRUMPET 鼓励音、COMBO* 连击音
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
}

# ---- 资源与配置表 ----
# 音效种类 → ogg 资源路径；_ready() 按这张表逐个建播放器
const _SOUND_PATHS: Dictionary = {
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
	Kind.MARK_WRONG_LOW: "res://assets/audio/sfx/mark_wrong_low.ogg",
	Kind.LEVEL_FAIL_LOW: "res://assets/audio/sfx/level_fail_low.ogg",
}

# 同时发声上限（表里没写的默认 1）：点得快的音效给多路，免得连点时被自己截断
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
	Kind.MARK_WRONG_LOW: 2,
}

# ---- 音效播放器（_ready 里一次建好，常驻复用） ----
# Kind → AudioStreamPlayer；播放就是 play() 复用同一个节点
var _players: Dictionary = {}
# 临时静音：教学演示等场景压制音效，不写存档、也不影响 BGM
var _silent: bool = false

# ---- BGM 播放器与状态 ----
# 唯一的 BGM 播放器，stream 懒加载（见 _ensure_bgm_stream）
var _bgm_player: AudioStreamPlayer
# 是否已由 start_bgm() 打开总闸；false 时 _apply_bgm_playback 一律停播
var _bgm_started: bool = false
# 结算弹窗要求暂停（失败页等调用 set_bgm_paused）
var _bgm_paused_for_dialog: bool = false
# 闪避标志：播 BOARD_ENTER / LEVEL_WIN 期间压低 BGM（实现上是整段暂停）
var _bgm_ducking: bool = false
# 广告展示中暂停（由 UniKitManager 的广告信号驱动）
var _bgm_paused_for_ad: bool = false
# 当前已加载的 BGM 路径，用来判断要不要重新 load
var _bgm_stream_path: String = ""

# 需要闪避 BGM 的音效：进入棋盘、通关
const _BGM_DUCK_KINDS: Array = [Kind.BOARD_ENTER, Kind.LEVEL_WIN]

# ---- 连击人声资源（内置，按连击数分级） ----
# 3~8 连击 → 男声 ogg；key 同时是封顶档位，超过 8 连击按 8 播
const _COMBO_VOICE_PATHS: Dictionary = {
	3: "res://assets/audio/sfx/combo_nice.ogg",
	4: "res://assets/audio/sfx/combo_great.ogg",
	5: "res://assets/audio/sfx/combo_perfect.ogg",
	6: "res://assets/audio/sfx/combo_excellent.ogg",
	7: "res://assets/audio/sfx/combo_amazing.ogg",
	8: "res://assets/audio/sfx/combo_unbelievable.ogg",
}

# 同上，女声版（资源名多 _a 后缀）
const _COMBO_VOICE_FEMALE_PATHS: Dictionary = {
	3: "res://assets/audio/sfx/combo_nice_a.ogg",
	4: "res://assets/audio/sfx/combo_great_a.ogg",
	5: "res://assets/audio/sfx/combo_perfect_a.ogg",
	6: "res://assets/audio/sfx/combo_excellent_a.ogg",
	7: "res://assets/audio/sfx/combo_amazing_a.ogg",
	8: "res://assets/audio/sfx/combo_unbelievable_a.ogg",
}
# 连击数 → 男声播放器
var _combo_voice_players: Dictionary = {}
# 连击数 → 女声播放器
var _combo_voice_female_players: Dictionary = {}

# AB 实验给的自定义音频路径 → 播放器（首次用到才建，加载失败会缓存 null）
var _combo_voice_path_players: Dictionary = {}


# ================= 生命周期 =================
# autoload 启动：把全部音效和连击人声预加载成播放器子节点，再延迟连接广告信号
func _ready() -> void:
	# 每个音效一个独立播放器，之后一直复用
	for kind in _SOUND_PATHS.keys():
		var path: String = _SOUND_PATHS[kind]
		var stream: AudioStream = load(path) as AudioStream
		# 资源缺失只报错跳过，不影响其它音效
		if stream == null:
			push_error("SoundManager: failed to load %s" % path)
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = "Master" # 所有播放器都挂 Master 总线，项目没有自定义音频总线布局，音量由总线统一决定
		player.max_polyphony = _POLYPHONY.get(kind, 1)
		add_child(player)
		_players[kind] = player
	# 连击人声：每个连击等级各一个播放器
	for level: int in _COMBO_VOICE_PATHS.keys():
		var path: String = _COMBO_VOICE_PATHS[level]
		var stream: AudioStream = load(path) as AudioStream
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = "Master"
		add_child(player)
		_combo_voice_players[level] = player
	# 女声版同理
	for level: int in _COMBO_VOICE_FEMALE_PATHS.keys():
		var path: String = _COMBO_VOICE_FEMALE_PATHS[level]
		var stream: AudioStream = load(path) as AudioStream
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = "Master"
		add_child(player)
		_combo_voice_female_players[level] = player

	# BGM 播放器最后建，stream 等到真要播时才加载
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	add_child(_bgm_player)

	# 延迟一帧：_ready 阶段 UniKitManager 这个 autoload 可能还没准备好
	_connect_ad_signals.call_deferred()


# ================= 音效播放 =================
# 播一个音效：先过临时静音和存档里的「音效」开关；BOARD_ENTER / LEVEL_WIN 会先闪避 BGM
func play(kind: int) -> void:
	if _silent:
		return
	# 存档中的音效总开关
	if not GameState.is_sound_on():
		return
	# 没注册过的 kind 视为无音效，静默忽略
	var player: AudioStreamPlayer = _players.get(kind, null)
	if player == null:
		return

	# 这两类音效和 BGM 频段重叠，先压低 BGM 再播
	if kind in _BGM_DUCK_KINDS:
		_duck_bgm_during(player)
	player.play()


# 设置临时静音（教学、切歌等场景用）：只挡音效，不落存档、不影响 BGM
func set_silent(value: bool) -> void:
	_silent = value


# 播内置连击人声：连击数封顶 8，female 决定用男声表还是女声表；受「音效」开关控制
func play_combo_voice(combo_count: int, female: bool = false) -> void:
	if _silent or not GameState.is_sound_on():
		return
	# 超过 8 连击按最高档播
	var level: int = mini(combo_count, 8)
	var players: Dictionary = _combo_voice_female_players if female else _combo_voice_players
	var player: AudioStreamPlayer = players.get(level, null)
	if player != null:
		player.play()


# 播 AB 实验指定的连击人声文件（按路径）；受「人声」开关而非音效开关控制
func play_combo_voice_by_path(path: String) -> void:
	if _silent:
		return
	# 人声是独立开关（is_people_on）
	if not GameState.is_people_on():
		return
	# AB 分组没配路径就不播
	if path.is_empty():
		return
	var player: AudioStreamPlayer = _ensure_combo_voice_player(path)
	if player != null:
		player.play()


# 按需创建并缓存自定义人声的播放器；路径不存在时也缓存 null，避免每次重复探测
func _ensure_combo_voice_player(path: String) -> AudioStreamPlayer:
	if _combo_voice_path_players.has(path):
		return _combo_voice_path_players[path]
	var player: AudioStreamPlayer = null
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path) as AudioStream
		if stream != null:
			player = AudioStreamPlayer.new()
			player.stream = stream
			player.bus = "Master"
			add_child(player)
	# 失败也写进缓存：null 表示这条路径已经试过且拿不到
	_combo_voice_path_players[path] = player
	return player


# 掐断某个音效的当前播放（例：撤销落子时立刻停掉 MARK_CAT）
func stop(kind: int) -> void:
	var player: AudioStreamPlayer = _players.get(kind, null)
	if player != null:
		player.stop()


# ================= BGM 与播放控制 =================
# 打开 BGM 总闸（首页、游戏页进入时调用），真正的播放交给 _apply_bgm_playback
func start_bgm() -> void:
	_bgm_started = true
	_apply_bgm_playback()


# 结算弹窗暂停 / 恢复 BGM（失败页调用），只改标志位、不直接停流
func set_bgm_paused(paused: bool) -> void:
	_bgm_paused_for_dialog = paused
	_apply_bgm_playback()


# 按当前设置重新应用 BGM：设置页切换「音乐」开关后调用
func refresh_bgm() -> void:
	_apply_bgm_playback()


# ================= 广告联动 =================
# 连接 UniKit 的广告信号，广告展示期间自动暂停 BGM
func _connect_ad_signals() -> void:
	# 广告开始播放 → 暂停 BGM
	if UniKitManager.ad_shown.connect(_on_ad_shown_pause_bgm) != OK:
		push_error("SoundManager: failed to connect UniKitManager.ad_shown")
	# 广告关闭 → 恢复 BGM
	if UniKitManager.ad_closed.connect(_on_ad_closed_resume_bgm) != OK:
		push_error("SoundManager: failed to connect UniKitManager.ad_closed")


# 广告展示回调：置暂停标志并立即生效（_placement_id 参数未使用）
func _on_ad_shown_pause_bgm(_placement_id: String) -> void:
	_bgm_paused_for_ad = true
	_apply_bgm_playback()


# 广告关闭回调：清暂停标志；是否真的继续播由 _should_play_bgm 决定
func _on_ad_closed_resume_bgm(_placement_id: String) -> void:
	_bgm_paused_for_ad = false
	_apply_bgm_playback()


# ================= BGM 内部实现 =================
# 闪避：标记 ducking 并等该音效播完再恢复；CONNECT_ONE_SHOT 保证只回调一次
func _duck_bgm_during(sfx_player: AudioStreamPlayer) -> void:
	if not _bgm_started:
		return
	_bgm_ducking = true
	_apply_bgm_playback()
	if not sfx_player.finished.is_connected(_on_duck_sfx_finished):
		sfx_player.finished.connect(_on_duck_sfx_finished, CONNECT_ONE_SHOT)


# 闪避用的那个音效播完了 → 取消 ducking
func _on_duck_sfx_finished() -> void:
	_bgm_ducking = false
	_apply_bgm_playback()


# 应用 BGM 的唯一出口：决定停播、换曲、续播和暂停状态
func _apply_bgm_playback() -> void:
	# 三个条件（总闸、AB 开关、音乐开关）任一不满足就彻底停掉并清空当前曲
	if not _should_play_bgm():
		_bgm_player.stop()
		return

	# BGM 放哪首由 AB 实验决定；空路径表示该分组不放 BGM
	var path: String = ABTestManager.bgm_test.bgm_path()
	if path == "" or not _ensure_bgm_stream(path):
		return

	# 先让流跑起来
	_resume_or_start_bgm()

	# 结算弹窗 / 音效闪避 / 广告，任一成立就暂停
	_bgm_player.stream_paused = _bgm_paused_for_dialog or _bgm_ducking or _bgm_paused_for_ad


# BGM 该不该响：总闸开过 + AB 分组启用了 BGM + 存档音乐开关为开
func _should_play_bgm() -> bool:
	return _bgm_started and ABTestManager.bgm_test.is_enabled() and GameState.is_music_on()


# 续播：只有在既没在播、也没被暂停时才 play()，避免暂停中被重置播放进度
func _resume_or_start_bgm() -> void:
	if not _bgm_player.playing and not _bgm_player.stream_paused:
		_bgm_player.play()


# 确保 BGM 流就位：路径没变且已加载就直接复用，否则重新 load 并强制循环
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
