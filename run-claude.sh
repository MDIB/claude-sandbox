#!/bin/bash
set -e

# Run claude-code in a Docker sandbox.
# Mounts workspace and config at real host paths so Claude Code sees
# the same CWD, HOME, and project keys as on the host.
# Works on both Linux and macOS (Intel + Apple Silicon).

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Get the directory where this script lives (where Dockerfile is)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default workspace is current directory, or use argument
WORKSPACE_DIR="${1:-$(pwd)}"
WORKSPACE_DIR="$(cd "$WORKSPACE_DIR" && pwd)"

# Optional command override (default: claude)
CONTAINER_CMD="${2:-claude --dangerously-skip-permissions}"

# Image name
IMAGE_NAME="claude-code-sandbox"

# Claude's dedicated SSH/git identity
CLAUDE_SSH_DIR="$HOME/.config/claude/ssh"
CLAUDE_GITCONFIG="$HOME/.config/claude/gitconfig"

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ── Docker detection ─────────────────────────────────────────────────────────

if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    case "$(uname -s)" in
        Darwin) log_error "Install Docker Desktop: https://www.docker.com/products/docker-desktop/" ;;
        *)      log_error "Install Docker: https://docs.docker.com/engine/install/" ;;
    esac
    exit 1
fi

detect_compose() {
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        log_error "Neither 'docker compose' (v2) nor 'docker-compose' (v1) found"
        exit 1
    fi
}
detect_compose

# ── Workspace validation ─────────────────────────────────────────────────────

if [ ! -d "$WORKSPACE_DIR" ]; then
    log_error "Workspace directory does not exist: $WORKSPACE_DIR"
    exit 1
fi

# ── First-run: Claude SSH identity setup ─────────────────────────────────────

if [ ! -d "$CLAUDE_SSH_DIR" ]; then
    log_warn "Claude's SSH identity not found at $CLAUDE_SSH_DIR"
    echo ""
    echo "Claude needs its own SSH key and git config for git operations."
    echo "This is separate from your personal SSH keys."
    echo ""

    read -p "Set up Claude's SSH identity now? [Y/n] " setup_ssh
    if [[ "$setup_ssh" =~ ^[Nn] ]]; then
        log_warn "Skipping SSH setup. Git operations over SSH won't work in the sandbox."
    else
        mkdir -p "$CLAUDE_SSH_DIR"

        # Git identity
        read -p "Git user name for Claude [Claude (AI Assistant)]: " git_name
        git_name="${git_name:-Claude (AI Assistant)}"
        read -p "Git email for Claude [claudinhozito33333@proton.me]: " git_email
        git_email="${git_email:-claudinhozito33333@proton.me}"

        # Generate SSH key
        ssh-keygen -t ed25519 -C "$git_email" -f "$CLAUDE_SSH_DIR/id_ed25519" -N ""
        echo ""

        # SSH config
        cat > "$CLAUDE_SSH_DIR/config" << 'SSHEOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host *
    AddKeysToAgent yes
    StrictHostKeyChecking accept-new
SSHEOF

        # Git config
        cat > "$CLAUDE_GITCONFIG" << GITEOF
[user]
    name = $git_name
    email = $git_email

[core]
    autocrlf = input
    editor = vim

[init]
    defaultBranch = main

[push]
    default = current
    autoSetupRemote = true
GITEOF

        echo ""
        log_info "SSH key generated. Add this public key to your Git hosting:"
        echo ""
        cat "$CLAUDE_SSH_DIR/id_ed25519.pub"
        echo ""
        log_info "GitHub:  https://github.com/settings/keys"
        log_info "Gitea:   Settings → SSH/GPG Keys → Add Key"
        echo ""
        read -p "Press Enter when you've added the key (or Ctrl+C to exit)..."
    fi
fi

# ── Credential check ─────────────────────────────────────────────────────────

if [ ! -d "$HOME/.claude" ]; then
    log_warn "Claude credentials not found at ~/.claude"
    log_warn "You may need to authenticate claude-code first"
fi

# ── Build image if missing ───────────────────────────────────────────────────

if [[ "$(docker images -q $IMAGE_NAME 2> /dev/null)" == "" ]]; then
    log_info "Building $IMAGE_NAME Docker image..."
    (cd "$SCRIPT_DIR" && $COMPOSE_CMD build)
fi

# ── Assemble volume mounts ───────────────────────────────────────────────────

VOLUMES=(
    # Workspace at real host path
    -v "$WORKSPACE_DIR:$WORKSPACE_DIR"
    # Claude config (RW — sessions, memory, audit all shared with host)
    -v "$HOME/.claude:$HOME/.claude"
)

# Claude's SSH identity (read-only)
if [ -d "$CLAUDE_SSH_DIR" ]; then
    VOLUMES+=(-v "$CLAUDE_SSH_DIR:$HOME/.ssh:ro")
fi

# Claude's git config (read-only)
if [ -f "$CLAUDE_GITCONFIG" ]; then
    VOLUMES+=(-v "$CLAUDE_GITCONFIG:$HOME/.gitconfig:ro")
fi

# mempalace shared memory (read-write)
if [ -d "$HOME/.mempalace" ]; then
    VOLUMES+=(-v "$HOME/.mempalace:$HOME/.mempalace")
else
    mkdir -p "$HOME/.mempalace"
    VOLUMES+=(-v "$HOME/.mempalace:$HOME/.mempalace")
fi

# SSH agent forwarding
SSH_AGENT_ARGS=()
if [ -n "$SSH_AUTH_SOCK" ]; then
    SSH_AGENT_ARGS=(-v "$SSH_AUTH_SOCK:/tmp/ssh-agent.sock" -e "SSH_AUTH_SOCK=/tmp/ssh-agent.sock")
fi

# ── Print run info ───────────────────────────────────────────────────────────

log_info "Starting claude-code in Docker sandbox"
log_info "Docker setup: $SCRIPT_DIR"
log_info "Workspace: $WORKSPACE_DIR"
log_info "User: $(whoami) (UID $(id -u))"
log_info "Platform: $(uname -s)/$(uname -m)"
echo ""

# ── Run ──────────────────────────────────────────────────────────────────────

docker run -it --rm \
    --network bridge \
    "${VOLUMES[@]}" \
    "${SSH_AGENT_ARGS[@]}" \
    -w "$WORKSPACE_DIR" \
    -e "HOST_USER=$(whoami)" \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -e "HOST_HOME=$HOME" \
    -e "HOME=$HOME" \
    -e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}" \
    $IMAGE_NAME \
    $CONTAINER_CMD
