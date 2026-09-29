# FIM One — Option C contribution deliverables

Two independent branches off `master` of `fim-ai/fim-one`, designed as two
separately reviewable PRs.

| PR | Branch | Commit | Files | +/- |
|---|---|---|---|---|
| 1 — lint gate | `fix/ruff-lint-gate` | `07850fb3` | 7 | +1758 / −6 |
| 2 — OpenAPI types | `feat/openapi-typed-client` | `59434bf8` | 8 | +25696 / −147 |

Patches ready to `git am` are in [`patches/`](patches/); the authored source
files are mirrored in [`files/`](files/) for reading without applying anything.

---

## 1. Exact commands run + results

### Environment bootstrap (sandbox had none of this)

```bash
python3 -m pip install --user --break-system-packages uv     # uv 0.12.20
git clone https://github.com/fim-ai/fim-one.git              # master @ e1b0d005
cd fim-one && uv sync --all-extras --python 3.11             # 154 packages
npm i -g pnpm@10 && cd frontend && pnpm install --frozen-lockfile   # pnpm 9.15.9 via packageManager
```

Note: `astral.sh` and `github.com/.../releases/download` are TLS-blocked in this
sandbox, so the usual `curl … | sh` uv installer and `uv python install` both
fail. pip + system Python 3.11.2 works.

### Baseline (before touching anything)

```bash
uv run pytest -x -q -m "not docker"     -> 4166 passed, 2 skipped, 6 deselected (3m24s)
uv run mypy src/fim_one/                -> Success: no issues found in 437 source files
uv run ruff check src/ tests/           -> Found 2106 errors   [ruff 0.15.2]
python3 -c "create_app()"               -> app created, 431 routes
```

### The two investigations that changed the plan

```bash
# (a) Is the ruff noise a version-drift problem?  NO.
uvx ruff@0.8.0  check src/ tests/ | grep -c ':'   -> 2095
uvx ruff@0.9.9  check src/ tests/                 -> 2095-ish
uvx ruff@0.11.13 check src/ tests/                -> 2095-ish
uvx ruff@0.14.6 check src/ tests/                 -> ~2106
uv run ruff check src/ tests/                     -> 2106   [0.15.2]

# (b) How big is the "just autofix it" option?  Too big.
uv run ruff check src/ tests/ --select I001,F401 --output-format concise \
  | grep -oE '^[^:]+' | sort -u | wc -l           -> 291 files

# (c) What does the published spec actually cover?
uv run python scripts/export_openapi.py           -> Exported 12 paths
uv run python -c "…count include_in_schema…"      -> 427 APIRoutes, 16 in schema, 411 excluded
grep -n "_PUBLIC_API" -A 20 src/fim_one/web/app.py -> 16-entry allowlist at app.py:450-476

# (d) What would the internal spec give?
uv run python scripts/export_openapi.py --internal -> 351 paths, 294 schemas (883 KB)
npx openapi-typescript@7 …                         -> 25,235 lines / 757 KB
```

### Post-change verification

```bash
# --- PR 1 (fix/ruff-lint-gate) ---
uv run python scripts/ruff_gate.py            -> no new violations (1724 total, baseline 1724)
uv run python scripts/ruff_gate.py --summary  -> 1724 across 356 files, 48 rules
uv run mypy src/fim_one/                      -> Success: 437 source files
uv run pytest -x -q -m "not docker"           -> 4166 passed, 2 skipped (3m56s)
python3 scripts/check_md_links.py             -> md-links: 293 file(s) clean
uv sync --all-extras --locked                 -> Resolved 154 packages (lock consistent)
# negative test — injected F401 + E501 + E402 into tests/test_calculator.py:
uv run python scripts/ruff_gate.py            -> exit 1, names all three, then restored -> exit 0

# --- PR 2 (feat/openapi-typed-client) ---
uv run python scripts/export_openapi.py                 -> 12 paths; git diff docs/openapi.json EMPTY
uv run python scripts/export_openapi.py --internal      -> 351 paths, 294 schemas, 411 routes un-hidden
uv run mypy src/fim_one/__init__.py scripts/export_openapi.py -> Success: 2 source files
uv run ruff check scripts/export_openapi.py             -> All checks passed
uv run pytest tests/test_openapi_parser.py -q           -> 20 passed
cd frontend && pnpm install --frozen-lockfile           -> Lockfile is up to date
cd frontend && pnpm exec tsc --noEmit                   -> clean (exit 0)
cd frontend && pnpm lint                                -> 0 errors, 13 warnings (pre-existing; 2 fewer than before)
cd frontend && pnpm test                                -> 15 files, 161 passed (was 14/155)
cd frontend && pnpm build                               -> BLOCKED, see §7
```

---

## 2. Final file list

### PR 1 — `fix/ruff-lint-gate` (`chore(lint): ratchet ruff against a committed baseline`)

| File | Change |
|---|---|
| `scripts/ruff_gate.py` | **new**, 253 lines — the ratchet gate |
| `ruff-baseline.json` | **new**, 30 KB — per-file/per-rule counts, 1724 violations / 356 files |
| `pyproject.toml` | `ruff>=0.8` → `ruff>=0.15,<0.16` (+why comment); new `[tool.ruff.lint.per-file-ignores]` for `migrations/versions/*` |
| `uv.lock` | **1 line** — the recorded ruff specifier |
| `.github/workflows/test.yml` | +1 step `Lint ratchet (ruff baseline)` in the backend job |
| `CONTRIBUTING.md` | dev-setup command, `### Lint Baseline (ratchet)` section, PR-checklist line |
| `README.md` | **1 line** — tech-stack table `Next.js 14` → `Next.js 15` (package.json pins `next ~15.5.12`) |

Zero Python source files touched.

### PR 2 — `feat/openapi-typed-client` (`feat(frontend): generate API types from the OpenAPI spec`)

| File | Change |
|---|---|
| `scripts/export_openapi.py` | +`--internal` / `--out`, `unhide_routes()`; public path unchanged |
| `frontend/src/lib/api-generated.ts` | **new**, 25,235 lines — generated, committed |
| `frontend/src/lib/api.ts` | 16 interfaces → `components["schemas"][…]` aliases; 2 dead interfaces removed; header comment explaining the split |
| `frontend/src/lib/__tests__/api-generated.test.ts` | **new**, 123 lines — 6 tests |
| `frontend/package.json` | +`openapi-typescript@^7` devDep; +`gen:api`, +`gen:api:export` scripts |
| `frontend/pnpm-lock.yaml` | transitive deps of the above only (lockfileVersion stays `9.0`) |
| `frontend/.gitignore` | ignore `/openapi.json` (the intermediate internal spec) |
| `CONTRIBUTING.md` | `### Generated API Types` section + 1 PR-checklist line |

**Migrated (16):** `DashboardStats`, `DashboardConversation`, `DashboardAgent`,
`DashboardKB`, `DashboardConnectorHealth`, `DashboardDayStat`,
`DashboardWorkflowRun`, `AdminLoginStats`, `AdminActiveSession`,
`AdminAnnouncement`, `AdminCredentialStats`, `AdminNotificationConfig`,
`AdminSensitiveWord`, `AdminUsageEntry`, `AdminTrendEntry`, `ConnectorStats`.

**Left hand-written (30)** — reasons are in the commit message and §6.

---

## 3. How to regenerate the OpenAPI types

```bash
cd frontend
pnpm gen:api:export   # -> uv run python scripts/export_openapi.py --internal
                      #    writes frontend/openapi.json (gitignored), 351 paths
pnpm gen:api          # -> openapi-typescript openapi.json -o src/lib/api-generated.ts
```

Commit `src/lib/api-generated.ts` with the backend change that prompted it.
`docs/openapi.json` (the public spec) is **not** touched by this flow —
regenerate it separately with `uv run python scripts/export_openapi.py`.

---

## 4. How to verify

```bash
uv sync --all-extras                     # backend deps (ruff is in the dev extra)

# --- lint / types / tests ---
uv run python scripts/ruff_gate.py       # PR1 gate: exit 0 == no new violations
uv run python scripts/ruff_gate.py --summary
uv run ruff check src/ tests/            # raw output: ~1.7k pre-existing, expected
uv run mypy src/fim_one/                 # strict, must be clean
uv run pytest -x -q -m "not docker"      # 4166 passed

# --- frontend ---
cd frontend && pnpm install --frozen-lockfile
pnpm exec tsc --noEmit                   # type check incl. api-generated.ts + tests
pnpm lint                                # eslint: 0 errors
pnpm test                                # vitest: 15 files / 161 passed
pnpm build                               # production build (needs fonts.googleapis.com)

# --- spec round-trip ---
uv run python scripts/export_openapi.py && git diff --exit-code docs/openapi.json
python3 scripts/check_md_links.py
```

---

## 5. GitHub issues to open first

CONTRIBUTING asks for an issue before anything large, and ranks bug reports
above code. One issue per PR.

### Issue A (open with PR 1)

**Title:** `The documented lint gate has never passed: \`ruff check src/ tests/\` reports ~2.1k violations and nothing runs ruff in CI`

**Body:**

```markdown
### What I found

`CONTRIBUTING.md` lists `uv run ruff check src/ tests/` as a PR requirement
(both in *Development Setup → Backend* and in the *Pull Request Checklist*).
That command does not pass, and has not at any ruff version:

| ruff | violations in `src/ tests/` |
|---|---|
| 0.8.0 | 2095 |
| 0.9.9 | ~2095 |
| 0.11.13 | ~2095 |
| 0.15.2 (what `uv.lock` resolves today) | 2106 |

So this is not version drift — pinning ruff cannot make the command green.
Nothing enforces it either: `.github/workflows/test.yml` runs mypy + pytest +
the docs link gate but never ruff, and `scripts/hooks/pre-commit` type-checks
staged files without linting them.

Top rules: `E501` 576, `I001` 321, `UP007` 193, `F401` 186, `E402` 106,
`RUF001` 91, `UP035` 90, `UP017` 73, `RUF100` 56, `SIM117` 55.

### Why the two obvious fixes are both wrong

- **Autofix everything.** `--select I001,F401 --fix` alone rewrites **291
  files**. That buries any real change in mechanical churn, against
  CONTRIBUTING's "keep changes focused".
- **Relax the config until it passes.** ~48 rules currently fire; ignoring them
  empties `select = ["E","F","I","N","UP","B","SIM","RUF"]` of meaning.

### Proposal: ratchet it, the way mypy was ratcheted

`scripts/hooks/pre-commit` records that this codebase went *"699/699 errors
resolved"* to reach a strict-clean `src/`. Ruff can follow the same path: a
committed per-file/per-rule baseline, and CI fails only when a PR **adds** a
violation. Removals are reported and never fail, so cleanup PRs are never
blocked by their own progress. New files start at zero.

That is #… (PR link). It also:

- bounds ruff to `>=0.15,<0.16`, since a baseline is only meaningful against a
  known rule set (a floating `>=0.8` let every `uv lock` move the number);
- exempts Alembic's `migrations/versions/` via `per-file-ignores` — 382
  violations, mostly the `UP007`/`UP035` that alembic's own template emits, in
  files that are a historical record of what already ran against a database.

### Two defects the audit turned up (separate from the proposal)

1. **`F821` — 6 real undefined names.** `tests/test_database_meta_tool.py`
   uses `Any` at lines 1173/1174/1192/1193/1207/1208 but never imports it.
   `mypy` agrees (`Did you forget to import it from "typing"?`). It does not
   blow up at runtime only because the file has
   `from __future__ import annotations`, and CI runs `mypy src/fim_one/` so
   `tests/` is never type-checked. One-line fix: add `from typing import Any`.

   I did **not** include it in the PR: that file already carries **19 mypy
   errors**, so the pre-commit hook (`xargs uv run mypy` on staged files)
   rejects any commit touching it until they are cleared. Worth its own issue —
   *"tests/ is outside the mypy scope, so the pre-commit hook blocks any edit
   to a test file that has pre-existing errors."*

2. **`README.md` tech-stack table says `Next.js 14`;** `frontend/package.json`
   pins `next ~15.5.12`. Fixed in the PR (1 line). Locale READMEs are
   generated, so I left them to the i18n workflow.

### Environment

fim-one `master` @ `e1b0d005`, Python 3.11.2, uv 0.12.20, Debian bookworm.
```

### Issue B (open with PR 2)

**Title:** `docs/openapi.json covers 12 of 427 routes, so the frontend's hand-written API types can't be generated from it — plus 7 live field-name bugs found while wiring codegen up`

**Body:**

```markdown
### Context

`PARKED.md` calls *"Typed frontend from OpenAPI"* the cheapest parked item and
the only one with a standing cost: `docs/openapi.json` is exported, nothing
consumes it, and `frontend/src/lib/api.ts` carries ~50 hand-written interfaces
that drift by construction. I picked it up and hit a blocker worth recording
before anyone else tries.

### Blocker: the exported spec is the *public* spec, not the app's spec

`src/fim_one/web/app.py:450-476` hides every route and re-enables a 16-entry
`_PUBLIC_API` allowlist:

```
APIRoutes total: 427
in schema:        16
excluded:        411
```

So `docs/openapi.json` has **12 paths / 14 schemas**. Generating frontend types
from it yields 975 lines that cannot type the portal client — the portal talks
to `/api/admin/*`, `/api/dashboard/*`, `/api/market/*`, none of which are in the
allowlist. The 14 schemas are almost entirely request bodies; there is no
`Agent`, `Conversation` or `KnowledgeBase` entity schema at all.

**Proposal:** keep `docs/openapi.json` exactly as it is (it is the published
public API document) and add an `--internal` export for codegen. That gives
**351 paths / 294 schemas**. This is a dev-only artifact; it publishes nothing
and changes no route's visibility.

### Second obstacle: a parallel hand-written type surface

`frontend/src/types/admin.ts` declares its own 21 interfaces, several of which
are second copies of the ones in `lib/api.ts` with **different optionality**.
Aliasing `AdminAgentInfo`, `AdminApiKeyInfo`, `AdminApiKeyCreated`,
`AdminKBDoc`, `AdminKBDetail` and `AdminLoginHistoryEntry` to their spec
schemas makes `tsc` fail at `admin-agents.tsx:98`, `admin-api-keys.tsx:112`
and `:140`, `admin-knowledge-bases.tsx:184`, `admin-security.tsx:143` — e.g.
`string | null | undefined` is not assignable to `string | null`. The
duplication, not the codegen, is what blocks those six. Collapsing it looks
like a good follow-up.

### The payoff: 7 live bugs the hand-written types were hiding

Field names in `lib/api.ts` that do not exist on the backend model. TypeScript
is happy; the UI renders a placeholder.

| Frontend read | Backend field | Effect |
|---|---|---|
| `admin-analytics.tsx:427` `item.owner` | `owner_username` (`admin_analytics.py:57`) | Agent analytics "owner" column always `--` |
| `admin-analytics.tsx:601` `item.owner` | `owner_username` (`admin_analytics.py:77`) | Workflow analytics "owner" column always `--` |
| `admin-analytics.tsx:428` `item.conversations` | `total_conversations` (`:58`) | always `0` |
| `admin-analytics.tsx:430` `item.avg_tokens_per_conv` | `avg_tokens_per_conversation` (`:60`) | always `0` |
| `admin-analytics.tsx:522` `item.errors` | `error_count` (`:68`) | always `0` |
| `admin-skills.tsx:270` `skill.agents_using` | `agent_count` (`admin_skills.py:49`) | "agents using" column always blank |
| `admin-skills.tsx:369,373` `detailTarget.system_prompt` | *no such field* (`admin_skills.py:53-57`) | detail block never renders |

`admin_analytics.py` even computes the value behind `agents_using` —
`_count_agents_using_skill()` at `admin_skills.py:78` — and returns it as
`agent_count`.

I have **not** fixed these in the codegen PR because they change what the admin
UI renders, which is your call and would want its own changelog line. Say the
word and I'll send them as a focused `fix(frontend):` PR — it is 7 line edits
once the types are generated.

### Related: endpoints with no `response_model`

~13 of the 46 interfaces in `lib/api.ts` have no spec counterpart at all
because their endpoint returns an untyped dict: `AdminEvalDataset`,
`AdminEvalRun`, `AdminSchedule`, `AdminCredential`, `AdminReview`,
`MarketItem`, `UserOrg`, `OrgMember`, `AdminWorkflowInfo`, `AdminIpRule`,
`AdminNotificationEvent`, `AdminCostProjection`, `AdminReviewStats`. Adding
`response_model=` to those is what makes them migratable — happy to do that as
a follow-up if you want it.

### Environment

fim-one `master` @ `e1b0d005`, Python 3.11.2, node 22.22.3, pnpm 9.15.9.
```

---

## 6. Ready-to-paste PR descriptions

### PR 1

**Title:** `chore(lint): ratchet ruff against a committed baseline`

**Branch:** `fix/ruff-lint-gate` → `fim-ai/fim-one:master`
**Issue:** closes #(issue A)

```markdown
## What

Makes the lint gate CONTRIBUTING documents real, without rewriting 291 files.

- **new** `scripts/ruff_gate.py` — fails CI only when a PR *adds* a ruff
  violation, comparing against a committed per-file/per-rule baseline
- **new** `ruff-baseline.json` — 1724 violations across 356 files, 48 rules
- `pyproject.toml` — bound `ruff` to `>=0.15,<0.16`; add `per-file-ignores` for
  Alembic's `migrations/versions/`
- `.github/workflows/test.yml` — run the gate in the backend job
- `CONTRIBUTING.md` — the real command, plus a *Lint Baseline (ratchet)* section
- `README.md` — tech-stack table said Next.js 14; `package.json` pins `~15.5.12`

## Why

`uv run ruff check src/ tests/` is in both the Development Setup block and the
PR checklist, and it does not pass — at any ruff version:

| ruff | violations |
|---|---|
| 0.8.0 | 2095 |
| 0.15.2 (resolved by `uv.lock` today) | 2106 |

Nothing enforced it: CI runs mypy, pytest and the docs-link gate but never
ruff, and the pre-commit hook type-checks staged files without linting them.

Both direct fixes were measured and rejected:

- `ruff check --select I001,F401 --fix` alone rewrites **291 files** — it would
  bury the actual change in mechanical churn.
- Ignoring the ~48 rules that fire would empty the declared rule set of
  meaning and delete the signal the project says it wants.

So ruff gets what mypy already got here. `scripts/hooks/pre-commit` records
*"the entire codebase is now mypy-clean (699/699 errors resolved)"* — that was
a burn-down from a committed number to zero. This starts ruff on the same path
instead of pretending it is already there.

## Design notes

- **Ratchet, not freeze.** Removals are reported and never fail a run, so a
  cleanup PR cannot be blocked by its own progress; it re-records with
  `--update` in the same commit.
- **New files start at zero.** No free budget.
- **The version bound is load-bearing.** A baseline is only meaningful against
  a known rule set; a floating `ruff>=0.8` let every `uv lock` move the number
  (2095 → 2106 between 0.8.0 and 0.15.2).
- **Migrations are exempt on purpose.** 382 violations, mostly the
  `UP007`/`UP035` that alembic's own template emits
  (`from typing import Sequence, Union`). A migration that already ran against
  a database is a historical record; reformatting it is worse than not linting
  it.
- **Follows the repo's existing gate pattern** — `scripts/check_md_links.py`
  and `scripts/eval_stamp.py` are the same shape: a stdlib-only script, a
  docstring explaining the failure mode it exists to catch, and a CI/hook call
  site.

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

Negative test — the gate has to be able to fail. Appending an unused import and
a 126-char line to `tests/test_calculator.py`:

```
  NEW  tests/test_calculator.py: E402 new -> now 1
  NEW  tests/test_calculator.py: E501 new -> now 1
  NEW  tests/test_calculator.py: F401 new -> now 1

ruff-gate: 3 new ruff violation(s) past the committed baseline.
exit 1
```

Reverting the file returns exit 0.

## Deliberately not in this PR

- **The 6 `F821` undefined-name errors** in `tests/test_database_meta_tool.py`
  (`Any` used at 1173/1174/1192/1193/1207/1208, never imported). One-line fix,
  but that file already carries **19 mypy errors**, so the pre-commit hook —
  which runs `xargs uv run mypy` on staged files — rejects any commit touching
  it. Reported in the issue; better as its own change, ideally alongside
  widening CI's mypy scope to `tests/`.
- **Burning down any of the 1724.** Every one of them is now visible and
  attributable via `--summary`; the burn-down is the point of the ratchet, not
  of this PR.
- **Locale READMEs.** `README.zh/ja/ko/de/fr.md` still say Next.js 14. Per
  CONTRIBUTING they are generated and the pre-commit hook refuses manual edits,
  so they are left to the i18n workflow.
```

### PR 2

**Title:** `feat(frontend): generate API types from the OpenAPI spec`

**Branch:** `feat/openapi-typed-client` → `fim-ai/fim-one:master`
**Issue:** closes #(issue B)

```markdown
## What

Picks up the item `PARKED.md` names as the first thing to restart:

> **Typed frontend from OpenAPI** — `docs/openapi.json` is already exported and
> nothing consumes it, while `frontend/src/lib/api.ts` carries roughly 50
> hand-written interfaces that drift by construction. … The last one is the
> cheapest and the only one with a standing cost, so it is the one to pick up
> first if any of this restarts.

- `scripts/export_openapi.py` gains `--internal` / `--out`
- **new** `frontend/src/lib/api-generated.ts` — 351 paths, 294 schemas
- `frontend/src/lib/api.ts` — 16 of 46 interfaces become spec aliases
- **new** `frontend/src/lib/__tests__/api-generated.test.ts` — 6 tests
- `openapi-typescript@^7` devDep + `pnpm gen:api` / `pnpm gen:api:export`
- `CONTRIBUTING.md` — *Generated API Types* section + one checklist line

## Why it needed a new export flag

`web/app.py:450-476` hides every route and re-enables a 16-entry `_PUBLIC_API`
allowlist, so the published spec covers **12 of 427 routes**. Generating from it
produces 975 lines of request-body types that cannot type the portal client —
the portal lives on `/api/admin/*`, `/api/dashboard/*`, `/api/market/*`, all
outside the allowlist.

`--internal` lifts the filter in-process and exports **351 paths / 294 schemas**
to `frontend/openapi.json` (gitignored build artifact). It changes no route's
visibility and publishes nothing.

> The public spec is untouched: `uv run python scripts/export_openapi.py &&
> git diff --exit-code docs/openapi.json` is empty.

## The migration

```ts
// before — 17 fields kept in sync by hand
export interface DashboardStats {
  total_conversations: number
  …
  recent_workflow_runs: DashboardWorkflowRun[]
}

// after
export type DashboardStats = components["schemas"]["DashboardStatsResponse"]
```

`DashboardStatsResponse` turned out to be a field-for-field match, including the
six nested item schemas, so the whole dashboard surface is now spec-derived.
Migrated: the 7 `Dashboard*` types, `AdminLoginStats`, `AdminActiveSession`,
`AdminAnnouncement`, `AdminCredentialStats`, `AdminNotificationConfig`,
`AdminSensitiveWord`, `AdminUsageEntry`, `AdminTrendEntry`, `ConnectorStats`.

`ConnectorCallStat` / `ConnectorActionStat` are deleted: the generated
`ConnectorStatsResponse` references identically-shaped generated versions, which
is what made them dead (eslint flagged both).

## What is *not* migrated, and why

Both reasons are concrete, not neglect.

**1. No schema exists (13).** These endpoints declare no `response_model`, so
the spec emits nothing: `AdminEvalDataset`, `AdminEvalRun`, `AdminSchedule`,
`AdminCredential`, `AdminReview`, `MarketItem`, `UserOrg`, `OrgMember`,
`AdminWorkflowInfo`, `AdminIpRule`, `AdminNotificationEvent`,
`AdminCostProjection`, `AdminReviewStats`. Adding `response_model=` is the
unblocking change — happy to follow up.

**2. A second hand-written copy disagrees (6).** `src/types/admin.ts` declares
its own 21 interfaces, some of them duplicates of the ones in `lib/api.ts` with
different optionality. Aliasing `AdminAgentInfo`, `AdminApiKeyInfo`,
`AdminApiKeyCreated`, `AdminKBDoc`, `AdminKBDetail`, `AdminLoginHistoryEntry`
makes `tsc` fail:

```
admin-agents.tsx(98,17)          description: string | null | undefined  ≠  string | null
admin-api-keys.tsx(112,15)       scopes:      string | null | undefined  ≠  string | null
admin-api-keys.tsx(140,13)       missing is_active, last_used_at, total_requests
admin-knowledge-bases.tsx(184,15) error_message: string | null | undefined ≠ string | null
admin-security.tsx(143,18)       user_id:     string | null | undefined  ≠  string | null
```

The duplication is the obstacle, not the codegen, so those six are left alone
and the reasoning is written into `api.ts` where the next person will see it.

## Bugs this surfaced (reported, **not** fixed here)

Generating the types made seven field-name mismatches visible. TypeScript was
happy; the UI renders a placeholder.

| Frontend read | Backend field | Effect |
|---|---|---|
| `admin-analytics.tsx:427` `item.owner` | `owner_username` (`admin_analytics.py:57`) | always `--` |
| `admin-analytics.tsx:601` `item.owner` | `owner_username` (`:77`) | always `--` |
| `admin-analytics.tsx:428` `item.conversations` | `total_conversations` (`:58`) | always `0` |
| `admin-analytics.tsx:430` `item.avg_tokens_per_conv` | `avg_tokens_per_conversation` (`:60`) | always `0` |
| `admin-analytics.tsx:522` `item.errors` | `error_count` (`:68`) | always `0` |
| `admin-skills.tsx:270` `skill.agents_using` | `agent_count` (`admin_skills.py:49`) | column always blank |
| `admin-skills.tsx:369,373` `detailTarget.system_prompt` | *no such field* (`:53-57`) | block never renders |

These change what the admin UI renders, so they are your call and want their own
changelog line. Say the word and I'll send a focused `fix(frontend):` PR — 7
line edits now that the types exist. This is the standing cost `PARKED.md`
predicted, caught on the first run.

## Before / after risk

| | Before | After |
|---|---|---|
| Can a backend rename silently break the UI? | Yes — 7 already have | Not for the 16 migrated types: `tsc` fails at every call site |
| Source of truth for those 16 types | A human keeping `api.ts` in sync with pydantic | The pydantic models themselves |
| Cost of a backend API change | Nothing, until the UI shows blanks | `pnpm gen:api:export && pnpm gen:api`, commit the file |
| Public API surface | 16 allowlisted routes | **Unchanged** — `docs/openapi.json` is byte-identical |
| Runtime bundle | — | **Unchanged** — `openapi-typescript` is a devDependency and emits types only; the generated file is fully erased at build |
| Repo size | — | +757 KB generated file (25,235 lines), committed so frontend-only contributors need no Python env |
| Review burden of a regeneration | — | One generated file; conflicts resolve by regenerating, never by hand-merging |

## Verification

```
uv run python scripts/export_openapi.py            -> 12 paths; git diff docs/openapi.json EMPTY
uv run python scripts/export_openapi.py --internal -> 351 paths, 294 schemas, 411 routes un-hidden
uv run mypy src/fim_one/ scripts/export_openapi.py -> Success (strict)
uv run ruff check scripts/export_openapi.py        -> All checks passed
uv run pytest tests/test_openapi_parser.py -q      -> 20 passed
pnpm install --frozen-lockfile                     -> Lockfile is up to date
pnpm exec tsc --noEmit                             -> clean
pnpm lint                                          -> 0 errors, 13 warnings (was 15: the 2 dead interfaces are gone)
pnpm test                                          -> 15 files, 161 passed (was 14 / 155)
pnpm build                                         -> see below
```

**`pnpm build` caveat, stated plainly:** it fails in my sandbox because
`next/font/google` cannot reach `fonts.googleapis.com` (TLS blocked; the npm
registry is reachable, so it is a selective block). The failure is in
`src/app/layout.tsx`, which this PR does not touch. To confirm the build
actually compiles my changes I temporarily pointed `layout.tsx` at the repo's
own `public/fonts/CabinetGrotesk-Bold.woff2`, got a **clean production build
(exit 0, all 40+ routes emitted)**, and reverted the file — `git status` shows
`layout.tsx` untouched. On CI, where fonts are reachable, `pnpm build` should
pass normally; flagging it rather than claiming a green build I did not observe.

## Notes for the reviewer

- `frontend/openapi.json` is gitignored on purpose: it is an 883 KB intermediate
  and committing both it and the generated TS would double the churn for no
  review benefit. The TS is committed so a frontend-only contributor never
  needs a Python environment.
- The lockfile diff is entirely `openapi-typescript`'s own transitive tree; no
  existing package changed version and `lockfileVersion` stays `9.0`.
- No i18n strings, no UI components, no routes, no migrations, no agent/workflow
  changes. `docs/*.mdx` untouched, so nothing needs regenerating in the five
  locales.
- This branch is independent of the ruff-gate branch. Both touch
  `CONTRIBUTING.md`; the only plausible conflict is one line in the PR
  checklist, a few seconds to resolve.
```

---

## 7. Blockers hit (nothing invented around them)

1. **`pnpm build` cannot complete in this sandbox.** `next/font/google` fetches
   Inter and JetBrains Mono at build time and `fonts.googleapis.com` is
   TLS-blocked (`SSL_ERROR_SYSCALL`, HTTP 000) while `registry.npmjs.org`
   returns 200. Failure is in `src/app/layout.tsx`, not in anything this work
   touches. Worked around *for verification only* by temporarily pointing the
   two fonts at the repo's local `CabinetGrotesk-Bold.woff2`: clean build,
   exit 0. `layout.tsx` reverted; `git status` confirms it is not in either
   diff. **Not** papered over in code.

2. **`docs/openapi.json` cannot type the frontend.** 12 paths / 14 schemas
   because of the deliberate `_PUBLIC_API` allowlist at `web/app.py:450-476`.
   Addressed by adding `--internal` rather than by changing route visibility,
   which would be a product decision. The public spec is verified
   byte-identical after the change.

3. **6 of the 46 interfaces cannot be aliased yet** — duplicate hand-written
   declarations in `src/types/admin.ts` with different optionality break `tsc`
   at 5 call sites. Reverted those 6 aliases and documented the reason in
   `api.ts` + the PR instead of editing four admin components to force it.

4. **13 interfaces have no spec counterpart at all** — their endpoints declare
   no `response_model`. Reported, not fabricated.

5. **The `F821` fix cannot be committed cleanly.** Adding
   `from typing import Any` to `tests/test_database_meta_tool.py` is correct and
   drops that file's mypy errors 19 → 13, but the pre-commit hook runs mypy on
   staged files and would still reject the commit. Reverted; reported in Issue A.

6. **`scripts/export_openapi.py` emits a mypy `import-untyped` note** for
   `from fim_one.web.app import create_app`. **Pre-existing** — the original
   file reports it at line 16 too, because `src/` has no `py.typed`. It
   disappears when a `src/` file shares the command line, exactly the dual
   regime the existing `[[tool.mypy.overrides]] module = "evals.*"` block
   documents. I did not add a `scripts.*` override: `scripts/` is not
   mypy-clean anyway (`check_md_links.py:85` is missing a return annotation),
   so an override would not have made it pass.

7. **Sandbox resets between turns wiped `/home/user/fim-contribution`** (only
   the tracked `/home/user/fimai` repo persists, and `~/.local` is excluded from
   snapshots). Re-cloned and re-installed once. Everything is therefore
   mirrored into `/home/user/fimai/fim-one-contribution/` as `git am`-able
   patches plus the authored files, so the work survives independent of the
   clone.

8. **No LLM API key** anywhere in this work — none of it needs one, as
   requested. `evals/` was not run (it requires a real LLM); no watched file in
   `scripts/eval_stamp.py` is touched by either PR, so no eval stamp is needed.
