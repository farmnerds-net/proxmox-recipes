#!/usr/bin/env bash
#
# ct/technitium.sh - Technitium DNS Server, a recursive and authoritative DNS
# server with ad blocking and a web console.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/technitium.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/technitium.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/technitium.sh

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="Technitium DNS Server"
  APP_SLUG="technitium"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="technitium"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=1024   # runs on .NET
  APP_DEFAULT_DISK_GB=4
  APP_INSTALL_SCRIPT="install/technitium.sh"
}

app_summary_text() {
  local ip
  ip=$(ct_ip_only)
  say "  Login:     http://${ip}:5380/ user admin, password admin. Change the password right away."
  if [[ "$CT_IP" == dhcp ]]; then
    say "  Note:      Technitium should keep the same IP. Reserve ${ip} for this container in your DHCP server."
  fi
}

app_notes_rows() {
  notes_row "First login" "user admin, password admin. Change it right away in the web console."
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
