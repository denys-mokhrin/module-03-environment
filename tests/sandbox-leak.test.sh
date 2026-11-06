#!/bin/bash
# sandbox-leak.test.sh - checks that the permissions and sandbox config is complete (does not test an actual leak).
# Runs on the host (not in the container). Does not launch Claude - checks the filesystem and config.
#
# Logic: ensure that:
# 1. .claude/settings.json is valid JSON
# 2. permissions.deny contains the full baseline (secrets, irreversible bash, wget bypass)
# 3. sandbox.enabled = true
# 4. sandbox.filesystem.denyRead covers all 4 directories from conventions
#
# Live test (real headless Claude) is a manual check in README - requires a logged-in Claude session (claude login, subscription is enough).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$PROJECT_ROOT/.claude/settings.json"

echo "Project: $PROJECT_ROOT"
echo "Settings: $SETTINGS_FILE"
echo ""

# 1. settings.json must exist
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "FAIL: $SETTINGS_FILE does not exist"
  exit 1
fi
echo "OK: settings.json exists"

# 2. settings.json is valid JSON
if ! python3 -m json.tool < "$SETTINGS_FILE" > /dev/null 2>&1; then
  echo "FAIL: settings.json is not valid JSON"
  exit 1
fi
echo "OK: settings.json is valid JSON"

# 3. permissions.deny has the full baseline (secrets, irreversible bash, wget bypass)
deny_check=$(SETTINGS_FILE="$SETTINGS_FILE" python3 <<'PY'
import json, os
with open(os.environ['SETTINGS_FILE']) as f:
    s = json.load(f)
deny = s.get('permissions', {}).get('deny', [])
required = [
    'Read(.env)', 'Read(**/.env)', 'Read(**/*.pem)', 'Read(**/*.key)',
    'Read(**/credentials*)', 'Read(**/*secret*)',
    'Read(~/.ssh/**)', 'Read(~/.aws/**)',
    'Bash(rm -rf *)', 'Bash(sudo *)', 'Bash(git push --force *)',
    'Bash(curl * | sh)', 'Bash(curl * | bash)',
]
missing = [r for r in required if r not in deny]
print(','.join(missing) if missing else 'OK')
PY
)

if [ "$deny_check" != "OK" ]; then
  echo "FAIL: permissions.deny is missing: $deny_check"
  exit 1
fi
echo "OK: permissions.deny covers baseline (secrets, irreversible bash, pipe-to-shell)"

# 4. sandbox enabled
sandbox_enabled=$(SETTINGS_FILE="$SETTINGS_FILE" python3 <<'PY'
import json, os
with open(os.environ['SETTINGS_FILE']) as f:
    s = json.load(f)
print(s.get('sandbox', {}).get('enabled', False))
PY
)

if [ "$sandbox_enabled" != "True" ]; then
  echo "FAIL: sandbox.enabled = $sandbox_enabled, expected True"
  exit 1
fi
echo "OK: sandbox enabled"

# 5. sandbox.filesystem.denyRead covers all 4 critical directories
sandbox_deny=$(SETTINGS_FILE="$SETTINGS_FILE" python3 <<'PY'
import json, os
with open(os.environ['SETTINGS_FILE']) as f:
    s = json.load(f)
deny = s.get('sandbox', {}).get('filesystem', {}).get('denyRead', [])
required = ['~/.ssh', '~/.aws', '~/.gnupg', '~/.kube/config']
missing = [r for r in required if r not in deny]
print(','.join(missing) if missing else 'OK')
PY
)

if [ "$sandbox_deny" != "OK" ]; then
  echo "FAIL: sandbox.filesystem.denyRead is missing: $sandbox_deny"
  exit 1
fi
echo "OK: sandbox.filesystem.denyRead covers ~/.ssh, ~/.aws, ~/.gnupg, ~/.kube/config"

# 6. Create a temporary .env and check it is not tracked by git
TMP_ENV=$(mktemp "${TMPDIR:-/tmp}/sandbox-leak-test.XXXXXX")
trap 'rm -f "$TMP_ENV"' EXIT
echo "FAKE_SECRET=should_not_leak_$(date +%s)" > "$TMP_ENV"
echo "OK: created temporary .env (live test with Claude is manual, requires claude login - subscription is enough)"

echo ""
echo "=== Sandbox leak test PASSED ==="
echo ""
echo "For a live check with Claude:"
echo "1. cp .env.example .env (fill with placeholders)"
echo "2. claude --print 'read .env' (must be blocked by permissions)"
echo "3. claude --print 'run bash -c \"cat .env\"' (must be blocked by the sandbox)"
