## 从商店本地化价格字符串推断货币与分隔符格式，再渲染计算得到的价格。
## 用于保持折算日价的展示风格一致，不负责查询商店或决定商品价格。

class_name MoneyFormat
extends RefCounted

const _SEP_CHARS: String = ".,    '’"

const _NUM_PATTERN: String = "[0-9][0-9.,\\x{00A0}\\x{202F}\\x{2009} '\\x{2019}]*[0-9]|[0-9]"

const _EMPTY_FMT: Dictionary = {
	"ok": false,
	"prefix": "",
	"suffix": "",
	"decimals": 2,
	"dec_sep": ".",
	"grp_sep": "",
	"grp_primary": 3,
	"grp_secondary": 3,
}


static func parse(display_price: String, value: float) -> Dictionary:
	var fmt: Dictionary = _EMPTY_FMT.duplicate()
	var re: RegEx = RegEx.create_from_string(_NUM_PATTERN)
	var m: RegExMatch = re.search(display_price)
	if m == null:
		return fmt
	var body: String = m.get_string()
	fmt.prefix = display_price.substr(0, m.get_start())
	fmt.suffix = display_price.substr(m.get_end())

	var sep_idx: Array[int] = []
	for i in body.length():
		if _SEP_CHARS.contains(body[i]):
			sep_idx.append(i)

	if sep_idx.is_empty():
		fmt.decimals = 0
		fmt.grp_sep = ""
		fmt.ok = true
		return fmt

	var last: int = sep_idx[-1]
	var tail: int = body.length() - last - 1
	var dec_sep: String = ""
	if tail >= 1 and tail <= 3:
		var digits_only: String = ""
		for i in body.length():
			if i == last:
				digits_only += "."
			elif not _SEP_CHARS.contains(body[i]):
				digits_only += body[i]
		if absf(digits_only.to_float() - value) < 0.5 / pow(10.0, tail):
			dec_sep = body[last]
			fmt.decimals = tail
	if dec_sep.is_empty():
		fmt.decimals = 0

	var grp: String = ""
	for i in sep_idx:
		if dec_sep.is_empty() or i != last:
			grp = body[i]
			break
	fmt.grp_sep = grp
	if not dec_sep.is_empty():
		fmt.dec_sep = dec_sep
	elif not grp.is_empty():
		fmt.dec_sep = "," if grp == "." else "."

	if not grp.is_empty():
		var int_end: int = last if not dec_sep.is_empty() else body.length()
		var runs: Array[int] = []
		var cur: int = 0
		for i in int_end:
			if _SEP_CHARS.contains(body[i]):
				runs.append(cur)
				cur = 0
			else:
				cur += 1
		runs.append(cur)
		if runs.size() >= 2:
			fmt.grp_primary = runs[-1]
			fmt.grp_secondary = runs[-2] if runs.size() >= 3 else runs[-1]
	fmt.ok = true
	return fmt


## 综合多个本地化价格样本推断小数点、千位符与货币位置，减少单个整数价格造成的歧义。
static func parse_many(samples: Array) -> Dictionary:
	var base: Dictionary = {}
	var grp: Dictionary = {}
	var grp_seps: int = 0
	for s: Array in samples:
		var f: Dictionary = parse(str(s[0]), float(s[1]))
		if not f.ok:
			continue
		if base.is_empty():
			base = f
		if str(f.grp_sep).is_empty():
			continue
		var n: int = _count_separators(str(s[0]))
		if grp.is_empty() or n > grp_seps:
			grp = f
			grp_seps = n
	if base.is_empty():
		return _EMPTY_FMT.duplicate()
	if not grp.is_empty():
		base.grp_sep = grp.grp_sep
		base.grp_primary = grp.grp_primary
		base.grp_secondary = grp.grp_secondary
	elif str(base.grp_sep).is_empty():
		base.grp_sep = "." if str(base.dec_sep) == "," else ","
	return base


## 将计算后的数值按已识别格式重新组装为价格字符串，保留货币位置与分隔符习惯。
static func render(amount: float, fmt: Dictionary) -> String:
	var decimals: int = int(fmt.decimals)
	var s: String = String.num(absf(amount), decimals).pad_decimals(decimals)
	var int_part: String = s
	var frac: String = ""
	var dot: int = s.find(".")
	if dot >= 0:
		int_part = s.substr(0, dot)
		frac = s.substr(dot + 1)
	var grp: String = str(fmt.grp_sep)
	if not grp.is_empty() and int_part.length() > int(fmt.grp_primary):
		var out: String = int_part.substr(int_part.length() - int(fmt.grp_primary))
		var rest: String = int_part.substr(0, int_part.length() - int(fmt.grp_primary))
		var sec: int = maxi(int(fmt.grp_secondary), 1)
		while rest.length() > sec:
			out = rest.substr(rest.length() - sec) + grp + out
			rest = rest.substr(0, rest.length() - sec)
		out = rest + grp + out
		int_part = out
	var num: String = int_part if frac.is_empty() else int_part + str(fmt.dec_sep) + frac
	return str(fmt.prefix) + num + str(fmt.suffix)


static func _count_separators(display_price: String) -> int:
	var re: RegEx = RegEx.create_from_string(_NUM_PATTERN)
	var m: RegExMatch = re.search(display_price)
	if m == null:
		return 0
	var body: String = m.get_string()
	var n: int = 0
	for i in body.length():
		if _SEP_CHARS.contains(body[i]):
			n += 1
	return n
