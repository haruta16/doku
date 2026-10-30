## 实际播放器交叠闪避、显式停止以及暂停时音乐开关的恢复。
extends SceneTree
var checks: int = 0
var failures: int = 0
var sound: Node
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	sound = root.get_node("SoundManager")
	game = root.get_node("GameState")
	root.get_node("ABTestManager").bgm_test.set_debug_override(4)
	game.set_sound_on(true)
	game.set_music_on(true)
	sound.start_bgm()
	_check(sound._bgm_player.playing, "configured music starts")
	var first_finished := {"done": false}
	sound._players[sound.Kind.BOARD_ENTER].finished.connect(func() -> void: first_finished.done = true, CONNECT_ONE_SHOT)
	sound.play(sound.Kind.BOARD_ENTER)
	await create_timer(0.4).timeout
	sound.play(sound.Kind.LEVEL_WIN)
	var deadline: int = Time.get_ticks_msec() + 2000
	while not first_finished.done and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(first_finished.done, "first effect delivered its actual completion signal")
	_check(sound._players[sound.Kind.LEVEL_WIN].playing, "second ducking effect remains playing after first ends")
	_check(sound._bgm_player.stream_paused, "first effect ending cannot release the second effect's ducking")
	sound.stop(sound.Kind.LEVEL_WIN)
	_check(not sound._bgm_player.stream_paused, "stopping last ducking effect releases music")
	sound.play(sound.Kind.BOARD_ENTER)
	sound.stop(sound.Kind.BOARD_ENTER)
	_check(not sound._bgm_player.stream_paused, "explicit stop does not leave music permanently ducked")
	sound.set_bgm_paused(true)
	game.set_music_on(false)
	sound.refresh_bgm()
	sound.set_bgm_paused(false)
	game.set_music_on(true)
	sound.refresh_bgm()
	_check(sound._bgm_player.playing and not sound._bgm_player.stream_paused, "music resumes after disabling while paused")
	var playback: AudioStreamPlayback = sound._bgm_player.get_stream_playback()
	sound.set_bgm_paused(true)
	sound.play(sound.Kind.BOARD_ENTER)
	sound.play(sound.Kind.BOARD_ENTER)
	sound.stop(sound.Kind.MARK_CAT)
	_check(sound._bgm_player.stream_paused, "unrelated effect stop does not release dialog or ducking")
	sound.stop(sound.Kind.BOARD_ENTER)
	_check(sound._bgm_player.stream_paused, "stopping a replayed effect preserves dialog pause")
	root.get_node("UniKitManager").ad_shown.emit("audio_test")
	sound.set_bgm_paused(false)
	_check(sound._bgm_player.stream_paused, "dialog ending preserves active ad pause")
	_check(sound._bgm_player.get_stream_playback() == playback, "overlapping pause reasons retain the existing playback position")
	root.get_node("ABTestManager").bgm_test.set_debug_override(2)
	sound.refresh_bgm()
	_check(sound._bgm_player.has_stream_playback() and sound._bgm_player.stream_paused, "changing music while paused retains an active paused playback")
	root.get_node("UniKitManager").ad_closed.emit("audio_test")
	_check(sound._bgm_player.playing and not sound._bgm_player.stream_paused, "last pause reason releases switched music without restarting settings")
	sound._bgm_player.stop()
	await create_timer(0.2).timeout
	print("PRODUCT AUDIO LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + label)
