### Context

`PARKED.md` calls *"Typed frontend from OpenAPI"* the cheapest parked item and the only one with a standing cost: `docs/openapi.json` is exported, nothing consumes it, and `frontend/src/lib/api.ts` carries ~50 hand-written interfaces that drift by construction. I picked it up and hit a blocker worth recording before anyone else tries.

### Blocker: the exported spec is the *public* spec, not the app's spec

`src/fim_one/web/app.py:450-476` hides every route and re-enables a 16-entry `_PUBLIC_API` allowlist:

```
APIRoutes total: 427
in schema:        16
excluded:        411
```

So `docs/openapi.json` has **12 paths / 14 schemas**. Generating frontend types from it yields 975 lines that cannot type the portal client — the portal talks to `/api/admin/*`, `/api/dashboard/*`, `/api/market/*`, none of which are in the allowlist. The 14 schemas are almost entirely request bodies; there is no `Agent`, `Conversation` or `KnowledgeBase` entity schema at all.

**Proposal:** keep `docs/openapi.json` exactly as it is (it is the published public API document) and add an `--internal` export for codegen. That gives **351 paths / 294 schemas**. This is a dev-only artifact; it publishes nothing and changes no route's visibility.

### Second obstacle: a parallel hand-written type surface

`frontend/src/types/admin.ts` declares its own 21 interfaces, several of which are second copies of the ones in `lib/api.ts` with **different optionality**. Aliasing `AdminAgentInfo`, `AdminApiKeyInfo`, `AdminApiKeyCreated`, `AdminKBDoc`, `AdminKBDetail` and `AdminLoginHistoryEntry` to their spec schemas makes `tsc` fail at `admin-agents.tsx:98`, `admin-api-keys.tsx:112` and `:140`, `admin-knowledge-bases.tsx:184`, `admin-security.tsx:143` — e.g. `string | null | undefined` is not assignable to `string | null`. The duplication, not the codegen, is what blocks those six. Collapsing it looks like a good follow-up.

### The payoff: 7 live bugs the hand-written types were hiding

Field names in `lib/api.ts` that do not exist on the backend model. TypeScript is happy; the UI renders a placeholder.

| Frontend read | Backend field | Effect |
|---|---|---|
| `admin-analytics.tsx:427` `item.owner` | `owner_username` (`admin_analytics.py:57`) | Agent analytics "owner" column always `--` |
| `admin-analytics.tsx:601` `item.owner` | `owner_username` (`admin_analytics.py:77`) | Workflow analytics "owner" column always `--` |
| `admin-analytics.tsx:428` `item.conversations` | `total_conversations` (`:58`) | always `0` |
| `admin-analytics.tsx:430` `item.avg_tokens_per_conv` | `avg_tokens_per_conversation` (`:60`) | always `0` |
| `admin-analytics.tsx:522` `item.errors` | `error_count` (`:68`) | always `0` |
| `admin-skills.tsx:270` `skill.agents_using` | `agent_count` (`admin_skills.py:49`) | "agents using" column always blank |
| `admin-skills.tsx:369,373` `detailTarget.system_prompt` | *no such field* (`admin_skills.py:53-57`) | detail block never renders |

`admin_skills.py` even computes the value behind `agents_using` — `_count_agents_using_skill()` at line 78 — and returns it as `agent_count`.

I have **not** fixed these in the codegen PR because they change what the admin UI renders, which is your call and would want its own changelog line. Say the word and I'll send them as a focused `fix(frontend):` PR — it is 7 line edits once the types are generated.

### Related: endpoints with no `response_model`

~13 of the 46 interfaces in `lib/api.ts` have no spec counterpart at all because their endpoint returns an untyped dict: `AdminEvalDataset`, `AdminEvalRun`, `AdminSchedule`, `AdminCredential`, `AdminReview`, `MarketItem`, `UserOrg`, `OrgMember`, `AdminWorkflowInfo`, `AdminIpRule`, `AdminNotificationEvent`, `AdminCostProjection`, `AdminReviewStats`. Adding `response_model=` to those is what makes them migratable — happy to do that as a follow-up if you want it.

### Environment

fim-one `master` @ `e1b0d005`, Python 3.11.2, node 22.22.3, pnpm 9.15.9.
