#!/usr/bin/env bash
#
# ct/fileflows.sh - FileFlows, flow-based file processing (media conversion,
# renaming, clean-up).
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/fileflows.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/fileflows.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/fileflows.sh
#
# FileFlows processes files with the Server's built-in node, on the CPU.
# Media folders and a GPU are passed in from the host afterwards (see
# docs/apps/fileflows.md): the recipe never changes host config.

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="FileFlows"
  APP_SLUG="fileflows"
  APP_DEBIAN_RELEASE=13    # FFmpeg 7.1; Debian 12 has 5.1
  APP_DEFAULT_HOSTNAME="fileflows"
  APP_DEFAULT_CORES=4      # the built-in node converts on the CPU
  APP_DEFAULT_RAM_MB=4096
  APP_DEFAULT_DISK_GB=16   # .NET SDK and FileFlows ~1.5 GB; the rest is temp space
  APP_INSTALL_SCRIPT="install/fileflows.sh"
}

app_summary_text() {
  say "  Login:     none: anyone who can reach port 19200 can use FileFlows."
  say "             (Its login is a paid-licence feature.) Keep it on a trusted network."
  say "  Media:     not mounted yet. Add a bind mount from the host, e.g.:"
  say "             pct set ${CT_ID} -mp0 /path/on/host,mp=/media"
}

app_notes_rows() {
  notes_row "Login" "none: anyone who can reach port 19200 can use it (FileFlows' login needs a paid licence). Keep it on a trusted network"
  notes_row "Media" "bind-mount it from the host: \`pct set ${CT_ID} -mp0 /path/on/host,mp=/media\`, then add a library for \`/media\`"
  notes_row "FFmpeg" "\`/usr/bin/ffmpeg\` (Debian)"
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
