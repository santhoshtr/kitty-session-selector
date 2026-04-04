#!/usr/bin/env bash
set -euo pipefail

# Make sure fd is in the path.
export PATH="$HOME/.cargo/bin:$PATH"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
SESSION_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kitty/sessions"
DEFAULT_SESSION="$CONFIG_DIR/default.kitty-session"
CURRENT_SESSION_TRACKER="/tmp/kitty-current-session"
ACTIVE_SESSIONS_TRACKER="/tmp/kitty-active-sessions"

source "$CONFIG_DIR/kitty-sessionizer.conf" 2>/dev/null || true

find_repos() {
    for entry in "${KS_SEARCH_PATHS[@]}"; do
        path="${entry%%:*}"
        depth="${entry##*:}"
        [[ "$path" == "$entry" ]] && depth="${KS_MAX_DEPTH:-1}"
        [[ -d "$path" ]] && fd --hidden -t d -d "$depth" .git "$path" --format '{//}'
    done
}

# Save current session state before switching
if [[ -f "$CURRENT_SESSION_TRACKER" ]]; then
    current_session=$(cat "$CURRENT_SESSION_TRACKER")
    if [[ -f "$current_session" ]]; then
        kitten @ action save_as_session --use-foreground-process --relocatable --match=session:. --save-only "$current_session" 2>/dev/null || true
    fi
fi

# Collect active session paths, deduplicated
declare -A active_map
if [[ -f "$ACTIVE_SESSIONS_TRACKER" ]]; then
    while IFS= read -r line; do
        [[ -f "$line" ]] && active_map["$line"]=1
    done < "$ACTIVE_SESSIONS_TRACKER"
fi

current_session=""
[[ -f "$CURRENT_SESSION_TRACKER" ]] && current_session=$(cat "$CURRENT_SESSION_TRACKER")

# Build fzf input: display_name\tsession_path
# Active sessions first, then remaining repos
fzf_input=""

for session_path in "${!active_map[@]}"; do
    name="${session_path##*/}"
    name="${name%.kitty-session}"
    tag="▶"
    [[ "$session_path" == "$current_session" ]] && tag="▶ (current)"
    fzf_input+="$tag $name\t$session_path\n"
done

while IFS= read -r repo; do
    if [[ -f "$repo/.kitty-session" ]]; then
        session_path="$repo/.kitty-session"
    else
        session_path="$SESSION_DIR/${repo##*/}.kitty-session"
    fi
    [[ -n "${active_map[$session_path]+_}" ]] && continue
    fzf_input+="  $repo\t$session_path\n"
done < <(find_repos | sort -f)

# fzf selection
selected=$(printf "$fzf_input" | fzf \
    --prompt "Project > " \
    --delimiter '\t' \
    --with-nth 1 \
    || exit 0)
[[ -z "$selected" ]] && exit 0

session_file="${selected##*$'\t'}"

# Ensure generated session exists
if [[ ! -f "$session_file" ]]; then
    mkdir -p "$SESSION_DIR"
    name=$(basename "$session_file" .kitty-session)
    # Find the repo path for template substitution
    repo_path=""
    for entry in "${KS_SEARCH_PATHS[@]}"; do
        path="${entry%%:*}"
        depth="${entry##*:}"
        [[ "$path" == "$entry" ]] && depth="${KS_MAX_DEPTH:-1}"
        [[ -d "$path" ]] || continue
        while IFS= read -r repo; do
            [[ "$(basename "$repo")" == "$name" ]] && { repo_path="$repo"; break; }
        done < <(find "$path" -mindepth 1 -maxdepth "$depth" -name .git -type d -printf '%h\n' 2>/dev/null)
        [[ -n "$repo_path" ]] && break
    done
    if [[ -n "$repo_path" ]]; then
        sed -e "s|@@session-path@@|$repo_path|g" -e "s|@@session@@|$name|g" "$DEFAULT_SESSION" > "$session_file"
    fi
fi

echo "$session_file" > "$CURRENT_SESSION_TRACKER"
echo "$session_file" >> "$ACTIVE_SESSIONS_TRACKER"
kitten @ action goto_session "$session_file"
