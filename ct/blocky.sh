#!/usr/bin/env bash
#
# ct/blocky.sh - Blocky, a DNS proxy and ad blocker.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/blocky.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/blocky.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/blocky.sh

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="Blocky"
  APP_SLUG="blocky"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="blocky"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=512
  APP_DEFAULT_DISK_GB=2
  APP_INSTALL_SCRIPT="install/blocky.sh"
}

app_summary_text() {
  local ip
  ip=$(ct_ip_only)
  say "  Config:    /etc/blocky/config.yml (no web UI); after editing: systemctl restart blocky"
  if [[ "$CT_IP" == dhcp ]]; then
    say "  Note:      Blocky should keep the same IP. Reserve ${ip} for this container in your DHCP server."
  fi
}

app_notes_rows() {
  notes_row "Settings" "no web UI: edit /etc/blocky/config.yml inside the container, then \`systemctl restart blocky\`"
  notes_row "API" "http://$(ct_ip_only):4000/ (REST API, metrics, DNS-over-HTTPS)"
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
