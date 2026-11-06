#!/bin/bash
# validate-whitelist.sh - checks that sandbox and firewall whitelists are consistent.
# sandbox.network.allowedDomains in .claude/settings.json must exactly match
# ALLOWED_DOMAINS in .devcontainer/init-firewall.sh.
#
# Why: if a domain is in the sandbox but not the firewall, Claude allows the request
# and iptables blocks it (silent fail). If it is in the firewall but not the sandbox,
# Claude blocks it before the firewall ever sees the packet.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_JSON="$PROJECT_ROOT/.claude/settings.json"
INIT_FW="$PROJECT_ROOT/.devcontainer/init-firewall.sh"

if [ ! -f "$SETTINGS_JSON" ] || [ ! -f "$INIT_FW" ]; then
  echo "FAIL: settings.json or init-firewall.sh not found"
  exit 1
fi

SETTINGS_JSON="$SETTINGS_JSON" INIT_FW="$INIT_FW" python3 <<'PY'
import json, os, re, sys
with open(os.environ['SETTINGS_JSON']) as f:
    s = json.load(f)
sandbox_domains = set(s.get('sandbox', {}).get('network', {}).get('allowedDomains', []))
with open(os.environ['INIT_FW']) as f:
    fw = f.read()
m = re.search(r'ALLOWED_DOMAINS=\(([^)]+)\)', fw, re.DOTALL)
if not m:
    print("FAIL: ALLOWED_DOMAINS array not found in init-firewall.sh")
    sys.exit(1)
fw_domains = set(re.findall(r'"([^"]+)"', m.group(1)))
only_sandbox = sandbox_domains - fw_domains
only_firewall = fw_domains - sandbox_domains
if only_sandbox or only_firewall:
    if only_sandbox:
        print(f"FAIL: only in sandbox.allowedDomains, not in firewall: {sorted(only_sandbox)}")
    if only_firewall:
        print(f"FAIL: only in firewall, not in sandbox.allowedDomains: {sorted(only_firewall)}")
    print("Whitelists must match - otherwise Claude allows a request that the firewall blocks (or vice versa).")
    sys.exit(1)
print(f"OK: sandbox and firewall whitelists match ({len(sandbox_domains)} domains)")
PY
