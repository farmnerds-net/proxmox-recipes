#!/usr/bin/env bash
#
# ct/coredns.sh - CoreDNS, a DNS server built from plugins.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/coredns.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/coredns.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/coredns.sh

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="CoreDNS"
  APP_SLUG="coredns"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="coredns"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=512
  APP_DEFAULT_DISK_GB=2
  APP_INSTALL_SCRIPT="install/coredns.sh"
}

app_summary_text() {
  local ip
  ip=$(ct_ip_only)
  say "  Config:    /etc/coredns/Corefile (no web UI); forwards to 1.1.1.1 and 9.9.9.9"
  if [[ "$CT_IP" == dhcp ]]; then
    say "  Note:      CoreDNS should keep the same IP. Reserve ${ip} for this container in your DHCP server."
  fi
}

app_notes_rows() {
  notes_row "DNS server" "$(ct_ip_only) port 53, forwarding to 1.1.1.1 and 9.9.9.9 with a cache"
  notes_row "Settings" "no web UI: edit /etc/coredns/Corefile inside the container, then \`systemctl restart coredns\`"
  notes_row "Logs" "/var/log/coredns.log and /var/log/coredns.err.log"
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
