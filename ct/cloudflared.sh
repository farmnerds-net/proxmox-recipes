#!/usr/bin/env bash
#
# ct/cloudflared.sh - cloudflared, the connector for Cloudflare Tunnel.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/cloudflared.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/cloudflared.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/cloudflared.sh
#
# The recipe does not ask for the tunnel token: it is a secret, and app
# options reach the container on the pct exec command line, which other
# users on the host can see. Paste it in inside the container instead.

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="cloudflared"
  APP_SLUG="cloudflared"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="cloudflared"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=512
  APP_DEFAULT_DISK_GB=2
  APP_INSTALL_SCRIPT="install/cloudflared.sh"
}

app_summary_text() {
  say "  Connect:   in Cloudflare, Networking > Tunnels > Create a tunnel (Cloudflared, Debian)."
  say "             Then: pct enter ${CT_ID}, and run only the line"
  say "             'cloudflared service install <token>' (without sudo)."
}

app_notes_rows() {
  notes_row "Connect" "in the Cloudflare dashboard: Networking > Tunnels > Create a tunnel (Cloudflared, Debian). Then \`pct enter ${CT_ID}\` and run only \`cloudflared service install TOKEN\` from the command it shows (TOKEN is the long code in it), without sudo"
  notes_row "Routes" "point published applications at LAN addresses, e.g. http://192.168.1.20:8080, not localhost: your apps run in other containers"
  notes_row "Status" "\`systemctl status cloudflared\` inside the container, or the tunnel's status in the dashboard (Healthy)"
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
