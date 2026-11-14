#!/bin/sh
# Versão Mac (OrbStack) do examples/tailscale-sidecar/firewall/cashbook-mcp-firewall.sh.
# Roda dentro da VM Linux do OrbStack (network_mode: host) e reaplica a cada 5 min (idempotente).
# Extra em relação ao original: 0.0.0.0/8, a faixa que o OrbStack usa pra chegar no Mac (host.docker.internal).
set -eu
SUBNET=${SUBNET:-172.31.2.0/24}
APP_PORT=${APP_PORT:-8743}
add() { chain=$1; shift; iptables -C "$chain" "$@" 2>/dev/null || iptables -I "$chain" "$@"; }
apply() {
  add INPUT -s "$SUBNET" -j DROP
  add INPUT -s "$SUBNET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  for dst in 0.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16; do
    add DOCKER-USER -s "$SUBNET" -d "$dst" -m conntrack --ctstate NEW -j DROP
  done
  add DOCKER-USER -s "$SUBNET" -d "$SUBNET" -p tcp --dport "$APP_PORT" -m conntrack --ctstate NEW -j ACCEPT
}
while true; do apply && echo "$(date -u +%FT%TZ) regras ok"; sleep 300; done
