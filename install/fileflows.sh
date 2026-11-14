# shellcheck shell=bash
#
# install/fileflows.sh - FileFlows, flow-based file processing (media
# conversion, renaming, clean-up).
#
# Runs inside the container, sourced by misc/install.func. Follows
# FileFlows' official documentation:
#
#   Install:  https://fileflows.com/docs/installation/linux
#             (needs .NET 10; download https://fileflows.com/downloads/tarxz,
#             extract it into a FileFlows folder; the Server is
#             Server/FileFlows.Server.dll; web UI on port 19200; FFmpeg for
#             the Video plugin is installed separately)
#   .NET:     https://learn.microsoft.com/dotnet/core/install/linux-debian
#             (Microsoft's packages-microsoft-prod.deb for this Debian
#             release, then 'apt install dotnet-sdk-10.0')
#   Service:  https://fileflows.com/docs/installation/linux/systemd-service
#             (from Server/: 'dotnet FileFlows.Server.dll --systemd install
#             --root true' writes and starts fileflows.service as root)
#   Update:   FileFlows updates itself from its web UI: it puts the new
#             release in Update/ and restarts, and the service's start
#             script (fileflows-systemd-entrypoint.sh) runs that release's
#             server-upgrade.sh. 'recipe update' runs the same script on
#             the latest tarball.
#
# The Server has a built-in processing node, so no Agent is installed.

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="19200/tcp (web UI, and the API for agents)"
  APP_CONFIG="/opt/fileflows/Data/ (database and settings)"
}

FF_DIR="/opt/fileflows"
FF_URL="https://fileflows.com/downloads/tarxz"
FF_PORT=19200

app_install() {
  install_dotnet
  step "Installing FFmpeg (for FileFlows' Video plugin)"
  apt_quiet install --no-install-recommends ffmpeg xz-utils
  ff_fetch "$FF_DIR"
  step "Installing the fileflows service"
  ( cd "${FF_DIR}/Server" && dotnet FileFlows.Server.dll --systemd install --root true )
  check_fileflows
}

app_update() {
  local tmp new cur
  tmp=$(mktemp -d)
  ff_fetch "${tmp}/ff"
  new=$(ff_version_in "${tmp}/ff") || new=""
  cur=$(app_version) || cur=""
  if [[ -n "$new" && "$new" == "$cur" ]]; then
    rm -rf "$tmp"
    msg "FileFlows ${cur} is already the latest release."
    return 0
  fi
  step "Updating FileFlows ${cur:-?} -> ${new:-latest}"
  # The same steps as upstream's service start script, which applies an
  # update it finds in Update/ with that release's server-upgrade.sh. Run
  # here with the service stopped: the start script stays in the deleted
  # Update/ folder afterwards, so its first launch fails and systemd has
  # to restart it.
  systemctl stop fileflows
  rm -rf "${FF_DIR}/Update"
  mv "${tmp}/ff" "${FF_DIR}/Update"
  rm -rf "$tmp"
  ( cd "${FF_DIR}/Update" && bash ./server-upgrade.sh systemd ) >/dev/null
  [[ ! -e "${FF_DIR}/Update" ]] || fail "server-upgrade.sh did not apply the update in ${FF_DIR}/Update."
  systemctl start fileflows
  check_fileflows
}

app_web() {
  printf 'http %s /\n' "$FF_PORT"
}

app_version() {
  ff_version_in "$FF_DIR"
}

# The tarball carries the matching Agent as Server/Agents/FileFlows-Agent-<version>.tar.xz.
ff_version_in() {   # <FileFlows folder>
  local f
  for f in "$1"/Server/Agents/FileFlows-Agent-*.tar.xz; do
    [[ -e "$f" ]] || return 1
    f=${f##*/FileFlows-Agent-}
    printf '%s' "${f%.tar.xz}"
    return 0
  done
}

install_dotnet() {
  local release deb
  release=$(sed -n 's/^VERSION_ID="\{0,1\}\([0-9]*\)"\{0,1\}$/\1/p' /etc/os-release)
  [[ -n "$release" ]] || fail "Could not read the Debian release from /etc/os-release."
  step "Adding Microsoft's package repository (Debian ${release})"
  deb=$(mktemp --suffix=.deb)
  curl -fsSL --retry 2 --max-time 60 -o "$deb" \
    "https://packages.microsoft.com/config/debian/${release}/packages-microsoft-prod.deb"
  dpkg -i "$deb" >/dev/null
  rm -f "$deb"
  apt_quiet update
  step "Installing .NET 10 SDK"
  apt_quiet install dotnet-sdk-10.0
}

ff_fetch() {   # <destination folder>: download and extract the latest release
  local tmp
  tmp=$(mktemp -d)
  step "Downloading FileFlows"
  curl -fsSL --retry 2 --max-time 300 -o "${tmp}/FileFlows.tar.xz" "$FF_URL"
  install -d -m 0755 "$1"
  tar -xJf "${tmp}/FileFlows.tar.xz" -C "$1"
  rm -rf "$tmp"
  [[ -f "$1/Server/FileFlows.Server.dll" ]] || fail "The FileFlows download has no Server/FileFlows.Server.dll."
}

check_fileflows() {
  local i
  step "Waiting for FileFlows' web UI"
  for (( i = 0; i < 90; i++ )); do
    if systemctl is-active --quiet fileflows &&
      curl -fs -o /dev/null --max-time 3 "http://127.0.0.1:${FF_PORT}/"; then
      return 0
    fi
    sleep 2
  done
  journalctl -u fileflows -n 30 --no-pager >&2 || true
  fail "FileFlows' web UI did not come up."
}
