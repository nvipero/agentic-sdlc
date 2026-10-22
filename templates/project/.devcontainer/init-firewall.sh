#!/bin/bash
# Outbound allowlist firewall for the agent container. Fails closed:
# the DROP policy is set before anything else, and any failure leaves only
# loopback open. Derived from anthropics/claude-code/.devcontainer/init-firewall.sh.
set -euo pipefail
IFS=$'\n\t'

# Only real root can override the allowlist (sudo resets the environment).
# Used by the exit check to prove the network stays closed on failure.
ALLOWLIST="${FACTORY_ALLOWLIST_FILE:-/etc/factory/allowlist.txt}"
MARKER=/run/firewall-ok
SET=allowed

log() { echo "init-firewall: $*" >&2; }

close_network() {
  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT DROP
  iptables -F
  iptables -X
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A OUTPUT -o lo -j ACCEPT
  ipset destroy "$SET" 2>/dev/null || true
}

on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    close_network || true
    log "FAILED (exit $rc): network closed except loopback"
  fi
  exit "$rc"
}
trap on_exit EXIT

rm -f "$MARKER"

# 1. Close everything first. The nat table is left alone so Docker's DNS keeps working.
close_network

# IPv6: drop everything except loopback. If the container has a global IPv6 address and the
# policy cannot be set, fail.
if { ip6tables -P INPUT DROP && ip6tables -P FORWARD DROP && ip6tables -P OUTPUT DROP; } 2>/dev/null; then
  ip6tables -F
  ip6tables -A INPUT -i lo -j ACCEPT
  ip6tables -A OUTPUT -o lo -j ACCEPT
else
  if ip -6 addr show scope global 2>/dev/null | grep -q inet6; then
    log "cannot set IPv6 policy on a container with global IPv6"
    exit 1
  fi
fi

# 2. Base rules: established traffic, and DNS only to the configured resolvers.
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
nameservers="$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | grep -E '^[0-9.]+$' || true)"
[ -n "$nameservers" ] || { log "no IPv4 nameserver in /etc/resolv.conf"; exit 1; }
for ns in $nameservers; do
  iptables -A OUTPUT -p udp -d "$ns" --dport 53 -j ACCEPT
  iptables -A OUTPUT -p tcp -d "$ns" --dport 53 -j ACCEPT
done

ipset create "$SET" hash:net
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set "$SET" dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

resolve() {
  local ips
  ips="$(dig +short +time=5 +tries=2 A "$1" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)"
  [ -n "$ips" ] || { log "cannot resolve $1"; return 1; }
  echo "$ips"
}

add_ips() {
  local ip
  for ip in $1; do ipset add -exist "$SET" "$ip"; done
}

# 3. Bootstrap GitHub: allow every A record of api.github.com, and pin curl to
# exactly those addresses so a DNS answer change between steps cannot break it.
gh_ips="$(resolve api.github.com)"
add_ips "$gh_ips"
gh_resolve="api.github.com:443:$(echo "$gh_ips" | paste -sd, -)"

# The only unauthenticated GitHub API call (60 per hour per IP); the token is
# not available here, because the firewall starts before any exec.
meta="$(curl -fsS --max-time 20 --resolve "$gh_resolve" https://api.github.com/meta)" \
  || { log "cannot fetch https://api.github.com/meta (if GitHub answered 403, the unauthenticated API limit of 60 requests per hour for this IP is used up; wait and start again)"; exit 1; }
echo "$meta" | jq -e '.web and .api and .git' >/dev/null || { log "unexpected GitHub meta document"; exit 1; }
gh_ranges="$(echo "$meta" | jq -r '(.web + .api + .git)[]' | grep -v ':' | aggregate -q)"
[ -n "$gh_ranges" ] || { log "no GitHub IPv4 ranges"; exit 1; }
add_ips "$gh_ranges"

# 4. Allowlisted domains.
[ -r "$ALLOWLIST" ] || { log "cannot read $ALLOWLIST"; exit 1; }
while IFS= read -r line; do
  domain="${line%%#*}"
  domain="$(echo "$domain" | tr -d '[:space:]')"
  [ -n "$domain" ] || continue
  ips="$(resolve "$domain")"   # an assignment, so set -e catches a failure
  add_ips "$ips"
done < "$ALLOWLIST"

# 5. Verify.
if curl -s --max-time 5 -o /dev/null https://example.com; then
  log "example.com is reachable"; exit 1
fi
if curl -s --max-time 5 -o /dev/null https://1.1.1.1; then
  log "1.1.1.1 is reachable"; exit 1
fi
# A web URL, not the API, so this check does not count against the API limit.
curl -fsS --max-time 10 -o /dev/null https://github.com/robots.txt \
  || { log "github.com is not reachable"; exit 1; }

touch "$MARKER"
log "OK: $(ipset list "$SET" | grep -c '^[0-9]') allowed networks"
