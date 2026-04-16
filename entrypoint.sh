#!/bin/bash
set -e

# Runtime identity: create a user matching the host user, then drop privileges.
# The image is generic — no user is baked in. This runs as root for ~50ms,
# creates the user, then permanently drops to that user via gosu.

HOST_USER="${HOST_USER:-claude}"
HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"
HOST_HOME="${HOST_HOME:-/home/$HOST_USER}"

# Validate UID is numeric
if ! echo "$HOST_UID" | grep -qE '^[0-9]+$'; then
    echo "[ERROR] HOST_UID must be numeric, got: $HOST_UID" >&2
    exit 1
fi

# Remove node user if its UID conflicts with the host user's UID
if id node &>/dev/null; then
    existing_uid=$(id -u node)
    if [ "$existing_uid" = "$HOST_UID" ]; then
        userdel -f node 2>/dev/null || true
    fi
fi

# Create group and user matching host identity
groupadd -g "$HOST_GID" -o "$HOST_USER" 2>/dev/null || true
useradd -m -d "$HOST_HOME" -u "$HOST_UID" -g "$HOST_GID" -s /bin/bash "$HOST_USER" 2>/dev/null || true

# Passwordless sudo (safe inside container — container is the security boundary)
echo "$HOST_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/"$HOST_USER"
chmod 0440 /etc/sudoers.d/"$HOST_USER"

# Ensure home directory exists with correct ownership
mkdir -p "$HOST_HOME"
chown "$HOST_UID:$HOST_GID" "$HOST_HOME"

# ── Ensure ~/.claude files are accessible ────────────────────────────────
# The bind mount preserves host UIDs, but files created by previous container
# runs (or by root during setup below) need correct ownership.
CLAUDE_DIR="$HOST_HOME/.claude"
if [ -d "$CLAUDE_DIR" ]; then
    chown "$HOST_UID:$HOST_GID" "$CLAUDE_DIR"
    for f in "$CLAUDE_DIR/.credentials.json" \
             "$CLAUDE_DIR/.claude.json" \
             "$CLAUDE_DIR/settings.json" \
             "$CLAUDE_DIR/settings.local.json"; do
        [ -f "$f" ] && chown "$HOST_UID:$HOST_GID" "$f"
    done
    [ -d "$CLAUDE_DIR/hooks" ] && chown -R "$HOST_UID:$HOST_GID" "$CLAUDE_DIR/hooks"
fi

# ── Audit hook auto-setup ────────────────────────────────────────────────
# Install the audit-bash.sh hook and register it in settings.json.
# Idempotent — skips if already present.
HOOKS_DIR="$CLAUDE_DIR/hooks"
HOOK_DST="$HOOKS_DIR/audit-bash.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_CMD="bash $HOOK_DST"

if [ ! -f "$HOOK_DST" ] && [ -f /opt/claude-audit/audit-bash.sh ]; then
    mkdir -p "$HOOKS_DIR"
    # Substitute __AUDIT_DIR__ with $HOME/.claude/audit (shell-expanded at hook runtime)
    sed 's|__AUDIT_DIR__|$HOME/.claude/audit|g' /opt/claude-audit/audit-bash.sh > "$HOOK_DST"
    chmod 755 "$HOOK_DST"
    chown -R "$HOST_UID:$HOST_GID" "$HOOKS_DIR"
fi

if [ -f "$HOOK_DST" ]; then
    if [ ! -f "$SETTINGS" ]; then
        # Create minimal settings.json with the audit hook
        mkdir -p "$CLAUDE_DIR"
        cat > "$SETTINGS" <<SETTINGSEOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_CMD"
          }
        ]
      }
    ]
  }
}
SETTINGSEOF
        chmod 600 "$SETTINGS"
        chown "$HOST_UID:$HOST_GID" "$SETTINGS"
    elif ! grep -q "audit-bash.sh" "$SETTINGS" 2>/dev/null; then
        # Merge the audit hook into existing settings.json via jq
        jq --arg cmd "$HOOK_CMD" '
          .hooks //= {} |
          .hooks.PreToolUse //= [] |
          if (.hooks.PreToolUse | map(select(.matcher == "Bash")) | length) == 0
          then .hooks.PreToolUse = [{"matcher": "Bash", "hooks": [{"type": "command", "command": $cmd}]}] + .hooks.PreToolUse
          else .hooks.PreToolUse = [.hooks.PreToolUse[] |
            if .matcher == "Bash"
            then .hooks = [{"type": "command", "command": $cmd}] + .hooks
            else . end]
          end
        ' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
        chmod 600 "$SETTINGS"
        chown "$HOST_UID:$HOST_GID" "$SETTINGS"
    fi
fi

# Drop privileges permanently and exec the command
exec gosu "$HOST_USER" "$@"
