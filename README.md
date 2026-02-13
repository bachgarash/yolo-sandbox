# yolo-sandbox

A secure sandbox for running AI coding agents and commands without risking your host system. Minimal image, install only what you need via [mise](https://mise.jdx.dev).

```bash
sandbox claude    # Claude Code in full auto mode
sandbox codex     # OpenAI Codex in full auto mode
sandbox cursor    # Open Cursor IDE in the sandbox
sandbox shell     # Interactive shell — do whatever you want
```

## Install

Requires [Docker](https://docs.docker.com/get-docker/).

```bash
curl -fsSL https://raw.githubusercontent.com/bachgarash/yolo-sandbox/refs/heads/main/install.sh | bash
```

Or clone manually:

```bash
git clone https://github.com/bachgarash/yolo-sandbox.git
cd yolo-sandbox
./sandbox.sh build
```

## Security Model

No host filesystem mounts. Zero. The container cannot see or touch your files.

```
Host                                   Container
────────────                           ────────────
~/project/ ──docker cp (in)─────────> /work/  (isolated copy)
                                           │
                                           │  agent works here
                                           │  background sync every 30s
                                           │
~/project/ <──docker cp (out)──────── /work/  (auto-sync on exit)
```

- **Zero host mounts** — container has no filesystem access to host
- **No macOS permission prompts** — `docker cp` goes through Docker daemon
- **Auto-sync on exit** — changes copied back when agent finishes
- **Background sync every 30s** — at most 30s of work lost on crash
- **Ctrl+C safe** — trap syncs before exiting
- **Capabilities dropped** — `--cap-drop=ALL`, minimal caps added back
- **Resource limited** — 8GB RAM, 4 CPUs, 512 PIDs (configurable)

## What's in the Box

The image is intentionally **minimal**:

| Included | Not included (install via mise) |
|----------|-------------------------------|
| git, build-essential | Node.js, Python, Go |
| curl, wget | Rust, Java, Ruby |
| ripgrep, fd, fzf, bat | Deno, Bun, Zig |
| jq, htop, tmux | Any of [900+ tools](https://mise.jdx.dev/registry.html) |
| zsh + Oh My Zsh | |
| **[mise](https://mise.jdx.dev)** (tool manager) | |

## Installing Dev Tools (mise)

Once inside the sandbox (`sandbox shell`), install any tool instantly:

```bash
# Single tool
mise use node@22

# Multiple tools
mise use node@22 python@3.12 go@1.23

# Specific versions
mise use python@3.11.8 rust@1.78

# Latest stable
mise use node@lts python@latest go@latest

# See what's installed
mise ls

# Run a one-off command with a tool without installing it globally
mise exec ruby@3.3 -- ruby -e "puts 'hello'"
```

### Common tool install examples

```bash
# JavaScript / TypeScript
mise use node@22
npm install -g typescript tsx pnpm yarn

# Python
mise use python@3.12
pip install ruff black pytest ipython

# Go
mise use go@1.23

# Rust
mise use rust@stable

# Java
mise use java@21
mise use maven@3

# Ruby
mise use ruby@3.3

# Deno / Bun
mise use deno@2
mise use bun@1

# Terraform, kubectl, etc.
mise use terraform@1
mise use kubectl@1.30

# See all 900+ available tools
mise registry
```

### Project-level tool config

Create a `mise.toml` in your project to pin tool versions:

```toml
# mise.toml
[tools]
node = "22"
python = "3.12"
```

Then `mise install` sets up everything. Teammates get the same versions.

## Usage

### AI Agents

```bash
# Claude Code — requires ANTHROPIC_API_KEY
export ANTHROPIC_API_KEY=sk-ant-...
sandbox claude

# OpenAI Codex — requires OPENAI_API_KEY
export OPENAI_API_KEY=sk-...
sandbox codex

# Cursor IDE
sandbox cursor
```

### Run on any project

```bash
# Point sandbox at a specific directory
SANDBOX_WORKDIR=~/projects/my-app sandbox claude
SANDBOX_WORKDIR=~/projects/my-app sandbox shell
```

### Run any command

```bash
sandbox run mise use python@3.12
sandbox run python3 script.py
sandbox run npm test
sandbox run make build
```

### Interactive shell

```bash
sandbox shell
# You're now inside the sandbox with zsh
# Install what you need:
mise use node@22 python@3.12
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SANDBOX_WORKDIR` | `$(pwd)` | Directory to copy into sandbox |
| `SANDBOX_MEMORY` | `8g` | Memory limit |
| `SANDBOX_CPUS` | `4` | CPU limit |
| `SANDBOX_PIDS` | `512` | Max processes |
| `SANDBOX_NETWORK` | `bridge` | Docker network mode (`none` for airgapped) |
| `SANDBOX_NO_SYNC` | `false` | Skip auto-sync on exit |
| `SANDBOX_IMAGE` | `ai-sandbox` | Docker image name |

```bash
# More resources
SANDBOX_MEMORY=16g SANDBOX_CPUS=8 sandbox claude

# Fully airgapped
SANDBOX_NETWORK=none sandbox shell

# Skip sync
SANDBOX_NO_SYNC=true sandbox run rm -rf /
```

## Cursor / VS Code Devcontainer

Works as a devcontainer too. Run `sandbox cursor` or open the folder and use **"Reopen in Container"** from the command palette.

## Project Structure

```
yolo-sandbox/
├── sandbox.sh                       # Main entry point
├── install.sh                       # One-liner installer
├── .devcontainer/
│   ├── Dockerfile                   # Minimal image (ubuntu + mise)
│   ├── devcontainer.json            # Cursor / VS Code config
│   └── scripts/
│       └── on-create.sh             # First-run setup
├── .cursor/rules/
│   └── yolo-sandbox.mdc            # AI rule for fearless execution
├── .gitignore
├── LICENSE
└── README.md
```

## Uninstall

```bash
rm -rf ~/.yolo-sandbox
docker rmi ai-sandbox
# Remove the PATH line from ~/.zshrc or ~/.bashrc
```

## FAQ

**Can `rm -rf /` destroy my files?**
No. There are no host mounts. The container can only destroy its own copy.

**Do I lose work if the container crashes?**
At most 30 seconds. Background sync copies changes to host every 30s while running.

**Why mise instead of pre-installing everything?**
Smaller image, faster builds, you install only what you need. mise supports [900+ tools](https://mise.jdx.dev/registry.html).

**How do I add a tool permanently to the image?**
Add `mise use -g <tool>` to `.devcontainer/scripts/on-create.sh`, or add a `RUN` to the Dockerfile.

**How do I update?**
Re-run the install one-liner.

## License

MIT
