#!/bin/bash
set -e

# Helper script to run claude-code in Docker sandbox
# Can be run from anywhere and can mount any directory
# Works on both Linux and macOS (Intel + Apple Silicon)

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the directory where this script lives (where Dockerfile is)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default workspace is current directory, or use argument
WORKSPACE_DIR="${1:-$(pwd)}"
WORKSPACE_DIR="$(cd "$WORKSPACE_DIR" && pwd)" # Convert to absolute path

# Optional command override (default: claude)
CONTAINER_CMD="${2:-claude --dangerously-skip-permissions}"

# Image name
IMAGE_NAME="claude-code-sandbox"

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect docker compose command (v2 plugin or v1 standalone)
detect_compose() {
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        log_error "Neither 'docker compose' (v2) nor 'docker-compose' (v1) found"
        log_error "Install Docker Desktop (macOS) or docker-compose (Linux)"
        exit 1
    fi
}

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    case "$(uname -s)" in
        Darwin) log_error "Install Docker Desktop: https://www.docker.com/products/docker-desktop/" ;;
        *)      log_error "Install Docker: https://docs.docker.com/engine/install/" ;;
    esac
    exit 1
fi

detect_compose

# Check if Claude credentials exist
if [ ! -d "$HOME/.claude" ]; then
    log_warn "Claude credentials not found at ~/.claude"
    log_warn "You may need to authenticate claude-code first"
fi

# Check if workspace directory exists
if [ ! -d "$WORKSPACE_DIR" ]; then
    log_error "Workspace directory does not exist: $WORKSPACE_DIR"
    exit 1
fi

# Build the image if it doesn't exist
if [[ "$(docker images -q $IMAGE_NAME 2> /dev/null)" == "" ]]; then
    log_info "Building $IMAGE_NAME Docker image..."
    (cd "$SCRIPT_DIR" && $COMPOSE_CMD build)
fi

# Print run information
log_info "Starting claude-code in Docker container"
log_info "Docker setup: $SCRIPT_DIR"
log_info "Workspace: $WORKSPACE_DIR -> /workspace"
log_info "Credentials: ~/.claude (read-only)"
log_info "Platform: $(uname -s)/$(uname -m)"
echo ""

# Run claude-code with the specified workspace
docker run -it --rm \
    --network bridge \
    -v "$WORKSPACE_DIR:/workspace" \
    -v "$HOME/.claude:/home/claude/.claude-host:ro" \
    -v "$HOME/.claude/audit:/home/claude/.claude/audit" \
    -w /workspace \
    -e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}" \
    -e "HOST_PROJECT_NAME=$(basename "$WORKSPACE_DIR")" \
    $IMAGE_NAME \
    $CONTAINER_CMD
