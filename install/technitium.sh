# shellcheck shell=bash
#
# install/technitium.sh - Technitium DNS Server, a recursive and authoritative
# DNS server with ad blocking and a web console.
#
# Runs inside the container, sourced by misc/install.func. Follows
# Technitium's official documentation:
#
#   Install:  https://blog.technitium.com/2017/11/running-dns-server-on-ubuntu-linux.html
#             (linked from the README at
#             https://github.com/TechnitiumSoftware/DnsServer#installation):
#             "curl -sSL https://download.technitium.com/dns/install.sh | sudo bash"
#             It installs the ASP.NET Core runtime to /opt/dotnet, the server
#             to /opt/technitium/dns (config in /etc/dns), a 'dns-server'
#             user and the systemd 'dns' service.
#   Update:   same post: "Automated installer script can be used to install
#             or update the DNS Server."
#
# The installer asks no questions. The web console is on port 5380.

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="53/tcp 53/udp 5380/tcp (web console)"
  APP_CONFIG="/etc/dns (managed from the web console)"
}

TECHNITIUM_INSTALL_URL="https://download.technitium.com/dns/install.sh"
TECHNITIUM_DIR="/opt/technitium/dns"

app_install() {
  technitium_installer
}

app_update() {
  technitium_installer
}

technitium_installer() {
  cd /root || return
  curl -fsSL --retry 2 --max-time 60 -o technitium-install.sh "$TECHNITIUM_INSTALL_URL"
  bash technitium-install.sh
  rm -f technitium-install.sh
  check_technitium
}

app_web() {
  printf 'http 5380 /\n'
}

app_version() {
  # deps.json names the app with its version, e.g. "DnsServerApp/15.6.2".
  sed -n 's/.*"DnsServerApp\/\([0-9][0-9.]*\)".*/\1/p' "${TECHNITIUM_DIR}/DnsServerApp.deps.json" 2>/dev/null | head -n 1
}

check_technitium() {
  local i
  step "Waiting for Technitium DNS Server to start"
  for (( i = 0; i < 60; i++ )); do
    if systemctl is-active --quiet dns &&
      curl -fs -o /dev/null --max-time 3 http://127.0.0.1:5380/; then
      return 0
    fi
    sleep 2
  done
  journalctl -u dns -n 20 --no-pager >&2 || true
  fail "Technitium DNS Server did not start (no web console on port 5380)."
}
