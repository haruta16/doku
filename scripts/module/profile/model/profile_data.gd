## 玩家资料的可序列化状态：身份、持有外观、红点、试用到期时间和形态提示进度。
## 读档兼容旧数据缺失字段；目录规则和存档字段分离，便于在 ProfileService 中校验。

class_name ProfileData
extends RefCounted

var nickname: String = ""
var avatar_id: int = 0
var frame_id: int = 0

var owned_frames: Dictionary = {}
var frame_red_dot: bool = false
var initialized: bool = false

var identity_customized: bool = false

var frame_form: int = 0

var frame_tier_backfill_done: bool = false

var frame_tier_presented_form: int = -1

const _LEGACY_BACKFILL_MAX_FORM: int = 4

var costume_id: int = 0

var costume_trials: Array = []

var costume_unlock_day: int = -1

var costume_unlock_id: int = 0

var costume_red_dot: bool = false

var avatar_red_dot: bool = false

var costume_tutorial_shown: bool = false

var owned_avatars: Array[int] = []

var costume_owned: Array[int] = []


## 将当前模型转换为字典，供保存或传输层使用；本方法本身不写磁盘。
func to_dict() -> Dictionary:
	var frames: Array = []
	for fid in owned_frames:
		frames.append((owned_frames[fid] as AvatarFrame).to_dict())
	return {
		"nickname": nickname,
		"avatar_id": avatar_id,
		"frame_id": frame_id,
		"owned_frames": frames,
		"frame_red_dot": frame_red_dot,
		"initialized": initialized,
		"identity_customized": identity_customized,
		"frame_form": frame_form,
		"frame_tier_backfill_done": frame_tier_backfill_done,
		"frame_tier_presented_form": frame_tier_presented_form,
		"costume_id": costume_id,
		"costume_trials": costume_trials.duplicate(true),
		"costume_unlock_day": costume_unlock_day,
		"costume_unlock_id": costume_unlock_id,
		"costume_red_dot": costume_red_dot,
		"avatar_red_dot": avatar_red_dot,
		"costume_tutorial_shown": costume_tutorial_shown,
		"owned_avatars": owned_avatars.duplicate(),
		"costume_owned": costume_owned.duplicate(),
	}


## 从兼容存档中读入正整数编号并去重；忽略不符合预期类型的字段，避免污染持有列表。
static func read_id_list(raw: Variant) -> Array[int]:
	var ids: Array[int] = []
	if not raw is Array:
		return ids
	var values: Array = raw
	for value in values:
		if value is int or value is float:
			var id: int = int(value)
			if id > 0 and not ids.has(id):
				ids.append(id)
	return ids


## 从字典恢复模型，并按这里定义的默认值兼容缺失字段；返回对象尚未自动写回存档。
static func from_dict(data: Dictionary) -> ProfileData:
	var profile := ProfileData.new()
	profile.nickname = str(data.get("nickname", ""))
	profile.avatar_id = int(data.get("avatar_id", 0))
	profile.frame_id = int(data.get("frame_id", 0))
	var frames: Array = data.get("owned_frames", [])
	for frame_data in frames:
		var frame := AvatarFrame.from_dict(frame_data)
		if frame.id != 0:
			profile.owned_frames[frame.id] = frame
	profile.frame_red_dot = bool(data.get("frame_red_dot", false))
	profile.initialized = bool(data.get("initialized", false))
	profile.identity_customized = bool(data.get("identity_customized", false))
	profile.frame_form = int(data.get("frame_form", 0))
	profile.frame_tier_backfill_done = bool(data.get("frame_tier_backfill_done", false))
	var first_frame: AvatarFrame = profile.owned_frames.get(ProfileCatalog.FIRST_PLACE_FRAME_ID)
	var wins: int = maxi(0, first_frame.acquired_count) if first_frame != null else 0
	profile.frame_tier_presented_form = resolve_frame_tier_presented_form(data, wins)
	profile.costume_id = int(data.get("costume_id", 0))

	var trials: Array = data.get("costume_trials", [])
	for raw in trials:
		if raw is Dictionary:
			var costume: int = int((raw as Dictionary).get("id", 0))
			var expire_at: int = int((raw as Dictionary).get("expire", 0))
			if costume > 0 and expire_at > 0:
				profile.costume_trials.append({"id": costume, "expire": expire_at})
	profile.costume_unlock_day = int(data.get("costume_unlock_day", -1))
	profile.costume_unlock_id = int(data.get("costume_unlock_id", 0))
	profile.costume_red_dot = bool(data.get("costume_red_dot", false))
	profile.avatar_red_dot = bool(data.get("avatar_red_dot", false))
	profile.costume_tutorial_shown = bool(data.get("costume_tutorial_shown", false))
	profile.owned_avatars = read_id_list(data.get("owned_avatars", []))
	profile.costume_owned = read_id_list(data.get("costume_owned", []))
	return profile


func get_pending_frame_tier_form(wins: int) -> int:
	var unlocked_form: int = ProfileCatalog.form_for_wins(wins)
	return unlocked_form if unlocked_form > frame_tier_presented_form else -1


## 兼容旧版没有“已展示形态”记录的存档，确定升级提示从哪一档继续。
static func resolve_frame_tier_presented_form(data: Dictionary, wins: int) -> int:
	var unlocked_form: int = ProfileCatalog.form_for_wins(wins)
	if data.has("frame_tier_presented_form"):
		return clampi(int(data["frame_tier_presented_form"]), -1, unlocked_form)
	if not bool(data.get("frame_tier_backfill_done", false)):
		return -1
	var legacy_form: int = mini(unlocked_form, _LEGACY_BACKFILL_MAX_FORM)

	var equipped_form: int = int(data.get("frame_form", 0))
	if ProfileCatalog.is_form_unlocked(equipped_form, wins):
		legacy_form = maxi(legacy_form, equipped_form)
	return legacy_form
