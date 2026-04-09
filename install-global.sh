#!/bin/bash
set -e

# Install script to make claude-sandbox available globally
# Works on both Linux and macOS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default install dir: ~/.local/bin (works on both Linux and macOS)
INSTALL_DIR="${1:-$HOME/.local/bin}"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Create install directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Create a wrapper script that points to the actual script
cat > "$INSTALL_DIR/claude-sandbox" << EOF
#!/bin/bash
# Claude Code Docker Sandbox - Global wrapper
# This script runs claude-code in a Docker sandbox

CLAUDE_DOCKER_DIR="$SCRIPT_DIR"

# Forward to the actual script
exec "\$CLAUDE_DOCKER_DIR/run-claude.sh" "\$@"
EOF

chmod +x "$INSTALL_DIR/claude-sandbox"

log_info "Installed claude-sandbox to $INSTALL_DIR/claude-sandbox"
echo ""
log_info "Usage:"
echo "  claude-sandbox              # Use current directory as workspace"
echo "  claude-sandbox /path/to/dir # Use specified directory as workspace"
echo ""

# Check if install dir is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    log_warn "$INSTALL_DIR is not in your PATH"
    # Detect shell config file
    case "$(uname -s)" in
        Darwin)
            SHELL_RC="~/.zshrc"
            ;;
        *)
            if [ -n "$ZSH_VERSION" ] || [ "$(basename "$SHELL")" = "zsh" ]; then
                SHELL_RC="~/.zshrc"
            else
                SHELL_RC="~/.bashrc"
            fi
            ;;
    esac
    log_warn "Add this to your $SHELL_RC:"
    echo ""
    echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
    echo ""
fi

log_info "Installation complete!"
