#!/usr/bin/env bash
# =============================================================================
# AI Agent Sandbox Runner
# =============================================================================
# Secure isolation wrapper for running AI coding agents inside Docker.
#
# SECURITY MODEL:
#   Host workspace is mounted READ-ONLY at /workspace-ro.
#   On container start, files are copied to /work (writable).
#   Agents work on /work. The host is NEVER writable from inside.
#   On exit, changes are automatically synced back to host.
#
# Usage:
#   ./sandbox.sh claude                    # Run Claude Code
#   ./sandbox.sh codex                     # Run OpenAI Codex
#   ./sandbox.sh aider                     # Run Aider
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
#   SANDBOX_WORKDIR     - Directory to mount as workspace (default: current dir)
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

# ---- Entrypoint script (runs INSIDE the container) ----
ENTRYPOINT_SCRIPT='#!/bin/bash
set -e

# Copy host files from read-only mount to writable working directory
if [ -d /workspace-ro ] && [ "$(ls -A /workspace-ro 2>/dev/null)" ]; then
  rsync -a --quiet /workspace-ro/ /work/
fi

# Track changes via git, but keep .git outside /work so it never syncs back
if [ ! -d /tmp/.sandbox-git ]; then
  git init --quiet --separate-git-dir=/tmp/.sandbox-git /work 2>/dev/null || true
  rm -f /work/.git 2>/dev/null || true
  git --git-dir=/tmp/.sandbox-git --work-tree=/work add -A 2>/dev/null || true
  git --git-dir=/tmp/.sandbox-git --work-tree=/work commit -m "initial snapshot" --quiet 2>/dev/null || true
fi
cd /work

# Run the actual command
exec "$@"
'

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
      if ! command -v aider &>/dev/null; then
        log "Installing Aider..."
        uv tool install aider-chat
      fi
      ;;
  esac
}

# Sync changes from a stopped container back to host, then remove it
sync_and_cleanup() {
  local dcmd="$1"
  local container_name="$2"
  local exit_code="$3"

  if [[ "${NO_SYNC}" == "true" ]]; then
    log "Skipping sync (SANDBOX_NO_SYNC=true)"
    ${dcmd} rm "${container_name}" &>/dev/null || true
    return
  fi

  # Copy /work from the stopped container back to host
  # .git is stored in /tmp inside the container, so it never leaks to host
  if ${dcmd} cp "${container_name}":/work/. "${WORKDIR}/" 2>/dev/null; then
    ok "Changes synced back to ${WORKDIR}"
  else
    warn "Could not sync /work — it may have been deleted inside the container."
    warn "Your original files on host are safe (read-only mount)."
  fi

  # Clean up the container
  ${dcmd} rm "${container_name}" &>/dev/null || true
}

# Core function: run a command inside the sandbox with auto-sync
run_sandbox() {
  local cmd=("$@")

  # If already inside a sandbox, just run directly
  if [[ "${INSIDE_SANDBOX}" == "true" ]]; then
    ok "Already inside sandbox — running command directly."
    exec "${cmd[@]}"
    return
  fi

  local dcmd
  dcmd=$(docker_cmd)
  ensure_image

  # Generate a unique container name
  local container_name="sandbox-$(date +%s)-$$"

  # Trap Ctrl+C / SIGTERM — stop the container and still sync before exiting
  trap '_sandbox_interrupted=true; ${dcmd} stop "${container_name}" 2>/dev/null || true' INT TERM

  log "Starting sandbox..."
  log "  Image:    ${IMAGE}"
  log "  Memory:   ${MEMORY}"
  log "  CPUs:     ${CPUS}"
  log "  PIDs:     ${PIDS}"
  log "  Network:  ${NETWORK}"
  log "  Workdir:  ${WORKDIR} (mounted read-only)"
  log "  Work:     /work (writable copy — auto-syncs on exit)"
  log "  Command:  ${cmd[*]}"
  echo ""

  # Run WITHOUT --rm so we can copy files back after exit
  local container_exit=0
  _sandbox_interrupted=false
  # shellcheck disable=SC2086
  ${dcmd} run \
    "${TTY_ARGS[@]}" \
    --name "${container_name}" \
    "${SECURITY_ARGS[@]}" \
    "${RESOURCE_ARGS[@]}" \
    --network="${NETWORK}" \
    --hostname=ai-sandbox \
    -v "${WORKDIR}":/workspace-ro:ro \
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
    -c "${ENTRYPOINT_SCRIPT}"' exec "$@"' _ "${cmd[@]}" \
    || container_exit=$?

  # Auto-sync changes back to host (runs even after Ctrl+C / crash / OOM)
  echo ""
  if [[ "${_sandbox_interrupted}" == "true" ]]; then
    warn "Interrupted! Syncing your work before exiting..."
  else
    log "Container exited (code: ${container_exit}). Syncing changes..."
  fi
  sync_and_cleanup "${dcmd}" "${container_name}" "${container_exit}"

  # Restore default signal handling
  trap - INT TERM

  return ${container_exit}
}

# Run an agent with install-if-missing logic
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

  # Trap Ctrl+C / SIGTERM — stop container and still sync
  trap '_sandbox_interrupted=true; ${dcmd} stop "${container_name}" 2>/dev/null || true' INT TERM

  log "Starting sandbox..."
  log "  Image:    ${IMAGE}"
  log "  Memory:   ${MEMORY}"
  log "  CPUs:     ${CPUS}"
  log "  PIDs:     ${PIDS}"
  log "  Network:  ${NETWORK}"
  log "  Workdir:  ${WORKDIR} (mounted read-only)"
  log "  Work:     /work (writable copy — auto-syncs on exit)"
  log "  Agent:    ${agent}"
  echo ""

  local container_exit=0
  _sandbox_interrupted=false
  # shellcheck disable=SC2086
  ${dcmd} run \
    "${TTY_ARGS[@]}" \
    --name "${container_name}" \
    "${SECURITY_ARGS[@]}" \
    "${RESOURCE_ARGS[@]}" \
    --network="${NETWORK}" \
    --hostname=ai-sandbox \
    -v "${WORKDIR}":/workspace-ro:ro \
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
    -c "${ENTRYPOINT_SCRIPT}
${install_cmd}"' exec "$@"' _ "${exec_cmd[@]}" \
    || container_exit=$?

  # Auto-sync changes back to host (runs even after Ctrl+C / crash / OOM)
  echo ""
  if [[ "${_sandbox_interrupted}" == "true" ]]; then
    warn "Interrupted! Syncing your work before exiting..."
  else
    log "Container exited (code: ${container_exit}). Syncing changes..."
  fi
  sync_and_cleanup "${dcmd}" "${container_name}" "${container_exit}"

  trap - INT TERM
  return ${container_exit}
}

# ---- Main ----

usage() {
  cat <<'USAGE'
AI Agent Sandbox Runner — Secure isolation for AI coding agents

SECURITY: Host files are mounted READ-ONLY. Agents work on a writable
copy inside the container. On exit, changes are auto-synced back to host.
Your host files can never be deleted from inside the sandbox.

Usage:
  ./sandbox.sh <agent>              Run an AI agent inside the sandbox
  ./sandbox.sh run <command...>     Run any command inside the sandbox
  ./sandbox.sh build                Build/rebuild the sandbox image
  ./sandbox.sh help                 Show this help

Agents:
  claude    Claude Code (Anthropic) — requires ANTHROPIC_API_KEY
  codex     OpenAI Codex CLI        — requires OPENAI_API_KEY
  aider     Aider                   — requires OPENAI_API_KEY or ANTHROPIC_API_KEY
  shell     Interactive zsh shell

Examples:
  ./sandbox.sh claude                         # Launch Claude Code
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
      'command -v aider &>/dev/null || uv tool install aider-chat' \
      aider
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
