#!/usr/bin/env bash
# Start Pi in a Herdr worktree pane.
#
# Hooks: worktree.created, worktree.opened, action start (prefix+shift+i).
# Herdr's new_cwd=follow inherits the previous pane cwd, so we cd to the
# checkout path before `agent start`. Trunkr opens via `herdr worktree open`,
# which emits worktree.opened (not created).
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
state_dir="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr-pi-worktree}"
mkdir -p "$state_dir"

ctx="${HERDR_PLUGIN_EVENT_JSON:-}"
if [[ -z "$ctx" || "$ctx" == "null" ]]; then
  ctx="${HERDR_PLUGIN_CONTEXT_JSON:-{}}"
fi
printf '%s\n' "$ctx" >"$state_dir/last-context.json"

jq_first() {
  local expr="$1"
  jq -r "$expr" <<<"$ctx" 2>/dev/null | awk 'NF && $0 != "null" { print; exit }'
}

workspace_id="${HERDR_WORKSPACE_ID:-}"
pane_id="${HERDR_PANE_ID:-${HERDR_ACTIVE_PANE_ID:-}}"
[[ -n "$workspace_id" ]] || workspace_id="$(jq_first '
  .workspace_id // .workspace.workspace_id // .workspace.id
  // .result.workspace.workspace_id // empty
')"
[[ -n "$pane_id" ]] || pane_id="$(jq_first '
  .pane_id // .pane.pane_id // .root_pane.pane_id
  // .workspace.root_pane.pane_id // .result.root_pane.pane_id
  // empty
')"

wt_path="$(jq_first '
  .worktree.path
  // .worktree.checkout_path
  // .workspace.worktree.checkout_path
  // .result.worktree.path
  // .result.workspace.worktree.checkout_path
  // empty
')"
already_open="$(jq_first '.already_open // .result.already_open // empty' || true)"
action_id="${HERDR_PLUGIN_ACTION_ID:-}"

pane_from_list() {
  local ws="$1" out
  [[ -n "$ws" ]] || return 1
  out="$("$herdr" pane list --workspace "$ws" 2>/dev/null || true)"
  if pane="$(jq -r '
      (.result.panes // .panes // .)
      | if type == "array" then .[0].pane_id // .[0].id
        else .pane_id // empty end
    ' <<<"$out" 2>/dev/null)" && [[ -n "$pane" && "$pane" != "null" ]]; then
    printf '%s\n' "$pane"
    return 0
  fi
  grep -Eo 'w[0-9]+:p[0-9]+' <<<"$out" | head -n1
}

if [[ -z "$pane_id" ]]; then
  pane_id="$(pane_from_list "$workspace_id" || true)"
fi
if [[ -z "$pane_id" ]]; then
  pane_id="$("$herdr" pane current 2>/dev/null || true)"
fi
if [[ -z "$pane_id" ]]; then
  echo "herdr-pi-worktree: no pane id in event/context" >&2
  exit 1
fi

pane_has_pi() {
  local out
  out="$("$herdr" agent list 2>/dev/null || true)"
  jq -e --arg p "$pane_id" '
    (.result.agents // .agents // [])
    | any(.pane_id == $p and ((.agent // "") | test("pi";"i")))
  ' <<<"$out" >/dev/null 2>&1
}

# Re-open of an already-open workspace: do not spawn a second Pi.
# Manual action (prefix+shift+i) still starts if the pane is a bare shell.
if [[ -z "$action_id" && "$already_open" == "true" ]] && pane_has_pi; then
  exit 0
fi
if pane_has_pi && [[ -z "$action_id" ]]; then
  exit 0
fi

lock="$state_dir/${pane_id//:/_}.starting"
while ! mkdir "$lock" 2>/dev/null; do
  if pane_has_pi; then
    exit 0
  fi
  sleep 0.2
done
trap 'rmdir "$lock" 2>/dev/null || true' EXIT

pane_shell_idle() {
  local info names
  info="$("$herdr" pane process-info --pane "$pane_id" 2>/dev/null || true)"
  names="$(jq -r '
    [.result.process_info.foreground_processes[]?.name] | join(" ")
  ' <<<"$info" 2>/dev/null || true)"
  [[ "$names" == "zsh" || "$names" == "bash" || "$names" == "sh" ]]
}

pane_cwd() {
  local info
  info="$("$herdr" pane process-info --pane "$pane_id" 2>/dev/null || true)"
  jq -r '.result.process_info.foreground_processes[0].cwd // empty' <<<"$info" 2>/dev/null
}

wait_shell() {
  local i
  for i in $(seq 1 40); do
    if pane_shell_idle; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

wait_shell || true

if [[ -n "$wt_path" && -d "$wt_path" ]]; then
  cur="$(pane_cwd || true)"
  if [[ "$cur" != "$wt_path" ]]; then
    "$herdr" pane run "$pane_id" "cd $(printf %q "$wt_path")" >/dev/null
    wait_shell || true
  fi
  if [[ -f "$wt_path/.envrc" ]] && command -v direnv >/dev/null 2>&1; then
    if (cd "$wt_path" && direnv status) 2>/dev/null | grep -qi 'blocked\|not allowed'; then
      "$herdr" pane run "$pane_id" "direnv allow" >/dev/null || true
      wait_shell || true
    fi
  fi
fi

if pane_has_pi && [[ -z "$action_id" ]]; then
  exit 0
fi

branch="$(jq_first '.worktree.branch // .branch // .workspace.branch // empty' || true)"
slug="$(printf '%s' "${branch:-pi}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-' | tr -s '-' | cut -c1-24)"
slug="${slug#-}"
[[ "$slug" =~ ^[a-z] ]] || slug="p${slug}"
[[ -n "$slug" ]] || slug="pi"
name="$slug"

start_args=()
if [[ -n "${HERDR_PI_MODEL:-}" ]]; then
  start_args+=(-- --model "$HERDR_PI_MODEL")
  if [[ -n "${HERDR_PI_THINKING:-}" ]]; then
    start_args+=(--thinking "$HERDR_PI_THINKING")
  fi
fi

started=0
for attempt in 1 2 3 4 5 6 7 8; do
  if out="$("$herdr" agent start "$name" --kind pi --pane "$pane_id" "${start_args[@]}" 2>&1)"; then
    started=1
    break
  fi
  if grep -qi 'already\|unique\|taken\|exists' <<<"$out"; then
    name="${slug}-$(printf '%02d' "$attempt")"
  fi
  sleep 1
  if [[ -z "${workspace_id:-}" ]]; then
    :
  elif [[ -z "$pane_id" ]]; then
    pane_id="$(pane_from_list "$workspace_id" || true)"
  fi
done

if [[ "$started" -ne 1 ]]; then
  echo "herdr-pi-worktree: failed to start pi in $pane_id" >&2
  exit 1
fi
