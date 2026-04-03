#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Python compatibility
: "${QQ_PY:=python3}"
command -v "$QQ_PY" >/dev/null 2>&1 || QQ_PY="python"

$QQ_PY "$SCRIPT_DIR/qq-doctor.py" "$@"
