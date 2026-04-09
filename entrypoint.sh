#!/bin/bash
# Entrypoint: copy host credentials into a writable location so the non-root
# claude user can both read and write config/session state without mutating
# the host bind-mount.

HOST_CLAUDE_DIR="/home/claude/.claude-host"
CLAUDE_DIR="/home/claude/.claude"

if [ -d "$HOST_CLAUDE_DIR" ]; then
    # Host files may be owned by a different UID with 600 perms, so use sudo to copy
    sudo cp -a "$HOST_CLAUDE_DIR/." "$CLAUDE_DIR/" 2>/dev/null || true
    sudo chown -R claude:claude "$CLAUDE_DIR"

    # Rewrite host home paths in settings so hooks resolve inside the container
    # e.g. /home/michel/.claude/hooks/... -> /home/claude/.claude/hooks/...
    if [ -f "$CLAUDE_DIR/settings.json" ]; then
        sed -i "s|/home/[^/]*/.claude/|/home/claude/.claude/|g" "$CLAUDE_DIR/settings.json"
    fi
fi

# Expose the real host project name so hooks (e.g. audit) can use it
# instead of the generic "workspace" container path.
if [ -n "$HOST_PROJECT_NAME" ]; then
    export CLAUDE_PROJECT_NAME="$HOST_PROJECT_NAME"
fi

exec "$@"
