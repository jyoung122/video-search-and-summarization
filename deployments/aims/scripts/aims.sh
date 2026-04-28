#!/usr/bin/env bash
# AIMS demo controller — start, stop, status, logs, destroy.
#
# Required env:
#   NGC_CLI_API_KEY   NGC API key (https://ngc.nvidia.com/setup/api-key)
#
# Optional env:
#   AIMS_DC           Datacenter id (auto-picked if unset)
#   AIMS_NIM_TEMPLATE Default: iyl91qhpsa
#   AIMS_APP_TEMPLATE Default: juolcnzk4l
#   AIMS_GPU_NIM      Default: "NVIDIA RTX PRO 6000 Blackwell Server Edition"
#   AIMS_GPU_APP      Default: "NVIDIA L4"
#   AIMS_NUM_SENSORS  Default: 15
#
# Usage:
#   aims.sh start      Launch NIM pod, wait for ready, launch app pod
#   aims.sh stop       Stop both pods (preserves disks; resumable)
#   aims.sh resume     Restart both pods
#   aims.sh status     Show pod state, balance, current spend
#   aims.sh logs nim   Tail NIM pod bootstrap log
#   aims.sh logs app   Tail app pod bootstrap log
#   aims.sh urls       Print proxy URLs for NIM and app pods
#   aims.sh destroy    Delete both pods (irreversible)
set -euo pipefail

# Load .env from the script's directory if present (lets you keep
# NGC_CLI_API_KEY etc. out of your shell rc).
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/.env"
  set +a
fi

NIM_TEMPLATE=${AIMS_NIM_TEMPLATE:-iyl91qhpsa}
APP_TEMPLATE=${AIMS_APP_TEMPLATE:-juolcnzk4l}
GPU_NIM=${AIMS_GPU_NIM:-"NVIDIA RTX PRO 6000 Blackwell Server Edition"}
GPU_APP=${AIMS_GPU_APP:-"NVIDIA L4"}
NUM_SENSORS=${AIMS_NUM_SENSORS:-15}
STATE_FILE=${AIMS_STATE_FILE:-$HOME/.aims-state.json}

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need runpodctl
need jq

state_get() {
  [ -f "$STATE_FILE" ] || { echo ""; return 0; }
  jq -r ".$1 // empty" "$STATE_FILE" 2>/dev/null || echo ""
}
state_set() {
  local k=$1 v=$2
  [ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"
  local tmp; tmp=$(mktemp)
  jq --arg k "$k" --arg v "$v" '.[$k]=$v' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

require_ngc() {
  : "${NGC_CLI_API_KEY:?Set NGC_CLI_API_KEY in env (do not paste in chat)}"
}

pick_dc() {
  if [ -n "${AIMS_DC:-}" ]; then echo "$AIMS_DC"; return; fi
  # Pick first DC where both GPUs are available with global networking.
  # Cheap heuristic: just return EU-RO-1 (commonly has both). Override with AIMS_DC.
  echo "EU-RO-1"
}

cmd_start() {
  require_ngc
  local dc; dc=$(pick_dc)
  local nim_id; nim_id=$(state_get nim_id)
  local app_id; app_id=$(state_get app_id)

  if [ -n "$nim_id" ] || [ -n "$app_id" ]; then
    echo "Pods already tracked in $STATE_FILE (nim=$nim_id app=$app_id)."
    echo "Run 'aims.sh resume' to restart, or 'aims.sh destroy' to wipe."
    exit 1
  fi

  echo "==> [1/4] Launching NIM pod in $dc"
  local nim_json
  nim_json=$(runpodctl pod create \
    --template-id "$NIM_TEMPLATE" \
    --name aims-nim \
    --gpu-id "$GPU_NIM" \
    --gpu-count 1 \
    --container-disk-in-gb 200 \
    --global-networking \
    --data-center-ids "$dc" \
    --env "$(jq -nc --arg k "$NGC_CLI_API_KEY" '{NGC_CLI_API_KEY:$k, AIMS_REPO_URL:"https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization.git", AIMS_REPO_REF:"main"}')")
  nim_id=$(echo "$nim_json" | jq -r '.id')
  state_set nim_id "$nim_id"
  state_set dc "$dc"
  echo "    NIM pod: $nim_id"

  echo "==> [2/4] Resolving NIM pod private IP (waiting for global networking)"
  local nim_ip=""
  for i in {1..40}; do
    nim_ip=$(runpodctl pod get "$nim_id" --include-machine 2>/dev/null \
      | jq -r '.privateIp // .machine.networkAddress // empty')
    if [ -n "$nim_ip" ]; then break; fi
    sleep 5
  done
  if [ -z "$nim_ip" ]; then
    echo "    Could not resolve NIM private IP. Inspect:"
    echo "      runpodctl pod get $nim_id --include-machine"
    exit 1
  fi
  state_set nim_ip "$nim_ip"
  echo "    NIM private IP: $nim_ip"

  echo "==> [3/4] Launching app pod in $dc"
  local app_json
  app_json=$(runpodctl pod create \
    --template-id "$APP_TEMPLATE" \
    --name aims-app \
    --gpu-id "$GPU_APP" \
    --gpu-count 1 \
    --container-disk-in-gb 80 \
    --global-networking \
    --data-center-ids "$dc" \
    --env "$(jq -nc --arg k "$NGC_CLI_API_KEY" --arg ip "$nim_ip" --arg n "$NUM_SENSORS" \
      '{NGC_CLI_API_KEY:$k, NIM_POD_HOST:$ip, NUM_SENSORS:$n, AIMS_REPO_URL:"https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization.git", AIMS_REPO_REF:"main"}')")
  app_id=$(echo "$app_json" | jq -r '.id')
  state_set app_id "$app_id"
  echo "    App pod: $app_id"

  echo "==> [4/4] Started. Bootstrap takes ~10–15 min on first run (NIM weights pull)."
  echo "    Watch:   $0 logs nim   |   $0 logs app"
  echo "    URLs:    $0 urls"
  echo "    Stop:    $0 stop       (preserves disks)"
  echo "    Destroy: $0 destroy"
}

cmd_stop() {
  local nim_id; nim_id=$(state_get nim_id)
  local app_id; app_id=$(state_get app_id)
  [ -n "$app_id" ] && { echo "Stopping app: $app_id"; runpodctl pod stop "$app_id" || true; }
  [ -n "$nim_id" ] && { echo "Stopping NIM: $nim_id"; runpodctl pod stop "$nim_id" || true; }
  echo "Stopped. Disks preserved. 'aims.sh resume' to restart."
}

cmd_resume() {
  local nim_id; nim_id=$(state_get nim_id)
  local app_id; app_id=$(state_get app_id)
  [ -n "$nim_id" ] && { echo "Starting NIM: $nim_id"; runpodctl pod start "$nim_id"; }
  [ -n "$app_id" ] && { echo "Starting app: $app_id"; runpodctl pod start "$app_id"; }
}

cmd_status() {
  echo "Account:"
  runpodctl user 2>/dev/null | jq '{balance:.clientBalance, spendPerHr:.currentSpendPerHr, spendLimit:.spendLimit}'
  echo
  echo "State file: $STATE_FILE"
  [ -f "$STATE_FILE" ] && cat "$STATE_FILE" | jq . || echo "  (empty)"
  echo
  for role in nim app; do
    local id; id=$(state_get "${role}_id")
    [ -z "$id" ] && continue
    echo "=== $role pod $id ==="
    runpodctl pod get "$id" 2>/dev/null \
      | jq '{name, desiredStatus, lastStatusChange, costPerHr, runtime: (.runtime // null)}' \
      || echo "  (not found)"
  done
}

cmd_logs() {
  local role=${1:?logs nim|app}
  local id; id=$(state_get "${role}_id")
  [ -z "$id" ] && { echo "no $role pod tracked"; exit 1; }
  echo "Tailing $role pod $id bootstrap log (Ctrl-C to detach)..."
  # Pod's start command tails /var/log/bootstrap.log to stdout, so pod logs is enough.
  runpodctl ssh info "$id" 2>/dev/null \
    | jq -r '.command // empty' \
    | grep -q . || { echo "ssh not ready yet — try: runpodctl pod get $id"; exit 1; }
  local sshcmd; sshcmd=$(runpodctl ssh info "$id" | jq -r '.command')
  # Strip "ssh " prefix and append the tail command.
  eval "$sshcmd 'tail -n 200 -f /var/log/bootstrap.log'"
}

cmd_urls() {
  local nim_id; nim_id=$(state_get nim_id)
  local app_id; app_id=$(state_get app_id)
  echo "NIM pod ($nim_id):"
  [ -n "$nim_id" ] && {
    echo "  VLM health: https://${nim_id}-30082.proxy.runpod.net/v1/health/ready"
    echo "  LLM health: https://${nim_id}-30081.proxy.runpod.net/v1/health/ready"
  }
  echo "App pod ($app_id):"
  [ -n "$app_id" ] && {
    echo "  UI:  https://${app_id}-8000.proxy.runpod.net"
    echo "  VST: https://${app_id}-30888.proxy.runpod.net"
    echo "  API: https://${app_id}-8081.proxy.runpod.net"
  }
}

cmd_destroy() {
  local nim_id; nim_id=$(state_get nim_id)
  local app_id; app_id=$(state_get app_id)
  echo "About to DELETE:"
  [ -n "$nim_id" ] && echo "  NIM pod $nim_id"
  [ -n "$app_id" ] && echo "  App pod $app_id"
  read -r -p "Type 'destroy' to confirm: " ans
  [ "$ans" = "destroy" ] || { echo "aborted"; exit 1; }
  [ -n "$app_id" ] && runpodctl pod delete "$app_id" || true
  [ -n "$nim_id" ] && runpodctl pod delete "$nim_id" || true
  rm -f "$STATE_FILE"
  echo "Destroyed."
}

cmd=${1:-}; shift || true
case "$cmd" in
  start)   cmd_start "$@" ;;
  stop)    cmd_stop "$@" ;;
  resume)  cmd_resume "$@" ;;
  status)  cmd_status "$@" ;;
  logs)    cmd_logs "$@" ;;
  urls)    cmd_urls "$@" ;;
  destroy) cmd_destroy "$@" ;;
  *) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /set -euo/d'; exit 1 ;;
esac
