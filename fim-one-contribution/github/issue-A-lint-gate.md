### What I found

`CONTRIBUTING.md` lists `uv run ruff check src/ tests/` as a PR requirement (both in *Development Setup → Backend* and in the *Pull Request Checklist*). That command does not pass, and has not at any ruff version:

| ruff | violations in `src/ tests/` |
|---|---|
| 0.8.0 | 2095 |
| 0.9.9 | ~2095 |
| 0.11.13 | ~2095 |
| 0.15.2 (what `uv.lock` resolves today) | 2106 |

So this is not version drift — pinning ruff cannot make the command green. Nothing enforces it either: `.github/workflows/test.yml` runs mypy, pytest and the docs-link gate but never ruff, and `scripts/hooks/pre-commit` type-checks staged files without linting them.

Top rules: `E501` 576, `I001` 321, `UP007` 193, `F401` 186, `E402` 106, `RUF001` 91, `UP035` 90, `UP017` 73, `RUF100` 56, `SIM117` 55.

### Why the two obvious fixes are both wrong

- **Autofix everything.** `--select I001,F401 --fix` alone rewrites **291 files**. That buries any real change in mechanical churn, against CONTRIBUTING's "keep changes focused".
- **Relax the config until it passes.** ~48 rules currently fire; ignoring them empties `select = ["E","F","I","N","UP","B","SIM","RUF"]` of meaning.

### Proposal: ratchet it, the way mypy was ratcheted

`scripts/hooks/pre-commit` records that this codebase went *"699/699 errors resolved"* to reach a strict-clean `src/`. Ruff can follow the same path: a committed per-file/per-rule baseline, and CI fails only when a PR **adds** a violation. Removals are reported and never fail, so cleanup PRs are never blocked by their own progress. New files start at zero.

Implementation is ready in the linked PR. It also:

- bounds ruff to `>=0.15,<0.16`, since a baseline is only meaningful against a known rule set (a floating `>=0.8` let every `uv lock` move the number);
- exempts Alembic's `migrations/versions/` via `per-file-ignores` — 382 violations, mostly the `UP007`/`UP035` that alembic's own template emits, in files that are a historical record of what already ran against a database.

### Two defects the audit turned up (separate from the proposal)

1. **`F821` — 6 real undefined names.** `tests/test_database_meta_tool.py` uses `Any` at lines 1173/1174/1192/1193/1207/1208 but never imports it. `mypy` agrees (`Did you forget to import it from "typing"?`). It does not blow up at runtime only because the file has `from __future__ import annotations`, and CI runs `mypy src/fim_one/` so `tests/` is never type-checked. One-line fix: add `from typing import Any`.

   I did **not** include it in the PR: that file already carries **19 mypy errors**, so the pre-commit hook (`xargs uv run mypy` on staged files) rejects any commit touching it until they are cleared. Worth its own issue — *"tests/ is outside the mypy scope, so the pre-commit hook blocks any edit to a test file that has pre-existing errors."*

2. **`README.md` tech-stack table says `Next.js 14`;** `frontend/package.json` pins `next ~15.5.12`. Fixed in the PR (1 line). Locale READMEs are generated, so I left them to the i18n workflow.

### Environment

fim-one `master` @ `e1b0d005`, Python 3.11.2, uv 0.12.20, Debian bookworm.
