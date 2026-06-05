#!/usr/bin/env bash
set -euo pipefail

# Make sure fd is in the path.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
SESSION_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kitty/sessions"
DEFAULT_SESSION="$CONFIG_DIR/default.kitty-session"

# Defaults so a missing config does not blow up under `set -u`.
KS_SEARCH_PATHS=()
KS_MAX_DEPTH=1
# shellcheck disable=SC1091
source "$CONFIG_DIR/kitty-sessionizer.conf" 2>/dev/null || true

mkdir -p "$SESSION_DIR"

# When launched from a floating quick-access window, the selector runs in a
# separate kitty instance. KITTY_MAIN_SOCKET (set by kitty-session-float.sh)
# redirects every remote-control call to the main instance instead of ourselves.
KITTEN_TO=()
[[ -n "${KITTY_MAIN_SOCKET:-}" ]] && KITTEN_TO=(--to "$KITTY_MAIN_SOCKET")

find_repos() {
    local entry path depth
    for entry in "${KS_SEARCH_PATHS[@]}"; do
        path="${entry%%:*}"
        depth="${entry##*:}"
        [[ "$path" == "$entry" ]] && depth="$KS_MAX_DEPTH"
        [[ -d "$path" ]] && fd --hidden -t d -d "$depth" .git "$path" --format '{//}'
    done
}

# Active sessions: derived from tab title prefixes in `kitten @ ls`, then
# intersected with on-disk session files so stray titles never appear as
# active. Current session is whatever --match=session:. resolves to from
# inside this overlay (the overlay inherits its parent's session attr).
declare -A active=()
current_name=""
if command -v jq >/dev/null 2>&1; then
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        [[ -f "$SESSION_DIR/$name.kitty-session" ]] && active["$name"]=1
    done < <(
        kitten @ "${KITTEN_TO[@]}" ls 2>/dev/null \
          | jq -r '[.[].tabs[].title] | .[] | sub(" - .*$"; "")' 2>/dev/null \
          | sort -u
    )
    if [[ ${#KITTEN_TO[@]} -gt 0 ]]; then
        # Remote (floating window): the calling window is not part of the main
        # instance, so session:. is meaningless. Derive the current session from
        # the focused OS window's first tab title (same convention as below).
        current_name=$(
            kitten @ "${KITTEN_TO[@]}" ls 2>/dev/null \
              | jq -r 'map(select(.is_focused))[0].tabs[0].title // empty' 2>/dev/null \
              | sed 's/ - .*//'
        )
    else
        current_name=$(
            kitten @ ls --match=session:. 2>/dev/null \
              | jq -r '.[0].tabs[0].title // empty' 2>/dev/null \
              | sed 's/ - .*//'
        )
    fi
fi

TSV=$(mktemp -t kitty-sessions.XXXXXX.tsv)
DEL_HELPER=$(mktemp -t kitty-del.XXXXXX.sh)
RELOAD_HELPER=$(mktemp -t kitty-reload.XXXXXX.sh)
trap 'rm -f "$TSV" "$DEL_HELPER" "$RELOAD_HELPER"' EXIT

cat > "$DEL_HELPER" <<EOF
#!/usr/bin/env bash
sdir='$SESSION_DIR'
f=\$1
if [[ -f "\$f" && "\$f" == "\$sdir"/*.kitty-session ]]; then
    rm -f -- "\$f"
fi
EOF
cat > "$RELOAD_HELPER" <<EOF
#!/usr/bin/env bash
awk -F'\t' -v p="\$1" '\$2 != p' '$TSV'
EOF
chmod +x "$DEL_HELPER" "$RELOAD_HELPER"

# Build TSV: display_name<TAB>session_path<TAB>repo_path(optional)
# Ordering: current session, other active sessions, inactive sessions, repos.
{
    if [[ -n "$current_name" && -f "$SESSION_DIR/$current_name.kitty-session" ]]; then
        printf '▶ (current) %s\t%s\t\n' \
            "$current_name" "$SESSION_DIR/$current_name.kitty-session"
    fi
    for name in $(printf '%s\n' "${!active[@]}" | sort -f); do
        [[ "$name" == "$current_name" ]] && continue
        printf '▶ %s\t%s\t\n' "$name" "$SESSION_DIR/$name.kitty-session"
    done
    if [[ -d "$SESSION_DIR" ]]; then
        while IFS= read -r session_path; do
            name="${session_path##*/}"
            name="${name%.kitty-session}"
            [[ -n "${active[$name]+_}" ]] && continue
            [[ "$name" == "$current_name" ]] && continue
            printf '  %s\t%s\t\n' "$name" "$session_path"
        done < <(find "$SESSION_DIR" -maxdepth 1 -name '*.kitty-session' | sort -f)
    fi
    while IFS= read -r repo; do
        name="${repo##*/}"
        session_path="$SESSION_DIR/${name}.kitty-session"
        [[ -f "$session_path" ]] && continue
        printf '  %s\t%s\t%s\n' "$repo" "$session_path" "$repo"
    done < <(find_repos | sort -f)
} > "$TSV"

PREVIEW='f={2}; if [[ -f "$f" ]]; then (bat --style=plain --color=always --paging=never -- "$f" 2>/dev/null || cat -- "$f"); else echo "(no session yet — will be generated from default template)"; fi'

selected=$(
    fzf \
        --prompt "Project > " \
        --delimiter $'\t' \
        --with-nth 1 \
        --preview "$PREVIEW" \
        --preview-window 'right,60%,wrap' \
        --header 'enter: switch · ctrl-e: edit · ctrl-d: delete' \
        --bind "ctrl-e:execute(\${EDITOR:-nvim} -- {2})" \
        --bind "ctrl-d:execute-silent($DEL_HELPER {2})+reload($RELOAD_HELPER {2})" \
        < "$TSV"
) || true

[[ -z "$selected" ]] && exit 0

session_file=$(printf '%s' "$selected" | cut -f2)
repo_path=$(printf '%s' "$selected" | cut -f3)

# Generate session from template if it does not exist
if [[ ! -f "$session_file" ]]; then
    name=$(basename "$session_file" .kitty-session)
    if [[ -n "$repo_path" ]]; then
        sed -e "s|@@session-path@@|$repo_path|g" -e "s|@@session@@|$name|g" \
            "$DEFAULT_SESSION" > "$session_file"
    fi
fi

# Persist the session we are leaving so it reopens in its last state.
if [[ -n "$current_name" \
   && "$session_file" != "$SESSION_DIR/$current_name.kitty-session" ]]; then
    if [[ "$(kitten @ "${KITTEN_TO[@]}" ls --match=session:"$current_name" 2>/dev/null \
            | jq -r 'length' 2>/dev/null || echo 0)" -gt 0 ]]; then
        kitten @ "${KITTEN_TO[@]}" action save_as_session \
            --match=session:"$current_name" \
            --use-foreground-process \
            --relocatable \
            --save-only \
            "$SESSION_DIR/$current_name.kitty-session" 2>/dev/null || true
    fi
fi

kitten @ "${KITTEN_TO[@]}" action goto_session "$session_file"
