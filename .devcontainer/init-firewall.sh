#!/bin/bash
# init-firewall.sh - default-deny outbound + minimal whitelist for the Claude Code container.
# Runs from the devcontainer postStartCommand or the docker compose entrypoint.
# Requires NET_ADMIN and NET_RAW capabilities (cap_add in Docker Compose or runArgs in devcontainer).
#
# Protections:
# - IPv4 (iptables) and IPv6 (ip6tables) both default-deny on OUTPUT
# - DNS restricted to the nameserver from /etc/resolv.conf (prevents DNS rebinding via an arbitrary resolver)
# - CIDR blocks from api.github.com/meta are regex-validated before adding (prevents 0.0.0.0/0 injection)
# - Self-validation at the end checks that the whitelist works and default-deny is intact

set -euo pipefail

# 1. Flush previous rules, set default policy for IPv4 and IPv6
iptables -F OUTPUT
iptables -F INPUT
iptables -P OUTPUT DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP

ip6tables -F OUTPUT
ip6tables -F INPUT
ip6tables -P OUTPUT DROP
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP

# 2. Loopback is always allowed
iptables  -A INPUT  -i lo -j ACCEPT
iptables  -A OUTPUT -o lo -j ACCEPT
ip6tables -A INPUT  -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT

# 3. Established connections - ACCEPT
iptables  -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables  -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 4. DNS restricted to the nameserver from /etc/resolv.conf (not every server on 53/udp).
#    This prevents bypassing the whitelist with an arbitrary DNS resolver.
DNS_SERVERS=$(awk '/^nameserver / {print $2}' /etc/resolv.conf | sort -u)
if [ -z "$DNS_SERVERS" ]; then
  echo "WARN: /etc/resolv.conf has no nameserver - using 127.0.0.11 (Docker embedded DNS)"
  DNS_SERVERS="127.0.0.11"
fi
for dns in $DNS_SERVERS; do
  if [[ "$dns" == *:* ]]; then
    ip6tables -A OUTPUT -p udp -d "$dns" --dport 53 -j ACCEPT
    ip6tables -A OUTPUT -p tcp -d "$dns" --dport 53 -j ACCEPT
  else
    iptables  -A OUTPUT -p udp -d "$dns" --dport 53 -j ACCEPT
    iptables  -A OUTPUT -p tcp -d "$dns" --dport 53 -j ACCEPT
  fi
done

# 5. Whitelist via ipset (dynamic resolution of domains to IPs)
ipset destroy claude-allowed   2>/dev/null || true
ipset destroy claude-allowed-6 2>/dev/null || true
ipset create  claude-allowed   hash:net family inet  hashsize 1024 maxelem 65536
ipset create  claude-allowed-6 hash:net family inet6 hashsize 1024 maxelem 65536

ALLOWED_DOMAINS=(
  "api.anthropic.com"
  "statsig.anthropic.com"
  "sentry.io"
  "registry.npmjs.org"
  "api.github.com"
  "github.com"
  "objects.githubusercontent.com"
  "codeload.github.com"
  "claude.ai"
  "platform.claude.com"
)

for domain in "${ALLOWED_DOMAINS[@]}"; do
  # IPv4 (A records)
  ips4=$(getent ahostsv4 "$domain" 2>/dev/null | awk '/STREAM/ {print $1}' | sort -u || true)
  for ip in $ips4; do
    ipset add claude-allowed "$ip" 2>/dev/null || true
  done
  # IPv6 (AAAA records) - if any
  ips6=$(getent ahostsv6 "$domain" 2>/dev/null | awk '/STREAM/ {print $1}' | sort -u || true)
  for ip in $ips6; do
    ipset add claude-allowed-6 "$ip" 2>/dev/null || true
  done
  if [ -z "$ips4" ] && [ -z "$ips6" ]; then
    echo "WARN: could not resolve $domain - skipping"
  fi
done

# 6. GitHub CIDR ranges from api.github.com/meta - temporarily open api.github.com,
#    fetch meta, regex-validate each CIDR (prevents 0.0.0.0/0 injection).
gh_ip=$(getent ahostsv4 api.github.com | awk '/STREAM/ {print $1; exit}' || true)
if [ -n "$gh_ip" ]; then
  iptables -I OUTPUT 1 -d "$gh_ip" -p tcp --dport 443 -j ACCEPT
  github_cidrs=$(curl -fsS --max-time 10 https://api.github.com/meta \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('\n'.join(c for c in d.get('git',[]) if ':' not in c))" \
    || true)
  cidr_re='^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$'
  for cidr in $github_cidrs; do
    # Reject CIDRs wider than /8 (prevents 0.0.0.0/0 and similar)
    if [[ "$cidr" =~ $cidr_re ]]; then
      prefix="${cidr##*/}"
      if [ "$prefix" -lt 8 ]; then
        echo "WARN: rejecting CIDR $cidr (prefix /$prefix too wide)"
        continue
      fi
      ipset add claude-allowed "$cidr" 2>/dev/null || true
    else
      echo "WARN: rejecting invalid CIDR $cidr"
    fi
  done
fi

# 7. ACCEPT all whitelisted IPs/CIDRs on ports 80/443 (IPv4 and IPv6)
iptables  -A OUTPUT -p tcp -m set --match-set claude-allowed   dst --dport 443 -j ACCEPT
iptables  -A OUTPUT -p tcp -m set --match-set claude-allowed   dst --dport 80  -j ACCEPT
ip6tables -A OUTPUT -p tcp -m set --match-set claude-allowed-6 dst --dport 443 -j ACCEPT
ip6tables -A OUTPUT -p tcp -m set --match-set claude-allowed-6 dst --dport 80  -j ACCEPT

# 8. Self-validation
echo "=== Firewall self-validation ==="

if curl -fsS --max-time 5 https://github.com -o /dev/null; then
  echo "OK: whitelist allows permitted domains (github.com)"
else
  echo "FAIL: allowed domain unreachable - whitelist is broken"
  exit 1
fi

# example.com must fail. Check that neither IPv4 nor IPv6 gets through.
if curl -fsS --max-time 5 https://example.com -o /dev/null 2>&1; then
  echo "FAIL: example.com should be blocked - default-deny is broken"
  exit 1
else
  echo "OK: example.com blocked (as expected)"
fi

# IPv6 sanity check - if ipv6.google.com resolves, the connect attempt must fail
if getent ahostsv6 ipv6.google.com >/dev/null 2>&1; then
  if curl -6 -fsS --max-time 5 https://ipv6.google.com -o /dev/null 2>&1; then
    echo "FAIL: ipv6.google.com reachable over IPv6 - ip6tables default-deny is broken"
    exit 1
  else
    echo "OK: IPv6 default-deny works"
  fi
fi

echo "=== Firewall ready ==="
