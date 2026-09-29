#!/usr/bin/env python3
"""Ruff baseline ratchet for ``src/`` and ``tests/``.

``CONTRIBUTING.md`` has always told contributors that ``uv run ruff check
src/ tests/`` must pass before a PR. It has never passed: the tree carries
~1.7k violations of the declared rule set (``E,F,I,N,UP,B,SIM,RUF``), and
the count is effectively version-independent — ruff 0.8.0 reports 2095 and
ruff 0.15.2 reports 2106 on the same tree — so no pin rescues the command.
Nothing enforced it either: CI runs mypy and pytest but not ruff, and the
pre-commit hook type-checks staged files without linting them.

Two ways out were measured and rejected:

- **Fix everything now.** The safe autofixes alone (``I001`` import sorting
  and ``F401`` unused imports) rewrite 291 files. That buries any real
  change in mechanical churn and is exactly what ``CONTRIBUTING.md`` warns
  against ("keep changes focused", "no over-engineering").
- **Relax the config until it passes.** Ignoring the ~50 rule codes that
  currently fire would empty the rule set of meaning and delete the signal
  the project says it wants.

So this script ratchets instead, the same way mypy was handled here: the
pre-commit hook records that the codebase went "699/699 errors resolved" to
reach a strict-clean ``src/``. Ruff starts from a committed baseline and is
only allowed to go down.

The baseline is a per-file, per-rule count of the violations that exist
today. A run fails when a file gains a violation of a rule it did not have,
or when the count for an existing (file, rule) pair rises. Violations that
disappear are reported so the baseline can be tightened; they never fail a
run, so a cleanup PR cannot be blocked by its own progress.

Usage::

    python3 scripts/ruff_gate.py             # fail on new violations (CI)
    python3 scripts/ruff_gate.py --update    # re-record the baseline
    python3 scripts/ruff_gate.py --summary   # per-rule totals, then exit 0

Exit status is non-zero when the tree regressed past the baseline.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any, cast

ROOT = Path(__file__).resolve().parent.parent
BASELINE_FILE = ROOT / "ruff-baseline.json"

# Keep this identical to the command CONTRIBUTING.md documents, so the gate
# and the documented developer experience never diverge.
LINT_TARGETS = ("src", "tests")


class RuffNotFoundError(RuntimeError):
    """Raised when no ruff executable can be located."""


def _find_ruff() -> list[str]:
    """Return the argv prefix that runs ruff from the project environment.

    Prefers ``uv run ruff`` because that is how every other tool is invoked
    in this repo (and it resolves the pinned version from ``uv.lock``);
    falls back to a ``ruff`` on PATH for contributors without uv.
    """
    if shutil.which("uv") is not None:
        return ["uv", "run", "ruff"]
    if shutil.which("ruff") is not None:
        return ["ruff"]
    raise RuffNotFoundError(
        "ruff not found. Install the dev extra first: uv sync --all-extras"
    )


def collect_violations() -> list[dict[str, Any]]:
    """Run ruff over the lint targets and return its JSON diagnostics.

    ruff exits 1 when it finds violations, which is the normal case here, so
    the return code is only inspected for the "could not run at all" values.
    """
    argv = [
        *_find_ruff(),
        "check",
        *LINT_TARGETS,
        "--output-format",
        "json",
    ]
    proc = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)
    if proc.returncode not in (0, 1):
        raise RuntimeError(
            f"ruff failed to run (exit {proc.returncode}):\n{proc.stderr.strip()}"
        )
    if not proc.stdout.strip():
        return []
    return cast(list[dict[str, Any]], json.loads(proc.stdout))


def tally(violations: list[dict[str, Any]]) -> dict[str, dict[str, int]]:
    """Group violations into ``{relative_path: {rule_code: count}}``.

    Paths are stored relative to the repo root so the baseline survives a
    clone into a different directory. Diagnostics with no rule code (ruff
    emits those for syntax errors) are bucketed under ``SYNTAX``, which
    should never appear in a committed baseline.
    """
    counts: dict[str, Counter[str]] = {}
    for v in violations:
        raw = str(v.get("filename", ""))
        try:
            rel = Path(raw).resolve().relative_to(ROOT).as_posix()
        except ValueError:
            rel = raw
        code = v.get("code") or "SYNTAX"
        counts.setdefault(rel, Counter())[str(code)] += 1
    return {path: dict(sorted(c.items())) for path, c in sorted(counts.items())}


def load_baseline() -> dict[str, dict[str, int]]:
    """Read the committed baseline, or an empty mapping when absent."""
    if not BASELINE_FILE.is_file():
        return {}
    data = json.loads(BASELINE_FILE.read_text(encoding="utf-8"))
    return cast(dict[str, dict[str, int]], data["files"])


def write_baseline(counts: dict[str, dict[str, int]]) -> int:
    """Persist *counts* as the new baseline and return the violation total."""
    total = sum(sum(codes.values()) for codes in counts.values())
    payload = {
        "_comment": (
            "Committed ruff baseline for `scripts/ruff_gate.py`. Regenerate "
            "with `python3 scripts/ruff_gate.py --update` after a cleanup. "
            "Counts may only go down."
        ),
        "targets": list(LINT_TARGETS),
        "total": total,
        "files": counts,
    }
    BASELINE_FILE.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return total


def diff(
    baseline: dict[str, dict[str, int]],
    current: dict[str, dict[str, int]],
) -> tuple[list[str], list[str]]:
    """Return ``(regressions, improvements)`` as human-readable lines."""
    regressions: list[str] = []
    improvements: list[str] = []
    for path in sorted(set(baseline) | set(current)):
        base_codes = baseline.get(path, {})
        curr_codes = current.get(path, {})
        for code in sorted(set(base_codes) | set(curr_codes)):
            before = base_codes.get(code, 0)
            after = curr_codes.get(code, 0)
            if after > before:
                state = "new" if before == 0 else f"was {before}"
                regressions.append(f"{path}: {code} {state} -> now {after}")
            elif after < before:
                improvements.append(f"{path}: {code} {before} -> {after}")
    return regressions, improvements


def print_summary(current: dict[str, dict[str, int]]) -> None:
    """Print per-rule totals, largest offenders first."""
    by_code: Counter[str] = Counter()
    for codes in current.values():
        by_code.update(codes)
    total = sum(by_code.values())
    print(f"{total} violation(s) across {len(current)} file(s), {len(by_code)} rule(s):")
    for code, n in by_code.most_common():
        print(f"  {code:8} {n:5}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--update",
        action="store_true",
        help="re-record the baseline from the current tree",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="print per-rule totals and exit without gating",
    )
    args = parser.parse_args(argv)

    try:
        current = tally(collect_violations())
    except (RuffNotFoundError, RuntimeError) as exc:
        print(f"ruff-gate: {exc}", file=sys.stderr)
        return 2

    if args.summary:
        print_summary(current)
        return 0

    if args.update:
        total = write_baseline(current)
        print(f"ruff-gate: baseline written to {BASELINE_FILE.name} ({total} violations)")
        return 0

    baseline = load_baseline()
    if not baseline and not BASELINE_FILE.is_file():
        print(
            f"ruff-gate: no baseline at {BASELINE_FILE.name}. "
            "Create one with --update.",
            file=sys.stderr,
        )
        return 2

    regressions, improvements = diff(baseline, current)

    for line in improvements:
        print(f"  improved  {line}")
    if improvements:
        print(
            f"\nruff-gate: {len(improvements)} violation(s) fixed since the baseline. "
            "Tighten it with: python3 scripts/ruff_gate.py --update"
        )

    if regressions:
        print("", file=sys.stderr)
        for line in regressions:
            print(f"  NEW  {line}", file=sys.stderr)
        print(
            f"\nruff-gate: {len(regressions)} new ruff violation(s) past the "
            "committed baseline.\n"
            "  Fix them, or — if the rule is wrong for this codebase — argue "
            "for a config\n"
            "  change in the PR rather than re-recording the baseline.\n"
            "  See the baseline section of CONTRIBUTING.md.",
            file=sys.stderr,
        )
        return 1

    base_total = sum(sum(c.values()) for c in baseline.values())
    curr_total = sum(sum(c.values()) for c in current.values())
    print(f"ruff-gate: no new violations ({curr_total} total, baseline {base_total})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
