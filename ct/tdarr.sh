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
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="tdarr"
  APP_DEFAULT_CORES=4      # the internal node transcodes on the CPU
  APP_DEFAULT_RAM_MB=4096
  APP_DEFAULT_DISK_GB=16   # Server and Node are ~1 GB; the rest is transcode cache
  APP_INSTALL_SCRIPT="install/tdarr.sh"
}

app_summary_text() {
  say "  Login:     user admin; password: pct exec ${CT_ID} -- cat /etc/tdarr/server.env"
  say "             (the seededApiKey value; change the password in Tdarr afterwards)"
  say "  Media:     not mounted yet. Add a bind mount from the host, e.g.:"
  say "             pct set ${CT_ID} -mp0 /path/on/host,mp=/media"
}

app_notes_rows() {
  notes_row "Login" "user \`admin\`, password = the \`seededApiKey\` value: \`pct exec ${CT_ID} -- cat /etc/tdarr/server.env\`"
  notes_row "Media" "bind-mount it from the host: \`pct set ${CT_ID} -mp0 /path/on/host,mp=/media\`, then add a library for \`/media\`"
  notes_row "Transcode cache" "\`/opt/tdarr/cache\` (set it in each library's settings)"
  notes_row "Nodes" "internal node \`${CT_HOSTNAME}-internal\` (CPU only); other nodes connect to port 8266 with the same API key"
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
