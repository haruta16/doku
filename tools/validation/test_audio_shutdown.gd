## Fixture shutdown is successful only after observed audio resource release.
extends SceneTree

const AudioDrain = preload("res://tools/validation/fixtures/audio_shutdown.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ProjectSettings.get_setting("test/audio_shutdown_isolated", false) and not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: isolated validation fixture required")
		quit(2)
		return
	await _test_observed_release()
	await _test_retained_reference_fails_closed()
	await _test_new_player_during_drain()
	var final_result: Dictionary = await AudioDrain.drain(self)
	_check(final_result.ok, "all test-owned audio really released before engine exit")
	print("AUDIO SHUTDOWN TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _new_player(name_hint: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = name_hint
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 8000
	var samples := PackedByteArray()
	samples.resize(16000)
	stream.data = samples
	player.stream = stream
	root.add_child(player)
	return player

func _test_observed_release() -> void:
	var player := _new_player("ObservedAudioRelease")
	player.play()
	var stream_ref: WeakRef = weakref(player.stream)
	var playback_ref: WeakRef = weakref(player.get_stream_playback())
	var result: Dictionary = await AudioDrain.drain(self)
	_check(result.ok and result.remaining.is_empty(), "released audio passes the shutdown protocol")
	_check(int(result.tracked_references) >= 2, "both stream and active playback are observed")
	_check(stream_ref.get_ref() == null, "stream WeakRef actually expired")
	_check(playback_ref.get_ref() == null, "playback WeakRef actually expired")
	_check(player.stream == null and not player.playing, "player stopped and detached before accepted release")
	player.free()

func _test_retained_reference_fails_closed() -> void:
	var player := _new_player("DeliberatelyRetainedAudio")
	player.play()
	var retained: AudioStream = player.stream
	var retained_ref: WeakRef = weakref(retained)
	var retained_id: int = retained.get_instance_id()
	var result: Dictionary = await AudioDrain.drain(self, 25)
	_check(not result.ok, "deadline cannot turn a retained audio stream into success")
	_check(int(result.elapsed_ms) >= 25 and int(result.polls) > 0, "retained reference reaches the bounded deadline")
	var found: bool = false
	for remaining: Dictionary in result.remaining:
		if int(remaining.instance_id) == retained_id and remaining.role == "stream":
			found = true
	_check(found and retained_ref.get_ref() != null, "failure identifies the actually retained stream")
	_check(player.stream == null and not player.playing, "stopped player alone is not a release proof")
	# The artificial owner releases its reference, then retry observes actual cleanup.
	player.stream = retained
	retained = null
	var cleaned: Dictionary = await AudioDrain.drain(self)
	_check(cleaned.ok and retained_ref.get_ref() == null, "release of deliberate ownership allows a real successful retry")
	player.free()

func _test_new_player_during_drain() -> void:
	var player := _new_player("OriginalAudioBeforeDrain")
	var retained: AudioStream = player.stream
	var created: Array[AudioStreamPlayer] = []
	_create_late_player.call_deferred(created)
	var result: Dictionary = await AudioDrain.drain(self, 25)
	_check(created.size() == 1, "a new player appeared during the asynchronous drain")
	var late: AudioStreamPlayer = created[0] if not created.is_empty() else null
	_check(not result.ok and late != null and str(late.get_path()) in result.reactivated, "final tree scan rejects a newly attached player outside the original snapshot")
	if late != null:
		late.free()
	created.clear()
	player.stream = retained
	retained = null
	var cleaned: Dictionary = await AudioDrain.drain(self)
	_check(cleaned.ok, "negative fixture releases all deliberate references and players")
	player.free()

func _create_late_player(created: Array[AudioStreamPlayer]) -> void:
	created.append(_new_player("LateAudioDuringDrain"))

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("TEST_FAILED: ", message)
