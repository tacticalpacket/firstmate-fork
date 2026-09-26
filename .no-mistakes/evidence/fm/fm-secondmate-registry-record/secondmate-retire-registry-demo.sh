#!/usr/bin/env bash
# Operator-level demo of retiring a second mate: build a real parent home with
# two registered second mates whose records carry indented hard-rule blocks,
# run bin/fm-teardown.sh against a chosen bin/ tree, and print the operator's
# own data/secondmates.md before and after.
#
# usage: secondmate-retire-registry-demo.sh <worktree-root> <bin-dir-under-test> <label>
set -u
WORKTREE=$1
BIN=$2
LABEL=$3
MODE=${4:-normal}

# shellcheck source=/dev/null
. "$WORKTREE/tests/secondmate-helpers.sh"

TMP_ROOT=$(fm_test_tmproot fm-retire-demo)
export FM_BACKEND=tmux
HOME_DIR="$TMP_ROOT/parent home"
KEEPER="$TMP_ROOT/keeper-home"
SUB="$TMP_ROOT/design-home"
LOG="$TMP_ROOT/tmux.log"

mkdir -p "$HOME_DIR/projects" "$HOME_DIR/data" "$HOME_DIR/state"
fm_git_init_commit "$HOME_DIR/projects/alpha"
fm_git_add_origin "$HOME_DIR/projects/alpha" "$TMP_ROOT/remotes/alpha.git"
printf -- '- alpha - alpha project (added 2026-06-22)\n' > "$HOME_DIR/data/projects.md"

FAKEBIN=$(make_fake_tmux "$TMP_ROOT/fake")
make_fake_no_mistakes "$TMP_ROOT/fake" >/dev/null

FM_SECONDMATE_SCOPE='keeper work' \
  scaffold_secondmate_charter "$HOME_DIR" keeper 'keeper charter' alpha
FM_SECONDMATE_SCOPE='customer onboarding' \
  scaffold_secondmate_charter "$HOME_DIR" design 'customer onboarding charter' alpha

PATH="$FAKEBIN:$PATH" FM_HOME="$HOME_DIR" "$WORKTREE/bin/fm-home-seed.sh" keeper "$KEEPER" alpha >/dev/null
PATH="$FAKEBIN:$PATH" FM_HOME="$HOME_DIR" "$WORKTREE/bin/fm-home-seed.sh" design "$SUB" alpha >/dev/null

# The operator writes each mate's hard rules as an indented block under its own
# routing line, the span a Markdown list item owns.
awk '
  index($0, "- keeper ") == 1 {
    print
    print "  HARD RULE (keeper): merge authority stays with the captain."
    next
  }
  index($0, "- design ") == 1 {
    print
    print "  HARD RULE (design): may merge its own PRs once CI is green."
    print ""
    print "  HARD RULE (design): escalates any schema change."
    next
  }
  { print }
' "$HOME_DIR/data/secondmates.md" > "$TMP_ROOT/reg.new"
mv "$TMP_ROOT/reg.new" "$HOME_DIR/data/secondmates.md"

PATH="$FAKEBIN:$PATH" FM_HOME="$HOME_DIR" FM_CONFIG_OVERRIDE="$HOME_DIR/parent-config" \
  FM_FAKE_TMUX_LOG="$LOG" FM_FAKE_TMUX_CAPTURE="$TMP_ROOT/fake/pane.txt" \
  "$WORKTREE/bin/fm-spawn.sh" design "$SUB" codex --secondmate >/dev/null 2>&1 \
  || { echo "demo setup failed: spawn"; exit 1; }

if [ "$MODE" = duplicate ]; then
  # A registry that somehow carries two records for the same id: the retirement
  # must not guess which one to drop.
  awk '
    index($0, "- design ") == 1 { dup = dup $0 "\n" }
    { print }
    END { printf "%s", dup }
  ' "$HOME_DIR/data/secondmates.md" > "$TMP_ROOT/reg.dup"
  mv "$TMP_ROOT/reg.dup" "$HOME_DIR/data/secondmates.md"
fi

scrub() { sed -e "s#$TMP_ROOT#<FLEET>#g"; }

echo "=============================================================="
echo "$LABEL"
echo "  teardown script: ${BIN#"$WORKTREE/"}"
echo "=============================================================="
echo
echo "--- BEFORE: data/secondmates.md -----------------------------"
scrub < "$HOME_DIR/data/secondmates.md"
echo
echo "\$ bin/fm-teardown.sh design"
PATH="$FAKEBIN:$PATH" FM_HOME="$HOME_DIR" FM_FAKE_TMUX_LOG="$LOG" \
  FM_FAKE_TMUX_CAPTURE="$TMP_ROOT/fake/pane.txt" \
  "$BIN/fm-teardown.sh" design 2>&1 | scrub
teardown_rc=${PIPESTATUS[0]}
echo "(exit $teardown_rc)"
echo
echo "--- AFTER: data/secondmates.md ------------------------------"
scrub < "$HOME_DIR/data/secondmates.md"
echo
echo "--- operator reads keeper's record: -------------------------"
awk '
  index($0, "- keeper ") == 1 { show = 1; print; next }
  show && ($0 ~ /^[ \t]/ || $0 ~ /^[ \t]*$/) { print; next }
  show { exit }
' "$HOME_DIR/data/secondmates.md" | scrub
echo
