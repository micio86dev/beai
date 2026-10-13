"""Tests for sdks/postprocess_typescript.py, stdlib only (no pytest, no coverage.py)."""

import contextlib
import io
import os
import pathlib
import runpy
import sys
import tempfile
import unittest
from unittest import mock

SDKS = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SDKS))

import postprocess_typescript as pp  # noqa: E402


def models(tmp, files):
    root = pathlib.Path(tmp) / "src"
    for name, content in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    return root


class SpecifierName(unittest.TestCase):
    def test_strips_the_type_keyword_only(self):
        self.assertEqual(pp.specifier_name("type Foo"), "Foo")
        self.assertEqual(pp.specifier_name("FooFromJSON"), "FooFromJSON")


class Prune(unittest.TestCase):
    def test_drops_a_whole_import_nothing_references(self):
        text = "import { mapValues } from '../runtime';\nexport const a = 1;\n"
        self.assertEqual(pp.prune(text), "export const a = 1;\n")

    def test_keeps_an_import_that_is_used(self):
        text = "import { mapValues } from '../runtime';\nmapValues(x);\n"
        self.assertEqual(pp.prune(text), text)

    def test_trims_unused_specifiers_of_a_single_line_import(self):
        text = "import { A, B } from './m';\nuse(A);\n"
        self.assertEqual(pp.prune(text), "import { A } from './m';\nuse(A);\n")

    def test_trims_unused_specifiers_of_a_multi_line_import(self):
        text = "import {\n    type A,\n    AFromJSON,\n    AToJSON,\n} from './A';\nlet x: A = AFromJSON(y);\n"
        expected = "import {\n    type A,\n    AFromJSON,\n} from './A';\nlet x: A = AFromJSON(y);\n"
        self.assertEqual(pp.prune(text), expected)

    def test_keeps_the_type_keyword_of_the_whole_import(self):
        text = "import type { A, B } from './m';\nlet a: A;\n"
        self.assertEqual(pp.prune(text), "import type { A } from './m';\nlet a: A;\n")

    def test_matches_whole_identifiers_only(self):
        text = "import { Foo } from './Foo';\nconst x = FooBar;\n"
        self.assertEqual(pp.prune(text), "const x = FooBar;\n")

    def test_a_name_used_only_by_another_import_does_not_count(self):
        text = "import { A } from './A';\nimport { B } from './B';\nconst b = B;\n"
        self.assertEqual(pp.prune(text), "import { B } from './B';\nconst b = B;\n")

    def test_a_name_used_in_a_type_position_survives(self):
        text = "import type { Page } from './Page';\nexport function f(p: Page[]) {}\n"
        self.assertEqual(pp.prune(text), text)


class UnescapeComments(unittest.TestCase):
    def test_unescapes_quotes_inside_jsdoc_lines_only(self):
        text = " * organization\\'s {\\\"status\\\":\\\"ok\\\"}\nconst s = 'it\\'s';\n"
        expected = " * organization's {\"status\":\"ok\"}\nconst s = 'it\\'s';\n"
        self.assertEqual(pp.unescape_comments(text), expected)

    def test_leaves_unrelated_text_alone(self):
        text = "/**\n * plain\n */\nconst a = 1;\n"
        self.assertEqual(pp.unescape_comments(text), text)


class Plan(unittest.TestCase):
    def test_lists_only_the_files_that_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = models(tmp, {
                "a.ts": "import { X } from './x';\nexport const a = 1;\n",
                "sub/b.ts": "export const b = 1;\n",
            })
            self.assertEqual(list(pp.plan(root)), [root / "a.ts"])

    def test_refuses_a_result_a_second_pass_would_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = models(tmp, {"a.ts": "x\n"})
            outputs = iter(["y", "z"])
            with mock.patch.object(pp, "process_text", side_effect=lambda _text: next(outputs)):
                with self.assertRaises(pp.PostProcessError):
                    pp.plan(root)


class Run(unittest.TestCase):
    def test_rewrites_changed_files_and_counts_them(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = models(tmp, {
                "a.ts": "import { X } from './x';\nexport const a = 1;\n",
                "b.ts": "export const b = 1;\n",
            })
            self.assertEqual(pp.run(root), 1)
            self.assertEqual((root / "a.ts").read_text(), "export const a = 1;\n")
            self.assertEqual((root / "b.ts").read_text(), "export const b = 1;\n")
            self.assertEqual(sorted(p.name for p in root.iterdir()), ["a.ts", "b.ts"])

    def test_a_failure_before_any_write_leaves_every_file_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            first = "import { X } from './x';\nexport const a = 1;\n"
            root = models(tmp, {"a.ts": first, "b.ts": "x\n"})
            with mock.patch.object(pp, "plan", side_effect=pp.PostProcessError("boom")):
                with self.assertRaises(pp.PostProcessError):
                    pp.run(root)
            self.assertEqual((root / "a.ts").read_text(), first)

    def test_a_failed_replace_keeps_the_original_and_removes_the_temp_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            original = "import { X } from './x';\nexport const a = 1;\n"
            root = models(tmp, {"a.ts": original})
            with mock.patch.object(os, "replace", side_effect=OSError("disk")):
                with self.assertRaises(OSError):
                    pp.run(root)
            self.assertEqual((root / "a.ts").read_text(), original)
            self.assertEqual(sorted(p.name for p in root.iterdir()), ["a.ts"])


class Main(unittest.TestCase):
    def call(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = pp.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_usage_error(self):
        code, _, err = self.call(["prog"])
        self.assertEqual(code, 2)
        self.assertIn("usage", err)

    def test_reports_a_post_processing_error(self):
        with mock.patch.object(pp, "run", side_effect=pp.PostProcessError("nope")):
            code, _, err = self.call(["prog", "src"])
        self.assertEqual(code, 1)
        self.assertIn("ERROR: nope", err)

    def test_reports_the_changed_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = models(tmp, {"a.ts": "import { X } from './x';\nexport const a = 1;\n"})
            code, out, _ = self.call(["prog", str(root)])
        self.assertEqual(code, 0)
        self.assertIn("in 1 typescript files", out)

    def test_runs_as_a_script(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = models(tmp, {"a.ts": "export const a = 1;\n"})
            with mock.patch.object(sys, "argv", ["postprocess_typescript.py", str(root)]):
                with contextlib.redirect_stdout(io.StringIO()):
                    with self.assertRaises(SystemExit) as raised:
                        runpy.run_path(str(SDKS / "postprocess_typescript.py"), run_name="__main__")
        self.assertEqual(raised.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
