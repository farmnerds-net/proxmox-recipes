#!/usr/bin/env bash
#
# ct/caddy.sh - Caddy, a web server and reverse proxy with automatic HTTPS.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/caddy.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/caddy.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/caddy.sh

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="Caddy"
  APP_SLUG="caddy"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="caddy"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=512
  APP_DEFAULT_DISK_GB=2
  APP_INSTALL_SCRIPT="install/caddy.sh"
}

app_summary_text() {
  say "  Sites:     pct enter ${CT_ID}, edit /etc/caddy/Caddyfile, then: systemctl reload caddy"
  say "  HTTPS:     point your domain's DNS here and forward ports 80 and 443 to this container"
}

app_notes_rows() {
  notes_row "Sites" "\`pct enter ${CT_ID}\`, edit \`/etc/caddy/Caddyfile\`, then \`systemctl reload caddy\`"
  notes_row "HTTPS" "automatic for real domains: point DNS here and forward ports 80 and 443 from your router; use LAN IPs, not localhost, for apps in other containers"
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
