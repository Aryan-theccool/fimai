# fimai

Working tree for an open-source contribution to [FIM Labs](https://github.com/fim-ai).

The upstream clone this work was developed against lives outside the tracked
repo (the sandbox wipes it between turns), so everything is persisted here as
`git am`-able patches plus the authored files.

## Layout

```
fim-one-contribution/
├── DELIVERABLES.md      commands run + results, file list, regeneration and
│                        verification steps, ready-to-paste GitHub issue and PR
│                        text, and every blocker hit
├── patches/
│   ├── 0001-chore-lint-ratchet-ruff-against-a-committed-baseline.patch
│   └── 0001-feat-frontend-generate-API-types-from-the-OpenAPI-sp.patch
└── files/               the authored sources, readable without applying anything
    ├── scripts/ruff_gate.py
    ├── scripts/export_openapi.py
    ├── ruff-baseline.json
    ├── pyproject.toml
    └── frontend-src-lib/{api.ts, __tests__/api-generated.test.ts}
```

## The two changes

Both target `fim-ai/fim-one` (`master` @ `e1b0d005`) as independent branches.

| Branch | Commit | Change |
|---|---|---|
| `fix/ruff-lint-gate` | `07850fb3` | Makes the lint gate `CONTRIBUTING.md` documents real: a committed ruff baseline ratchet that fails CI only on *new* violations, plus a version bound and an Alembic-migrations exemption. Zero Python source files touched. |
| `feat/openapi-typed-client` | `59434bf8` | Generates frontend API types from the backend's own pydantic models and migrates 16 of 46 hand-written interfaces onto them. Found 7 live field-name bugs where the admin UI reads fields the API never returns. |

## Applying a patch to your own fork

```bash
git clone https://github.com/<you>/fim-one.git && cd fim-one
git remote add upstream https://github.com/fim-ai/fim-one.git
git fetch upstream && git checkout -b fix/ruff-lint-gate upstream/master
git am /path/to/fim-one-contribution/patches/0001-chore-lint-*.patch
```

Repeat from `upstream/master` with a new branch name for the second patch.

## Verification status

Backend: `pytest` 4166 passed · `mypy --strict` clean on 437 files · lint gate
green · docs link gate clean.
Frontend: `tsc --noEmit` clean · `eslint` 0 errors · `vitest` 161 passed ·
production build verified with a temporary local-font substitution because
`fonts.googleapis.com` is unreachable from this sandbox (see DELIVERABLES.md §7).
