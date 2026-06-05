#!/usr/bin/env bash
set -euo pipefail

# Invoked via `launch --type=background`, which runs us with NO kitty env vars
# (KITTY_LISTEN_ON and friends are only exported to programs running inside a
# kitty window). So we discover the main kitty control socket ourselves.
#
# With `listen_on unix:/tmp/kitty`, every kitty instance owns a /tmp/kitty-<pid>
# socket. Quick-access-terminal windows run as `kitty +kitten panel ...
# --app-id=kitty-quick-access ...`, so the main instance is the kitty socket
# whose process is not a quick-access panel.
main_sock=""
for sock in /tmp/kitty-*; do
    [[ -S "$sock" ]] || continue
    pid="${sock##*-}"
    cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)" || continue
    [[ "$cmd" == *kitty-quick-access* ]] && continue
    main_sock="unix:$sock"
    break
done

if [[ -z "$main_sock" ]]; then
    echo "kitty-session-float: could not find the main kitty socket" >&2
    exit 1
fi

# The selector runs inside a floating quick-access-terminal (a separate kitty
# instance). Forward the main socket so it switches the main session, not the
# floating window's. The QAT auto-loads quick-access-terminal.conf (centered).
exec kitten quick-access-terminal \
    --instance-group session-selector \
    /bin/bash -c "KITTY_MAIN_SOCKET='$main_sock' exec \"\$HOME/.config/kitty/scripts/kitty-list-sessions.sh\""

