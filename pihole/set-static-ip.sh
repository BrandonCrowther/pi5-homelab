#!/usr/bin/env bash
# Pins the host's wired interface to a static IP so it no longer depends on
# DHCP for its own address. Required because Pi-hole is the only DHCP server
# on the network (Bell Home Hub's DHCP is disabled) - without this, the host
# can lose its address on reboot/lease expiry and take the whole LAN down
# with it. See DHCP_RELIABILITY.md for background.
set -euo pipefail

CONNECTION="${1:-Wired connection 1}"
IP_ADDR="192.168.2.208/24"
GATEWAY="192.168.2.1"

sudo nmcli connection modify "$CONNECTION" \
  ipv4.method manual \
  ipv4.addresses "$IP_ADDR" \
  ipv4.gateway "$GATEWAY"

sudo nmcli connection up "$CONNECTION"

nmcli -t -f ipv4.method,ipv4.addresses,ipv4.gateway connection show "$CONNECTION"
