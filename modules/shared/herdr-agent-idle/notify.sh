#!/usr/bin/env bash
# Herdr event hook: named implementer settled → toast + prompt an idle coordinator.
# Wired as [[events]] on = "pane.agent_status_changed". Do not invoke by hand.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
state_dir="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr-agent-idle}"
mkdir -p "$state_dir"

ctx="${HERDR_PLUGIN_EVENT_JSON:-}"
if [[ -z "$ctx" || "$ctx" == "null" ]]; then
  ctx="${HERDR_PLUGIN_CONTEXT_JSON:-{}}"
fi
printf '%s\n' "$ctx" >"$state_dir/last-event.json"

jq_first() {
  local expr="$1"
  jq -r "$expr" <<<"$ctx" 2>/dev/null | awk 'NF && $0 != "null" { print; exit }'
}

status="$(jq_first '
  .agent_status // .event.agent_status // .event.data.agent_status // empty
')"
pane_id="$(jq_first '
  .pane_id // .event.pane_id // .event.data.pane_id // empty
')"
workspace_id="$(jq_first '
  .workspace_id // .event.workspace_id // .event.data.workspace_id // empty
')"

case "$status" in
  idle|done|blocked) ;;
  *) exit 0 ;;
esac

listed="$("$herdr" agent list 2>/dev/null || echo '{}')"
if [[ -z "$pane_id" ]]; then
  pane_id="$(jq -r --arg st "$status" '
    (.result.agents // .agents // [])
    | map(select(.agent_status == $st and ((.name // "") != "")))
    | .[0].pane_id // empty
  ' <<<"$listed")"
fi
[[ -n "$pane_id" ]] || exit 0

row="$(jq -c --arg p "$pane_id" '
  (.result.agents // .agents // [])
  | map(select(.pane_id == $p))
  | .[0] // {}
' <<<"$listed")"

name="$(jq -r '.name // empty' <<<"$row")"
cwd="$(jq -r '.cwd // empty' <<<"$row")"
[[ -n "$status" ]] || status="$(jq -r '.agent_status // empty' <<<"$row")"
[[ -n "$workspace_id" ]] || workspace_id="$(jq -r '.workspace_id // empty' <<<"$row")"

# Unnamed panes are coordinators. Named coord/coordinator are listeners, not implementers.
case "$name" in
  ""|coord|coordinator) exit 0 ;;
esac

case "$status" in
  idle|done|blocked) ;;
  *) exit 0 ;;
esac

debounce="$state_dir/last-${name}-${status}"
now="$(date +%s)"
if [[ -f "$debounce" ]]; then
  prev="$(cat "$debounce" 2>/dev/null || echo 0)"
  if [[ "$prev" =~ ^[0-9]+$ ]] && (( now - prev < 4 )); then
    exit 0
  fi
fi
printf '%s\n' "$now" >"$debounce"

sound="done"
[[ "$status" == "blocked" ]] && sound="request"
body="${name} ${status}  ${pane_id}"
[[ -n "$cwd" ]] && body="${body}  ${cwd}"

"$herdr" notification show "${name} ${status}" --body "$body" --sound "$sound" >/dev/null 2>&1 || true

coord="$(jq -r --arg src "$pane_id" '
  (.result.agents // .agents // [])
  | map(select(
      .pane_id != $src
      and ((.name // "") == "" or (.name // "") == "coord" or (.name // "") == "coordinator")
      and ((.agent_status // "") == "idle" or (.agent_status // "") == "done")
    ))
  | .[0].name // .[0].pane_id // empty
' <<<"$listed")"

[[ -n "$coord" ]] || exit 0

msg="Implementer ${name} is ${status} (${pane_id}"
[[ -n "$workspace_id" ]] && msg="${msg} ${workspace_id}"
[[ -n "$cwd" ]] && msg="${msg} ${cwd}"
msg="${msg}). Read that pane, then resume. herdr agent read ${name} --source recent-unwrapped --lines 80"

"$herdr" agent prompt "$coord" "$msg" >/dev/null 2>&1 || true
