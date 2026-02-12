#!/usr/bin/env bash
# =============================================================================
# AI Agent Sandbox Runner
# =============================================================================
# Secure isolation wrapper for running AI coding agents inside Docker.
#
# SECURITY MODEL:
#   NO host filesystem mounts. Zero. None.
#   Files are copied IN via 'docker cp' before the agent starts.
#   Files are copied OUT via 'docker cp' after the agent exits.
#   The container has no access to the host filesystem at any point.
#
# Usage:
#   ./sandbox.sh claude                    # Run Claude Code
#   ./sandbox.sh codex                     # Run OpenAI Codex
#   ./sandbox.sh aider                     # Run Aider
#   ./sandbox.sh cursor                    # Open Cursor IDE in sandbox
#   ./sandbox.sh shell                     # Interactive shell
#   ./sandbox.sh run <any-command>         # Run arbitrary command in sandbox
#   ./sandbox.sh build                     # Build/rebuild the sandbox image
#
# Environment variables:
#   ANTHROPIC_API_KEY   - Required for Claude Code
#   OPENAI_API_KEY      - Required for Codex
#   SANDBOX_IMAGE       - Custom image name (default: ai-sandbox)
#   SANDBOX_MEMORY      - Memory limit (default: 8g)
#   SANDBOX_CPUS        - CPU limit (default: 4)
#   SANDBOX_PIDS        - PID limit (default: 512)
#   SANDBOX_WORKDIR     - Source directory to copy into sandbox (default: current dir)
#   SANDBOX_EXTRA_ARGS  - Additional docker run arguments
#   SANDBOX_NETWORK     - Docker network mode (default: bridge)
#   SANDBOX_NO_SYNC     - Set to "true" to skip auto-sync on exit
# =============================================================================
set -euo pipefail

# ---- Configuration ----
IMAGE="${SANDBOX_IMAGE:-ai-sandbox}"
MEMORY="${SANDBOX_MEMORY:-8g}"
CPUS="${SANDBOX_CPUS:-4}"
PIDS="${SANDBOX_PIDS:-512}"
WORKDIR="${SANDBOX_WORKDIR:-$(pwd)}"
NETWORK="${SANDBOX_NETWORK:-bridge}"
NO_SYNC="${SANDBOX_NO_SYNC:-false}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[sandbox]${NC} $*"; }
ok()   { echo -e "${GREEN}[sandbox]${NC} $*"; }
warn() { echo -e "${YELLOW}[sandbox]${NC} $*"; }
err()  { echo -e "${RED}[sandbox]${NC} $*" >&2; }

# ---- Detect if already inside a sandbox ----
is_inside_sandbox() {
  [[ "${AI_SANDBOX:-}" == "true" ]] && return 0
  [[ "${YOLO_SANDBOX:-}" == "true" ]] && return 0
  [[ "$(hostname 2>/dev/null)" == *sandbox* ]] && return 0
  [[ -f /.dockerenv ]] && return 0
  return 1
}

INSIDE_SANDBOX=false
if is_inside_sandbox; then
  INSIDE_SANDBOX=true
fi

# ---- TTY detection ----
TTY_ARGS=()
if [ -t 0 ] && [ -t 1 ]; then
  TTY_ARGS=(-it)
else
  TTY_ARGS=(-i)
fi

# ---- Security flags ----
SECURITY_ARGS=(
  --cap-drop=ALL
  --cap-add=NET_BIND_SERVICE
  --cap-add=SETUID
  --cap-add=SETGID
  --cap-add=DAC_OVERRIDE
  --cap-add=AUDIT_WRITE
  --cap-add=CHOWN
  --cap-add=FOWNER
)

# ---- Resource limits ----
RESOURCE_ARGS=(
  --memory="${MEMORY}"
  --memory-swap="${MEMORY}"
  --cpus="${CPUS}"
  --pids-limit="${PIDS}"
)

# ---- Functions ----

docker_cmd() {
  if docker info &>/dev/null 2>&1; then
    echo "docker"
  elif sudo docker info &>/dev/null 2>&1; then
    warn "Docker socket requires root. Using sudo."
    echo "sudo docker"
  else
    err "Docker is not available or not running."
    exit 1
  fi
}

build_image() {
  local dcmd
  dcmd=$(docker_cmd)
  log "Building sandbox image '${IMAGE}'..."
  ${dcmd} build -t "${IMAGE}" -f "${SCRIPT_DIR}/.devcontainer/Dockerfile" "${SCRIPT_DIR}"
  ok "Image '${IMAGE}' built successfully."
}

ensure_image() {
  local dcmd
  dcmd=$(docker_cmd)
  if ! ${dcmd} image inspect "${IMAGE}" &>/dev/null; then
    warn "Image '${IMAGE}' not found. Building..."
    build_image
  fi
}

install_agent() {
  local agent="$1"
  case "${agent}" in
    claude)
      if ! command -v claude &>/dev/null; then
        log "Installing Claude Code..."
        sudo npm install -g @anthropic-ai/claude-code
      fi
      ;;
    codex)
      if ! command -v codex &>/dev/null; then
        log "Installing Codex..."
        sudo npm install -g @openai/codex
      fi
      ;;
    aider)
      # aider runs via uvx, no install needed
      ;;
  esac
}

# Create a container, copy files in
create_sandbox() {
  local dcmd="$1"
  local container_name="$2"
  local setup_cmd="${3:-}"
  shift 3

  # Build the command that runs inside the container
  local inner_cmd="cd /work"
  if [ -n "${setup_cmd}" ]; then
    inner_cmd="${inner_cmd} && ${setup_cmd}"
  fi
  inner_cmd="${inner_cmd}"' && exec "$@"'

  # Create the container (stopped) with no host mounts
  # shellcheck disable=SC2086
  ${dcmd} create \
    "${TTY_ARGS[@]}" \
    --name "${container_name}" \
    "${SECURITY_ARGS[@]}" \
    "${RESOURCE_ARGS[@]}" \
    --network="${NETWORK}" \
    --hostname=ai-sandbox \
    -w /work \
    --entrypoint /bin/bash \
    ${ANTHROPIC_API_KEY:+"-e" "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"} \
    ${OPENAI_API_KEY:+"-e" "OPENAI_API_KEY=${OPENAI_API_KEY}"} \
    ${OPENAI_ORG_ID:+"-e" "OPENAI_ORG_ID=${OPENAI_ORG_ID}"} \
    ${GITHUB_TOKEN:+"-e" "GITHUB_TOKEN=${GITHUB_TOKEN}"} \
    ${GH_TOKEN:+"-e" "GH_TOKEN=${GH_TOKEN}"} \
    -e "AI_SANDBOX=true" \
    -e "AI_SANDBOX_MEMORY=${MEMORY}" \
    -e "AI_SANDBOX_CPUS=${CPUS}" \
    ${SANDBOX_EXTRA_ARGS:-} \
    "${IMAGE}" \
    -c "${inner_cmd}" _ "$@" \
    > /dev/null

  # Copy workspace files into the container (no mount needed)
  if [ -d "${WORKDIR}" ] && [ "$(ls -A "${WORKDIR}" 2>/dev/null)" ]; then
    log "Copying files into sandbox..."
    ${dcmd} cp "${WORKDIR}/." "${container_name}":/work/
  fi
}

# Sync files back from container to host, then clean up
sync_and_cleanup() {
  local dcmd="$1"
  local container_name="$2"

  if [[ "${NO_SYNC}" == "true" ]]; then
    log "Skipping sync (SANDBOX_NO_SYNC=true)"
    ${dcmd} rm "${container_name}" &>/dev/null || true
    return
  fi

  # Copy /work back to host — .git is in /tmp inside container, never leaks
  if ${dcmd} cp "${container_name}":/work/. "${WORKDIR}/" 2>/dev/null; then
    ok "Changes synced back to ${WORKDIR}"
  else
    warn "Could not sync /work — it may have been deleted inside the container."
    warn "Your original files on host are untouched (no mounts were used)."
  fi

  # Clean up
  ${dcmd} rm "${container_name}" &>/dev/null || true
}

# ---- Core: run a command inside the sandbox ----
run_sandbox() {
  local cmd=("$@")

  if [[ "${INSIDE_SANDBOX}" == "true" ]]; then
    ok "Already inside sandbox — running command directly."
    exec "${cmd[@]}"
    return
  fi

  local dcmd
  dcmd=$(docker_cmd)
  ensure_image

  local container_name="sandbox-$(date +%s)-$$"

  # Trap Ctrl+C / SIGTERM — stop container, still sync
  trap '_sandbox_interrupted=true; ${dcmd} stop "${container_name}" 2>/dev/null || true' INT TERM

  log "Starting sandbox..."
  log "  Image:    ${IMAGE}"
  log "  Memory:   ${MEMORY}"
  log "  CPUs:     ${CPUS}"
  log "  PIDs:     ${PIDS}"
  log "  Network:  ${NETWORK}"
  log "  Workdir:  ${WORKDIR} (copied in, no mount)"
  log "  Command:  ${cmd[*]}"
  echo ""

  # Create container and copy files in
  _sandbox_interrupted=false
  create_sandbox "${dcmd}" "${container_name}" "" "${cmd[@]}"

  # Start periodic background sync (every 30s) to avoid losing work
  _bg_sync_pid=""
  if [[ "${NO_SYNC}" != "true" ]]; then
    (
      while true; do
        sleep 30
        ${dcmd} cp "${container_name}":/work/. "${WORKDIR}/" 2>/dev/null || true
      done
    ) &
    _bg_sync_pid=$!
  fi

  # Start the container and wait for it to finish
  local container_exit=0
  ${dcmd} start -a "${container_name}" || container_exit=$?

  # Stop background sync
  if [ -n "${_bg_sync_pid}" ]; then
    kill "${_bg_sync_pid}" 2>/dev/null || true
    wait "${_bg_sync_pid}" 2>/dev/null || true
  fi

  # Auto-sync on exit
  echo ""
  if [[ "${_sandbox_interrupted}" == "true" ]]; then
    warn "Interrupted! Syncing your work before exiting..."
  else
    log "Container exited (code: ${container_exit}). Syncing changes..."
  fi
  sync_and_cleanup "${dcmd}" "${container_name}"

  trap - INT TERM
  return ${container_exit}
}

# ---- Core: run an agent with install-if-missing logic ----
run_agent() {
  local agent="$1"
  shift
  local install_cmd="$1"
  shift
  local exec_cmd=("$@")

  if [[ "${INSIDE_SANDBOX}" == "true" ]]; then
    install_agent "${agent}"
    exec "${exec_cmd[@]}"
    return
  fi

  local dcmd
  dcmd=$(docker_cmd)
  ensure_image

  local container_name="sandbox-${agent}-$(date +%s)-$$"

  trap '_sandbox_interrupted=true; ${dcmd} stop "${container_name}" 2>/dev/null || true' INT TERM

  log "Starting sandbox..."
  log "  Image:    ${IMAGE}"
  log "  Memory:   ${MEMORY}"
  log "  CPUs:     ${CPUS}"
  log "  PIDs:     ${PIDS}"
  log "  Network:  ${NETWORK}"
  log "  Workdir:  ${WORKDIR} (copied in, no mount)"
  log "  Agent:    ${agent}"
  echo ""

  _sandbox_interrupted=false
  create_sandbox "${dcmd}" "${container_name}" "${install_cmd}" "${exec_cmd[@]}"

  # Start periodic background sync (every 30s)
  _bg_sync_pid=""
  if [[ "${NO_SYNC}" != "true" ]]; then
    (
      while true; do
        sleep 30
        ${dcmd} cp "${container_name}":/work/. "${WORKDIR}/" 2>/dev/null || true
      done
    ) &
    _bg_sync_pid=$!
  fi

  local container_exit=0
  ${dcmd} start -a "${container_name}" || container_exit=$?

  # Stop background sync
  if [ -n "${_bg_sync_pid}" ]; then
    kill "${_bg_sync_pid}" 2>/dev/null || true
    wait "${_bg_sync_pid}" 2>/dev/null || true
  fi

  echo ""
  if [[ "${_sandbox_interrupted}" == "true" ]]; then
    warn "Interrupted! Syncing your work before exiting..."
  else
    log "Container exited (code: ${container_exit}). Syncing changes..."
  fi
  sync_and_cleanup "${dcmd}" "${container_name}"

  trap - INT TERM
  return ${container_exit}
}

# ---- Main ----

usage() {
  cat <<'USAGE'
AI Agent Sandbox Runner — Secure isolation for AI coding agents

SECURITY: No host filesystem mounts. Files are copied in/out via
docker cp. The container cannot access your host filesystem at all.
Changes are auto-synced back on exit.

Usage:
  ./sandbox.sh <agent>              Run an AI agent inside the sandbox
  ./sandbox.sh run <command...>     Run any command inside the sandbox
  ./sandbox.sh build                Build/rebuild the sandbox image
  ./sandbox.sh help                 Show this help

Agents:
  claude    Claude Code (Anthropic) — requires ANTHROPIC_API_KEY
  codex     OpenAI Codex CLI        — requires OPENAI_API_KEY
  aider     Aider                   — requires OPENAI_API_KEY or ANTHROPIC_API_KEY
  cursor    Open Cursor IDE in the devcontainer sandbox
  shell     Interactive zsh shell

Examples:
  ./sandbox.sh claude                         # Launch Claude Code
  ./sandbox.sh cursor                         # Open Cursor in sandbox
  ./sandbox.sh shell                          # Interactive sandbox shell
  SANDBOX_MEMORY=16g ./sandbox.sh claude      # Claude with 16GB RAM
  SANDBOX_NETWORK=none ./sandbox.sh shell     # Fully airgapped shell
  ./sandbox.sh run python3 my_script.py       # Run a script in sandbox
  SANDBOX_NO_SYNC=true ./sandbox.sh run ...   # Skip auto-sync on exit

USAGE
}

case "${1:-help}" in
  build)
    build_image
    ;;

  claude)
    run_agent claude \
      'command -v claude &>/dev/null || sudo npm install -g @anthropic-ai/claude-code' \
      claude --dangerously-skip-permissions
    ;;

  codex)
    run_agent codex \
      'command -v codex &>/dev/null || sudo npm install -g @openai/codex' \
      codex --full-auto
    ;;

  aider)
    run_agent aider \
      '' \
      uvx --from aider-chat aider
    ;;

  cursor)
    if ! command -v cursor &>/dev/null; then
      err "Cursor IDE not found. Install it from https://cursor.com"
      err "Then enable the 'cursor' shell command via:"
      err "  Cursor > Cmd+Shift+P > 'Install cursor command in PATH'"
      exit 1
    fi
    ensure_image

    # Copy devcontainer config into the target workspace so Cursor detects it
    if [ ! -f "${WORKDIR}/.devcontainer/devcontainer.json" ]; then
      log "Adding .devcontainer/ config to ${WORKDIR}..."
      mkdir -p "${WORKDIR}/.devcontainer/scripts"
      cp "${SCRIPT_DIR}/.devcontainer/Dockerfile"           "${WORKDIR}/.devcontainer/Dockerfile"
      cp "${SCRIPT_DIR}/.devcontainer/devcontainer.json"    "${WORKDIR}/.devcontainer/devcontainer.json"
      cp "${SCRIPT_DIR}/.devcontainer/scripts/on-create.sh" "${WORKDIR}/.devcontainer/scripts/on-create.sh"
    fi

    if [ ! -f "${WORKDIR}/.cursor/rules/yolo-sandbox.mdc" ]; then
      log "Adding .cursor/rules/ for YOLO mode..."
      mkdir -p "${WORKDIR}/.cursor/rules"
      cp "${SCRIPT_DIR}/.cursor/rules/yolo-sandbox.mdc" "${WORKDIR}/.cursor/rules/yolo-sandbox.mdc"
    fi

    cursor --install-extension ms-vscode-remote.remote-containers 2>/dev/null || true

    echo ""
    ok "Opening Cursor..."
    echo ""
    log "  When Cursor opens, it will detect the devcontainer config."
    log "  Click 'Reopen in Container' in the notification that appears."
    log ""
    log "  If you miss the notification:"
    log "    1. Press Cmd+Shift+P"
    log "    2. Type 'Reopen in Container'"
    log "    3. Select 'Dev Containers: Reopen in Container'"
    log ""
    log "  First launch builds the image inside Cursor (takes a few minutes)."
    log "  Subsequent launches are instant."
    echo ""

    cursor "${WORKDIR}"
    ;;

  shell)
    run_sandbox /bin/zsh
    ;;

  run)
    shift
    if [ $# -eq 0 ]; then
      err "No command specified. Usage: ./sandbox.sh run <command...>"
      exit 1
    fi
    run_sandbox "$@"
    ;;

  help|--help|-h)
    usage
    ;;

  *)
    err "Unknown command: $1"
    usage
    exit 1
    ;;
esac
