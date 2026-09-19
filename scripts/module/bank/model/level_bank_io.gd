# 题库文件读取：编辑器里读 assets/editor/levels 的明文 JSON，导出后读 assets/resources/levels 的密文
# 密文 = 明文逐字节异或 _KEY（由 addons/level_bank_encryptor 生成），只防手改、不防逆向
class_name LevelBankIO
extends RefCounted

# ---- 常量：密钥与两个题库目录 ----
const _KEY: String = "meowdoku-2026-bank-secret"  # XOR 密钥，明文写死在脚本里，加解密共用
const _EDITOR_DIR: String = "res://assets/editor/levels"  # 编辑器环境：明文题库目录
const _RUNTIME_DIR: String = "res://assets/resources/levels"  # 非编辑器（导出后）：加密题库目录


# 读一个题库 JSON：编辑器外先异或解密再解析；文件缺失 / 打开失败 / 解析失败一律返回 null
static func load_json(filename: String) -> Variant:
	var is_editor: bool = OS.has_feature("editor")  # 用引擎特性判断当前进程是不是编辑器
	var path: String = (_EDITOR_DIR if is_editor else _RUNTIME_DIR) + "/" + filename  # 两个目录里的文件名完全一致，只换根目录
	if not FileAccess.file_exists(path):
		return null  # 文件不存在：调用方按「没有这份题库」处理
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("LevelBankIO: cannot open %s" % path)  # 只报错不中断，调用方拿到的还是 null
		return null
	var bytes: PackedByteArray = f.get_buffer(f.get_length())  # 一次性把整份文件读成字节流
	f.close()
	if not is_editor:
		_xor_inplace(bytes)  # 导出后的文件是密文，先就地异或回明文
	var text: String = bytes.get_string_from_utf8()  # 解密出来的字节按 UTF-8 还原成 JSON 文本
	return JSON.parse_string(text)  # 解析失败会返回 null，由调用方判类型


# 原地 XOR 解密：密钥按字节循环异或，加密与解密是同一套操作
static func _xor_inplace(bytes: PackedByteArray) -> void:
	var key_len: int = _KEY.length()
	if key_len == 0 or bytes.is_empty():
		return
	for i in bytes.size():
		bytes[i] ^= _KEY.unicode_at(i % key_len)
