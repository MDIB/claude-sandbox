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

# Drop privileges permanently and exec the command
exec gosu "$HOST_USER" "$@"
