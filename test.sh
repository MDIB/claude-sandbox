#!/bin/bash
set -e

# Integration tests for claude-code-sandbox.
# Builds the image and verifies runtime identity, mounts, and tools.

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
IMAGE_NAME="claude-code-sandbox"
PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1: $2"; FAIL=$((FAIL + 1)); }

run() {
    docker run --rm \
        -e "HOST_USER=$(whoami)" \
        -e "HOST_UID=$(id -u)" \
        -e "HOST_GID=$(id -g)" \
        -e "HOST_HOME=$HOME" \
        -e "HOME=$HOME" \
        $IMAGE_NAME \
        "$@"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== claude-code-sandbox integration tests ==="
echo ""

# ── Build ────────────────────────────────────────────────────────────────────

echo "Building image..."
(cd "$SCRIPT_DIR" && docker build -q --network=host -t $IMAGE_NAME . > /dev/null)
echo ""

# ── Test 1: UID matches host ────────────────────────────────────────────────

echo "Test 1: Container UID matches host"
CONTAINER_UID=$(run id -u)
if [ "$CONTAINER_UID" = "$(id -u)" ]; then
    pass "UID=$(id -u)"
else
    fail "Expected UID $(id -u), got $CONTAINER_UID"
fi

# ── Test 2: Username matches host ────────────────────────────────────────────

echo "Test 2: Container username matches host"
CONTAINER_USER=$(run whoami)
if [ "$CONTAINER_USER" = "$(whoami)" ]; then
    pass "user=$(whoami)"
else
    fail "Expected $(whoami), got $CONTAINER_USER"
fi

# ── Test 3: Not running as root ──────────────────────────────────────────────

echo "Test 3: Not running as root"
CONTAINER_UID_CHECK=$(run id -u)
if [ "$CONTAINER_UID_CHECK" != "0" ]; then
    pass "UID=$CONTAINER_UID_CHECK (not root)"
else
    fail "Running as root (UID 0)"
fi

# ── Test 4: Sudo works ──────────────────────────────────────────────────────

echo "Test 4: Passwordless sudo works"
SUDO_CHECK=$(run sudo whoami 2>&1)
if [ "$SUDO_CHECK" = "root" ]; then
    pass "sudo whoami = root"
else
    fail "sudo whoami" "$SUDO_CHECK"
fi

# ── Test 5: HOME is set to host home ────────────────────────────────────────

echo "Test 5: HOME matches host"
CONTAINER_HOME=$(run sh -c 'echo $HOME')
if [ "$CONTAINER_HOME" = "$HOME" ]; then
    pass "HOME=$HOME"
else
    fail "Expected HOME=$HOME, got $CONTAINER_HOME"
fi

# ── Test 6: Workspace mount at real host path ────────────────────────────────

echo "Test 6: Workspace mounted at real host path"
TEST_DIR="$SCRIPT_DIR"
CONTAINER_LS=$(docker run --rm \
    -e "HOST_USER=$(whoami)" \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -e "HOST_HOME=$HOME" \
    -e "HOME=$HOME" \
    -v "$TEST_DIR:$TEST_DIR" \
    -w "$TEST_DIR" \
    $IMAGE_NAME \
    ls Dockerfile 2>&1)
if [ "$CONTAINER_LS" = "Dockerfile" ]; then
    pass "Workspace at $TEST_DIR"
else
    fail "Workspace mount" "$CONTAINER_LS"
fi

# ── Test 7: ~/.claude writable ───────────────────────────────────────────────

echo "Test 7: ~/.claude is writable"
TMPDIR_CLAUDE=$(mktemp -d "$HOME/.claude/test-XXXXXX")
WRITE_CHECK=$(docker run --rm \
    -e "HOST_USER=$(whoami)" \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -e "HOST_HOME=$HOME" \
    -e "HOME=$HOME" \
    -v "$HOME/.claude:$HOME/.claude" \
    $IMAGE_NAME \
    sh -c "echo test > $TMPDIR_CLAUDE/write-test && cat $TMPDIR_CLAUDE/write-test" 2>&1)
if [ "$WRITE_CHECK" = "test" ]; then
    pass "~/.claude writable"
else
    fail "~/.claude write" "$WRITE_CHECK"
fi
rm -rf "$TMPDIR_CLAUDE"

# ── Test 8: File ownership matches host user ─────────────────────────────────

echo "Test 8: Files created by container owned by host user"
TMPDIR_OWN=$(mktemp -d "$HOME/.claude/test-XXXXXX")
docker run --rm \
    -e "HOST_USER=$(whoami)" \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -e "HOST_HOME=$HOME" \
    -e "HOME=$HOME" \
    -v "$HOME/.claude:$HOME/.claude" \
    $IMAGE_NAME \
    touch "$TMPDIR_OWN/ownership-test" 2>&1
FILE_OWNER=$(stat -c '%u' "$TMPDIR_OWN/ownership-test" 2>/dev/null || stat -f '%u' "$TMPDIR_OWN/ownership-test" 2>/dev/null)
if [ "$FILE_OWNER" = "$(id -u)" ]; then
    pass "Owner UID=$(id -u)"
else
    fail "Expected owner $(id -u), got $FILE_OWNER"
fi
rm -rf "$TMPDIR_OWN"

# ── Test 9: Essential tools available ────────────────────────────────────────

echo "Test 9: Essential tools available"
TOOLS_CHECK=$(run sh -c 'which jq && which flock && which git && which claude && which python3 && echo OK' 2>&1 | tail -1)
if [ "$TOOLS_CHECK" = "OK" ]; then
    pass "jq, flock, git, claude, python3"
else
    fail "Missing tools" "$TOOLS_CHECK"
fi

# ── Test 10: mempalace importable ────────────────────────────────────────────

echo "Test 10: mempalace importable"
MP_CHECK=$(run python3 -c "import mempalace; print('OK')" 2>&1)
if [ "$MP_CHECK" = "OK" ]; then
    pass "mempalace"
else
    fail "mempalace import" "$MP_CHECK"
fi

# ── Test 11: Invalid HOST_UID rejected ───────────────────────────────────────

echo "Test 11: Invalid HOST_UID rejected gracefully"
INVALID_CHECK=$(docker run --rm \
    -e "HOST_USER=test" \
    -e "HOST_UID=abc" \
    -e "HOST_GID=1000" \
    -e "HOST_HOME=/home/test" \
    $IMAGE_NAME \
    echo "should not reach here" 2>&1 || true)
if echo "$INVALID_CHECK" | grep -q "ERROR"; then
    pass "Invalid UID rejected"
else
    fail "Invalid UID not caught" "$INVALID_CHECK"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
