"""Regression checks for conservative comment matching; no project files change.

Run: python3 -m unittest discover -s tools -p 'test_migrate_learning_comments.py'
"""

import unittest

from migrate_learning_comments import migrate_text, parse_source


class CommentMigrationTests(unittest.TestCase):
    def migrate(self, old, new):
        result, report = migrate_text(old, new)
        self.assertEqual(parse_source(new).fingerprint, parse_source(result).fingerprint)
        # These cases migrate leading comments only. All existing physical code
        # and blank lines, including their line endings, must survive verbatim.
        def without_comment_lines(text):
            return [line.raw for line in parse_source(text).lines
                    if not (line.comment is not None and not line.code.strip())]
        self.assertEqual(without_comment_lines(new), without_comment_lines(result))
        repeated, _ = migrate_text(old, result)
        self.assertEqual(result, repeated)
        return result, report

    def test_lambda_body_indentation_changes_control_flow(self):
        old = (
            "extends Node\n\n## b 在 if 外执行。\nfunc run():\n"
            "\tcall(func():\n\t\tif ok:\n\t\t\ta()\n\t\tb()\n\t)\n"
        )
        new = old.replace("## b 在 if 外执行。\n", "").replace("\n\t\tb()", "\n\t\t\tb()")
        result, report = self.migrate(old, new)
        self.assertNotEqual(parse_source(old).fingerprint, parse_source(new).fingerprint)
        self.assertEqual(new, result)
        self.assertEqual(1, report["counts"]["changed_function"])

    def test_changed_lambda_does_not_block_an_unchanged_helper(self):
        old = (
            "extends Node\n## 主函数\nfunc run():\n\tcall(func():\n"
            "\t\tif ok:\n\t\t\ta()\n\t\tb()\n\t)\n"
            "\n## 无变化的辅助函数\nfunc helper():\n\tpass\n"
        )
        new = old.replace("## 主函数\n", "").replace("## 无变化的辅助函数\n", "")
        new = new.replace("\n\t\tb()", "\n\t\t\tb()")
        result, _ = self.migrate(old, new)
        self.assertNotIn("## 主函数", result)
        self.assertIn("## 无变化的辅助函数", result)

    def test_unchanged_multiline_lambda_can_keep_comments(self):
        old = (
            "extends Node\n## 回调\nfunc run():\n\tcall(func():\n"
            "\t\tif ok:\n\t\t\ta()\n\t\tb()\n\t)\n"
        )
        result, _ = self.migrate(old, old.replace("## 回调\n", ""))
        self.assertEqual(old, result)

    def test_multiline_lambda_rewrapping_is_conservatively_rejected(self):
        old = "extends Node\n## 回调\nfunc run():\n\tcall(func():\n\t\ta()\n\t)\n"
        new = "extends Node\nfunc run():\n\tcall(\n\t\tfunc():\n\t\t\ta()\n\t)\n"
        result, report = self.migrate(old, new)
        self.assertEqual(new, result)
        self.assertEqual(1, report["counts"]["changed_function"])

    def test_nested_class_base_change_rejects_member_comments(self):
        old = (
            "extends RefCounted\nclass Inner extends Node:\n"
            "\t## 节点方法\n\tfunc run():\n\t\tpass\n"
        )
        new = old.replace("Inner extends Node", "Inner extends RefCounted")
        new = new.replace("\t## 节点方法\n", "")
        result, report = self.migrate(old, new)
        self.assertEqual(new, result)
        self.assertEqual(1, report["counts"]["changed_enclosing_class"])

    def test_class_body_extends_change_rejects_member_comments(self):
        old = (
            "extends RefCounted\nclass Inner:\n\textends Node\n"
            "\t## 节点方法\n\tfunc run():\n\t\tpass\n"
        )
        new = old.replace("\textends Node", "\textends RefCounted")
        new = new.replace("\t## 节点方法\n", "")
        result, report = self.migrate(old, new)
        self.assertEqual(new, result)
        self.assertEqual(1, report["counts"]["changed_enclosing_class"])

    def test_outer_ancestor_base_change_rejects_deep_member(self):
        old = (
            "extends RefCounted\nclass Outer extends Node:\n"
            "\tclass Inner:\n\t\t## 依赖外层的说明\n\t\tfunc run():\n\t\t\tpass\n"
        )
        new = old.replace("Outer extends Node", "Outer extends RefCounted")
        new = new.replace("\t\t## 依赖外层的说明\n", "")
        result, report = self.migrate(old, new)
        self.assertEqual(new, result)
        self.assertEqual(1, report["counts"]["changed_enclosing_class"])

    def test_unchanged_nested_class_method_survives_sibling_change(self):
        old = (
            "extends RefCounted\nclass Inner extends Node:\n"
            "\t## 无变化的方法\n\tfunc run():\n\t\tpass\n"
            "\tfunc sibling():\n\t\treturn 1\n"
        )
        new = old.replace("\t## 无变化的方法\n", "").replace("return 1", "return 2")
        result, _ = self.migrate(old, new)
        self.assertIn("\t## 无变化的方法\n", result)

    def test_ordinary_statement_reflow_still_matches(self):
        old = "extends Node\n## 相加\nfunc add(a, b):\n\treturn a + b\n"
        new = "extends Node\n\nfunc add(\n\ta,\n\tb\n):\n\treturn (a + b)\n"
        # Parentheses are actual tokens, so only reflow the declaration here.
        new = new.replace("return (a + b)", "return a + b")
        result, _ = self.migrate(old, new)
        self.assertIn("## 相加\nfunc add(", result)

    def test_string_content_and_crlf_remain_literal(self):
        old = 'extends Node\r\n## 字符串内的 # 不是注释\r\nfunc run():\r\n\treturn "# \\n func("'
        new = old.replace("## 字符串内的 # 不是注释\r\n", "")
        result, _ = self.migrate(old, new)
        self.assertEqual(old, result)
        self.assertFalse(result.endswith("\n"))


if __name__ == "__main__":
    unittest.main()
