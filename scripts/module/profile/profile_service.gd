## 玩家资料的唯一写入入口；管理昵称、头像框、服装试用与永久所有权，并写入 user://profile.cfg。
## 界面通过变化信号刷新；云同步通过同一份模型覆盖资料，避免页面各自维护持有状态。

extends Node

const SAVE_PATH := "user://profile.cfg"
const _MAX_NICKNAME_LEN: int = 12

const _NICK_B64_PREFIX := "b64:"

signal avatar_frame_changed

signal profile_saved

signal costume_changed

var _data: ProfileData = ProfileData.new()
var _loaded: bool = false


## 读入资料并初始化默认外观，再接入全量重置和云同步注册流程。
func _ready() -> void:
	_ensure_loaded()

	GameState.all_data_reset.connect(reset)

	DataSyncRegistry.register(self)


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load()
	_ensure_initialized()


func reset() -> void:
	_data = ProfileData.new()
	_ensure_initialized()


func get_nickname() -> String:
	return _data.nickname


func set_nickname(new_name: String) -> void:
	var n := new_name.strip_edges()
	if n.is_empty():
		return
	if n.length() > _MAX_NICKNAME_LEN:
		n = n.substr(0, _MAX_NICKNAME_LEN)
	if n == _data.nickname:
		return
	_data.nickname = n
	_data.identity_customized = true
	_save()
	avatar_frame_changed.emit()


func get_avatar_id() -> int:
	return _data.avatar_id


func set_avatar_id(id: int) -> void:
	if not ProfileCatalog.is_valid_avatar(id) or not is_avatar_owned(id):
		return
	if id == _data.avatar_id:
		return
	_data.avatar_id = id
	_data.identity_customized = true
	_save()
	avatar_frame_changed.emit()


func get_frame_id() -> int:
	return _data.frame_id


func set_frame_id(id: int) -> void:
	if not ProfileCatalog.is_valid_frame(id):
		return
	if not is_frame_unlocked(id):
		return
	if id == _data.frame_id:
		return
	_data.frame_id = id
	_data.identity_customized = true
	_save()
	avatar_frame_changed.emit()


func get_frame_form() -> int:
	_ensure_loaded()
	return _data.frame_form


func set_frame_form(form: int) -> void:
	_ensure_loaded()
	if not ProfileCatalog.is_form_unlocked(form, get_first_place_wins()):
		return
	if _data.frame_form == form:
		return
	_data.frame_form = form
	_data.identity_customized = true
	_save()
	avatar_frame_changed.emit()


func get_first_place_wins() -> int:
	return maxi(0, get_frame_count(ProfileCatalog.FIRST_PLACE_FRAME_ID))


func get_max_unlocked_form() -> int:
	return ProfileCatalog.form_for_wins(get_first_place_wins())


func is_frame_tier_backfill_done() -> bool:
	_ensure_loaded()
	return _data.frame_tier_backfill_done


func mark_frame_tier_backfill_done() -> void:
	_ensure_loaded()
	if _data.frame_tier_backfill_done:
		return
	_data.frame_tier_backfill_done = true
	_save()


func get_pending_frame_tier_form(wins: int = -1) -> int:
	_ensure_loaded()
	var effective_wins: int = get_first_place_wins() if wins < 0 else wins
	return _data.get_pending_frame_tier_form(effective_wins)


func mark_frame_tier_presented(form: int) -> void:
	_ensure_loaded()
	if not ProfileCatalog.is_form_unlocked(form, get_first_place_wins()):
		return
	if form <= _data.frame_tier_presented_form and _data.frame_tier_backfill_done:
		return
	_data.frame_tier_presented_form = maxi(_data.frame_tier_presented_form, form)
	_data.frame_tier_backfill_done = true
	_save()


func set_frame_red_dot() -> void:
	_ensure_loaded()
	if _data.frame_red_dot:
		return
	_data.frame_red_dot = true
	_save()
	avatar_frame_changed.emit()


## 校验头像框编号并累加获得次数；首次解锁设置红点，保存后通知界面刷新。
func grant_frame(frame_id: int, times: int = 1) -> bool:
	_ensure_loaded()
	if not ProfileCatalog.is_valid_frame(frame_id) or times <= 0:
		return false
	var f: AvatarFrame = _data.owned_frames.get(frame_id, null)
	if f == null:
		f = AvatarFrame.new(frame_id, ProfileCatalog.default_frame_count(frame_id))
		_data.owned_frames[frame_id] = f

	var before: int = f.acquired_count
	f.acquired_count = maxi(f.acquired_count, 0) + times

	if before < 1 and f.acquired_count >= 1:
		_data.frame_red_dot = true
	_save()
	avatar_frame_changed.emit()
	return true


func cheat_revoke_frame(frame_id: int) -> void:
	_ensure_loaded()
	if not _data.owned_frames.has(frame_id):
		return
	_data.owned_frames.erase(frame_id)
	if _data.frame_id == frame_id:
		_data.frame_id = ProfileCatalog.CLASSIC_FRAME_IDS[0]
	_save()
	avatar_frame_changed.emit()


func cheat_revoke_avatar(avatar_id: int) -> void:
	_ensure_loaded()
	if not _data.owned_avatars.has(avatar_id):
		return
	_data.owned_avatars.erase(avatar_id)
	if _data.avatar_id == avatar_id:
		_data.avatar_id = ProfileCatalog.AVATAR_IDS[0]
	_save()
	avatar_frame_changed.emit()


func is_frame_unlocked(frame_id: int) -> bool:
	return _data.owned_frames.has(frame_id)


func is_avatar_owned(avatar_id: int) -> bool:
	if ProfileCatalog.is_default_owned_avatar(avatar_id):
		return ProfileCatalog.is_valid_avatar(avatar_id)
	return _data.owned_avatars.has(avatar_id)


## 把有效且未持有的头像加入所有权列表，保存并设置新内容提示。
func grant_avatar(avatar_id: int) -> bool:
	_ensure_loaded()
	if (
		not ProfileCatalog.is_valid_avatar(avatar_id)
		or ProfileCatalog.is_default_owned_avatar(avatar_id)
	):
		return false
	if _data.owned_avatars.has(avatar_id):
		return false
	_data.owned_avatars.append(avatar_id)
	_data.avatar_red_dot = true
	_save()
	avatar_frame_changed.emit()
	return true


func get_frame_count(frame_id: int) -> int:
	var f: AvatarFrame = _data.owned_frames.get(frame_id, null)
	return f.acquired_count if f != null else ProfileCatalog.default_frame_count(frame_id)


func get_frame_info(frame_id: int) -> Dictionary:
	return {"unlocked": is_frame_unlocked(frame_id), "count": get_frame_count(frame_id)}


func has_frame_red_dot() -> bool:
	return _data.frame_red_dot


func clear_frame_red_dot() -> void:
	if not _data.frame_red_dot:
		return
	_data.frame_red_dot = false
	_save()
	avatar_frame_changed.emit()


func has_avatar_red_dot() -> bool:
	return _data.avatar_red_dot


func clear_avatar_red_dot() -> void:
	if not _data.avatar_red_dot:
		return
	_data.avatar_red_dot = false
	_save()
	avatar_frame_changed.emit()


func is_identity_default() -> bool:
	_ensure_loaded()
	return not _data.identity_customized


func notify_profile_saved() -> void:
	profile_saved.emit()


## 把当前资料组装成排行榜与头像组件共用的 PlayerInfo，避免 UI 直接依赖存档字段。
func get_player_info() -> PlayerInfo:
	var info := PlayerInfo.new()
	info.nickname = _data.nickname
	info.avatar_id = _data.avatar_id

	info.frame = AvatarFrame.new(_data.frame_id, get_frame_count(_data.frame_id), get_frame_form())
	info.player_id = PlayerInfo.LOCAL_PLAYER_ID
	info.is_robot = false
	return info


func get_avatar_ids() -> Array:
	return ProfileCatalog.AVATAR_IDS.duplicate()


func get_frame_ids() -> Array:
	return ProfileCatalog.CLASSIC_FRAME_IDS.duplicate()


func list_avatar_ids(include_event_ids: Array[int] = []) -> Array:
	var ids: Array = ProfileCatalog.AVATAR_IDS.duplicate()
	var event_ids: Array[int] = ProfileCatalog.EVENT_AVATAR_IDS
	for id in event_ids:
		if is_avatar_owned(id) or include_event_ids.has(id):
			ids.append(id)
	return ids


func get_frame_groups(include_event_ids: Array[int] = []) -> Array:
	var groups: Array = [
		{"group": &"leaderboard", "ids": ProfileCatalog.LEADERBOARD_FRAME_IDS.duplicate()},
	]
	var event_ids: Array = []
	var catalog_event_ids: Array[int] = ProfileCatalog.EVENT_FRAME_IDS
	for id in catalog_event_ids:
		if is_frame_unlocked(id) or include_event_ids.has(id):
			event_ids.append(id)
	if not event_ids.is_empty():
		groups.append({"group": &"event", "ids": event_ids})
	groups.append({"group": &"classic", "ids": ProfileCatalog.CLASSIC_FRAME_IDS.duplicate()})
	return groups


func _ensure_initialized() -> void:
	var rng := _rng()
	var dirty := false

	for cid in ProfileCatalog.CLASSIC_FRAME_IDS:
		if not _data.owned_frames.has(cid):
			_data.owned_frames[cid] = AvatarFrame.new(cid, ProfileCatalog.default_frame_count(cid))
			dirty = true

	if not ProfileCatalog.is_valid_avatar(_data.avatar_id) or not is_avatar_owned(_data.avatar_id):
		_data.avatar_id = ProfileCatalog.AVATAR_IDS[rng.randi_range(
			0, ProfileCatalog.AVATAR_IDS.size() - 1
		)]
		dirty = true

	if not is_frame_unlocked(_data.frame_id):
		_data.frame_id = ProfileCatalog.CLASSIC_FRAME_IDS[rng.randi_range(
			0, ProfileCatalog.CLASSIC_FRAME_IDS.size() - 1
		)]
		dirty = true

	if _data.nickname.strip_edges().is_empty():
		_data.nickname = ProfileNickname.random_default(rng)
		dirty = true
	if not _data.initialized:
		_data.initialized = true
		dirty = true
	if dirty:
		_save()


func cloud_save_id() -> String:
	return "profile"


func export_cloud_data() -> Dictionary:
	_ensure_loaded()
	var frames: Array = []
	for fid in _data.owned_frames:
		if int(fid) >= ProfileCatalog.ACQUIRE_THRESHOLD:
			frames.append((_data.owned_frames[fid] as AvatarFrame).to_dict())
	return {
		"nickname": _NICK_B64_PREFIX + Marshalls.utf8_to_base64(_data.nickname),
		"avatar_id": _data.avatar_id,
		"frame_id": _data.frame_id,
		"identity_customized": _data.identity_customized,
		"owned_frames": frames,
		"frame_form": _data.frame_form,
		"frame_tier_backfill_done": _data.frame_tier_backfill_done,
		"frame_tier_presented_form": _data.frame_tier_presented_form,
		"costume_id": _data.costume_id,
		"costume_trials": _data.costume_trials.duplicate(true),
		"costume_unlock_day": _data.costume_unlock_day,
		"costume_unlock_id": _data.costume_unlock_id,
		"costume_tutorial_shown": _data.costume_tutorial_shown,
		"owned_avatars": _data.owned_avatars.duplicate(),
		"costume_owned": _data.costume_owned.duplicate(),
	}


## 只有上下文决定采用云端时才覆盖本地资料；随后保存并发出变化信号。
func merge_cloud_data(cloud_data: Dictionary, ctx: MergeContext) -> void:
	_ensure_loaded()

	if not ctx.use_cloud:
		return
	_overwrite_from_cloud(cloud_data)
	_save()
	avatar_frame_changed.emit()


func _overwrite_from_cloud(cloud_data: Dictionary) -> void:
	if cloud_data.has("nickname"):
		_data.nickname = _decode_cloud_nick(str(cloud_data["nickname"]))

	if cloud_data.has("owned_avatars"):
		_data.owned_avatars = ProfileData.read_id_list(cloud_data["owned_avatars"])
	var rav: int = int(cloud_data.get("avatar_id", _data.avatar_id))
	if ProfileCatalog.is_valid_avatar(rav) and is_avatar_owned(rav):
		_data.avatar_id = rav
	_data.identity_customized = bool(
		cloud_data.get("identity_customized", _data.identity_customized)
	)

	var to_erase: Array = []
	for fid in _data.owned_frames:
		if int(fid) >= ProfileCatalog.ACQUIRE_THRESHOLD:
			to_erase.append(fid)
	for fid in to_erase:
		_data.owned_frames.erase(fid)
	var remote_frames: Array = cloud_data.get("owned_frames", [])
	for frame_data in remote_frames:
		var remote_frame := AvatarFrame.from_dict(frame_data)
		if remote_frame.id >= ProfileCatalog.ACQUIRE_THRESHOLD:
			_data.owned_frames[remote_frame.id] = remote_frame

	_data.frame_id = int(cloud_data.get("frame_id", _data.frame_id))
	_data.frame_form = int(cloud_data.get("frame_form", _data.frame_form))
	_data.frame_tier_backfill_done = bool(
		cloud_data.get("frame_tier_backfill_done", _data.frame_tier_backfill_done)
	)
	_data.frame_tier_presented_form = ProfileData.resolve_frame_tier_presented_form(
		cloud_data, get_first_place_wins()
	)

	_clamp_frame_form()
	_overwrite_costumes_from_cloud(cloud_data)


func _overwrite_costumes_from_cloud(cloud_data: Dictionary) -> void:
	if cloud_data.has("costume_trials"):
		_data.costume_trials.clear()
		var remote_trials: Array = cloud_data.get("costume_trials", [])
		for raw in remote_trials:
			if raw is Dictionary:
				var cid: int = int((raw as Dictionary).get("id", 0))
				var exp_at: int = int((raw as Dictionary).get("expire", 0))
				if cid > 0 and exp_at > 0:
					_data.costume_trials.append({"id": cid, "expire": exp_at})

	_data.costume_unlock_day = int(cloud_data.get("costume_unlock_day", _data.costume_unlock_day))
	_data.costume_unlock_id = int(cloud_data.get("costume_unlock_id", _data.costume_unlock_id))
	_data.costume_tutorial_shown = bool(
		cloud_data.get("costume_tutorial_shown", _data.costume_tutorial_shown)
	)
	if cloud_data.has("costume_owned"):
		_data.costume_owned = ProfileData.read_id_list(cloud_data["costume_owned"])
	_data.costume_id = int(cloud_data.get("costume_id", _data.costume_id))

	_prune_expired_trials()
	if _data.costume_id != 0 and not _is_costume_held(_data.costume_id):
		_data.costume_id = CostumeCatalog.DEFAULT_COSTUME_ID


func _decode_cloud_nick(raw: String) -> String:
	if raw.begins_with(_NICK_B64_PREFIX):
		return Marshalls.base64_to_utf8(raw.substr(_NICK_B64_PREFIX.length()))
	return raw


func costume_now() -> int:
	return int(Time.get_unix_time_from_system())


## 移除已到期的试用记录；试用时间是绝对到期时刻，退出游戏不会暂停倒计时。
func _prune_expired_trials() -> bool:
	var now: int = costume_now()
	var kept: Array = []
	for entry in _data.costume_trials:
		if int((entry as Dictionary).get("expire", 0)) > now:
			kept.append(entry)
	if kept.size() == _data.costume_trials.size():
		return false
	_data.costume_trials = kept
	return true


## 更新过期试用与当前装备状态，保证已失效的服装不会继续作为有效装备。
func _refresh_costume_state() -> void:
	var before_equipped: int = _data.costume_id
	var pruned: bool = _prune_expired_trials()

	if _data.costume_id != 0 and not _is_costume_held(_data.costume_id):
		_data.costume_id = CostumeCatalog.DEFAULT_COSTUME_ID
	if pruned or before_equipped != _data.costume_id:
		_save()
		costume_changed.emit()


func _is_costume_held(id: int) -> bool:
	if CostumeCatalog.is_default_owned(id) or _data.costume_owned.has(id):
		return true
	var now: int = costume_now()
	for entry in _data.costume_trials:
		var dict_entry: Dictionary = entry
		if int(dict_entry.get("id", 0)) == id and int(dict_entry.get("expire", 0)) > now:
			return true
	return false


func is_costume_held(id: int) -> bool:
	_ensure_loaded()
	_refresh_costume_state()
	return _is_costume_held(id)


func is_costume_owned(id: int) -> bool:
	_ensure_loaded()
	return CostumeCatalog.is_default_owned(id) or _data.costume_owned.has(id)


## 只为符合条件的活动服装创建试用到期记录；永久持有或已有试用时不会重复发放。
func grant_costume_trial(id: int, start_at: int) -> bool:
	_ensure_loaded()
	_refresh_costume_state()
	if not CostumeCatalog.is_event(id) or _data.costume_owned.has(id):
		return false
	for entry in _data.costume_trials:
		var dict_entry: Dictionary = entry
		if int(dict_entry.get("id", 0)) == id:
			return false
	_data.costume_trials.append({"id": id, "expire": start_at + CostumeCatalog.TRIAL_DURATION_SEC})
	_data.costume_red_dot = true
	_save()
	costume_changed.emit()
	return true


## 授予永久所有权并移除同服装的临时试用，避免同一件服装存在两种互相矛盾的持有状态。
func grant_costume_permanent(id: int) -> bool:
	_ensure_loaded()
	if not CostumeCatalog.is_event(id) or _data.costume_owned.has(id):
		return false
	_data.costume_owned.append(id)
	var kept: Array = []
	for entry in _data.costume_trials:
		if int((entry as Dictionary).get("id", 0)) != id:
			kept.append(entry)
	_data.costume_trials = kept
	_data.costume_red_dot = true
	_save()
	costume_changed.emit()
	return true


func costume_trial_remaining_sec(id: int) -> int:
	_ensure_loaded()
	_refresh_costume_state()
	var now: int = costume_now()
	for entry in _data.costume_trials:
		var dict_entry: Dictionary = entry
		if int(dict_entry.get("id", 0)) == id:
			return maxi(0, int(dict_entry.get("expire", 0)) - now)
	return 0


func get_costume_id() -> int:
	_ensure_loaded()
	_refresh_costume_state()
	if _data.costume_id != 0 and _is_costume_held(_data.costume_id):
		return _data.costume_id
	return CostumeCatalog.DEFAULT_COSTUME_ID


func set_costume_id(id: int) -> bool:
	_ensure_loaded()
	_refresh_costume_state()
	if not CostumeCatalog.is_valid(id) or not _is_costume_held(id):
		return false
	if _data.costume_id == id:
		return true
	_data.costume_id = id
	_save()
	costume_changed.emit()
	return true


func clear_costume_equip() -> void:
	_ensure_loaded()
	if get_costume_id() == CostumeCatalog.DEFAULT_COSTUME_ID:
		return
	_data.costume_id = CostumeCatalog.DEFAULT_COSTUME_ID
	_save()
	costume_changed.emit()


## 若今日已经解锁过服装，继续返回该编号；否则按日期与持有列表挑选今日候选。
func get_today_costume() -> int:
	_ensure_loaded()
	_refresh_costume_state()
	if has_unlocked_today_costume() and CostumeCatalog.is_trial(_data.costume_unlock_id):
		return _data.costume_unlock_id
	return CostumeCatalog.costume_for_day_skipping(
		CostumeCatalog.today_day_offset(), _held_costume_ids()
	)


func _held_costume_ids() -> Array[int]:
	var held: Array[int] = []
	var all_ids: Array[int] = CostumeCatalog.all_ids()
	for id in all_ids:
		if _is_costume_held(id):
			held.append(id)
	return held


func has_unlocked_today_costume() -> bool:
	_ensure_loaded()
	return _data.costume_unlock_day == CostumeCatalog.today_day_offset()


## 检查每日领取限制后授予今日试用，并保存领取日期和编号；重复进入页面不会再次领取。
func unlock_today_costume() -> bool:
	_ensure_loaded()
	_refresh_costume_state()
	if has_unlocked_today_costume():
		return false
	var day: int = CostumeCatalog.today_day_offset()

	var id: int = CostumeCatalog.costume_for_day_skipping(day, _held_costume_ids())
	if not CostumeCatalog.is_trial(id):
		return false
	var expire_at: int = costume_now() + CostumeCatalog.TRIAL_DURATION_SEC

	var found: bool = false
	for entry in _data.costume_trials:
		var dict_entry: Dictionary = entry
		if int(dict_entry.get("id", 0)) == id:
			dict_entry["expire"] = maxi(int(dict_entry.get("expire", 0)), expire_at)
			found = true
			break
	if not found:
		_data.costume_trials.append({"id": id, "expire": expire_at})
	_data.costume_unlock_day = day

	_data.costume_unlock_id = id
	_data.costume_red_dot = true
	_save()
	costume_changed.emit()
	return true


func has_costume_red_dot() -> bool:
	_ensure_loaded()
	return _data.costume_red_dot


func clear_costume_red_dot() -> void:
	_ensure_loaded()
	if not _data.costume_red_dot:
		return
	_data.costume_red_dot = false
	_save()
	costume_changed.emit()


func is_costume_tutorial_shown() -> bool:
	_ensure_loaded()
	return _data.costume_tutorial_shown


func mark_costume_tutorial_shown() -> void:
	_ensure_loaded()
	if _data.costume_tutorial_shown:
		return
	_data.costume_tutorial_shown = true
	_save()


func cheat_clear_costumes() -> void:
	_ensure_loaded()
	_data.costume_trials.clear()
	_data.costume_unlock_day = -1

	_data.costume_unlock_id = 0
	_data.costume_id = CostumeCatalog.DEFAULT_COSTUME_ID
	_data.costume_red_dot = false
	_save()
	costume_changed.emit()


func cheat_hold_all_costumes() -> int:
	_ensure_loaded()
	_refresh_costume_state()
	var expire_at: int = costume_now() + CostumeCatalog.TRIAL_DURATION_SEC
	var added: int = 0
	var trial_ids: Array[int] = CostumeCatalog.TRIAL_COSTUME_IDS
	for id in trial_ids:
		var found: bool = false
		for entry in _data.costume_trials:
			var dict_entry: Dictionary = entry
			if int(dict_entry.get("id", 0)) == id:
				dict_entry["expire"] = maxi(int(dict_entry.get("expire", 0)), expire_at)
				found = true
				break
		if not found:
			_data.costume_trials.append({"id": id, "expire": expire_at})
			added += 1
	_data.costume_red_dot = true
	_save()
	costume_changed.emit()
	return added


func cheat_clear_event_costumes() -> void:
	_ensure_loaded()
	var event_ids: Array[int] = CostumeCatalog.EVENT_COSTUME_IDS
	var kept: Array = []
	for entry in _data.costume_trials:
		if not event_ids.has(int((entry as Dictionary).get("id", 0))):
			kept.append(entry)
	_data.costume_trials = kept
	for id in event_ids:
		_data.costume_owned.erase(id)
	if CostumeCatalog.is_event(_data.costume_id):
		_data.costume_id = CostumeCatalog.DEFAULT_COSTUME_ID
	_save()
	costume_changed.emit()


func cheat_reset_costume_tutorial() -> void:
	_ensure_loaded()
	if not _data.costume_tutorial_shown:
		return
	_data.costume_tutorial_shown = false
	_save()


func cheat_expire_costumes() -> void:
	_ensure_loaded()
	for entry in _data.costume_trials:
		(entry as Dictionary)["expire"] = 0
	_save()
	_refresh_costume_state()
	costume_changed.emit()


## 将 ProfileData 写入资料配置文件；同步请求由相应的业务通知触发，而非 UI 直接上传。
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "data", _data.to_dict())
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var d: Dictionary = cfg.get_value("profile", "data", {})
	if d.is_empty():
		return
	_data = ProfileData.from_dict(d)
	_clamp_frame_form()


## 按冠军框累计次数限制当前形态；存档中的形态超过解锁门槛时回退为合法值。
func _clamp_frame_form() -> void:
	var wins: int = maxi(0, get_frame_count(ProfileCatalog.FIRST_PLACE_FRAME_ID))
	if ProfileCatalog.is_form_unlocked(_data.frame_form, wins):
		return
	var clamped: int = maxi(0, ProfileCatalog.form_for_wins(wins))
	push_warning(
		(
			"ProfileService: frame_form=%d 与 wins=%d 不匹配(老云存档缺键/脏档)，clamp 到 %d"
			% [_data.frame_form, wins, clamped]
		)
	)
	_data.frame_form = clamped


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng
