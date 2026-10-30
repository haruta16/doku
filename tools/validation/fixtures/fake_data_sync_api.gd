extends DataSyncApi
var uploads: Array[Dictionary] = []
var remote: Dictionary = {"core": {"current_level": 99, "current_strategy": 3, "tool_hint": 17}, "rank": {"period_count": 7}}
var after_upload: Callable
func _init() -> void:
	super(null)
func upload(_bearer: String, data: String, _schema: String, _code: int, _extra: String = "") -> ApiResponse:
	uploads.append(JSON.parse_string(data))
	if after_upload.is_valid():
		after_upload.call()
	return ApiResponse.received(200, ApiConfig.CODE_SYNC_CODE_TOO_LOW if uploads.size() == 1 else ApiConfig.CODE_OK, "fixture", {}, 0)
func download(_bearer: String) -> ApiResponse:
	return ApiResponse.received(200, ApiConfig.CODE_OK, "fixture", {"game_data": JSON.stringify(remote), "sync_code": 4}, 0)
