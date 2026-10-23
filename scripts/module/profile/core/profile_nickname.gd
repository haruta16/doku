## 生成初次进入时使用的随机默认昵称；昵称持久化和用户修改由 ProfileService 管理。

class_name ProfileNickname
extends RefCounted

const _LENGTH: int = 6
const _ALPHABET: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"


static func random_default(rng: RandomNumberGenerator) -> String:
	var s: String = ""
	for _i in range(_LENGTH):
		s += _ALPHABET[rng.randi_range(0, _ALPHABET.length() - 1)]
	return s
