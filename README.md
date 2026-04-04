# Kitty Session Selector

Project-based session switching for Kitty terminal using `fzf` and `fd`.

Switch between projects and automatically open sessions with pre-configured tabs, working directories, and programs. Sessions track active state and can be saved/restored.

## Configuration

### `kitty-sessionizer.conf`

Defines where to search for git repositories. Example:

```bash
KS_SEARCH_PATHS=(/home/santhosh/work:5 /home/santhosh/dotfiles /home/santhosh/Documents/docs/)
KS_MAX_DEPTH=1
```

Each entry is `path:depth`. If no depth is specified, `KS_MAX_DEPTH` is used.

### `default.kitty-session`

Template used when creating sessions for new projects. Placeholders are substituted at generation time:

- `@@session@@` — project name
- `@@session-path@@` — absolute path to the repo

The default template opens two tabs: one with `nvim .` in the project root, and one with a plain shell.

## Usage

Press `Ctrl+Shift+P` to open the project selector overlay.

The selector shows:
- Active sessions (marked with `▶`)
- Current session (marked with `▶ (current)`)
- All discovered git repositories

Selecting a project:
1. Saves the current session state
2. Generates a session file from the template if one doesn't exist
3. Switches to the selected session

## Session State

Two temp files track session state:

| File | Purpose |
|------|---------|
| `/tmp/kitty-current-session` | Path to the currently active session file |
| `/tmp/kitty-active-sessions` | Append-only log of all sessions used in this terminal instance |

## Generated Sessions

Session files are stored in `$XDG_DATA_HOME/kitty/sessions/` (default: `~/.local/share/kitty/sessions/`). A project can also ship its own `.kitty-session` file in the repo root, which takes priority.

## Dependencies

- `fzf` — fuzzy finder for the project selector
- `fd` — fast file finder for repository discovery
- `kitten` — Kitty's built-in scripting tool