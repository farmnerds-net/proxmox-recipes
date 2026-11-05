#!/usr/bin/env bash
#
# ct/powerdns.sh - PowerDNS Recursor and Authoritative Server in one
# container: a resolver for the network plus your own local DNS zone.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/powerdns.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/powerdns.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/powerdns.sh

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="PowerDNS"
  APP_SLUG="powerdns"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="powerdns"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=512
  APP_DEFAULT_DISK_GB=4
  APP_INSTALL_SCRIPT="install/powerdns.sh"
}

app_summary_text() {
  local ip
  ip=$(ct_ip_only)
  say "  DNS:       ${ip} port 53 (Recursor); local zone home.arpa (Authoritative)"
  say "  API:       http://${ip}:8081/api/v1 ; key in /etc/powerdns/pdns.d/recipe.conf"
  if [[ "$CT_IP" == dhcp ]]; then
    say "  Note:      PowerDNS should keep the same IP. Reserve ${ip} for this container in your DHCP server."
  fi
}

app_notes_rows() {
  local ip
  ip=$(ct_ip_only)
  notes_row "DNS server" "${ip} port 53 (Recursor, DNSSEC validating, private networks only)"
  notes_row "Local zone" "home.arpa, served by the Authoritative Server. Add a name: \`pdnsutil rrset add home.arpa NAME.home.arpa A IP\`"
  notes_row "API" "http://${ip}:8081/api/v1 (key: \`grep api-key /etc/powerdns/pdns.d/recipe.conf\`)"
}

if [[ -n "${RECIPES_SRC:-}" ]]; then
  # shellcheck source=/dev/null
  source "${RECIPES_SRC%/}/misc/build.func"
else
  engine=$(curl -fsSL --retry 2 --max-time 30 \
    "https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/${RECIPES_REF:-main}/misc/build.func") || {
    printf 'proxmox-recipes: could not download misc/build.func\n' >&2
    exit 1
  }
  # shellcheck source=/dev/null
  source /dev/stdin <<<"$engine"
fi

recipe_main
