extends Node







enum Kind{
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

var _players: Dictionary = {}
var _silent: bool = false






var _bgm_player: AudioStreamPlayer
var _bgm_started: bool = false
var _bgm_paused_for_dialog: bool = false
var _bgm_ducking: bool = false
var _bgm_paused_for_ad: bool = false
var _bgm_stream_path: String = ""

const _BGM_DUCK_KINDS: Array = [Kind.BOARD_ENTER, Kind.LEVEL_WIN]


const _COMBO_VOICE_PATHS: Dictionary = {
    3: "res://assets/audio/sfx/combo_nice.ogg", 
    4: "res://assets/audio/sfx/combo_great.ogg", 
    5: "res://assets/audio/sfx/combo_perfect.ogg", 
    6: "res://assets/audio/sfx/combo_excellent.ogg", 
    7: "res://assets/audio/sfx/combo_amazing.ogg", 
    8: "res://assets/audio/sfx/combo_unbelievable.ogg", 
}


const _COMBO_VOICE_FEMALE_PATHS: Dictionary = {
    3: "res://assets/audio/sfx/combo_nice_a.ogg", 
    4: "res://assets/audio/sfx/combo_great_a.ogg", 
    5: "res://assets/audio/sfx/combo_perfect_a.ogg", 
    6: "res://assets/audio/sfx/combo_excellent_a.ogg", 
    7: "res://assets/audio/sfx/combo_amazing_a.ogg", 
    8: "res://assets/audio/sfx/combo_unbelievable_a.ogg", 
}
var _combo_voice_players: Dictionary = {}
var _combo_voice_female_players: Dictionary = {}



var _combo_voice_path_players: Dictionary = {}

func _ready() -> void :
    for kind in _SOUND_PATHS.keys():
        var path: String = _SOUND_PATHS[kind]
        var stream: AudioStream = load(path) as AudioStream
        if stream == null:
            push_error("SoundManager: failed to load %s" % path)
            continue
        var player: = AudioStreamPlayer.new()
        player.stream = stream
        player.bus = "Master"
        player.max_polyphony = _POLYPHONY.get(kind, 1)
        add_child(player)
        _players[kind] = player
    for level: int in _COMBO_VOICE_PATHS.keys():
        var path: String = _COMBO_VOICE_PATHS[level]
        var stream: AudioStream = load(path) as AudioStream
        if stream == null:
            continue
        var player: = AudioStreamPlayer.new()
        player.stream = stream
        player.bus = "Master"
        add_child(player)
        _combo_voice_players[level] = player
    for level: int in _COMBO_VOICE_FEMALE_PATHS.keys():
        var path: String = _COMBO_VOICE_FEMALE_PATHS[level]
        var stream: AudioStream = load(path) as AudioStream
        if stream == null:
            continue
        var player: = AudioStreamPlayer.new()
        player.stream = stream
        player.bus = "Master"
        add_child(player)
        _combo_voice_female_players[level] = player

    _bgm_player = AudioStreamPlayer.new()
    _bgm_player.bus = "Master"
    add_child(_bgm_player)



    _connect_ad_signals.call_deferred()


func play(kind: int) -> void :
    if _silent:
        return
    if not GameState.is_sound_on():
        return
    var player: AudioStreamPlayer = _players.get(kind, null)
    if player == null:
        return

    if kind in _BGM_DUCK_KINDS:
        _duck_bgm_during(player)
    player.play()



func set_silent(value: bool) -> void :
    _silent = value



func play_combo_voice(combo_count: int, female: bool = false) -> void :
    if _silent or not GameState.is_sound_on():
        return
    var level: int = mini(combo_count, 8)
    var players: Dictionary = _combo_voice_female_players if female else _combo_voice_players
    var player: AudioStreamPlayer = players.get(level, null)
    if player != null:
        player.play()





func play_combo_voice_by_path(path: String) -> void :
    if _silent:
        return
    if not GameState.is_people_on():
        return
    if path.is_empty():
        return
    var player: AudioStreamPlayer = _ensure_combo_voice_player(path)
    if player != null:
        player.play()



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
    _combo_voice_path_players[path] = player
    return player



func stop(kind: int) -> void :
    var player: AudioStreamPlayer = _players.get(kind, null)
    if player != null:
        player.stop()




func start_bgm() -> void :
    _bgm_started = true
    _apply_bgm_playback()


func set_bgm_paused(paused: bool) -> void :
    _bgm_paused_for_dialog = paused
    _apply_bgm_playback()


func refresh_bgm() -> void :
    _apply_bgm_playback()


func _connect_ad_signals() -> void :
    if UniKitManager.ad_shown.connect(_on_ad_shown_pause_bgm) != OK:
        push_error("SoundManager: failed to connect UniKitManager.ad_shown")
    if UniKitManager.ad_closed.connect(_on_ad_closed_resume_bgm) != OK:
        push_error("SoundManager: failed to connect UniKitManager.ad_closed")


func _on_ad_shown_pause_bgm(_placement_id: String) -> void :
    _bgm_paused_for_ad = true
    _apply_bgm_playback()


func _on_ad_closed_resume_bgm(_placement_id: String) -> void :
    _bgm_paused_for_ad = false
    _apply_bgm_playback()


func _duck_bgm_during(sfx_player: AudioStreamPlayer) -> void :

    if not _bgm_started:
        return
    _bgm_ducking = true
    _apply_bgm_playback()
    if not sfx_player.finished.is_connected(_on_duck_sfx_finished):
        sfx_player.finished.connect(_on_duck_sfx_finished, CONNECT_ONE_SHOT)

func _on_duck_sfx_finished() -> void :
    _bgm_ducking = false
    _apply_bgm_playback()



func _apply_bgm_playback() -> void :

    if not _should_play_bgm():
        _bgm_player.stop()
        return

    var path: String = ABTestManager.bgm_test.bgm_path()
    if path == "" or not _ensure_bgm_stream(path):
        return

    _resume_or_start_bgm()

    _bgm_player.stream_paused = _bgm_paused_for_dialog or _bgm_ducking or _bgm_paused_for_ad


func _should_play_bgm() -> bool:
    return _bgm_started and ABTestManager.bgm_test.is_enabled() and GameState.is_music_on()




func _resume_or_start_bgm() -> void :
    if not _bgm_player.playing and not _bgm_player.stream_paused:
        _bgm_player.play()



func _ensure_bgm_stream(path: String) -> bool:
    if _bgm_stream_path == path and _bgm_player.stream != null:
        return true
    if not ResourceLoader.exists(path):
        return false
    var stream: AudioStream = ResourceLoader.load(path) as AudioStream
    if stream == null:
        return false

    if "loop" in stream:
        stream.set("loop", true)
    _bgm_player.stream = stream
    _bgm_stream_path = path
    return true
