#!/usr/bin/env bash
# Start Pi in the worktree (or focused) pane. Used as a Herdr plugin event
# hook (`worktree.created`) and as the `start` action (prefix+shift+i).
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

branch="$(jq_first '.worktree.branch // .branch // .workspace.branch // empty' || true)"
slug="$(printf '%s' "${branch:-pi}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-' | tr -s '-' | cut -c1-24)"
slug="${slug#-}"
[[ "$slug" =~ ^[a-z] ]] || slug="p${slug}"
[[ -n "$slug" ]] || slug="pi"
name="$slug"

started=0
for attempt in 1 2 3 4 5 6 7 8; do
  if out="$("$herdr" agent start "$name" --kind pi --pane "$pane_id" 2>&1)"; then
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
