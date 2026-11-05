#!/usr/bin/env bash
#
# ct/unbound.sh - Unbound, a validating, recursive, caching DNS resolver for
# the local network.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/unbound.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/unbound.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/unbound.sh

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="Unbound"
  APP_SLUG="unbound"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="unbound"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=512
  APP_DEFAULT_DISK_GB=2
  APP_INSTALL_SCRIPT="install/unbound.sh"
}

app_summary_text() {
  local ip
  ip=$(ct_ip_only)
  say "  Config:    /etc/unbound/unbound.conf.d/recipe.conf (no web UI)"
  say "  Clients:   private networks only (10/8, 172.16/12, 192.168/16)"
  if [[ "$CT_IP" == dhcp ]]; then
    say "  Note:      Unbound should keep the same IP. Reserve ${ip} for this container in your DHCP server."
  fi
}

app_notes_rows() {
  notes_row "DNS server" "$(ct_ip_only) port 53, recursive with DNSSEC validation"
  notes_row "Clients" "private networks only (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)"
  notes_row "Settings" "no web UI: edit /etc/unbound/unbound.conf.d/recipe.conf inside the container, run \`unbound-checkconf\`, then \`systemctl restart unbound\`"
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
