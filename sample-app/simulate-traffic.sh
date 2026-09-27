#!/usr/bin/env bash
# Forty failures, with at least ten landing in one 60-second alarm period.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON:-python3}" "$SCRIPT_DIR/app.py" --requests 40 --error-rate 1 --interval 0.1 "$@"
