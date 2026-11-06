#!/bin/bash
# validate-devcontainer.sh - checks that .devcontainer/devcontainer.json has runArgs
# with NET_ADMIN and NET_RAW capabilities, and that postStartCommand runs init-firewall.sh.
# Without NET_ADMIN/NET_RAW, iptables fails to run in postStartCommand.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVCONTAINER_JSON="$PROJECT_ROOT/.devcontainer/devcontainer.json"

if [ ! -f "$DEVCONTAINER_JSON" ]; then
  echo "FAIL: $DEVCONTAINER_JSON does not exist"
  exit 1
fi

DEVCONTAINER_JSON="$DEVCONTAINER_JSON" python3 <<'PY'
import json, os, sys
with open(os.environ['DEVCONTAINER_JSON']) as f:
    d = json.load(f)
run_args = d.get('runArgs', [])
required_caps = ['--cap-add=NET_ADMIN', '--cap-add=NET_RAW']
missing = [c for c in required_caps if c not in run_args]
if missing:
    print(f"FAIL: devcontainer.json runArgs is missing: {','.join(missing)}")
    print("Without NET_ADMIN/NET_RAW iptables cannot run; firewall is broken.")
    sys.exit(1)
print("OK: devcontainer.json runArgs has NET_ADMIN, NET_RAW")
psc = d.get('postStartCommand', '')
if 'init-firewall.sh' not in psc:
    print(f"FAIL: postStartCommand does not run init-firewall.sh: {psc!r}")
    sys.exit(1)
print("OK: postStartCommand runs init-firewall.sh")
PY
