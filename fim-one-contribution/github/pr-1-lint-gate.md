Closes #ISSUE_A#

## What

Makes the lint gate CONTRIBUTING documents real, without rewriting 291 files.

- **new** `scripts/ruff_gate.py` — fails CI only when a PR *adds* a ruff violation, comparing against a committed per-file/per-rule baseline
- **new** `ruff-baseline.json` — 1724 violations across 356 files, 48 rules
- `pyproject.toml` — bound `ruff` to `>=0.15,<0.16`; add `per-file-ignores` for Alembic's `migrations/versions/`
- `.github/workflows/test.yml` — run the gate in the backend job
- `CONTRIBUTING.md` — the real command, plus a *Lint Baseline (ratchet)* section
- `README.md` — tech-stack table said Next.js 14; `package.json` pins `~15.5.12`

## Why

`uv run ruff check src/ tests/` is in both the Development Setup block and the PR checklist, and it does not pass — at any ruff version:

| ruff | violations |
|---|---|
| 0.8.0 | 2095 |
| 0.15.2 (resolved by `uv.lock` today) | 2106 |

Nothing enforced it: CI runs mypy, pytest and the docs-link gate but never ruff, and the pre-commit hook type-checks staged files without linting them.

Both direct fixes were measured and rejected:

- `ruff check --select I001,F401 --fix` alone rewrites **291 files** — it would bury the actual change in mechanical churn.
- Ignoring the ~48 rules that fire would empty the declared rule set of meaning and delete the signal the project says it wants.

So ruff gets what mypy already got here. `scripts/hooks/pre-commit` records *"the entire codebase is now mypy-clean (699/699 errors resolved)"* — that was a burn-down from a committed number to zero. This starts ruff on the same path instead of pretending it is already there.

## Design notes

- **Ratchet, not freeze.** Removals are reported and never fail a run, so a cleanup PR cannot be blocked by its own progress; it re-records with `--update` in the same commit.
- **New files start at zero.** No free budget.
- **The version bound is load-bearing.** A baseline is only meaningful against a known rule set; a floating `ruff>=0.8` let every `uv lock` move the number (2095 → 2106 between 0.8.0 and 0.15.2).
- **Migrations are exempt on purpose.** 382 violations, mostly the `UP007`/`UP035` that alembic's own template emits (`from typing import Sequence, Union`). A migration that already ran against a database is a historical record; reformatting it is worse than not linting it.
- **Follows the repo's existing gate pattern** — `scripts/check_md_links.py` and `scripts/eval_stamp.py` are the same shape: a stdlib-only script, a docstring explaining the failure mode it exists to catch, and a CI/hook call site.

## Before / after risk

| | Before | After |
|---|---|---|
| Can a PR add lint debt? | Yes, silently — nothing runs ruff | No — CI fails with the file, rule and count |
| Does `ruff check src/ tests/` pass? | No (2106) | Still no (1724) — but it is now a measured, shrinking number instead of an unenforced claim |
| Cost to a contributor today | A documented command that always fails, so it gets ignored | One command that passes, and a precise list of what to fix if it doesn't |
| Can the number drift under people? | Yes — unpinned `ruff>=0.8` | No — bounded to `>=0.15,<0.16` |
| Blast radius of this PR | — | **Zero Python source files touched.** Config, one new script, one new data file, CI, docs. |

## Verification

```
uv run python scripts/ruff_gate.py     -> no new violations (1724 total, baseline 1724)
uv run mypy src/fim_one/               -> Success: no issues found in 437 source files
uv run pytest -x -q -m "not docker"    -> 4166 passed, 2 skipped, 6 deselected
python3 scripts/check_md_links.py      -> md-links: 293 file(s) clean
uv sync --all-extras --locked          -> Resolved 154 packages (lock consistent, 1-line diff)
uv run mypy scripts/ruff_gate.py       -> Success (strict)
uv run ruff check scripts/ruff_gate.py -> All checks passed
```

Negative test — the gate has to be able to fail. Appending an unused import and a 126-char line to `tests/test_calculator.py`:

```
  NEW  tests/test_calculator.py: E402 new -> now 1
  NEW  tests/test_calculator.py: E501 new -> now 1
  NEW  tests/test_calculator.py: F401 new -> now 1

ruff-gate: 3 new ruff violation(s) past the committed baseline.
exit 1
```

Reverting the file returns exit 0.

## Deliberately not in this PR

- **The 6 `F821` undefined-name errors** in `tests/test_database_meta_tool.py` (`Any` used at 1173/1174/1192/1193/1207/1208, never imported). One-line fix, but that file already carries **19 mypy errors**, so the pre-commit hook — which runs `xargs uv run mypy` on staged files — rejects any commit touching it. Reported in the issue; better as its own change, ideally alongside widening CI's mypy scope to `tests/`.
- **Burning down any of the 1724.** Every one of them is now visible and attributable via `--summary`; the burn-down is the point of the ratchet, not of this PR.
- **Locale READMEs.** `README.zh/ja/ko/de/fr.md` still say Next.js 14. Per CONTRIBUTING they are generated and the pre-commit hook refuses manual edits, so they are left to the i18n workflow.
