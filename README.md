# yolo-sandbox

A secure sandbox for running AI coding agents (Claude Code, Codex, Aider) and arbitrary commands without risking your host system. One script, zero config.

```bash
sandbox claude    # Claude Code in full auto mode
sandbox codex     # OpenAI Codex in full auto mode
sandbox aider     # Aider
sandbox cursor    # Open Cursor IDE in the sandbox
sandbox shell     # Interactive shell — do whatever you want
```

## Install

Requires [Docker](https://docs.docker.com/get-docker/) running on your machine.

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/bachgarash/yolo-sandbox/refs/heads/main/install.sh | bash
```

This downloads the sandbox, builds the Docker image, and adds `sandbox` to your PATH.

### Manual

```bash
git clone https://github.com/bachgarash/yolo-sandbox.git
cd yolo-sandbox
./sandbox.sh build
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

## Usage

### Run AI Agents

```bash
# Claude Code — requires ANTHROPIC_API_KEY
export ANTHROPIC_API_KEY=sk-ant-...
sandbox claude

# OpenAI Codex — requires OPENAI_API_KEY
export OPENAI_API_KEY=sk-...
sandbox codex

# Aider — requires OPENAI_API_KEY or ANTHROPIC_API_KEY
sandbox aider

# Cursor IDE — opens in devcontainer
sandbox cursor
```

### Run on Your Own Project

```bash
SANDBOX_WORKDIR=~/projects/my-app sandbox claude
```

### Interactive Shell

```bash
sandbox shell
```

### Run Any Command

```bash
sandbox run python3 script.py
sandbox run npm test
sandbox run make build
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

All settings via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SANDBOX_WORKDIR` | `$(pwd)` | Directory to mount in sandbox |
| `SANDBOX_MEMORY` | `8g` | Memory limit |
| `SANDBOX_CPUS` | `4` | CPU limit |
| `SANDBOX_PIDS` | `512` | Max processes |
| `SANDBOX_NETWORK` | `bridge` | Docker network mode (`none` for airgapped) |
| `SANDBOX_NO_SYNC` | `false` | Skip auto-sync on exit |
| `SANDBOX_IMAGE` | `ai-sandbox` | Docker image name |
| `SANDBOX_EXTRA_ARGS` | | Extra docker run arguments |

Examples:

```bash
# More resources
SANDBOX_MEMORY=16g SANDBOX_CPUS=8 sandbox claude

# Fully airgapped (no network)
SANDBOX_NETWORK=none sandbox shell

# Skip syncing changes back
SANDBOX_NO_SYNC=true sandbox run rm -rf /   # go wild, nothing happens
```

## Cursor / VS Code Devcontainer

This repo also works as a devcontainer. Open the folder in Cursor or VS Code, install the **Dev Containers** extension, then run **"Reopen in Container"** from the command palette.

The `.cursor/rules/yolo-sandbox.mdc` rule tells the AI to run commands without asking for confirmation.

## Uninstall

```bash
rm -rf ~/.yolo-sandbox
# Remove the PATH line from your ~/.zshrc or ~/.bashrc
```

## Project Structure

```
yolo-sandbox/
├── sandbox.sh                       # Main entry point
├── install.sh                       # One-liner installer
├── .devcontainer/
│   ├── Dockerfile                   # Container image definition
│   ├── devcontainer.json            # VS Code / Cursor devcontainer config
│   └── scripts/
│       └── on-create.sh             # First-run setup (aliases, tools, git)
├── .cursor/rules/
│   └── yolo-sandbox.mdc            # Cursor AI rule for fearless execution
├── .gitignore
├── LICENSE
└── README.md
```

## FAQ

**Can `rm -rf /` destroy my files?**
No. Your files are mounted read-only. We tested it — the kernel blocks it with "Read-only file system".

**Do I lose my work if the container crashes?**
No. The container is kept after exit (no `--rm`), so `docker cp` can extract your work. The script handles this automatically, even after Ctrl+C.

**Can I use this in CI?**
Yes. The script detects non-TTY environments and adapts. Set `SANDBOX_NO_SYNC=true` if you don't need changes back.

**How do I add more tools?**
Edit `.devcontainer/Dockerfile` and run `sandbox build`.

**How do I update?**
Re-run the install one-liner. It overwrites the existing installation.

## License

MIT
