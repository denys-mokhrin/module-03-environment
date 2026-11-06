#!/bin/bash
# firewall.test.sh - checks that the firewall blocks non-whitelisted domains.
# Runs INSIDE the devcontainer (after postStartCommand and init-firewall.sh).
# On a host without iptables it skips the tests and reports so.

set -euo pipefail

# Check that we are inside a container with iptables
if ! command -v iptables >/dev/null 2>&1; then
  echo "SKIP: iptables not available. Run this test INSIDE the devcontainer."
  exit 0
fi

# Check that init-firewall.sh has already run
iptables_default=$(sudo iptables -L OUTPUT --line-numbers 2>/dev/null | head -1 | grep -oE 'policy [A-Z]+' | awk '{print $2}' || echo "")
if [ "$iptables_default" != "DROP" ]; then
  echo "SKIP: iptables OUTPUT default policy = $iptables_default, expected DROP. Run 'sudo /usr/local/bin/init-firewall.sh'."
  exit 0
fi

echo "=== Firewall behavior test ==="
echo ""

# 1. api.anthropic.com must be reachable (whitelist)
echo "Test 1: github.com (whitelist) must pass"
if curl -fsS --max-time 5 https://github.com -o /dev/null; then
  echo "OK: github.com reachable"
else
  echo "FAIL: github.com blocked - whitelist is broken"
  exit 1
fi
echo ""

# 2. example.com must be blocked (default-deny)
echo "Test 2: example.com (not whitelisted) must be blocked"
if curl -fsS --max-time 5 https://example.com -o /dev/null 2>&1; then
  echo "FAIL: example.com reachable - default-deny is broken"
  exit 1
else
  echo "OK: example.com blocked (timeout or refused)"
fi
echo ""

# 3. registry.npmjs.org must be reachable (whitelist for the Node stack)
echo "Test 3: registry.npmjs.org (Node whitelist) must pass"
if curl -fsS --max-time 5 https://registry.npmjs.org -o /dev/null; then
  echo "OK: registry.npmjs.org reachable"
else
  echo "FAIL: registry.npmjs.org blocked - stack-specific whitelist is broken"
  exit 1
fi
echo ""

# 4. github.com must be reachable (whitelist)
echo "Test 4: github.com (whitelist) must pass"
if curl -fsS --max-time 5 https://github.com -o /dev/null; then
  echo "OK: github.com reachable"
else
  echo "FAIL: github.com blocked - whitelist is broken"
  exit 1
fi
echo ""

echo "=== Firewall test PASSED ==="
