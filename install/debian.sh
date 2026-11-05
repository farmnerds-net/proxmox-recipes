# shellcheck shell=bash
#
# install/debian.sh - plain Debian, no app.
#
# Runs inside the container, sourced by misc/install.func. The OS itself is
# installed by the Proxmox template and upgraded by install.func, so there
# is nothing app-specific to do.

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS=""
  APP_CONFIG=""
}

app_install() { :; }

app_update() { :; }

app_version() { printf 'Debian %s' "$(cat /etc/debian_version)"; }
