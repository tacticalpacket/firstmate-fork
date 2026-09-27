#!/usr/bin/env bash
# Real-herdr end-to-end reproduction of the 2026-09-26 incident shape.
#
# Isolation: every herdr call here runs with XDG_CONFIG_HOME pointed at a
# throwaway scratch directory, so this script's server has its own config root
# and its own api socket and CANNOT see or stop the host's live `default` or
# `ops` servers - `herdr session list` under that root proves it sees nothing
# else. The session name is a private throwaway name, and the host's real root
# is re-listed before and after to show it never changed.
set -u
ROOT=${ROOT:?ROOT must be the firstmate worktree}
SESSION="fm-lab-paneenv-$$"
# The PATH the incident launcher had: truncated, no /usr/bin/core_perl and no
# operator additions. LAUNCH_PATH lets this run pick which installed herdr
# binary that truncated PATH resolves to.
LAUNCH_PATH=${LAUNCH_PATH:-/usr/bin:/bin}
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/fm-paneenv.XXXXXX")
export XDG_CONFIG_HOME="$SCRATCH/config"
export FM_HERDR_LAB_STATE_DIR="$SCRATCH/lab-state"
mkdir -p "$XDG_CONFIG_HOME" "$FM_HERDR_LAB_STATE_DIR"
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION

# The launcher's task pin: a shell already answering about task-b.
FAKE_HOME="$SCRATCH/fm-home"
mkdir -p "$FAKE_HOME/state"
printf 'worktree=%s\nkind=ship\n' "$SCRATCH/gone-b" > "$FAKE_HOME/state/task-b.meta"
printf 'working [at=1]: task-b\n' > "$FAKE_HOME/state/task-b.status"

say() { printf '\n=== %s ===\n' "$*"; }

cleanup() {
  say "teardown (scratch config root only - this client cannot reach any other root)"
  herdr server stop --session "$SESSION" 2>&1 | head -3
  herdr session delete "$SESSION" --force 2>&1 | head -3
  herdr session list --json 2>/dev/null | jq -c '.sessions' 2>/dev/null
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

say "host servers BEFORE (real config root, must be untouched)"
XDG_CONFIG_HOME="$HOME/.config" herdr session list --json | jq -c '[.sessions[] | {name, running}]'

say "the scratch herdr config root this run uses"
echo "XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
herdr session list --json | jq -c '.sessions'

herdr session create "$SESSION" >/dev/null 2>&1 || true

say "the incident launcher: a non-interactive script, SHELL=/bin/sh, truncated PATH ($LAUNCH_PATH), pinned to task-b"
/usr/bin/env -i \
  PATH="$LAUNCH_PATH" \
  SHELL=/bin/sh \
  HOME="$HOME" \
  XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
  HERDR_SESSION="$SESSION" \
  FM_HOME="$FAKE_HOME" \
  FM_CREW_STATE_META_OVERRIDE="$FAKE_HOME/state/task-b.meta" \
  FM_CREW_STATE_STATUS_OVERRIDE="$FAKE_HOME/state/task-b.status" \
  FM_SNAPSHOT_CACHE_DIR="$SCRATCH/snapshot-cache" \
  bash -c '
    echo "launcher SHELL=${SHELL:-<unset>}"
    echo "launcher PATH=$PATH"
    echo "launcher FM_CREW_STATE_META_OVERRIDE=$FM_CREW_STATE_META_OVERRIDE"
    . "$0/bin/backends/herdr.sh"
    fm_backend_herdr_server_ensure "$HERDR_SESSION"
    echo "server_ensure exit=$?"
  ' "$ROOT"

say "the server that launch produced"
herdr status --json --session "$SESSION" | jq -c '{socket: .server.socket, running: .server.running, server_version: .server.version, client_version: .client.version}'

say "a real task pane in that server"
. "$ROOT/bin/fm-backend.sh"
fm_backend_source herdr || { echo "fm_backend_source failed"; exit 1; }
export HERDR_SESSION="$SESSION"
CONTAINER_RAW=$(fm_backend_herdr_container_ensure "$SCRATCH") || { echo "container_ensure failed"; exit 1; }
CONTAINER=${CONTAINER_RAW%%$'\t'*}
SEEDED=${CONTAINER_RAW#*$'\t'}
IDS=$(fm_backend_herdr_create_task "$CONTAINER" "fm-paneenv" "$SCRATCH" "$SEEDED") || { echo "create_task failed"; exit 1; }
read -r TAB_ID PANE_ID <<<"$IDS"
echo "container=$CONTAINER pane=$PANE_ID"
TARGET="$SESSION:$PANE_ID"

say "what an operator sees IN that pane"
fm_backend_herdr_send_text_line "$TARGET" "clear"
sleep 1
fm_backend_herdr_send_text_line "$TARGET" 'echo "pane-SHELL=$SHELL"'
fm_backend_herdr_send_text_line "$TARGET" 'echo "pane-shell-proc=$(ps -o comm= -p $$)"; shopt -q login_shell && echo "pane-login-shell=yes" || echo "pane-login-shell=no"'
fm_backend_herdr_send_text_line "$TARGET" 'echo "pane-argv0=$0"; echo "pane-shell-cmdline=$(tr "\\0" " " < /proc/$$/cmdline)"'
fm_backend_herdr_send_text_line "$TARGET" 'echo "pane-PATH=$PATH"'
fm_backend_herdr_send_text_line "$TARGET" 'echo "pane-shasum=$(command -v shasum || echo UNREACHABLE)"'
fm_backend_herdr_send_text_line "$TARGET" 'shasum -a 256 /etc/hostname >/dev/null 2>&1; echo "pane-shasum-exit=$?"'
fm_backend_herdr_send_text_line "$TARGET" 'echo "pane-leaked-task-pin=${FM_CREW_STATE_META_OVERRIDE:-<none>}"'
fm_backend_herdr_send_text_line "$TARGET" "FM_HOME='$FAKE_HOME' bash '$ROOT/bin/fm-crew-state.sh' task-a 2>&1 | sed 's/^/pane-state-read: /'"
sleep 3
fm_backend_herdr_capture "$TARGET" 60

say "host servers AFTER (real config root, must be unchanged)"
XDG_CONFIG_HOME="$HOME/.config" herdr session list --json | jq -c '[.sessions[] | {name, running}]'
