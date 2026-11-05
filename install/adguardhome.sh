# shellcheck shell=bash
#
# install/adguardhome.sh - AdGuard Home, network-wide ad and tracker blocking.
#
# Runs inside the container, sourced by misc/install.func. Every step
# follows AdGuard Home's official documentation:
#
#   Install:  https://github.com/AdguardTeam/AdGuardHome#automated-install-linux-unix-macos-freebsd-openbsd
#             (the official scripts/install.sh; installs to /opt/AdGuardHome
#             and registers the systemd service with 'AdGuardHome -s install')
#   Setup:    https://adguard-dns.io/kb/adguard-home/getting-started/
#             (first start: setup wizard on 0.0.0.0:3000)
#   Update:   https://adguard-dns.io/kb/adguard-home/getting-started/#update
#             ('./AdGuardHome --update')
#
# The installer asks no questions; the remaining setup (admin account,
# web and DNS ports) happens in AdGuard Home's own web wizard afterwards.

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="53/tcp 53/udp 80/tcp 3000/tcp"
  APP_CONFIG="/opt/AdGuardHome/AdGuardHome.yaml (created by the setup wizard)"
}

AGH_DIR="/opt/AdGuardHome"
AGH_BIN="${AGH_DIR}/AdGuardHome"
AGH_YAML="${AGH_DIR}/AdGuardHome.yaml"
AGH_INSTALL_URL="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"

app_install() {
  cd /root || return
  curl -fsSL --retry 2 --max-time 60 -o agh-install.sh "$AGH_INSTALL_URL"
  sh agh-install.sh -v
  rm -f agh-install.sh
}

app_update() {
  "$AGH_BIN" --update
}

# Web UI address. Before the setup wizard has run there is no config file
# and the wizard listens on port 3000. Afterwards, http.address in
# AdGuardHome.yaml (e.g. "0.0.0.0:80") holds the port chosen in the wizard.
app_web() {
  local addr port
  if [[ ! -f "$AGH_YAML" ]]; then
    printf 'http 3000 /\n'
    return 0
  fi
  addr=$(awk '
    /^[^[:space:]]/ { in_http = ($0 ~ /^http:/) }
    in_http && $1 == "address:" { print $2; exit }
  ' "$AGH_YAML")
  port=${addr##*:}
  [[ "$port" =~ ^[0-9]+$ ]] || return 0
  printf 'http %s /\n' "$port"
}

app_version() {
  "$AGH_BIN" --version 2>/dev/null | awk '{ print $NF; exit }'
}
