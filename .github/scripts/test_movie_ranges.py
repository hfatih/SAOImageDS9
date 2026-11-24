"""Exercise DS9 movie Tcl commands without GUI or movie encoder dependencies."""

import argparse
from contextlib import contextmanager
import math
from pathlib import Path
import tkinter
import unittest
import uuid


@contextmanager
def script_file(contents):
    path = Path(__file__).resolve().parent / (".movie-test-" + uuid.uuid4().hex + ".cmd")
    try:
        path.write_text(contents, encoding="utf-8")
        yield path
    finally:
        path.unlink(missing_ok=True)


class MovieRangeTests(unittest.TestCase):
    def setUp(self):
        self.tcl = tkinter.Tcl()
        self.tcl.eval(SOURCE)
        self.commands = []
        self.errors = []
        self.photos = 0
        self.stop_after = None
        self.reject_command = False
        self.tcl.createcommand("ds9Cmd", self.ds9_command)
        self.tcl.createcommand("MoviePhoto", self.photo)
        self.tcl.createcommand("Error", lambda message: self.errors.append(message))
        self.tcl.eval('namespace eval msgcat {proc mc {message args} {return $message}}')

    def ds9_command(self, command):
        self.commands.append(command)
        if self.reject_command:
            raise tkinter.TclError("rejected by DS9")
        return ""

    def photo(self):
        self.photos += 1
        return int(self.stop_after is not None and self.photos >= self.stop_after)

    def run_movie(self, command):
        return int(self.tcl.call("MovieScriptCommand", command))

    def values(self):
        self.assertTrue(all(command.startswith("-zoom to ") for command in self.commands),
                        self.commands)
        return [float(command.split()[-1]) for command in self.commands]

    def test_linear_and_log_values(self):
        cases = (
            ("linear 0 360 5", [0, 90, 180, 270, 360]),
            ("linear 5 -5 5", [5, 2.5, 0, -2.5, -5]),
            ("linear 3 3 3", [3, 3, 3]),
            ("linear -1 1 3", [-1, 0, 1]),
            ("linear 0.1 0.3 3", [0.1, 0.2, 0.3]),
            ("linear 7 100 1", [7]),
            ("log 1 100 3", [1, 10, 100]),
            ("log 1000 1 4", [1000, 100, 10, 1]),
            ("log 0.01 1 3", [0.01, 0.1, 1]),
            ("log 2 2 3", [2, 2, 2]),
            ("log 2 100 1", [2]),
            ("linear -1e308 1e308 3", [-1e308, 0, 1e308]),
            ("log 1e-300 1e300 3", [1e-300, 1, 1e300]),
        )
        for specification, expected in cases:
            with self.subTest(specification=specification):
                self.commands.clear()
                self.photos = 0
                self.assertEqual(self.run_movie(f"foreach {specification} {{zoom to @}}"), 0)
                actual = self.values()
                self.assertEqual(len(actual), len(expected))
                for value, want in zip(actual, expected):
                    self.assertTrue(math.isfinite(value))
                    self.assertTrue(math.isclose(value, want, rel_tol=1e-12, abs_tol=1e-14),
                                    (value, want))
                self.assertEqual(self.photos, len(expected))
                self.assertEqual(self.errors, [])

    def test_invalid_ranges_do_not_execute_or_capture(self):
        cases = (
            "linear 0 1 0", "linear 0 1 -1", "linear 0 1 2.5",
            "linear 0 1 abc", "linear 0 1 {}", "linear {} 1 3",
            "linear abc 1 3", "linear 0 abc 3", "linear NaN 1 3",
            "linear 0 NaN 3", "linear Inf 1 3", "linear 0 -Inf 3",
            "linear 1e999 1 3", "linear 0 1e999 3",
            "linear " + "9" * 500 + " 1 3",
            "log 0 10 3", "log -1 10 3", "log 1 0 3", "log 1 -10 3",
            "log NaN 1 3", "log 1 Inf 3",
            "linear 0 1", "log 1 10", "linear 0 1 3 extra extra",
        )
        for specification in cases:
            with self.subTest(specification=specification):
                self.errors.clear()
                self.assertEqual(self.run_movie(f"foreach {specification} {{zoom to @}}"), 1)
                self.assertTrue(self.errors)
                self.assertEqual(self.commands, [])
                self.assertEqual(self.photos, 0)

    def test_existing_lists_and_waypoints_are_unchanged(self):
        self.assertEqual(self.run_movie("foreach {1 2 4} {zoom to @}"), 0)
        self.assertEqual(self.commands, ["-zoom to 1", "-zoom to 2", "-zoom to 4"])
        self.commands.clear()
        self.assertEqual(self.run_movie("foreach {{12 34} {56 78}} {pan to @ physical}"), 0)
        self.assertEqual(self.commands, ["-pan to 12 34 physical", "-pan to 56 78 physical"])
        self.commands.clear()
        self.assertEqual(self.run_movie("foreach {} {zoom to @}"), 0)
        self.assertEqual(self.commands, [])

    def test_legacy_list_named_linear_or_log_is_unchanged(self):
        for value in ("linear", "log"):
            with self.subTest(value=value):
                self.commands.clear()
                self.assertEqual(self.run_movie(f"foreach {value} {{scale @}}"), 0)
                self.assertEqual(self.commands, [f"-scale {value}"])

    def test_cancellation_stops_a_large_range_without_preallocation(self):
        self.stop_after = 2
        self.assertEqual(self.run_movie("foreach linear 0 1 1000000000 {zoom to @}"), 1)
        self.assertEqual(len(self.commands), 2)
        self.assertEqual(self.photos, 2)

    def test_command_failure_stops_before_capture(self):
        self.reject_command = True
        self.assertEqual(self.run_movie("foreach log 1 1000 100 {zoom to @}"), 1)
        self.assertEqual(self.commands, ["-zoom to 1"])
        self.assertEqual(self.photos, 0)
        self.assertTrue(self.errors)

    def test_templates_are_not_evaluated_as_tcl(self):
        self.tcl.eval("set injected 0")
        self.assertEqual(self.run_movie(
            "foreach linear 1 2 2 {zoom to @; [set injected 1]}"), 0)
        self.assertEqual(self.tcl.eval("set injected"), "0")
        self.assertEqual(self.commands, ["-zoom to 1; [set injected 1]",
                                         "-zoom to 2; [set injected 1]"])

    def test_endpoints_preserve_input_spelling(self):
        self.assertEqual(self.run_movie("foreach linear 1e-3 1.00 2 {zoom to @}"), 0)
        self.assertEqual(self.commands, ["-zoom to 1e-3", "-zoom to 1.00"])

    def test_script_file_comments_continuations_and_cleanup(self):
        contents = ("# A complete movie script\n\n"
                    "foreach linear 1 3 3 \\\n"
                    "    {zoom to @}\n"
                    "foreach log 1 100 3 {zoom to @}\n"
                    "zoom to 1 &&\n")
        with script_file(contents) as script:
            self.tcl.call("MovieScript", str(script))
        for actual, want in zip(self.values(), [1, 2, 3, 1, 10, 100, 1], strict=True):
            self.assertAlmostEqual(actual, want, places=12)
        self.assertEqual(self.photos, 6)
        self.assertEqual(self.tcl.eval("info exists movie(3d,sync)"), "0")

    def test_invalid_range_stops_file_and_cleans_up(self):
        with script_file("foreach log 0 10 3 {zoom to @}\nzoom to 9\n") as script:
            self.tcl.call("MovieScript", str(script))
        self.assertTrue(self.errors)
        self.assertEqual(self.commands, [])
        self.assertEqual(self.photos, 0)
        self.assertEqual(self.tcl.eval("info exists movie(3d,sync)"), "0")

    def test_number_fields_cannot_execute_tcl(self):
        self.tcl.eval("set injected 0")
        for specification in (
            "linear {[set injected 1]} 5 3",
            "log 1 {[set injected 1]} 3",
            "linear 1 2 {[set injected 1]}",
        ):
            with self.subTest(specification=specification):
                self.assertEqual(self.run_movie(f"foreach {specification} {{zoom to @}}"), 1)
                self.assertEqual(self.tcl.eval("set injected"), "0")
                self.assertEqual(self.commands, [])

    def test_non_range_movie_commands_are_unchanged(self):
        self.assertEqual(self.run_movie("zoom to 2 &&"), 0)
        self.assertEqual(self.photos, 0)
        self.assertEqual(self.run_movie("zoom to 4"), 0)
        self.assertEqual(self.photos, 1)
        self.assertEqual(self.commands, ["-zoom to 2", "-zoom to 4"])

    def test_extreme_log_values_remain_finite_and_within_endpoints(self):
        maximum = "1.7976931348623157e308"
        for first, last in ((maximum, maximum), ("1e-300", maximum),
                            (maximum, "1e-300"), ("1e308", maximum),
                            (maximum, "1e308")):
            with self.subTest(first=first, last=last):
                self.commands.clear()
                self.assertEqual(self.run_movie(
                    f"foreach log {first} {last} 50 {{zoom to @}}"), 0)
                values = self.values()
                self.assertEqual(len(values), 50)
                self.assertTrue(all(math.isfinite(value) for value in values))
                low, high = sorted((float(first), float(last)))
                self.assertTrue(all(low <= value <= high for value in values))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--overlay", type=Path)
    args = parser.parse_args()
    SOURCE = args.source.read_text(encoding="utf-8")
    if args.overlay:
        # Evaluate the candidate in memory; never write into the project checkout.
        SOURCE += "\n" + args.overlay.read_text(encoding="utf-8")
    print("Tcl", tkinter.Tcl().eval("info patchlevel"), flush=True)
    unittest.main(argv=[__file__], verbosity=2)
