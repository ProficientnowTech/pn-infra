#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
import time
import traceback
import unittest
from collections import OrderedDict
from dataclasses import dataclass


@dataclass(frozen=True)
class TestOutcome:
    status: str  # "pass" | "fail" | "error" | "skip" | "xfail" | "xpass"
    duration_s: float
    details: str | None = None


def _iter_tests(suite: unittest.TestSuite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from _iter_tests(item)
        else:
            yield item


class JestLikeResult(unittest.TestResult):
    def __init__(self):
        super().__init__()
        self._started_at: dict[str, float] = {}
        self.outcomes: dict[str, TestOutcome] = {}

    def startTest(self, test):
        super().startTest(test)
        self._started_at[test.id()] = time.perf_counter()

    def _finish(self, test, status: str, details: str | None = None):
        started = self._started_at.get(test.id())
        duration = time.perf_counter() - started if started is not None else 0.0
        self.outcomes[test.id()] = TestOutcome(status=status, duration_s=duration, details=details)

    def addSuccess(self, test):
        super().addSuccess(test)
        self._finish(test, "pass")

    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        self._finish(test, "skip", str(reason))

    def addExpectedFailure(self, test, err):
        super().addExpectedFailure(test, err)
        details = "".join(traceback.format_exception(*err))
        self._finish(test, "xfail", details)

    def addUnexpectedSuccess(self, test):
        super().addUnexpectedSuccess(test)
        self._finish(test, "xpass")

    def addFailure(self, test, err):
        super().addFailure(test, err)
        details = "".join(traceback.format_exception(*err))
        self._finish(test, "fail", details)

    def addError(self, test, err):
        super().addError(test, err)
        details = "".join(traceback.format_exception(*err))
        self._finish(test, "error", details)


def _discover(start_dir: str, pattern: str) -> unittest.TestSuite:
    loader = unittest.TestLoader()
    return loader.discover(start_dir=start_dir, pattern=pattern, top_level_dir=None)


def _collect_structure(suite: unittest.TestSuite):
    # Preserve discovery/run order.
    modules: "OrderedDict[str, OrderedDict[str, list[str]]]" = OrderedDict()
    for test in _iter_tests(suite):
        module = test.__class__.__module__
        cls = test.__class__.__name__
        method = getattr(test, "_testMethodName", test.id().split(".")[-1])
        modules.setdefault(module, OrderedDict()).setdefault(cls, []).append(method)
    return modules


def _format_seconds(s: float) -> str:
    if s < 1:
        return f"{s*1000:.0f} ms"
    return f"{s:.2f} s"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Run unittest with Jest-like output (no extra deps).")
    parser.add_argument(
        "--start-dir",
        default=os.path.join(os.path.dirname(__file__), "tests"),
        help="Directory to discover tests from (default: tools/tests).",
    )
    parser.add_argument("--pattern", default="test_*.py", help="Discovery pattern (default: test_*.py).")
    args = parser.parse_args(argv)

    suite = _discover(args.start_dir, args.pattern)
    structure = _collect_structure(suite)

    started = time.perf_counter()
    result = JestLikeResult()
    suite.run(result)
    total_duration = time.perf_counter() - started

    def module_display_name(module: str) -> str:
        mod = sys.modules.get(module)
        mod_file = getattr(mod, "__file__", None)
        if not mod_file:
            return module
        try:
            return os.path.relpath(mod_file, start=os.getcwd())
        except ValueError:
            return mod_file

    def outcome_for(module: str, cls: str, method: str) -> TestOutcome | None:
        test_id = f"{module}.{cls}.{method}"
        return result.outcomes.get(test_id)

    suites_total = len(structure)
    suites_failed = 0

    tests_total = 0
    tests_failed = 0
    tests_skipped = 0
    tests_passed = 0

    failing_details: list[tuple[str, str]] = []

    for module, classes in structure.items():
        module_failed = False
        for cls, methods in classes.items():
            for method in methods:
                tests_total += 1
                oc = outcome_for(module, cls, method)
                if oc is None:
                    module_failed = True
                    tests_failed += 1
                    failing_details.append((f"{module}.{cls}.{method}", "No outcome recorded"))
                elif oc.status in ("fail", "error", "xpass"):
                    module_failed = True
                    tests_failed += 1
                    if oc.details:
                        failing_details.append((f"{module}.{cls}.{method}", oc.details))
                elif oc.status == "skip":
                    tests_skipped += 1
                else:
                    tests_passed += 1

        if module_failed:
            suites_failed += 1
            print(f"FAIL {module_display_name(module)}")
        else:
            print(f"PASS {module_display_name(module)}")

        for cls, methods in classes.items():
            print(f"  {cls}")
            for method in methods:
                oc = outcome_for(module, cls, method)
                if oc is None:
                    print(f"    ✗ {method}")
                    continue
                dur = _format_seconds(oc.duration_s)
                if oc.status == "pass":
                    print(f"    ✓ {method} ({dur})")
                elif oc.status == "skip":
                    print(f"    ○ {method} (skipped: {oc.details})")
                elif oc.status == "xfail":
                    print(f"    ○ {method} (expected failure, {dur})")
                elif oc.status == "xpass":
                    print(f"    ✗ {method} (unexpected success, {dur})")
                elif oc.status == "fail":
                    print(f"    ✗ {method} ({dur})")
                else:
                    print(f"    ✗ {method} ({oc.status}, {dur})")

    if failing_details:
        print("\nFailures:\n")
        for test_id, details in failing_details:
            print(f"  ● {test_id}")
            for line in details.rstrip("\n").splitlines():
                print(f"    {line}")
            print()

    suites_passed = suites_total - suites_failed

    print(
        "\n"
        f"Test Suites: {suites_passed} passed, {suites_failed} failed, {suites_total} total\n"
        f"Tests:       {tests_passed} passed, {tests_failed} failed, {tests_skipped} skipped, {tests_total} total\n"
        f"Time:        {_format_seconds(total_duration)}\n"
    )

    return 0 if (result.wasSuccessful() and not result.unexpectedSuccesses) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
