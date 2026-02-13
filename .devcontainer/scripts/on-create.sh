#!/usr/bin/env bash
# =============================================================================
# YOLO Dev Sandbox — First-run setup
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  YOLO Dev Sandbox — Setting up..."
echo "================================================"

# ---- Git defaults ----
git config --global init.defaultBranch main
git config --global core.autocrlf input
git config --global pull.rebase false
git config --global push.autoSetupRemote true
git config --global safe.directory /workspace
git config --global safe.directory /work

# ---- mise: activate and trust ----
eval "$(~/.local/bin/mise activate bash)"

# ---- Shell aliases ----
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
alias py="python3"

# mise shortcuts
alias mi="mise install"
alias mu="mise use"
alias ml="mise ls"
alias mr="mise run"

# Show sandbox info
yolo-info() {
  echo "YOLO Dev Sandbox"
  echo "   OS:      $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
  echo "   mise:    $(mise --version 2>/dev/null || echo 'not found')"
  echo ""
  echo "   Installed tools:"
  mise ls 2>/dev/null || echo "   (none yet — use 'mise use <tool>' to install)"
  echo ""
  echo "   Memory:  $(free -h | awk '/^Mem:/{print $2}') total"
  echo "   Disk:    $(df -h /work | awk 'NR==2{print $4}') free"
}
ALIASES

echo ""
echo "================================================"
echo "  Setup complete!"
echo ""
echo "  Install tools with mise:"
echo "    mise use node@22"
echo "    mise use python@3.12"
echo "    mise use go@1.23"
echo ""
echo "  Run 'yolo-info' to see sandbox status."
echo "================================================"
