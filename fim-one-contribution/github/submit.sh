#!/usr/bin/env bash
# Submit the two fim-one contributions from this directory to GitHub.
#
# The agent sandbox could not do this itself: its token is a GitHub App
# installation scoped to Aryan-theccool/fimai only, with push/triage/pull all
# false on fim-ai/fim-one. This script runs as YOU, so it can fork, push and
# open the issues and PRs.
#
# What it does, in order:
#   1. forks fim-ai/fim-one into your account (skipped if the fork exists)
#   2. clones it, creates both branches off upstream/master, `git am`s the patches
#   3. pushes both branches to your fork
#   4. opens Issue A + Issue B on fim-ai/fim-one
#   5. opens PR 1 + PR 2 against fim-ai/fim-one:master, bodies cross-referencing
#      the issue numbers from step 4
#
# Usage:
#   ./submit.sh --dry-run     # print every command and GitHub call, change nothing
#   ./submit.sh               # ask for confirmation, then do it
#   ./submit.sh --yes         # skip the confirmation prompt
#   ./submit.sh --no-issues   # PRs only (issue refs left as #ISSUE_A#/#ISSUE_B#)
#
# Requires: git, gh (authenticated as you: `gh auth status`), and network access
# to github.com. Nothing here needs uv, pnpm or an LLM key.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES="$HERE/../patches"

UPSTREAM_REPO="fim-ai/fim-one"
BASE_BRANCH="master"

B1_BRANCH="fix/ruff-lint-gate"
B1_PATCH="$PATCHES/0001-chore-lint-ratchet-ruff-against-a-committed-baseline.patch"
B1_TITLE="chore(lint): ratchet ruff against a committed baseline"
B1_BODY="$HERE/pr-1-lint-gate.md"

B2_BRANCH="feat/openapi-typed-client"
B2_PATCH="$PATCHES/0001-feat-frontend-generate-API-types-from-the-OpenAPI-sp.patch"
B2_TITLE="feat(frontend): generate API types from the OpenAPI spec"
B2_BODY="$HERE/pr-2-openapi-types.md"

ISSUE_A_TITLE='The documented lint gate has never passed: `ruff check src/ tests/` reports ~2.1k violations and nothing runs ruff in CI'
ISSUE_A_BODY="$HERE/issue-A-lint-gate.md"
ISSUE_B_TITLE="docs/openapi.json covers 12 of 427 routes, so the frontend's hand-written API types can't be generated from it — plus 7 live field-name bugs found while wiring codegen up"
ISSUE_B_BODY="$HERE/issue-B-openapi-types.md"

DRY_RUN=0
ASSUME_YES=0
MAKE_ISSUES=1

for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=1 ;;
    --yes|-y)    ASSUME_YES=1 ;;
    --no-issues) MAKE_ISSUES=0 ;;
    -h|--help)   sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# Run a command, or just show it in dry-run mode.
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '  DRY  %s\n' "$*"
  else
    printf '  RUN  %s\n' "$*"
    "$@"
  fi
}

fail() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

echo "== preflight =="
command -v git >/dev/null || fail "git not found"
command -v gh  >/dev/null || fail "gh not found — install GitHub CLI and run: gh auth login"

[[ -f "$B1_PATCH" ]] || fail "missing patch: $B1_PATCH"
[[ -f "$B2_PATCH" ]] || fail "missing patch: $B2_PATCH"
for f in "$B1_BODY" "$B2_BODY" "$ISSUE_A_BODY" "$ISSUE_B_BODY"; do
  [[ -f "$f" ]] || fail "missing body file: $f"
done

# gh prints an API error body to *stdout* (not stderr) when the token is
# rejected, so a non-empty result is not enough — it has to look like a login.
GH_USER="$(gh api user --jq .login 2>/dev/null || true)"
if [[ ! "$GH_USER" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
  fail "gh is not authenticated as a user account.
  'gh api user' returned: ${GH_USER:-<empty>}

  Run: gh auth login
  A GitHub App / bot token will not work here — this needs push access to a
  fork of $UPSTREAM_REPO and the ability to open issues there."
fi

echo "  authenticated as: $GH_USER"
echo "  upstream:         $UPSTREAM_REPO (base branch: $BASE_BRANCH)"
echo "  fork:             $GH_USER/fim-one"
echo "  branches:         $B1_BRANCH, $B2_BRANCH"
echo "  dry run:          $([[ $DRY_RUN -eq 1 ]] && echo yes || echo no)"
echo

if [[ $DRY_RUN -eq 0 && $ASSUME_YES -eq 0 ]]; then
  cat <<PROMPT
This will create PUBLIC content on $UPSTREAM_REPO under your account:
  - a fork (if you don't have one)
  - 2 pushed branches
  - $([[ $MAKE_ISSUES -eq 1 ]] && echo "2 issues" || echo "0 issues")
  - 2 pull requests

CONTRIBUTING.md asks for an issue before large changes, which is why the issues
come first. The maintainer is notified for each.
PROMPT
  read -r -p "Proceed? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "aborted, nothing was created."; exit 0; }
fi

# ---------------------------------------------------------------------------
# 1. Fork
# ---------------------------------------------------------------------------

echo
echo "== 1. fork $UPSTREAM_REPO =="
if gh repo view "$GH_USER/fim-one" >/dev/null 2>&1; then
  echo "  fork already exists, reusing it"
else
  run gh repo fork "$UPSTREAM_REPO" --clone=false
fi
FORK_URL="https://github.com/$GH_USER/fim-one.git"

# ---------------------------------------------------------------------------
# 2. Clone + apply patches
# ---------------------------------------------------------------------------

echo
echo "== 2. clone and apply patches =="
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
echo "  workdir: $WORKDIR"

run git clone --quiet "$FORK_URL" "$WORKDIR/fim-one"

if [[ $DRY_RUN -eq 0 ]]; then
  cd "$WORKDIR/fim-one"
  git remote add upstream "https://github.com/$UPSTREAM_REPO.git"
  git fetch --quiet upstream "$BASE_BRANCH"

  # Patches were generated against upstream master @ e1b0d005. Rebase onto
  # whatever master is now; git am -3 falls back to a 3-way merge if it moved.
  for pair in "$B1_BRANCH:$B1_PATCH" "$B2_BRANCH:$B2_PATCH"; do
    branch="${pair%%:*}"; patch="${pair##*:}"
    echo "  branch $branch <- $(basename "$patch")"
    git checkout --quiet -B "$branch" "upstream/$BASE_BRANCH"
    if ! git am -3 "$patch"; then
      git am --abort || true
      fail "git am failed for $branch. Upstream master has moved past e1b0d005 and
  conflicted with the patch. Resolve manually:
    git checkout -b $branch upstream/$BASE_BRANCH && git am -3 $patch"
    fi
  done
else
  printf '  DRY  git checkout -B %s upstream/%s && git am -3 %s\n' "$B1_BRANCH" "$BASE_BRANCH" "$(basename "$B1_PATCH")"
  printf '  DRY  git checkout -B %s upstream/%s && git am -3 %s\n' "$B2_BRANCH" "$BASE_BRANCH" "$(basename "$B2_PATCH")"
fi

# ---------------------------------------------------------------------------
# 3. Push
# ---------------------------------------------------------------------------

echo
echo "== 3. push branches to fork =="
if [[ $DRY_RUN -eq 0 ]]; then
  cd "$WORKDIR/fim-one"
  git push --quiet -u origin "$B1_BRANCH"
  git push --quiet -u origin "$B2_BRANCH"
  echo "  pushed $B1_BRANCH and $B2_BRANCH"
else
  printf '  DRY  git push -u origin %s\n' "$B1_BRANCH"
  printf '  DRY  git push -u origin %s\n' "$B2_BRANCH"
fi

# ---------------------------------------------------------------------------
# 4. Issues
# ---------------------------------------------------------------------------

ISSUE_A_NUM="ISSUE_A"
ISSUE_B_NUM="ISSUE_B"

echo
echo "== 4. open issues on $UPSTREAM_REPO =="
if [[ $MAKE_ISSUES -eq 1 ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '  DRY  gh issue create --repo %s --title "%s" --body-file %s\n' \
      "$UPSTREAM_REPO" "$ISSUE_A_TITLE" "$(basename "$ISSUE_A_BODY")"
    printf '  DRY  gh issue create --repo %s --title "%s" --body-file %s\n' \
      "$UPSTREAM_REPO" "$ISSUE_B_TITLE" "$(basename "$ISSUE_B_BODY")"
  else
    URL_A="$(gh issue create --repo "$UPSTREAM_REPO" --title "$ISSUE_A_TITLE" --body-file "$ISSUE_A_BODY")"
    ISSUE_A_NUM="${URL_A##*/}"
    echo "  Issue A: $URL_A"

    URL_B="$(gh issue create --repo "$UPSTREAM_REPO" --title "$ISSUE_B_TITLE" --body-file "$ISSUE_B_BODY")"
    ISSUE_B_NUM="${URL_B##*/}"
    echo "  Issue B: $URL_B"
  fi
else
  echo "  skipped (--no-issues); PR bodies keep the #ISSUE_A#/#ISSUE_B# placeholders"
fi

# ---------------------------------------------------------------------------
# 5. Pull requests
# ---------------------------------------------------------------------------

echo
echo "== 5. open pull requests against $UPSTREAM_REPO:$BASE_BRANCH =="

render_body() {  # <source> <issue-a-num> <issue-b-num> -> stdout
  sed -e "s/#ISSUE_A#/#$2/g" -e "s/#ISSUE_B#/#$3/g" "$1"
}

if [[ $DRY_RUN -eq 1 ]]; then
  printf '  DRY  gh pr create --repo %s --base %s --head %s:%s --title "%s" --body-file <pr-1>\n' \
    "$UPSTREAM_REPO" "$BASE_BRANCH" "$GH_USER" "$B1_BRANCH" "$B1_TITLE"
  printf '  DRY  gh pr create --repo %s --base %s --head %s:%s --title "%s" --body-file <pr-2>\n' \
    "$UPSTREAM_REPO" "$BASE_BRANCH" "$GH_USER" "$B2_BRANCH" "$B2_TITLE"
else
  TMP_A="$(mktemp)"; TMP_B="$(mktemp)"
  render_body "$B1_BODY" "$ISSUE_A_NUM" "$ISSUE_B_NUM" > "$TMP_A"
  render_body "$B2_BODY" "$ISSUE_A_NUM" "$ISSUE_B_NUM" > "$TMP_B"

  PR1_URL="$(gh pr create --repo "$UPSTREAM_REPO" --base "$BASE_BRANCH" \
    --head "$GH_USER:$B1_BRANCH" --title "$B1_TITLE" --body-file "$TMP_A")"
  echo "  PR 1: $PR1_URL"

  PR2_URL="$(gh pr create --repo "$UPSTREAM_REPO" --base "$BASE_BRANCH" \
    --head "$GH_USER:$B2_BRANCH" --title "$B2_TITLE" --body-file "$TMP_B")"
  echo "  PR 2: $PR2_URL"

  rm -f "$TMP_A" "$TMP_B"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo
echo "== done =="
echo "  Review both PRs in the browser and check CI:"
echo "    https://github.com/$UPSTREAM_REPO/pulls?q=is%3Apr+author%3A$GH_USER"
echo
echo "  CI runs the new ruff gate on PR 1, and mypy/pytest/pnpm build on both."
echo "  PR 2's pnpm build should pass on GitHub Actions — the only failure seen"
echo "  locally was next/font being unable to reach fonts.googleapis.com."
echo
echo "  After your PR merges, per CONTRIBUTING.md comment:"
echo "    @all-contributors please add @$GH_USER for code"
