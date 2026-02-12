# yolo-dev

A secure sandbox for running AI coding agents (Claude Code, Codex, Aider) and arbitrary commands without risking your host system. One script, zero config.

```
./sandbox.sh claude    # Claude Code in full auto mode
./sandbox.sh codex     # OpenAI Codex in full auto mode
./sandbox.sh aider     # Aider
./sandbox.sh shell     # Interactive shell — do whatever you want
```

## Why

AI coding agents need to run shell commands, install packages, and modify files. Giving them unrestricted access to your machine is risky. This project runs everything inside a locked-down Docker container so agents can go full YOLO while your host stays safe.

## Security Model

```
Host filesystem                        Container
──────────────────                     ──────────────────
~/my-project/ ────read-only mount───> /workspace-ro/  (cannot write or delete)
                                            │
                                            │ rsync (copy on start)
                                            ▼
                                       /work/  (writable copy, fully disposable)
                                            │
                                            │ docker cp (auto-sync on exit)
                                            ▼
~/my-project/ <───────────────────── changes copied back
```

- **Host is read-only** — `rm -rf /` inside the container cannot touch your files
- **Auto-sync on exit** — code changes are copied back when the agent finishes
- **Ctrl+C safe** — interrupt at any time, work still syncs before exiting
- **Crash safe** — container filesystem persists after OOM/crash, sync still runs
- **Capabilities dropped** — `--cap-drop=ALL`, only minimal caps added back
- **Resource limited** — 8GB RAM, 4 CPUs, 512 PIDs (configurable)
- **Non-root** — runs as `sandbox` user (with sudo for package installs inside container)

## Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running

### Setup

```bash
git clone https://github.com/user/yolo-dev.git
cd yolo-dev
./sandbox.sh build    # Build the sandbox image (first time only)
```

### Run an AI Agent

```bash
# Claude Code — requires ANTHROPIC_API_KEY
export ANTHROPIC_API_KEY=sk-ant-...
./sandbox.sh claude

# OpenAI Codex — requires OPENAI_API_KEY
export OPENAI_API_KEY=sk-...
./sandbox.sh codex

# Aider — requires OPENAI_API_KEY or ANTHROPIC_API_KEY
./sandbox.sh aider
```

### Run on Your Own Project

```bash
# Point the sandbox at any directory on your machine
SANDBOX_WORKDIR=~/projects/my-app ./sandbox.sh claude
```

### Interactive Shell

```bash
./sandbox.sh shell    # Drops you into a zsh shell inside the sandbox
```

### Run Any Command

```bash
./sandbox.sh run python3 script.py
./sandbox.sh run npm test
./sandbox.sh run make build
```

## What's in the Container

| Category | Tools |
|----------|-------|
| **Languages** | Node.js 22, Python 3 (via uv), Go 1.23, Rust (stable) |
| **Package Managers** | npm, yarn, pnpm, uv, cargo |
| **Python Tools** | ruff, black, mypy, pytest, ipython, httpie |
| **Shell** | Zsh + Oh My Zsh (autosuggestions, syntax highlighting) |
| **Version Control** | Git, git-lfs, GitHub CLI |
| **Container** | Docker CLI (Docker-outside-of-Docker) |
| **Utilities** | ripgrep, fd, fzf, bat, jq, yq, htop, tmux, curl, wget |
| **Build** | gcc, g++, make, cmake, autotools |
| **Databases** | SQLite, PostgreSQL client |

## Configuration

All settings are via environment variables:

```bash
SANDBOX_IMAGE=ai-sandbox      # Docker image name
SANDBOX_MEMORY=8g             # Memory limit
SANDBOX_CPUS=4                # CPU limit
SANDBOX_PIDS=512              # Max processes
SANDBOX_WORKDIR=$(pwd)        # Directory to mount
SANDBOX_NETWORK=bridge        # Docker network mode ("none" for airgapped)
SANDBOX_NO_SYNC=false         # Skip auto-sync on exit
SANDBOX_EXTRA_ARGS=""         # Extra docker run arguments
```

Examples:

```bash
# More resources
SANDBOX_MEMORY=16g SANDBOX_CPUS=8 ./sandbox.sh claude

# Fully airgapped (no network)
SANDBOX_NETWORK=none ./sandbox.sh shell

# Skip syncing changes back
SANDBOX_NO_SYNC=true ./sandbox.sh run rm -rf /   # go wild, nothing happens
```

## Cursor / VS Code Devcontainer

This repo also works as a devcontainer. Open the folder in Cursor or VS Code, install the **Dev Containers** extension, then run **"Reopen in Container"** from the command palette.

The `.cursor/rules/yolo-sandbox.mdc` rule tells the AI to run commands without asking for confirmation.

## Project Structure

```
yolo-dev/
├── sandbox.sh                       # Main entry point — run this
├── .devcontainer/
│   ├── Dockerfile                   # Container image definition
│   ├── devcontainer.json            # VS Code / Cursor devcontainer config
│   └── scripts/
│       └── on-create.sh             # First-run setup (aliases, tools, git)
├── .cursor/rules/
│   └── yolo-sandbox.mdc            # Cursor AI rule for fearless execution
├── .gitignore
└── README.md
```

## FAQ

**Can `rm -rf /` destroy my files?**
No. Your files are mounted read-only. We tested this — [it fails with "Read-only file system"](#security-model).

**Do I lose my work if the container crashes?**
No. The container is kept after exit (no `--rm`), so `docker cp` can extract your work. The script handles this automatically, even after Ctrl+C.

**Can I use this in CI?**
Yes. The script detects non-TTY environments and adapts. Set `SANDBOX_NO_SYNC=true` if you don't need changes back.

**How do I add more tools?**
Edit `.devcontainer/Dockerfile` and run `./sandbox.sh build`.

**How do I reset the sandbox?**
Run `./sandbox.sh build` to rebuild from scratch.

## License

MIT
