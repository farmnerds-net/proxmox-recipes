#!/usr/bin/env bash
#
# ct/adguardhome.sh - AdGuard Home, network-wide ad and tracker blocking.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/adguardhome.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/adguardhome.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/adguardhome.sh

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="AdGuard Home"
  APP_SLUG="adguardhome"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="adguard"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=512
  APP_DEFAULT_DISK_GB=4
  APP_INSTALL_SCRIPT="install/adguardhome.sh"
}

app_summary_text() {
  local ip
  ip=$(ct_ip_only)
  say "  Setup:     open http://${ip}:3000/ to create the admin account and pick the web and DNS ports"
  if [[ "$CT_IP" == dhcp ]]; then
    say "  Note:      AdGuard Home should keep the same IP. Reserve ${ip} for this container in your DHCP server."
  fi
}

app_notes_rows() {
  notes_row "First visit" "the link opens AdGuard Home's setup wizard on port 3000. After setup, the web UI moves to the port you choose there (default 80): http://$(ct_ip_only)/"
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
