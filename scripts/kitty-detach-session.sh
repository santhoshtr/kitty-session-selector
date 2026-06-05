#!/usr/bin/env bash
set -euo pipefail

CURRENT_SESSION_TRACKER="/tmp/kitty-current-session"

rm -f "$CURRENT_SESSION_TRACKER"
kitten @ action close_session .

