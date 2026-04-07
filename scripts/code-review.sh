#!/usr/bin/env bash
# code-review.sh — Send code changes to Codex CLI for review
#
# Usage:
#   ./scripts/code-review.sh                           # Default: main...HEAD (--base)
#   ./scripts/code-review.sh --base main               # Custom base branch
#   ./scripts/code-review.sh --commits                 # Last commit only (--commit HEAD)
#   ./scripts/code-review.sh --ext "*.py"              # Filter by extension (files mode only)
#   ./scripts/code-review.sh --prompt "custom prompt"  # Custom prompt
#   ./scripts/code-review.sh --files "a.cs b.cs"       # Specific files (legacy path)
#   ./scripts/code-review.sh --effort high             # Override reasoning effort (low/medium/high)
#
# Environment:
#   QQ_CODEX_EFFORT — default reasoning effort (default: high)
#                     Reviews with reasoning=none (Codex default) return shallow "No findings"
#                     results. Always force at least medium for meaningful review.
#
# Output:
#   Review saved to Docs/<branch>/codex-code-review_<timestamp>.md
#   Also printed to stdout

set -euo pipefail

source "$(dirname "$0")/platform/detect.sh"

if ! command -v codex &>/dev/null; then
  echo "Error: codex CLI not found. Install with: npm install -g @openai/codex" >&2
  exit 1
fi

# Detect whether `codex review` subcommand exists (codex-cli >= 0.x).
# If not, fall back to legacy `codex exec` path with a warning.
HAVE_REVIEW_SUBCMD=0
if codex review --help >/dev/null 2>&1; then
  HAVE_REVIEW_SUBCMD=1
fi

# Auto-detect default base branch: develop > main > master
BASE_BRANCH=""
for candidate in develop main master; do
  if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
    BASE_BRANCH="$candidate"
    break
  fi
done
MODE="branch"
EXT_FILTER=""
CUSTOM_PROMPT=""
FILES_LIST=()
# Default reasoning effort — `none` gives shallow reviews, force `high` for code review.
CODEX_EFFORT="${QQ_CODEX_EFFORT:-high}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)    BASE_BRANCH="$2"; shift 2 ;;
    --commits) MODE="commits"; shift ;;
    --ext)     EXT_FILTER="$2"; shift 2 ;;
    --prompt)  CUSTOM_PROMPT="$2"; shift 2 ;;
    --files)   IFS=' ' read -ra FILES_LIST <<< "$2"; MODE="files"; shift 2 ;;
    --effort)  CODEX_EFFORT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Validate effort
case "$CODEX_EFFORT" in
  low|medium|high) ;;
  *) echo "Error: --effort must be low/medium/high (got: $CODEX_EFFORT)" >&2; exit 1 ;;
esac

# Validate base branch looks like a git ref (prevent flag injection)
if [[ "$BASE_BRANCH" == -* ]]; then
  echo "Error: invalid base branch: $BASE_BRANCH" >&2
  exit 1
fi

# Output file — sanitize branch name to prevent path traversal
BRANCH=$(git branch --show-current | tr '/' '_')
TIMESTAMP=$(date +"%Y-%m-%d-%H%M")
OUT_DIR="Docs/${BRANCH}"
mkdir -p "$OUT_DIR"
REVIEW_FILE="${OUT_DIR}/codex-code-review_${TIMESTAMP}.md"

# Build the review prompt body (shared across both paths)
if [[ -n "$CUSTOM_PROMPT" ]]; then
  REVIEW_PROMPT="$CUSTOM_PROMPT"
else
  REVIEW_PROMPT="Review the following code changes.

Review criteria:
1. Bugs: Logic errors, off-by-one, null derefs, race conditions
2. Architecture: Dependency violations, coupling issues, layering breaks
3. Performance: O(N^2) in hot paths, unnecessary allocations, missing cleanup
4. Security: Injection, XSS, unsafe deserialization (if applicable)
5. Style: Violations of project coding standards (see below)

Classify each finding by severity: [Critical] [Moderate] [Suggestion]
For each finding, cite the specific file and line range.
For anything you're unsure about, mark it [Uncertain] — do NOT guess.
Be concise. Only output review findings."
fi

PROMPT_BODY="${REVIEW_PROMPT}

---

## Project Context

Read the CLAUDE.md file at the project root for coding standards.
Read the AGENTS.md file at the project root for architecture rules (if it exists).

## Unity Best-Practice Checklist (18 rules — check every one)

Anti-Patterns:
1. [High] FindObjectOfType in runtime code — use Registry/Manager (Editor code exempt)
2. [Moderate] Untyped object[] message parameters — use strongly-typed interfaces
3. [High] Accessing shared data in Awake/Start — use lifecycle ready callbacks
4. [High] Caching read-only interface then mutating through it
5. [Moderate] SendMessage/BroadcastMessage — use C# events or interfaces
6. [Notice] Unsolicited UI code changes

Performance:
7. [High] GetComponent in Update/FixedUpdate/LateUpdate — cache in Awake/Start
8. [High] Per-frame heap allocations (new List, string concat, LINQ, closures in Update)
9. [High] Coroutines started without cleanup in OnDisable
10. [Moderate] gameObject.tag == string comparison — use CompareTag()

Runtime Safety:
11. [High] Event subscription without matching unsubscription
12. [Moderate] Missing [RequireComponent] for GetComponent dependencies

Architecture:
13. Circular dependency risk (check using directives)
14. Missing .asmdef references
15. [Moderate] Incorrect namespace conventions
16. [Moderate] Public fields instead of [SerializeField] private

Code Quality:
17. Excessive null checks (project style: minimal, trust contracts)
18. Missing documentation comments on public classes"

# ═══════════════════════════════════════════════════════════════════════════
# Path selection: prefer native `codex review` subcommand when possible.
#
# `codex review` is the purpose-built review mode with native diff handling
# and review-specific prompting. It handles branch / single-commit / uncommitted
# scopes natively, and a multi-commit branch diff (36 files across 10 commits)
# works exactly the same as a single-file change — the full diff is analyzed
# as one coherent review.
#
# Fall back to `codex exec` + manual diff construction for:
#   (a) --files explicit file list — codex review has no native "these files only"
#   (b) --ext extension filter — codex review has no native extension filter
#
# In both paths we force `model_reasoning_effort=high` to avoid the shallow
# "No findings" result that the default (`none`) produces.
# ═══════════════════════════════════════════════════════════════════════════

USE_REVIEW_SUBCMD=0
if [[ $HAVE_REVIEW_SUBCMD -eq 1 && -z "$EXT_FILTER" && "$MODE" != "files" ]]; then
  USE_REVIEW_SUBCMD=1
fi

if [[ $USE_REVIEW_SUBCMD -eq 1 ]]; then
  # ─────────────────────────────────────────────────────────────────────────
  # Path A: native `codex review` subcommand (no manual diff)
  # ─────────────────────────────────────────────────────────────────────────

  MODE_ARGS=()
  case "$MODE" in
    branch)
      # Pre-check: if branch diff is empty, fall back to --uncommitted so we
      # still review whatever the user has in progress. (Old behavior preserved.)
      if git diff --quiet "${BASE_BRANCH}...HEAD" 2>/dev/null; then
        echo ">>> No committed changes on ${BASE_BRANCH}...HEAD. Falling back to --uncommitted..." >&2
        MODE_ARGS=(--uncommitted)
        DIFF_DESC="uncommitted changes"
      else
        MODE_ARGS=(--base "$BASE_BRANCH")
        DIFF_DESC="${BASE_BRANCH}...HEAD"
      fi
      ;;
    commits)
      MODE_ARGS=(--commit HEAD)
      DIFF_DESC="commit HEAD"
      ;;
  esac

  echo ">>> codex review (${DIFF_DESC}, reasoning=${CODEX_EFFORT})" >&2

  codex review \
    -c "model_reasoning_effort=\"${CODEX_EFFORT}\"" \
    "${MODE_ARGS[@]}" \
    "$PROMPT_BODY" | tee "$REVIEW_FILE"

else
  # ─────────────────────────────────────────────────────────────────────────
  # Path B: legacy `codex exec` with manual diff construction
  # Used when --ext filter or explicit --files list is in play, since
  # `codex review` has no native support for these scopes.
  # ─────────────────────────────────────────────────────────────────────────

  if [[ $HAVE_REVIEW_SUBCMD -eq 0 ]]; then
    echo ">>> Note: codex CLI lacks 'review' subcommand; using legacy 'exec' path" >&2
  fi

  # Build diff command args
  DIFF_ARGS=()
  if [[ -n "$EXT_FILTER" ]]; then
    DIFF_ARGS+=(-- "$EXT_FILTER")
  fi

  case "$MODE" in
    branch)
      DIFF=$(git diff "${BASE_BRANCH}...HEAD" "${DIFF_ARGS[@]+"${DIFF_ARGS[@]}"}")
      DIFF_DESC="${BASE_BRANCH}...HEAD"
      ;;
    commits)
      DIFF=$(git diff "HEAD~1...HEAD" "${DIFF_ARGS[@]+"${DIFF_ARGS[@]}"}")
      DIFF_DESC="HEAD~1...HEAD"
      ;;
    files)
      DIFF=""
      for f in "${FILES_LIST[@]}"; do
        if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
          file_diff=$(git diff HEAD -- "$f")
          if [[ -n "$file_diff" ]]; then
            DIFF="${DIFF}${file_diff}"$'\n'
          fi
        elif [[ -f "$f" ]]; then
          # 未跟踪的新文件：生成合成 diff
          DIFF="${DIFF}$(git diff --no-index /dev/null "$f" 2>/dev/null || true)"$'\n'
        fi
      done
      DIFF_DESC="files: ${FILES_LIST[*]}"
      ;;
  esac

  # Fallback: if branch diff is empty, try uncommitted changes
  if [[ -z "$DIFF" && "$MODE" == "branch" ]]; then
    echo ">>> No committed changes (${DIFF_DESC}). Trying uncommitted changes..." >&2
    UNCOMMITTED_FILES=$(git diff --name-only HEAD 2>/dev/null || true)
    UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null || true)
    ALL_FILES=$(printf '%s\n%s' "$UNCOMMITTED_FILES" "$UNTRACKED_FILES" | sort -u | grep -v '^$' || true)
    if [[ -n "$ALL_FILES" ]]; then
      MODE="files"
      mapfile -t FILES_LIST <<< "$ALL_FILES"
      for f in "${FILES_LIST[@]}"; do
        if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
          file_diff=$(git diff HEAD -- "$f")
          if [[ -n "$file_diff" ]]; then
            DIFF="${DIFF}${file_diff}"$'\n'
          fi
        elif [[ -f "$f" ]]; then
          DIFF="${DIFF}$(git diff --no-index /dev/null "$f" 2>/dev/null || true)"$'\n'
        fi
      done
      DIFF_DESC="uncommitted changes (${#FILES_LIST[@]} files)"
    fi
  fi

  if [[ -z "$DIFF" ]]; then
    echo "No code changes found (${DIFF_DESC})" >&2
    exit 0
  fi

  # Write diff to temp file so Codex reads it from disk (avoids ARG_MAX)
  DIFF_FILE=$(mktemp "$QQ_TEMP_DIR/code-review-diff-XXXXXXXX")
  printf '%s' "$DIFF" > "$DIFF_FILE"

  FULL_PROMPT="${PROMPT_BODY}

---

## Code Changes (${DIFF_DESC})

Read ${DIFF_FILE} for the full diff."

  echo ">>> codex exec (${DIFF_DESC}, reasoning=${CODEX_EFFORT})" >&2
  echo ">>> Diff written to ${DIFF_FILE} ($(wc -l < "$DIFF_FILE") lines)" >&2

  codex exec \
    --sandbox read-only \
    -c "model_reasoning_effort=\"${CODEX_EFFORT}\"" \
    "$FULL_PROMPT" | tee "$REVIEW_FILE"

  rm -f "$DIFF_FILE"
fi

echo "" >&2
echo ">>> Review saved to: ${REVIEW_FILE}" >&2
