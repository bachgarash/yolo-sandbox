#!/usr/bin/env bash
# =============================================================================
# yolo-sandbox installer
# Usage: curl -fsSL https://raw.githubusercontent.com/bachgarash/yolo-sandbox/refs/heads/main/install.sh | bash
# =============================================================================
set -euo pipefail

REPO="bachgarash/yolo-sandbox"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}"
INSTALL_DIR="${YOLO_INSTALL_DIR:-${HOME}/.yolo-sandbox}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[yolo]${NC} $*"; }
ok()  { echo -e "${GREEN}[yolo]${NC} $*"; }
err() { echo -e "${RED}[yolo]${NC} $*" >&2; }

# ---- Preflight checks ----
if ! command -v docker &>/dev/null; then
  err "Docker is required but not installed."
  err "Install it from https://docs.docker.com/get-docker/"
  exit 1
fi

if ! docker info &>/dev/null 2>&1; then
  err "Docker is installed but not running. Start Docker and try again."
  exit 1
fi

if ! command -v curl &>/dev/null; then
  err "curl is required but not installed."
  exit 1
fi

# ---- Download files ----
log "Installing yolo-sandbox to ${INSTALL_DIR}..."

mkdir -p "${INSTALL_DIR}/.devcontainer/scripts"
mkdir -p "${INSTALL_DIR}/.cursor/rules"

curl -fsSL "${BASE_URL}/sandbox.sh"                          -o "${INSTALL_DIR}/sandbox.sh"
curl -fsSL "${BASE_URL}/.devcontainer/Dockerfile"            -o "${INSTALL_DIR}/.devcontainer/Dockerfile"
curl -fsSL "${BASE_URL}/.devcontainer/devcontainer.json"     -o "${INSTALL_DIR}/.devcontainer/devcontainer.json"
curl -fsSL "${BASE_URL}/.devcontainer/scripts/on-create.sh"  -o "${INSTALL_DIR}/.devcontainer/scripts/on-create.sh"
curl -fsSL "${BASE_URL}/.cursor/rules/yolo-sandbox.mdc"      -o "${INSTALL_DIR}/.cursor/rules/yolo-sandbox.mdc"
curl -fsSL "${BASE_URL}/.gitignore"                          -o "${INSTALL_DIR}/.gitignore"

chmod +x "${INSTALL_DIR}/sandbox.sh"
chmod +x "${INSTALL_DIR}/.devcontainer/scripts/on-create.sh"

# ---- Build the Docker image ----
log "Building sandbox Docker image (this takes a few minutes the first time)..."
"${INSTALL_DIR}/sandbox.sh" build

# ---- Add to PATH ----
SHELL_NAME=$(basename "${SHELL:-/bin/bash}")
SHELL_RC="${HOME}/.${SHELL_NAME}rc"
ALIAS_LINE="alias sandbox='${INSTALL_DIR}/sandbox.sh'"
PATH_EXPORT="export PATH=\"${INSTALL_DIR}:\$PATH\""

# Create a symlink so "sandbox" works from anywhere
ln -sf "${INSTALL_DIR}/sandbox.sh" "${INSTALL_DIR}/sandbox"

if [ -f "${SHELL_RC}" ]; then
  if ! grep -q "yolo-sandbox" "${SHELL_RC}" 2>/dev/null; then
    {
      echo ""
      echo "# yolo-sandbox"
      echo "${PATH_EXPORT}"
    } >> "${SHELL_RC}"
    log "Added to PATH in ${SHELL_RC}"
  fi
fi

# ---- Done ----
echo ""
ok "yolo-sandbox installed successfully!"
echo ""
echo "  Usage:"
echo "    sandbox shell                          # Interactive shell"
echo "    sandbox claude                         # Claude Code"
echo "    sandbox codex                          # OpenAI Codex"
echo "    sandbox cursor                         # Cursor IDE"
echo "    SANDBOX_WORKDIR=~/my-project sandbox claude  # Run on your project"
echo ""
echo "  Restart your terminal or run: source ${SHELL_RC}"
echo ""
