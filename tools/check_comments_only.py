#!/usr/bin/env python3
"""校验 .gd 文件的改动是否「只增加了注释」。

原理：把「原版（git HEAD）」和「工作区版本」各自剥掉注释、去掉空行后逐字符比较。
只要代码一模一样，就说明这次改动没有碰过任何一行真实代码。

用法：
    python3 tools/check_comments_only.py                # 校验 git 里所有被改动的 .gd 文件
    python3 tools/check_comments_only.py a.gd b/        # 校验指定文件或目录（目录会递归展开）
    python3 tools/check_comments_only.py --hazards a.gd # 只做续行/缩进等语法风险扫描
"""

import os
import subprocess
import sys


def analyze(text: str):
    """把源码拆成「每行的代码部分」和「该行是否含真注释」。

    字符串字面量（含三引号跨行串）里的 # 不算注释，所以这里做了完整的状态机扫描。
    """
    code_lines = [""]
    has_comment = [False]
    index = 0
    length = len(text)
    quote = None  # None 表示在代码里，否则是当前字符串的引号（" ' \"\"\" '''）

    while index < length:
        char = text[index]

        if quote is None:
            if char == "#":
                has_comment[-1] = True
                while index < length and text[index] != "\n":
                    index += 1
                continue
            if char in "\"'":
                triple = char * 3
                if text[index : index + 3] == triple:
                    quote = triple
                    code_lines[-1] += triple
                    index += 3
                else:
                    quote = char
                    code_lines[-1] += char
                    index += 1
                continue
            if char == "\n":
                code_lines.append("")
                has_comment.append(False)
                index += 1
                continue
            code_lines[-1] += char
            index += 1
            continue

        # 字符串内部：原样保留（包括 #），换行要断行
        if char == "\\":
            code_lines[-1] += text[index : index + 2]
            index += 2
            continue
        if len(quote) == 3:
            if text[index : index + 3] == quote:
                code_lines[-1] += quote
                index += 3
                quote = None
                continue
        elif char == quote:
            code_lines[-1] += char
            index += 1
            quote = None
            continue
        elif char == "\n":
            quote = None  # 单引号串不该跨行，保守地当作结束

        if char == "\n":
            code_lines.append("")
            has_comment.append(False)
            index += 1
            continue
        code_lines[-1] += char
        index += 1

    return code_lines, has_comment


def code_lines(text: str):
    """返回「去掉注释、去掉空行、去掉行尾空白」后的代码行列表。"""
    lines, _ = analyze(text)
    return [line.rstrip() for line in lines if line.strip()]


def read_head(path: str) -> str:
    """读取 git HEAD 里的原版文件内容。"""
    return subprocess.run(
        ["git", "show", "HEAD:%s" % path],
        capture_output=True,
        text=True,
        check=True,
    ).stdout


def first_difference(old_lines, new_lines):
    """返回第一个不同之处 (序号, 原版行, 新版行)。"""
    for index in range(max(len(old_lines), len(new_lines))):
        old = old_lines[index] if index < len(old_lines) else "<缺少此行>"
        new = new_lines[index] if index < len(new_lines) else "<缺少此行>"
        if old != new:
            return index, old, new
    return None


def scan_hazards(path: str):
    """扫描容易破坏语法的注释写法：续行、空格缩进、紧贴代码的注释。"""
    issues = []
    with open(path, encoding="utf-8") as handle:
        raw_lines = handle.read().split("\n")

    code_lines_of_file, has_comment = analyze("\n".join(raw_lines))

    # 先判断这个文件本身是用 Tab 还是空格缩进的，注释应跟它保持一致
    tab_body = 0
    space_body = 0
    for number, line in enumerate(raw_lines, start=1):
        if not line.strip() or line.strip().startswith("#"):
            continue
        if line.startswith("\t"):
            tab_body += 1
        elif line.startswith(" "):
            space_body += 1
    file_uses_tabs = tab_body >= space_body

    for number, line in enumerate(raw_lines, start=1):
        code = code_lines_of_file[number - 1] if number - 1 < len(code_lines_of_file) else ""
        is_comment_only = line.strip().startswith("#")
        hangs = code.rstrip().endswith("\\")

        # 行尾续行符所在行不能追加注释
        if hangs and has_comment[number - 1]:
            issues.append("%s:%d 续行符 \\ 所在行被追加了注释" % (path, number))

        # 行尾续行符后面不能插入注释行
        if hangs and number < len(raw_lines):
            next_line = raw_lines[number]
            if next_line.strip().startswith("#"):
                issues.append("%s:%d 续行符 \\ 后面插入了注释行" % (path, number))

        # 注释行的缩进要和本文件的代码缩进风格一致
        if is_comment_only:
            indent = line[: len(line) - len(line.lstrip())]
            if file_uses_tabs and " " in indent:
                issues.append("%s:%d 注释行缩进里出现空格（本文件代码用 Tab）" % (path, number))
            if not file_uses_tabs and "\t" in indent:
                issues.append("%s:%d 注释行缩进里出现 Tab（本文件代码用空格）" % (path, number))

        # 代码与注释之间要有空格
        if has_comment[number - 1] and not is_comment_only and code:
            if not code.endswith((" ", "\t")):
                issues.append("%s:%d 注释紧贴代码，缺少空格" % (path, number))

    return issues


def expand(paths):
    """把目录展开成目录下所有 .gd 文件。"""
    result = []
    for path in paths:
        if os.path.isdir(path):
            for root, _dirs, files in os.walk(path):
                result.extend(
                    os.path.join(root, name) for name in sorted(files) if name.endswith(".gd")
                )
        else:
            result.append(path)
    return sorted(result)


def main(argv):
    hazards_only = "--hazards" in argv
    paths = expand([a for a in argv if not a.startswith("--")])

    if not paths:
        changed = subprocess.run(
            ["git", "status", "--porcelain", "--", "*.gd"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        paths = sorted(line[3:].strip() for line in changed.splitlines() if line.strip())

    if not paths:
        print("没有需要校验的 .gd 文件")
        return 0

    failures = []
    warnings = []

    for path in paths:
        if not os.path.isfile(path):
            failures.append("%s 文件不存在" % path)
            continue

        warnings.extend(scan_hazards(path))

        if hazards_only:
            continue

        with open(path, encoding="utf-8") as handle:
            new_text = handle.read()

        try:
            old_text = read_head(path)
        except subprocess.CalledProcessError:
            continue  # 新增文件，没有原版可比

        old_lines = code_lines(old_text)
        new_lines = code_lines(new_text)
        if old_lines == new_lines:
            continue

        index, old, new = first_difference(old_lines, new_lines)
        failures.append(
            "%s 代码被改动了：第 %d 条代码行\n    原版: %s\n    新版: %s" % (path, index + 1, old, new)
        )

    for issue in warnings:
        print("WARN %s" % issue)

    if failures:
        for failure in failures:
            print("FAIL %s" % failure)
        print("\n结果：%d 个文件未通过" % len(failures))
        return 1

    print("结果：%d 个文件全部只增加了注释，代码逐字符一致 ✅" % len(paths))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
