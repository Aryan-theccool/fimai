Closes #ISSUE_B#

## What

Picks up the item `PARKED.md` names as the first thing to restart:

> **Typed frontend from OpenAPI** — `docs/openapi.json` is already exported and nothing consumes it, while `frontend/src/lib/api.ts` carries roughly 50 hand-written interfaces that drift by construction. … The last one is the cheapest and the only one with a standing cost, so it is the one to pick up first if any of this restarts.

- `scripts/export_openapi.py` gains `--internal` / `--out`
- **new** `frontend/src/lib/api-generated.ts` — 351 paths, 294 schemas
- `frontend/src/lib/api.ts` — 16 of 46 interfaces become spec aliases
- **new** `frontend/src/lib/__tests__/api-generated.test.ts` — 6 tests
- `openapi-typescript@^7` devDep + `pnpm gen:api` / `pnpm gen:api:export`
- `CONTRIBUTING.md` — *Generated API Types* section + one checklist line

## Why it needed a new export flag

`web/app.py:450-476` hides every route and re-enables a 16-entry `_PUBLIC_API` allowlist, so the published spec covers **12 of 427 routes**. Generating from it produces 975 lines of request-body types that cannot type the portal client — the portal lives on `/api/admin/*`, `/api/dashboard/*`, `/api/market/*`, all outside the allowlist.

`--internal` lifts the filter in-process and exports **351 paths / 294 schemas** to `frontend/openapi.json` (gitignored build artifact). It changes no route's visibility and publishes nothing.

> The public spec is untouched: `uv run python scripts/export_openapi.py && git diff --exit-code docs/openapi.json` is empty.

## The migration

```ts
// before — 17 fields kept in sync by hand
export interface DashboardStats {
  total_conversations: number
  // ...
  recent_workflow_runs: DashboardWorkflowRun[]
}

// after
export type DashboardStats = components["schemas"]["DashboardStatsResponse"]
```

`DashboardStatsResponse` turned out to be a field-for-field match, including the six nested item schemas, so the whole dashboard surface is now spec-derived. Migrated: the 7 `Dashboard*` types, `AdminLoginStats`, `AdminActiveSession`, `AdminAnnouncement`, `AdminCredentialStats`, `AdminNotificationConfig`, `AdminSensitiveWord`, `AdminUsageEntry`, `AdminTrendEntry`, `ConnectorStats`.

`ConnectorCallStat` / `ConnectorActionStat` are deleted: the generated `ConnectorStatsResponse` references identically-shaped generated versions, which is what made them dead (eslint flagged both).

## What is *not* migrated, and why

Both reasons are concrete, not neglect.

**1. No schema exists (13).** These endpoints declare no `response_model`, so the spec emits nothing: `AdminEvalDataset`, `AdminEvalRun`, `AdminSchedule`, `AdminCredential`, `AdminReview`, `MarketItem`, `UserOrg`, `OrgMember`, `AdminWorkflowInfo`, `AdminIpRule`, `AdminNotificationEvent`, `AdminCostProjection`, `AdminReviewStats`. Adding `response_model=` is the unblocking change — happy to follow up.

**2. A second hand-written copy disagrees (6).** `src/types/admin.ts` declares its own 21 interfaces, some of them duplicates of the ones in `lib/api.ts` with different optionality. Aliasing `AdminAgentInfo`, `AdminApiKeyInfo`, `AdminApiKeyCreated`, `AdminKBDoc`, `AdminKBDetail`, `AdminLoginHistoryEntry` makes `tsc` fail:

```
admin-agents.tsx(98,17)           description:   string | null | undefined  !=  string | null
admin-api-keys.tsx(112,15)        scopes:        string | null | undefined  !=  string | null
admin-api-keys.tsx(140,13)        missing is_active, last_used_at, total_requests
admin-knowledge-bases.tsx(184,15) error_message: string | null | undefined  !=  string | null
admin-security.tsx(143,18)        user_id:       string | null | undefined  !=  string | null
```

The duplication is the obstacle, not the codegen, so those six are left alone and the reasoning is written into `api.ts` where the next person will see it.

## Bugs this surfaced (reported, **not** fixed here)

Generating the types made seven field-name mismatches visible. TypeScript was happy; the UI renders a placeholder.

| Frontend read | Backend field | Effect |
|---|---|---|
| `admin-analytics.tsx:427` `item.owner` | `owner_username` (`admin_analytics.py:57`) | always `--` |
| `admin-analytics.tsx:601` `item.owner` | `owner_username` (`:77`) | always `--` |
| `admin-analytics.tsx:428` `item.conversations` | `total_conversations` (`:58`) | always `0` |
| `admin-analytics.tsx:430` `item.avg_tokens_per_conv` | `avg_tokens_per_conversation` (`:60`) | always `0` |
| `admin-analytics.tsx:522` `item.errors` | `error_count` (`:68`) | always `0` |
| `admin-skills.tsx:270` `skill.agents_using` | `agent_count` (`admin_skills.py:49`) | column always blank |
| `admin-skills.tsx:369,373` `detailTarget.system_prompt` | *no such field* (`:53-57`) | block never renders |

These change what the admin UI renders, so they are your call and want their own changelog line. Say the word and I'll send a focused `fix(frontend):` PR — 7 line edits now that the types exist. This is the standing cost `PARKED.md` predicted, caught on the first run.

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

**`pnpm build` caveat, stated plainly:** it fails in my sandbox because `next/font/google` cannot reach `fonts.googleapis.com` (TLS blocked; the npm registry is reachable, so it is a selective block). The failure is in `src/app/layout.tsx`, which this PR does not touch. To confirm the build actually compiles my changes I temporarily pointed `layout.tsx` at the repo's own `public/fonts/CabinetGrotesk-Bold.woff2`, got a **clean production build (exit 0, all routes emitted)**, and reverted the file — `git status` shows `layout.tsx` untouched. On CI, where fonts are reachable, `pnpm build` should pass normally; flagging it rather than claiming a green build I did not observe.

## Notes for the reviewer

- `frontend/openapi.json` is gitignored on purpose: it is an 883 KB intermediate and committing both it and the generated TS would double the churn for no review benefit. The TS is committed so a frontend-only contributor never needs a Python environment.
- The lockfile diff is entirely `openapi-typescript`'s own transitive tree; no existing package changed version and `lockfileVersion` stays `9.0`.
- No i18n strings, no UI components, no routes, no migrations, no agent/workflow changes. `docs/*.mdx` untouched, so nothing needs regenerating in the five locales.
- This branch is independent of the ruff-gate branch. Both touch `CONTRIBUTING.md`; the only plausible conflict is one line in the PR checklist, a few seconds to resolve.
