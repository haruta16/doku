## 与 Python 发布器共用地址样本，签出的频道地址必须符合客户端的同一合同。
extends SceneTree

const Channel = preload("res://scripts/framework/content/content_channel.gd")


func _initialize() -> void:
	var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/validation/fixtures/content_channel_urls.json"))
	if not cases is Array or cases.is_empty():
		push_error("TEST_FAILED: content URL cases must be a nonempty array")
		print("CONTENT_CHANNEL_URL_TEST checks=1 failures=1")
		quit(1)
		return
	var checks: int = 1
	var failures: int = 0
	for entry: Variant in cases:
		checks += 1
		if not entry is Dictionary or not entry.get("url") is String or not entry.get("local") is bool or not entry.get("allowed") is bool:
			failures += 1
			push_error("TEST_FAILED: malformed content URL case")
		elif Channel.allowed_url(entry.url, entry.local) != entry.allowed:
			failures += 1
			push_error("CONTENT_URL_FAILED: " + str(entry.url))
	print("CONTENT_CHANNEL_URL_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
