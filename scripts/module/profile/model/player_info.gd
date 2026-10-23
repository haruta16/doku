## 排行榜与资料界面共用的身份模型；统一昵称、头像和头像框，使用固定标识区分本机玩家。

class_name PlayerInfo
extends RefCounted

const LOCAL_PLAYER_ID := "self"

var nickname: String = ""
var avatar_id: int = 0
var frame: AvatarFrame = AvatarFrame.new()
var player_id: String = ""
var level_index: int = 0
var is_robot: bool = false


func is_self() -> bool:
	return player_id == LOCAL_PLAYER_ID


## 将当前模型转换为字典，供保存或传输层使用；本方法本身不写磁盘。
func to_dict() -> Dictionary:
	return {
		"nickname": nickname,
		"avatar_id": avatar_id,
		"frame": frame.to_dict(),
		"player_id": player_id,
		"level_index": level_index,
		"is_robot": is_robot,
	}


## 从字典恢复模型，并按这里定义的默认值兼容缺失字段；返回对象尚未自动写回存档。
static func from_dict(d: Dictionary) -> PlayerInfo:
	var p := PlayerInfo.new()
	p.nickname = str(d.get("nickname", ""))
	p.avatar_id = int(d.get("avatar_id", 0))
	p.frame = AvatarFrame.from_dict(d.get("frame", {}))
	p.player_id = str(d.get("player_id", ""))
	p.level_index = int(d.get("level_index", 0))
	p.is_robot = bool(d.get("is_robot", false))
	return p
