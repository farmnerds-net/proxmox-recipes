#!/usr/bin/env bash
#
# ct/tdarr.sh - Tdarr, distributed transcoding and media library health
# checks.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/tdarr.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/tdarr.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/tdarr.sh
#
# The container runs the Tdarr Server and one internal Node that
# transcodes on the CPU. Media folders and a GPU are passed in from the
# host afterwards (see docs/apps/tdarr.md): the recipe never changes host
# config.

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="Tdarr"
  APP_SLUG="tdarr"
  APP_DEBIAN_RELEASE=13
  APP_DEFAULT_HOSTNAME="tdarr"
  APP_DEFAULT_CORES=4      # the internal node transcodes on the CPU
  APP_DEFAULT_RAM_MB=4096
  APP_DEFAULT_DISK_GB=16   # Server and Node are ~1 GB; the rest is transcode cache
  APP_INSTALL_SCRIPT="install/tdarr.sh"
}

# The seeded API key, read from the container. Printed only in the summary,
# which goes to the terminal and not to the install log. The notes only say
# how to show it, like every other recipe's credentials.
tdarr_api_key() {
  pct exec "$CT_ID" -- sed -n 's/^seededApiKey=//p' /etc/tdarr/server.env 2>/dev/null || true
}

tdarr_key_cmd() {
  printf "pct exec %s -- sed -n 's/^seededApiKey=//p' /etc/tdarr/server.env" "$CT_ID"
}

app_summary_text() {
  local ip key
  ip=$(ct_ip_only)
  key=$(tdarr_api_key)
  say "  API key:   ${key:-could not read it; run: $(tdarr_key_cmd)}"
  say "             Nodes need it. It is also the admin password until you change"
  say "             that in Tdarr (changing the password does not change the key)."
  say "  Login:     user admin, password = the API key above"
  say "  Nodes:     connect other nodes to http://${ip:-<container-ip>}:8266 with the API key"
  say "  Show key:  $(tdarr_key_cmd)"
  say "  Media:     not mounted yet. Add a bind mount from the host, e.g.:"
  say "             pct set ${CT_ID} -mp0 /path/on/host,mp=/media"
}

app_notes_rows() {
  local ip
  ip=$(ct_ip_only)
  notes_row "API key" "nodes need it; show it on the host with \`$(tdarr_key_cmd)\`"
  notes_row "Login" "user \`admin\`, password = the API key until you change it in Tdarr (the key stays the same)"
  notes_row "Media" "bind-mount it from the host: \`pct set ${CT_ID} -mp0 /path/on/host,mp=/media\`, then add a library for \`/media\`"
  notes_row "Transcode cache" "\`/opt/tdarr/cache\` (set it in each library's settings)"
  notes_row "Nodes" "internal node \`${CT_HOSTNAME}-internal\` (CPU only); other nodes connect to \`http://${ip:-<container-ip>}:8266\` with the API key"
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
