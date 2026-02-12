#!/usr/bin/env bash
# =============================================================================
# YOLO Dev Sandbox - On Create Script
# Runs once when the container is first created.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  YOLO Dev Sandbox — First-time setup"
echo "================================================"

# ---- Git config (safe defaults) ----
git config --global init.defaultBranch main
git config --global core.autocrlf input
git config --global pull.rebase false
git config --global push.autoSetupRemote true
git config --global safe.directory /workspace

# ---- Create useful aliases ----
cat >> ~/.zshrc << 'ALIASES'

# ----- YOLO Sandbox Aliases -----
alias ll="ls -lah --color=auto"
alias la="ls -A --color=auto"
alias ..="cd .."
alias ...="cd ../.."
alias gs="git status"
alias gl="git log --oneline --graph --decorate -20"
alias gd="git diff"
alias gc="git commit"
alias gp="git push"
alias dc="docker compose"
alias py="python3"
alias nuke="rm -rf node_modules .next .cache dist build __pycache__ .pytest_cache"

# Quick project scaffolding
yolo-init-node() {
  mkdir -p "$1" && cd "$1" && npm init -y && git init
  echo "node_modules/\n.env\ndist/\n.cache/" > .gitignore
  echo "Node project '$1' ready"
}

yolo-init-python() {
  mkdir -p "$1" && cd "$1" && uv init && git init
  echo "Python project '$1' ready"
}

yolo-init-go() {
  mkdir -p "$1" && cd "$1" && go mod init "$1" && git init
  echo "Go project '$1' ready"
}

# Show sandbox info
yolo-info() {
  echo "YOLO Dev Sandbox"
  echo "   OS:      $(lsb_release -ds)"
  echo "   Node:    $(node --version)"
  echo "   Python:  $(python3 --version) (uv $(uv --version | awk '{print $2}'))"
  echo "   Go:      $(go version | awk '{print $3}')"
  echo "   Rust:    $(rustc --version | awk '{print $2}')"
  echo "   Git:     $(git --version | awk '{print $3}')"
  echo "   Docker:  $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo 'not available')"
  echo "   Memory:  $(free -h | awk '/^Mem:/{print $2}') total"
  echo "   Disk:    $(df -h /work | awk 'NR==2{print $4}') free"
}
ALIASES

# ---- Python: install common global tools via uv ----
uv tool install ruff
uv tool install black
uv tool install mypy
uv tool install pytest
uv tool install ipython
uv tool install httpie

# ---- Create a scratch area for experiments ----
mkdir -p ~/scratch

echo ""
echo "================================================"
echo "  Setup complete! Run 'yolo-info' for details."
echo "================================================"
