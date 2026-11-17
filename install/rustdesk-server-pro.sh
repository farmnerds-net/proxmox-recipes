# shellcheck shell=bash
#
# install/rustdesk-server-pro.sh - RustDesk Server Pro, a self-hosted ID,
# relay and web console server for RustDesk remote desktop. Needs a
# RustDesk Server Pro licence (entered in the web console afterwards).
#
# Runs inside the container, sourced by misc/install.func. Follows
# RustDesk's official documentation and RustDesk's own install scripts:
#
#   Install:  https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/installscript/
#             ("Method 2: install.sh"), i.e. the steps in
#             https://github.com/rustdesk/rustdesk-server-pro/blob/main/install.sh:
#             download the latest release's rustdesk-server-linux-<arch>.tar.gz
#             (the -nativetls build when libssl.so.3 is present), put hbbs,
#             hbbr and rustdesk-utils in /usr/bin and static/ in
#             /var/lib/rustdesk-server, and create the rustdesk-hbbs and
#             rustdesk-hbbr systemd services (WorkingDirectory
#             /var/lib/rustdesk-server, logs in /var/log/rustdesk-server).
#             The script's unprivileged-user option is used, with a
#             'rustdesk' system user. Its ufw and Nginx/Certbot steps are
#             left out: a recipe never changes firewall config, and HTTPS
#             belongs to your own reverse proxy.
#   Update:   https://github.com/rustdesk/rustdesk-server-pro/blob/main/update.sh
#             (stop both services, replace static/ and the three binaries
#             with the latest release, start them again)
#   Ports:    https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/installscript/
#             (21114 web console/API, 21115-21117 TCP, 21116 UDP;
#             21118-21119 only for the web client)

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="21114/tcp (web console) 21115-21117/tcp 21116/udp (clients) 21118-21119/tcp (web client, optional)"
  APP_CONFIG="/var/lib/rustdesk-server/ (database, key pair: id_ed25519.pub is the key clients need)"
}

RD_DIR="/var/lib/rustdesk-server"
RD_LOG_DIR="/var/log/rustdesk-server"
RD_USER="rustdesk"
RD_API="https://api.github.com/repos/rustdesk/rustdesk-server-pro/releases/latest"
RD_DL="https://github.com/rustdesk/rustdesk-server-pro/releases/download"
RD_VERSION_FILE="${RD_DIR}/.recipe-version"
RD_PORT=21114

app_install() {
  local tag
  tag=$(rd_latest_tag)
  step "Creating the ${RD_USER} system user"
  id -u "$RD_USER" >/dev/null 2>&1 ||
    useradd --system --home-dir "$RD_DIR" --no-create-home --shell /usr/sbin/nologin "$RD_USER"
  install -d -m 0750 -o "$RD_USER" -g "$RD_USER" "$RD_DIR"
  install -d -m 0700 -o "$RD_USER" -g "$RD_USER" "$RD_LOG_DIR"
  rd_fetch "$tag"
  rd_write_units
  rd_write_logrotate
  systemctl daemon-reload
  step "Starting RustDesk Server Pro"
  systemctl enable --now rustdesk-hbbr.service rustdesk-hbbs.service >/dev/null 2>&1
  check_rustdesk
}

app_update() {
  local latest current
  latest=$(rd_latest_tag)
  current=$(app_version) || current=""
  if [[ -n "$current" && "$current" == "$latest" ]]; then
    msg "RustDesk Server Pro ${current} is already the latest release."
    return 0
  fi
  step "Updating RustDesk Server Pro ${current:-?} -> ${latest}"
  systemctl stop rustdesk-hbbs.service rustdesk-hbbr.service
  rd_fetch "$latest"
  systemctl start rustdesk-hbbr.service rustdesk-hbbs.service
  check_rustdesk
}

app_web() {
  printf 'http %s /\n' "$RD_PORT"
}

app_version() {
  [[ -r "$RD_VERSION_FILE" ]] || return 1
  cat "$RD_VERSION_FILE"
}

rd_latest_tag() {
  local tag
  tag=$(curl -fsSL --retry 2 --max-time 30 "$RD_API" |
    sed -n 's/^ *"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
  [[ "$tag" =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "Could not find RustDesk Server Pro's latest release on GitHub."
  printf '%s' "$tag"
}

# The tarball name, as upstream's install.sh picks it: architecture, plus
# -nativetls when the system has OpenSSL 3 (Debian 12 and 13 do).
rd_tar_name() {
  local name tls=""
  case "$(dpkg --print-architecture)" in
    amd64) name=amd64 ;;
    arm64) name=arm64v8 ;;
    armhf) name=armv7 ;;
    *) fail "No RustDesk Server Pro release for architecture $(dpkg --print-architecture)." ;;
  esac
  if [[ "$name" != armv7 ]] && ldconfig -p | grep -q 'libssl\.so\.3'; then
    tls="-nativetls"
  fi
  printf '%s%s' "$name" "$tls"
}

rd_fetch() {   # <tag>: download that release and put its files in place
  local tag=$1 name tmp
  name=$(rd_tar_name)
  tmp=$(mktemp -d)
  step "Downloading RustDesk Server Pro ${tag} (${name})"
  curl -fsSL --retry 3 --max-time 300 -o "${tmp}/rd.tar.gz" \
    "${RD_DL}/${tag}/rustdesk-server-linux-${name}.tar.gz"
  tar -xzf "${tmp}/rd.tar.gz" -C "$tmp"
  [[ -x "${tmp}/${name}/hbbs" && -x "${tmp}/${name}/hbbr" && -d "${tmp}/${name}/static" ]] ||
    { rm -rf "$tmp"; fail "The RustDesk download does not have the expected hbbs, hbbr and static/."; }
  install -m 0755 "${tmp}/${name}/hbbs" "${tmp}/${name}/hbbr" "${tmp}/${name}/rustdesk-utils" /usr/bin/
  rm -rf "${RD_DIR}/static"
  mv "${tmp}/${name}/static" "${RD_DIR}/static"
  chown -R "${RD_USER}:${RD_USER}" "${RD_DIR}/static"
  printf '%s\n' "$tag" >"$RD_VERSION_FILE"
  rm -rf "$tmp"
}

rd_write_units() {   # <name> <description>, as in upstream's install.sh
  step "Writing the rustdesk-hbbs and rustdesk-hbbr services"
  rd_unit hbbs "RustDesk Signal Server"
  rd_unit hbbr "RustDesk Relay Server"
}

rd_unit() {
  cat >"/etc/systemd/system/rustdesk-$1.service" <<EOF
[Unit]
Description=$2
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/$1
WorkingDirectory=${RD_DIR}
User=${RD_USER}
Group=${RD_USER}
Restart=always
RestartSec=10
StandardOutput=append:${RD_LOG_DIR}/$1.log
StandardError=append:${RD_LOG_DIR}/$1.error

[Install]
WantedBy=multi-user.target
EOF
}

# Upstream's services append to these logs forever; rotate them weekly.
rd_write_logrotate() {
  cat >/etc/logrotate.d/rustdesk-server <<EOF
${RD_LOG_DIR}/*.log ${RD_LOG_DIR}/*.error {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    copytruncate
}
EOF
}

check_rustdesk() {
  local i
  step "Waiting for RustDesk Server Pro"
  for (( i = 0; i < 60; i++ )); do
    if systemctl is-active --quiet rustdesk-hbbr && systemctl is-active --quiet rustdesk-hbbs &&
      [[ -s "${RD_DIR}/id_ed25519.pub" ]] &&
      curl -fs -o /dev/null --max-time 3 "http://127.0.0.1:${RD_PORT}/"; then
      return 0
    fi
    sleep 2
  done
  tail -n 30 "${RD_LOG_DIR}/hbbs.log" "${RD_LOG_DIR}/hbbs.error" >&2 2>/dev/null || true
  fail "RustDesk Server Pro did not come up (web console on port ${RD_PORT}, key in ${RD_DIR})."
}
