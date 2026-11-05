#!/usr/bin/env bash
#
# ct/debian.sh - a plain Debian 12 container with no app installed.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/debian.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/debian.sh

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="Debian"
  APP_SLUG="debian"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="debian"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=512
  APP_DEFAULT_DISK_GB=4
  APP_INSTALL_SCRIPT=""   # no app: nothing to run inside the container
}

if [[ -n "${RECIPES_SRC:-}" ]]; then
  # shellcheck source=/dev/null
  source "${RECIPES_SRC%/}/misc/build.func"
else
  engine=$(curl -fsSL --retry 2 --max-time 30 \
    "https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/misc/build.func") || {
    printf 'proxmox-recipes: could not download misc/build.func\n' >&2
    exit 1
  }
  # shellcheck source=/dev/null
  source /dev/stdin <<<"$engine"
fi

recipe_main
