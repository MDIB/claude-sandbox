# Claude Sandbox

A Docker-based sandbox for running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in an isolated container. Mount any project directory, get a fully-equipped dev environment, and let Claude work without touching your host system.

Works on **Linux** and **macOS** (Intel + Apple Silicon).

## Why

Running Claude Code directly on your machine gives it broad access to your filesystem and tools. This sandbox:

- **Isolates Claude** to a single project directory mounted as `/workspace`
- **Protects credentials** by mounting `~/.claude` read-only
- **Provides a reproducible environment** with common dev tools pre-installed
- **Skips permissions prompts** (`--dangerously-skip-permissions`) since the container itself is the security boundary

## Prerequisites

| | Linux | macOS |
|---|---|---|
| **Docker** | [Docker Engine](https://docs.docker.com/engine/install/) | [Docker Desktop](https://www.docker.com/products/docker-desktop/) |
| **Compose** | `docker-compose` (v1) or `docker compose` (v2) | Included with Docker Desktop |
| **Claude auth** | `~/.claude` directory | `~/.claude` directory |

> The scripts auto-detect whether you have `docker compose` (v2 plugin, default on macOS) or the standalone `docker-compose` (v1, common on Linux). Both work.

## Quick Start

### Option 1: Run directly (recommended)

```bash
# Clone or unzip this folder, then:
cd claude-sandbox
chmod +x run-claude.sh

# Run with current directory as workspace
./run-claude.sh

# Or specify a project directory
./run-claude.sh ~/dev/my-project
```

The script auto-builds the Docker image on first run (~2-3 min).

### Option 2: Install globally

```bash
cd claude-sandbox
chmod +x install-global.sh
./install-global.sh
```

This installs a `claude-sandbox` command to `~/.local/bin/`. Then from anywhere:

```bash
cd ~/dev/my-project
claude-sandbox

# Or specify a directory
claude-sandbox ~/dev/another-project
```

If `~/.local/bin` is not in your `PATH`, add this to your shell config:

```bash
# Add to ~/.zshrc (macOS default) or ~/.bashrc (Linux)
export PATH="$PATH:$HOME/.local/bin"
```

You can also install to a custom location:

```bash
./install-global.sh /usr/local/bin
```

### Option 3: docker compose

```bash
cd claude-sandbox

# v2 (macOS / newer Linux)
docker compose build
docker compose run --rm claude-code claude

# v1 (older Linux)
docker-compose build
docker-compose run --rm claude-code claude
```

Note: this mounts the `claude-sandbox` directory itself as `/workspace`. Use `run-claude.sh` to mount arbitrary directories.

### Option 4: Plain Docker

```bash
docker build -t claude-code-sandbox .

docker run -it --rm \
  -v "$(pwd):/workspace" \
  -v "$HOME/.claude:/home/claude/.claude:ro" \
  -w /workspace \
  claude-code-sandbox claude
```

## What's in the Container

**Base:** Alpine Linux + Node.js 20 (~398 MB, multi-arch: amd64 + arm64)

| Category | Tools |
|----------|-------|
| **Editors** | vim, nano |
| **Search** | ripgrep (`rg`), fd, grep, jq, yq |
| **Languages** | Node.js 20, Python 3 |
| **Node tools** | TypeScript, tsx, Prettier, ESLint, json-server |
| **Python tools** | IPython, pytest, black, ruff, mypy, requests, httpx, pandas, BeautifulSoup |
| **Build** | make, gcc/g++ |
| **Network** | curl, wget, openssh-client, bind-tools |
| **Database CLIs** | sqlite, postgresql-client, redis |
| **Misc** | git, Docker CLI, tree, strace, lsof, patch, diffutils |

> The Alpine base image is multi-arch. Docker automatically pulls the correct image for your platform (amd64 on Intel, arm64 on Apple Silicon). No configuration needed.

Claude can install additional tools at runtime:

```bash
apk add --no-cache <package>    # Alpine packages
npm install -g <package>         # Node packages
pip install <package>            # Python packages
```

## Configuration

### Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `ANTHROPIC_API_KEY` | API key (if not using `~/.claude` auth) | empty |

Pass via environment:

```bash
ANTHROPIC_API_KEY=sk-ant-... ./run-claude.sh ~/my-project
```

### Customizing the Image

- **Add system packages:** Edit `Dockerfile`, add to the `apk add` block
- **Add Python packages:** Edit `Dockerfile`, add to the `pip3 install` block
- **Add Node packages:** Edit `Dockerfile`, add to the `npm install -g` block
- **Change base image:** Edit the `FROM` line in `Dockerfile`

After changes, rebuild:

```bash
# v2
docker compose build --no-cache
# v1
docker-compose build --no-cache
# or plain docker
docker build -t claude-code-sandbox --no-cache .
```

### Mounting Extra Volumes

To give Claude access to SSH keys, additional configs, etc.:

```bash
docker run -it --rm \
  -v "$(pwd):/workspace" \
  -v "$HOME/.claude:/home/claude/.claude:ro" \
  -v "$HOME/.ssh:/home/claude/.ssh:ro" \
  -v "$HOME/.gitconfig:/home/claude/.gitconfig:ro" \
  -w /workspace \
  claude-code-sandbox claude
```

### Docker-in-Docker

To let Claude run Docker commands inside the container, mount the Docker socket. The socket path differs by platform:

```bash
# Linux
docker run -it --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$(pwd):/workspace" \
  -v "$HOME/.claude:/home/claude/.claude:ro" \
  claude-code-sandbox claude

# macOS (Docker Desktop)
docker run -it --rm \
  -v "$HOME/.docker/run/docker.sock:/var/run/docker.sock" \
  -v "$(pwd):/workspace" \
  -v "$HOME/.claude:/home/claude/.claude:ro" \
  claude-code-sandbox claude
```

Or uncomment the relevant line in `docker-compose.yml`.

### Changing the Default Command

The `run-claude.sh` script defaults to `claude --dangerously-skip-permissions`. To override:

```bash
./run-claude.sh ~/my-project bash    # Get a shell instead
```

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Container image definition with all pre-installed tools |
| `docker-compose.yml` | Compose config for building and running the container |
| `run-claude.sh` | Main entry script -- run from anywhere, mount any directory |
| `install-global.sh` | Installs `claude-sandbox` command to your PATH |
| `entrypoint.sh` | Fixes credential permissions at container start (runs via sudo before dropping to the `claude` user) |

## Troubleshooting

**Image not building:**
```bash
docker compose build --no-cache   # or docker-compose
```

**Credentials not found:**
Ensure `~/.claude` exists on your host. Run `claude` natively once to authenticate.

**Permission errors:**
The container runs as user `claude` (UID 1000) with passwordless sudo. If your host files have a different UID, you may need to adjust the UID in the `Dockerfile`.

**Slow on macOS (file I/O):**
Docker Desktop's file sharing can be slow with large `node_modules`. If you hit this, consider adding `:cached` to the workspace mount in `docker-compose.yml` or using Docker's VirtioFS file sharing backend (Docker Desktop > Settings > General > VirtioFS).

**Apple Silicon -- image build fails:**
The Alpine base image supports arm64 natively. If a specific `apk` or `pip` package fails on arm64, check if it has a pre-built wheel or needs a platform override:
```bash
docker build --platform linux/amd64 -t claude-code-sandbox .
```
This runs under Rosetta emulation (slower but compatible).

**Network issues:**
Ensure Docker can reach `api.anthropic.com`:
```bash
docker run --rm alpine wget -q -O- https://api.anthropic.com
```

**Rebuild from scratch:**
```bash
docker rmi claude-code-sandbox
./run-claude.sh  # Rebuilds automatically
```

## Security Model

- The container is the security boundary -- Claude has full access *inside* the container but cannot reach your host filesystem beyond the mounted volumes
- Claude runs as a non-root user (`claude`, UID 1000) with **passwordless sudo** -- this gives it full privileges inside the container while avoiding the "refuses to run as root" issue
- `--dangerously-skip-permissions` is safe here because the container limits blast radius
- `~/.claude` is mounted read-only (credentials can't be modified)
- Network access is enabled (required for the Claude API)
