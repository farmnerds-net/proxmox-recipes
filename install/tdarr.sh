# shellcheck shell=bash
#
# install/tdarr.sh - Tdarr, distributed transcoding and media library
# health checks.
#
# Runs inside the container, sourced by misc/install.func. Follows Tdarr's
# official documentation:
#
#   Install:  https://docs.tdarr.io/docs/installation/windows-linux-macos
#             (download Tdarr_Updater.zip for linux_x64 / linux_arm64,
#             unzip, chmod +x, run ./Tdarr_Updater; it downloads
#             Tdarr_Server and Tdarr_Node next to itself. Then run
#             Tdarr_Server/Tdarr_Server and Tdarr_Node/Tdarr_Node; their
#             configs land in configs/. apt packages: mkvtoolnix for
#             mkvpropedit, handbrake-cli for HandBrake)
#   Auth:     https://docs.tdarr.io/docs/other/authentication
#             (auth is on by default; set seededApiKey before the first
#             start so nobody else can claim the admin account: it creates
#             the key and an 'admin' user whose password is the key. Nodes
#             need that key in apiKey)
#   Config:   https://docs.tdarr.io/docs/installation/configuration-variables
#             (environment variables override the JSON config files)
#   Update:   the same install page: stop Tdarr, run Tdarr_Updater again
#             (its README.txt: "Stop Tdarr before running Tdarr_Updater")
#
# The page also lists libtesseract-dev for CCExtractor, but the bundled
# CCExtractor wants libtesseract.so.4 and Debian ships .so.5, so the
# package doesn't help and the recipe leaves it out. The node's CCExtractor
# check warns; it is only used to detect closed captions.
#
# Upstream has no systemd units; the recipe writes one per program, each
# started from /opt/tdarr like the docs' "./Tdarr_Server/Tdarr_Server".

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="8265/tcp (web UI), 8266/tcp (server, for nodes)"
  APP_CONFIG="/opt/tdarr/configs/ (Tdarr's JSON configs); /etc/tdarr/ (admin password and API key, root only)"
}

TDARR_DIR="/opt/tdarr"
TDARR_CONFIGS="${TDARR_DIR}/configs"
TDARR_CACHE="${TDARR_DIR}/cache"
TDARR_UPDATER="${TDARR_DIR}/Tdarr_Updater"
TDARR_ETC="/etc/tdarr"
TDARR_SERVER_ENV="${TDARR_ETC}/server.env"
TDARR_NODE_ENV="${TDARR_ETC}/node.env"
# The download link the install page gives. The Updater fetches the newest
# Tdarr_Server and Tdarr_Node itself, whatever its own version.
TDARR_UPDATER_URL="https://storage.tdarr.io/versions/3.04.00"

app_install() {
  step "Installing the packages Tdarr's checks use"
  apt_quiet install --no-install-recommends unzip mkvtoolnix handbrake-cli
  install -d -m 0755 "$TDARR_DIR" "$TDARR_CACHE"
  tdarr_fetch_updater
  tdarr_run_updater
  write_tdarr_env
  write_tdarr_units
  systemctl daemon-reload
  systemctl enable --now tdarr-server tdarr-node
  check_tdarr
}

app_update() {
  step "Stopping Tdarr"
  systemctl stop tdarr-node tdarr-server
  tdarr_run_updater
  # The recipe may have changed the units since the install.
  write_tdarr_units
  systemctl daemon-reload
  systemctl start tdarr-server tdarr-node
  check_tdarr
}

app_web() {
  printf 'http %s /\n' "$(tdarr_json "${TDARR_CONFIGS}/Tdarr_Server_Config.json" webUIPort 8265)"
}

# Tdarr_Updater records what it installed in its config, e.g.
#   "Tdarr_Server": { ..., "currentVersion": "3.08.00" }
app_version() {
  local v
  v=$(sed -n '/"Tdarr_Server"/,/}/ s/.*"currentVersion": *"\([^"]*\)".*/\1/p' \
    "${TDARR_CONFIGS}/Tdarr_Updater_Config.json" 2>/dev/null | head -n 1)
  [[ -n "$v" ]] || return 1
  printf '%s' "$v"
}

tdarr_platform() {
  case "$(dpkg --print-architecture)" in
    amd64) printf 'linux_x64' ;;
    arm64) printf 'linux_arm64' ;;
    *) fail "Tdarr has no Linux build for $(dpkg --print-architecture)." ;;
  esac
}

tdarr_fetch_updater() {
  local tmp
  tmp=$(mktemp -d)
  step "Downloading Tdarr_Updater"
  curl -fsSL --retry 2 --max-time 120 -o "${tmp}/Tdarr_Updater.zip" \
    "${TDARR_UPDATER_URL}/$(tdarr_platform)/Tdarr_Updater.zip"
  unzip -q -o "${tmp}/Tdarr_Updater.zip" -d "$tmp"
  [[ -f "${tmp}/Tdarr_Updater" ]] || { rm -rf "$tmp"; fail "Tdarr_Updater.zip has no Tdarr_Updater in it."; }
  install -m 0755 "${tmp}/Tdarr_Updater" "$TDARR_UPDATER"
  rm -rf "$tmp"
}

tdarr_run_updater() {
  step "Running Tdarr_Updater (downloads Tdarr_Server and Tdarr_Node)"
  ( cd "$TDARR_DIR" && ./Tdarr_Updater ) ||
    fail "Tdarr_Updater failed; its log is ${TDARR_CONFIGS}/Tdarr_Updater_Log.txt. Run it again to recover."
  [[ -x "${TDARR_DIR}/Tdarr_Server/Tdarr_Server" && -x "${TDARR_DIR}/Tdarr_Node/Tdarr_Node" ]] ||
    fail "Tdarr_Updater did not install Tdarr_Server and Tdarr_Node."
}

# The seeded API key is created once, at the server's first start, together
# with an 'admin' user whose password is the key. The internal node uses
# the same key. Kept in root-only files, never on a command line.
write_tdarr_env() {
  local key
  [[ -f "$TDARR_SERVER_ENV" ]] && return 0
  key="tapi_$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)" || true
  [[ ${#key} -eq 37 ]] || fail "Could not generate an API key."
  install -d -m 0700 "$TDARR_ETC"
  ( umask 077
    printf 'seededApiKey=%s\n' "$key" >"$TDARR_SERVER_ENV"
    printf 'apiKey=%s\nnodeName=%s-internal\nserverURL=http://127.0.0.1:8266\n' \
      "$key" "$(hostname -s)" >"$TDARR_NODE_ENV" )
}

write_tdarr_units() {
  cat >/etc/systemd/system/tdarr-server.service <<EOF
[Unit]
Description=Tdarr Server
Documentation=https://docs.tdarr.io/
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=${TDARR_DIR}
EnvironmentFile=${TDARR_SERVER_ENV}
ExecStart=${TDARR_DIR}/Tdarr_Server/Tdarr_Server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  cat >/etc/systemd/system/tdarr-node.service <<EOF
[Unit]
Description=Tdarr Node (internal)
Documentation=https://docs.tdarr.io/
After=tdarr-server.service
Wants=tdarr-server.service

[Service]
WorkingDirectory=${TDARR_DIR}
EnvironmentFile=${TDARR_NODE_ENV}
ExecStart=${TDARR_DIR}/Tdarr_Node/Tdarr_Node
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

tdarr_json() {   # <file> <key> <default>: a top-level string or number value
  local v=""
  [[ -r "$1" ]] && v=$(sed -n "s/^ *\"$2\": *\"\{0,1\}\([^\",]*\)\"\{0,1\},\{0,1\} *\$/\1/p" "$1" | head -n 1)
  printf '%s' "${v:-$3}"
}

check_tdarr() {
  local i port
  step "Waiting for Tdarr's web UI"
  for (( i = 0; i < 90; i++ )); do
    port=$(tdarr_json "${TDARR_CONFIGS}/Tdarr_Server_Config.json" webUIPort 8265)
    if systemctl is-active --quiet tdarr-server &&
      curl -fs -o /dev/null --max-time 3 "http://127.0.0.1:${port}/"; then
      return 0
    fi
    sleep 2
  done
  journalctl -u tdarr-server -n 30 --no-pager >&2 || true
  fail "Tdarr's web UI did not come up."
}
