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

# ── Test 12: Audit hook template bundled in image ───────────────────────────

echo "Test 12: Audit hook template bundled in image"
AUDIT_TPL=$(run cat /opt/claude-audit/audit-bash.sh 2>&1 | head -1)
if [ "$AUDIT_TPL" = "#!/bin/bash" ]; then
    pass "audit-bash.sh in /opt/claude-audit/"
else
    fail "audit template missing" "$AUDIT_TPL"
fi

# ── Test 13: Audit hook auto-installed to ~/.claude/hooks ───────────────────

echo "Test 13: Audit hook auto-installed on first run"
TMPDIR_HOOK=$(mktemp -d)
# Run with a fresh ~/.claude (empty tmpdir) so entrypoint installs the hook
HOOK_CHECK=$(docker run --rm \
    -e "HOST_USER=$(whoami)" \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -e "HOST_HOME=$HOME" \
    -e "HOME=$HOME" \
    -v "$TMPDIR_HOOK:$HOME/.claude" \
    $IMAGE_NAME \
    cat "$HOME/.claude/hooks/audit-bash.sh" 2>&1 | grep -c 'AUDIT_DIR')
if [ "$HOOK_CHECK" -ge 1 ]; then
    pass "audit-bash.sh auto-installed"
else
    fail "audit hook not installed" "$HOOK_CHECK"
fi
rm -rf "$TMPDIR_HOOK"

# ── Test 14: settings.json created with audit hook on fresh start ───────────

echo "Test 14: settings.json created with audit hook on fresh start"
TMPDIR_SETTINGS=$(mktemp -d)
docker run --rm \
    -e "HOST_USER=$(whoami)" \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -e "HOST_HOME=$HOME" \
    -e "HOME=$HOME" \
    -v "$TMPDIR_SETTINGS:$HOME/.claude" \
    $IMAGE_NAME \
    true 2>&1
SETTINGS_CHECK=$(cat "$TMPDIR_SETTINGS/settings.json" 2>/dev/null | jq -r '.hooks.PreToolUse[0].hooks[0].command // empty' 2>/dev/null)
if echo "$SETTINGS_CHECK" | grep -q "audit-bash.sh"; then
    pass "settings.json has audit hook"
else
    fail "settings.json missing audit hook" "$SETTINGS_CHECK"
fi
rm -rf "$TMPDIR_SETTINGS"

# ── Test 15: Audit hook idempotent — existing settings.json preserved ───────

echo "Test 15: Audit hook idempotent on existing settings.json"
TMPDIR_IDEM=$(mktemp -d)
mkdir -p "$TMPDIR_IDEM/hooks"
# Pre-populate settings.json with existing content + the audit hook
cat > "$TMPDIR_IDEM/settings.json" <<'JSONEOF'
{
  "model": "Opus",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /home/test/.claude/hooks/audit-bash.sh"
          }
        ]
      }
    ]
  }
}
JSONEOF
# Pre-create the hook file so it's not re-installed
cp /dev/null "$TMPDIR_IDEM/hooks/audit-bash.sh"
echo '#!/bin/bash' > "$TMPDIR_IDEM/hooks/audit-bash.sh"
echo 'AUDIT_DIR="existing"' >> "$TMPDIR_IDEM/hooks/audit-bash.sh"

docker run --rm \
    -e "HOST_USER=$(whoami)" \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -e "HOST_HOME=$HOME" \
    -e "HOME=$HOME" \
    -v "$TMPDIR_IDEM:$HOME/.claude" \
    $IMAGE_NAME \
    true 2>&1
# Model setting should be preserved, hook should not be duplicated
MODEL_CHECK=$(cat "$TMPDIR_IDEM/settings.json" 2>/dev/null | jq -r '.model // empty' 2>/dev/null)
HOOK_COUNT=$(cat "$TMPDIR_IDEM/settings.json" 2>/dev/null | jq '[.hooks.PreToolUse[].hooks[]? | select(.command | test("audit-bash"))] | length' 2>/dev/null)
if [ "$MODEL_CHECK" = "Opus" ] && [ "$HOOK_COUNT" = "1" ]; then
    pass "Existing settings preserved, no duplicate hook"
else
    fail "Idempotency" "model=$MODEL_CHECK, hook_count=$HOOK_COUNT"
fi
rm -rf "$TMPDIR_IDEM"

# ── Test 16: ~/.claude file ownership correct after entrypoint ──────────────

echo "Test 16: ~/.claude file ownership correct after entrypoint"
TMPDIR_PERM=$(mktemp -d)
# Create files with root ownership to simulate stale permissions
sudo chown root:root "$TMPDIR_PERM" 2>/dev/null || true
docker run --rm \
    -e "HOST_USER=$(whoami)" \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -e "HOST_HOME=$HOME" \
    -e "HOME=$HOME" \
    -v "$TMPDIR_PERM:$HOME/.claude" \
    $IMAGE_NAME \
    stat -c '%u' "$HOME/.claude" 2>&1
DIR_OWNER=$(stat -c '%u' "$TMPDIR_PERM" 2>/dev/null)
SETTINGS_OWNER=$(stat -c '%u' "$TMPDIR_PERM/settings.json" 2>/dev/null)
if [ "$DIR_OWNER" = "$(id -u)" ] && [ "$SETTINGS_OWNER" = "$(id -u)" ]; then
    pass "Ownership fixed to UID=$(id -u)"
else
    fail "Ownership" "dir=$DIR_OWNER, settings=$SETTINGS_OWNER"
fi
rm -rf "$TMPDIR_PERM"

# ── Test 17: .gitignore excludes claude-audit.log ───────────────────────────

echo "Test 17: .gitignore excludes claude-audit.log"
GITIGNORE_CHECK=$(git -C "$SCRIPT_DIR" check-ignore claude-audit.log 2>/dev/null)
if [ "$GITIGNORE_CHECK" = "claude-audit.log" ]; then
    pass "claude-audit.log is gitignored"
else
    fail ".gitignore" "claude-audit.log not ignored"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
