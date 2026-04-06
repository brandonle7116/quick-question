#!/usr/bin/env bash
# qq-release.sh — Release helper for quick-question.
#
# Wraps the manual ceremony: bump version, README badge, append CHANGELOG entry,
# commit, push, watch CI. Pre-validates via test.sh section 5 lint before
# committing so badge / version drift is caught locally.
#
# Usage:
#   scripts/qq-release.sh <patch|minor|major> "<one-paragraph release notes>"
#   scripts/qq-release.sh patch "Hook scripts now fall back to python3 when jq is missing."
#
# Optional flags:
#   --dry-run         Print every action but never write files, commit, or push.
#   --no-push         Commit locally but skip git push and CI watch.
#   --skip-tests      Skip running ./test.sh before committing (use only for doc-only fixes).
#   --version <X.Y.Z> Force a specific version instead of bumping.
#
# Notes:
#   - Always creates a NEW commit (never amends).
#   - Refuses to push to main if working tree has unstaged changes outside the
#     5 release-managed files (plugin.json, README.md, CHANGELOG.md).
#   - Refuses to release if section 5 lint fails (unless --skip-tests).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Python compatibility (Windows Store python3 alias is on PATH but broken;
# use --version to detect a working interpreter, not command -v)
: "${QQ_PY:=python3}"
"$QQ_PY" --version >/dev/null 2>&1 || QQ_PY="python"

PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"
README_FILE="$REPO_ROOT/README.md"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"
TEST_SCRIPT="$REPO_ROOT/test.sh"

# ── arg parsing ──
DRY_RUN=0
NO_PUSH=0
SKIP_TESTS=0
FORCED_VERSION=""
BUMP_KIND=""
RELEASE_NOTES=""
POSITIONAL=()

usage() {
  sed -n '2,22p' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --no-push) NO_PUSH=1; shift ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --version)
      [[ $# -ge 2 ]] || { echo "Error: --version requires X.Y.Z"; exit 1; }
      FORCED_VERSION="$2"
      shift 2
      ;;
    --version=*) FORCED_VERSION="${1#--version=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "Error: unknown flag: $1"; usage >&2; exit 1 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ ${#POSITIONAL[@]} -lt 2 && -z "$FORCED_VERSION" ]]; then
  usage >&2
  exit 1
fi

if [[ -z "$FORCED_VERSION" ]]; then
  BUMP_KIND="${POSITIONAL[0]}"
  RELEASE_NOTES="${POSITIONAL[1]}"
  case "$BUMP_KIND" in
    patch|minor|major) ;;
    *) echo "Error: bump kind must be patch, minor, or major"; exit 1 ;;
  esac
else
  RELEASE_NOTES="${POSITIONAL[0]:-${POSITIONAL[1]:-}}"
  if [[ -z "$RELEASE_NOTES" ]]; then
    echo "Error: --version still requires release notes as the next positional arg"
    exit 1
  fi
fi

# ── derive current + new version ──
CURRENT_VERSION="$("$QQ_PY" -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$PLUGIN_JSON")"
if [[ -n "$FORCED_VERSION" ]]; then
  NEW_VERSION="$FORCED_VERSION"
else
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
  case "$BUMP_KIND" in
    patch) PATCH=$((PATCH + 1)) ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  esac
  NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
fi

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: new version '$NEW_VERSION' is not in X.Y.Z form"
  exit 1
fi

TODAY="$(date +%Y-%m-%d)"

echo "── qq-release ──"
echo "  Current: v$CURRENT_VERSION"
echo "  Next:    v$NEW_VERSION"
echo "  Date:    $TODAY"
echo "  Notes:   $RELEASE_NOTES"
[[ "$DRY_RUN" -eq 1 ]] && echo "  Mode:    DRY RUN"
echo ""

# ── safety: detect and capture extra dirty files for inclusion in the commit ──
# Note: the v1.16.12 dogfood found that the warning here was a lie — it said
# "These will be included in the release commit" but the actual staging step
# below only added the 3 release-managed files. As of this version we now
# auto-stage the listed files in the commit step, matching the warning's claim.
DIRTY_OTHER="$(cd "$REPO_ROOT" && git status --porcelain | awk '{print $2}' | grep -v -E '^(\.claude-plugin/plugin\.json|README\.md|CHANGELOG\.md)$' || true)"
if [[ -n "$DIRTY_OTHER" ]]; then
  echo "Warning: working tree has uncommitted changes outside the release-managed files:"
  printf '  %s\n' $DIRTY_OTHER
  echo ""
  echo "These will be auto-staged into the release commit alongside the version bump."
  echo "If that's not what you want, stash them first or run with --no-include-dirty."
  echo ""
fi

# ── pre-flight: section 5 lint ──
if [[ "$SKIP_TESTS" -ne 1 ]]; then
  echo "→ Pre-flight: running test.sh section 5 (README consistency)..."
  if [[ ! -x "$TEST_SCRIPT" ]]; then
    echo "Error: test.sh not found or not executable: $TEST_SCRIPT"
    exit 1
  fi
  # We can't easily isolate just section 5 — run the whole thing and grep.
  # Section 5 failures will show up here either way.
  TEST_OUTPUT="$(bash "$TEST_SCRIPT" 2>&1 || true)"
  SECTION5_FAILS="$(printf '%s\n' "$TEST_OUTPUT" | sed -n '/\[5\/10\]/,/\[6\/10\]/p' | grep '✗' || true)"
  if [[ -n "$SECTION5_FAILS" ]]; then
    echo "Error: section 5 (README consistency) failures detected:"
    printf '%s\n' "$SECTION5_FAILS"
    echo ""
    echo "Fix README / plugin.json / language docs before releasing."
    echo "(Use --skip-tests to bypass.)"
    exit 1
  fi
  echo "  ✓ section 5 clean"
fi

# ── apply: bump plugin.json + README badge + CHANGELOG ──
apply_changes() {
  echo "→ Bumping plugin.json: $CURRENT_VERSION → $NEW_VERSION"
  "$QQ_PY" - "$PLUGIN_JSON" "$NEW_VERSION" <<'PY'
import json
import sys

path = sys.argv[1]
new_version = sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
data["version"] = new_version
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY

  echo "→ Bumping README version badge: v$CURRENT_VERSION → v$NEW_VERSION"
  "$QQ_PY" - "$README_FILE" "$CURRENT_VERSION" "$NEW_VERSION" <<'PY'
import sys

path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
# This is text.replace, not re.sub — the substring is literal, no regex escaping.
old_pattern = f"version-v{old}-blue"
new_pattern = f"version-v{new}-blue"
if old_pattern not in text:
    print(f"Warning: README badge '{old_pattern}' not found; skipping badge bump", file=sys.stderr)
else:
    text = text.replace(old_pattern, new_pattern)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
PY

  echo "→ Prepending CHANGELOG entry for v$NEW_VERSION"
  "$QQ_PY" - "$CHANGELOG_FILE" "$NEW_VERSION" "$TODAY" "$RELEASE_NOTES" <<'PY'
import sys

path, version, date, notes = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
header = "All notable changes to quick-question are documented here."
if header not in text:
    print(f"Error: changelog header not found in {path}", file=sys.stderr)
    sys.exit(1)
entry = f"## [{version}] — {date}\n\n{notes}\n\n"
new_text = text.replace(header, header + "\n\n" + entry, 1)
# The replacement above leaves the original header line in place and inserts
# the entry directly under it; collapse the duplicate blank lines that creates.
new_text = new_text.replace(header + "\n\n\n" + entry, header + "\n\n" + entry)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(new_text)
PY
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "(dry-run) Would bump plugin.json, README badge, and CHANGELOG."
  echo "(dry-run) Would commit + push + watch CI."
  echo ""
  echo "Re-run without --dry-run to apply."
  exit 0
fi

apply_changes

# ── post-bump: re-run section 5 to confirm new version is consistent ──
if [[ "$SKIP_TESTS" -ne 1 ]]; then
  echo "→ Post-bump: re-running section 5 to confirm new version is consistent..."
  POST_OUTPUT="$(bash "$TEST_SCRIPT" 2>&1 || true)"
  POST_FAILS="$(printf '%s\n' "$POST_OUTPUT" | sed -n '/\[5\/10\]/,/\[6\/10\]/p' | grep '✗' || true)"
  if [[ -n "$POST_FAILS" ]]; then
    echo "Error: section 5 lint regressed after bump:"
    printf '%s\n' "$POST_FAILS"
    echo ""
    echo "The release-managed files were edited but the lint now fails."
    echo "Inspect changes manually and either fix or revert."
    exit 1
  fi
  echo "  ✓ section 5 still clean"
fi

# ── commit ──
echo "→ Staging release-managed files"
(cd "$REPO_ROOT" && git add "$PLUGIN_JSON" "$README_FILE" "$CHANGELOG_FILE")

# Also stage the "extra dirty" files captured before the bump, so the warning
# above is actually true. v1.16.12 shipped a release commit that bumped the
# version + added a CHANGELOG entry describing tykit doc changes that weren't
# actually committed — that was this lying-warning bug.
if [[ -n "$DIRTY_OTHER" ]]; then
  echo "→ Auto-staging extra dirty files into the release commit:"
  for f in $DIRTY_OTHER; do
    if [[ -e "$REPO_ROOT/$f" ]]; then
      printf '    %s\n' "$f"
      (cd "$REPO_ROOT" && git add -- "$f")
    fi
  done
fi

echo "→ Committing"
COMMIT_MSG=$(cat <<EOF
release: v$NEW_VERSION

$RELEASE_NOTES

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)
(cd "$REPO_ROOT" && git commit -m "$COMMIT_MSG")
COMMIT_SHA="$(cd "$REPO_ROOT" && git rev-parse --short HEAD)"
echo "  ✓ committed $COMMIT_SHA"

if [[ "$NO_PUSH" -eq 1 ]]; then
  echo ""
  echo "──"
  echo "Released v$NEW_VERSION locally as $COMMIT_SHA. Push manually when ready:"
  echo "  git push origin main"
  exit 0
fi

# ── push ──
echo "→ Pushing to origin main"
(cd "$REPO_ROOT" && git push origin main)

# ── watch CI ──
echo "→ Watching latest CI run on main"
sleep 2
RUN_ID="$(gh run list --branch main --workflow Validate --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
if [[ -z "$RUN_ID" ]]; then
  echo "  (could not find a Validate run id; skipping watch — check manually with 'gh run list')"
else
  gh run watch "$RUN_ID" --exit-status || {
    echo ""
    echo "Error: CI failed for v$NEW_VERSION (run $RUN_ID)"
    echo "Inspect with: gh run view $RUN_ID --log-failed"
    exit 1
  }
fi

echo ""
echo "──"
echo "Released v$NEW_VERSION as $COMMIT_SHA. CI green."
