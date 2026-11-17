# shellcheck shell=bash
#
# install/guacamole.sh - Apache Guacamole, a clientless remote desktop
# gateway: RDP, VNC and SSH in a web browser.
#
# Runs inside the container, sourced by misc/install.func. Follows the
# Apache Guacamole manual (v1.6.0) and Apache Tomcat's documentation:
#
#   guacd:    https://guacamole.apache.org/doc/gug/guacamole-native.html
#             (build guacamole-server from the release source tarball with
#             the listed Debian -dev packages; './configure
#             --with-systemd-dir=/usr/local/lib/systemd/system', make,
#             make install, ldconfig; the build installs guacd.service)
#   FreeRDP:  Debian 12's FreeRDP 2.11. guacamole-server 1.6.0's configure
#             calls FreeRDP 3 support experimental and recommends 2.x, and
#             it does not compile against Debian 13's FreeRDP 3.15.
#   Web app:  same page ("Deploying Guacamole"): guacamole.war from the
#             release's binary downloads, copied into Tomcat's webapps/.
#             Guacamole 1.6.0 is a javax.servlet web app, so it needs
#             Tomcat 9 (Tomcat 10+ is jakarta.servlet). Debian 12 has no
#             tomcat9 package, so Tomcat 9 comes from Apache's binary
#             distribution: https://tomcat.apache.org/download-90.cgi,
#             installed per RUNNING.txt with CATALINA_HOME (the release)
#             and CATALINA_BASE (this instance's conf/webapps/logs) apart,
#             https://tomcat.apache.org/tomcat-9.0-doc/RUNNING.txt
#   Database: https://guacamole.apache.org/doc/gug/postgresql-auth.html
#             (guacamole-auth-jdbc's PostgreSQL extension in
#             GUACAMOLE_HOME/extensions, the JDBC driver in
#             GUACAMOLE_HOME/lib, schema/*.sql loaded into guacamole_db,
#             guacamole_user with the documented GRANTs, and the
#             postgresql-* properties; upgrades run the
#             schema/upgrade/upgrade-pre-<version>.sql scripts newer than
#             the installed release, then the GRANTs again)
#   guacd.conf: https://guacamole.apache.org/doc/gug/configuring-guacamole.html
#             ("Configuring guacd": [server] bind_host and bind_port in
#             /etc/guacamole/guacd.conf)
#   Checksums: every Apache download is checked against the .sha256 or
#             .sha512 file Apache publishes next to it.

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="8080/tcp (web UI, /guacamole/); guacd on 127.0.0.1:4822 only"
  APP_CONFIG="/etc/guacamole/guacamole.properties (database login in it); data in PostgreSQL database guacamole_db; first guacadmin password in /root/guacadmin-password"
}

GUAC_HOME="/etc/guacamole"
GUAC_VERSION_FILE="${GUAC_HOME}/.recipe-version"
GUAC_DL="https://dlcdn.apache.org/guacamole"
GUAC_SUMS="https://downloads.apache.org/guacamole"
TC_DL="https://dlcdn.apache.org/tomcat/tomcat-9"
TC_SUMS="https://downloads.apache.org/tomcat/tomcat-9"
TC_ROOT="/opt/tomcat9"                 # releases + 'current' symlink (CATALINA_HOME)
TC_BASE="/var/lib/guacamole-tomcat"    # CATALINA_BASE
TC_USER="tomcat"
GUAC_DB="guacamole_db"
GUAC_DB_USER="guacamole_user"
GUAC_PORT=8080
GUAC_ADMIN_PW_FILE="/root/guacadmin-password"

GUAC_BUILD_DEPS=(
  build-essential libcairo2-dev libjpeg62-turbo-dev libpng-dev libtool-bin uuid-dev
  freerdp2-dev libpango1.0-dev libssh2-1-dev libtelnet-dev libvncserver-dev
  libwebsockets-dev libpulse-dev libssl-dev libvorbis-dev libwebp-dev
  libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
)

app_install() {
  local guac tc
  guac=$(guac_latest)
  tc=$(tc_latest)
  step "Installing build tools and libraries for guacamole-server"
  apt_quiet install --no-install-recommends "${GUAC_BUILD_DEPS[@]}" \
    fonts-dejavu-core fonts-liberation2
  step "Installing Java, PostgreSQL and its JDBC driver"
  apt_quiet install --no-install-recommends openjdk-17-jre-headless \
    postgresql libpostgresql-jdbc-java

  guac_build_server "$guac"
  tc_install "$tc"
  guac_setup_home
  guacd_setup_user
  systemctl daemon-reload
  systemctl enable --now guacd >/dev/null 2>&1
  guac_setup_db "$guac"
  guac_deploy_web "$guac"
  printf '%s\n' "$guac" >"$GUAC_VERSION_FILE"
  systemctl enable --now guacamole-tomcat >/dev/null 2>&1
  check_guacamole
}

app_update() {
  local guac_new guac_cur tc_new tc_cur changed=0
  guac_new=$(guac_latest)
  guac_cur=$(cat "$GUAC_VERSION_FILE" 2>/dev/null) || guac_cur=""
  tc_new=$(tc_latest)
  tc_cur=$(tc_current) || tc_cur=""

  if [[ "$tc_new" != "$tc_cur" ]]; then
    step "Updating Tomcat ${tc_cur:-?} -> ${tc_new}"
    systemctl stop guacamole-tomcat
    tc_fetch "$tc_new"
    changed=1
  else
    msg "Tomcat ${tc_cur} is already the latest 9.0 release."
  fi

  if [[ -n "$guac_cur" && "$guac_new" == "$guac_cur" ]]; then
    msg "Guacamole ${guac_cur} is already the latest release."
  else
    step "Updating Guacamole ${guac_cur:-?} -> ${guac_new}"
    systemctl stop guacamole-tomcat
    guac_build_server "$guac_new"
    systemctl daemon-reload
    systemctl restart guacd
    guac_upgrade_db "$guac_cur" "$guac_new"
    guac_deploy_web "$guac_new"
    printf '%s\n' "$guac_new" >"$GUAC_VERSION_FILE"
    changed=1
  fi

  if (( changed )); then
    systemctl start guacamole-tomcat
    check_guacamole
  fi
}

app_web() {
  printf 'http %s /guacamole/\n' "$GUAC_PORT"
}

app_version() {
  local g t
  g=$(cat "$GUAC_VERSION_FILE" 2>/dev/null) || return 1
  t=$(tc_current) || t="?"
  printf '%s (Tomcat %s)' "$g" "$t"
}

# ---- releases ----------------------------------------------------------------

latest_in_listing() {   # <url> <grep -o pattern for 'href="X/"'> -> highest X
  local v
  v=$(curl -fsSL --retry 2 --max-time 30 "$1" | grep -oE "$2" |
    sed -E 's/^href="v?//; s/\/"$//' | sort -V | tail -n 1)
  printf '%s' "$v"
}

guac_latest() {
  local v
  v=$(latest_in_listing "${GUAC_SUMS}/" 'href="[0-9]+\.[0-9]+\.[0-9]+/"')
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Could not find Guacamole's latest release at ${GUAC_SUMS}/."
  printf '%s' "$v"
}

tc_latest() {
  local v
  v=$(latest_in_listing "${TC_SUMS}/" 'href="v9\.0\.[0-9]+/"')
  [[ "$v" =~ ^9\.0\.[0-9]+$ ]] || fail "Could not find Tomcat 9's latest release at ${TC_SUMS}/."
  printf '%s' "$v"
}

tc_current() {
  local t
  t=$(readlink "${TC_ROOT}/current") || return 1
  printf '%s' "${t##*apache-tomcat-}"
}

fetch_checked() {   # <url> <checksum url> <sha256|sha512> <destination>
  local sum
  curl -fsSL --retry 3 --max-time 600 -o "$4" "$1"
  sum=$(curl -fsSL --retry 2 --max-time 30 "$2" | awk '{ print $1; exit }')
  [[ -n "$sum" ]] || fail "Could not download the checksum for ${1##*/}."
  printf '%s  %s\n' "$sum" "$4" | "${3}sum" -c --quiet - ||
    fail "Checksum mismatch for ${1##*/}; not installing it."
}

# ---- guacamole-server (guacd) -------------------------------------------------

guac_build_server() {   # <version>
  local v=$1 tmp src
  tmp=$(mktemp -d)
  src="guacamole-server-${v}"
  step "Downloading guacamole-server ${v}"
  fetch_checked "${GUAC_DL}/${v}/source/${src}.tar.gz" \
    "${GUAC_SUMS}/${v}/source/${src}.tar.gz.sha256" sha256 "${tmp}/${src}.tar.gz"
  tar -xzf "${tmp}/${src}.tar.gz" -C "$tmp"
  step "Building guacamole-server ${v} (takes a few minutes)"
  (
    cd "${tmp}/${src}"
    ./configure --with-systemd-dir=/usr/local/lib/systemd/system >"${tmp}/configure.log" 2>&1 ||
      { tail -n 30 "${tmp}/configure.log" >&2; exit 1; }
    grep -q 'RDP \.* yes' "${tmp}/configure.log" ||
      { grep -A 30 'Library status' "${tmp}/configure.log" >&2; exit 1; }
    make -j "$(nproc)" >"${tmp}/make.log" 2>&1 || { tail -n 30 "${tmp}/make.log" >&2; exit 1; }
    make install >"${tmp}/install.log" 2>&1 || { tail -n 30 "${tmp}/install.log" >&2; exit 1; }
  ) || { rm -rf "$tmp"; fail "Building guacamole-server ${v} failed."; }
  ldconfig
  rm -rf "$tmp"
}

# guacamole-server's guacd.service runs as 'daemon', whose home (/usr/sbin)
# is not writable. FreeRDP keeps its certificate store in the home folder,
# and without it RDP connections fail TLS negotiation (guacd logs "FreeRDP
# initialization may fail: ... home directory is not writable"). A
# systemd drop-in runs guacd as its own user with a writable home; the
# unit file itself stays as 'make install' wrote it.
guacd_setup_user() {
  step "Creating the guacd system user"
  id -u guacd >/dev/null 2>&1 ||
    useradd --system --home-dir /var/lib/guacd --shell /usr/sbin/nologin guacd
  install -d -m 0750 -o guacd -g guacd /var/lib/guacd
  install -d -m 0755 /etc/systemd/system/guacd.service.d
  cat >/etc/systemd/system/guacd.service.d/recipe.conf <<'EOF'
# Written by proxmox-recipes: run guacd as its own user, with a writable
# home for FreeRDP (see install/guacamole.sh).
[Service]
User=guacd
Group=guacd
EOF
}

# ---- Tomcat 9 -------------------------------------------------------------------

tc_install() {   # <version>
  step "Creating the ${TC_USER} system user"
  id -u "$TC_USER" >/dev/null 2>&1 ||
    useradd --system --home-dir "$TC_BASE" --no-create-home --shell /usr/sbin/nologin "$TC_USER"
  tc_fetch "$1"
  tc_make_base
  tc_write_unit
}

tc_fetch() {   # <version>: unpack that release under TC_ROOT and point 'current' at it
  local v=$1 tmp name
  name="apache-tomcat-${v}"
  tmp=$(mktemp -d)
  step "Downloading Tomcat ${v}"
  fetch_checked "${TC_DL}/v${v}/bin/${name}.tar.gz" \
    "${TC_SUMS}/v${v}/bin/${name}.tar.gz.sha512" sha512 "${tmp}/${name}.tar.gz"
  install -d -m 0755 "$TC_ROOT"
  rm -rf "${TC_ROOT:?}/${name}"
  tar -xzf "${tmp}/${name}.tar.gz" -C "$TC_ROOT"
  rm -rf "$tmp"
  # Apache's tarball is mode 0750/0640: Tomcat reads it through its group,
  # and cannot change its own program files.
  chown -R "root:${TC_USER}" "${TC_ROOT}/${name}"
  ln -sfn "${TC_ROOT}/${name}" "${TC_ROOT}/current"
  # Keep the running release and the one before it.
  find "$TC_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'apache-tomcat-*' |
    sort -V | head -n -2 | xargs -r rm -rf
}

# CATALINA_BASE with this instance's own conf/, webapps/, logs/, temp/ and
# work/ (RUNNING.txt, "Advanced Configuration - Multiple Tomcat Instances").
# Tomcat's sample web apps are not copied: only Guacamole is deployed.
tc_make_base() {
  local d
  step "Setting up the Tomcat instance in ${TC_BASE}"
  for d in conf webapps logs temp work; do
    install -d -m 0750 -o "$TC_USER" -g "$TC_USER" "${TC_BASE}/${d}"
  done
  cp -a "${TC_ROOT}/current/conf/." "${TC_BASE}/conf/"
  chown -R "root:${TC_USER}" "${TC_BASE}/conf"
  chmod -R g+rX,o-rwx "${TC_BASE}/conf"
  # The site root sends visitors on to Guacamole.
  install -d -m 0755 -o "$TC_USER" -g "$TC_USER" "${TC_BASE}/webapps/ROOT"
  cat >"${TC_BASE}/webapps/ROOT/index.html" <<'EOF'
<!DOCTYPE html>
<meta http-equiv="refresh" content="0; url=/guacamole/">
<a href="/guacamole/">Guacamole</a>
EOF
  chown "${TC_USER}:${TC_USER}" "${TC_BASE}/webapps/ROOT/index.html"
}

tc_write_unit() {
  local jhome
  jhome=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
  [[ -x "${jhome}/bin/java" ]] || fail "Could not find the Java installation."
  step "Writing the guacamole-tomcat service"
  cat >/etc/systemd/system/guacamole-tomcat.service <<EOF
[Unit]
Description=Apache Tomcat 9 for Apache Guacamole
After=network-online.target postgresql.service guacd.service
Wants=network-online.target postgresql.service guacd.service

[Service]
Type=simple
User=${TC_USER}
Group=${TC_USER}
UMask=0027
Environment=JAVA_HOME=${jhome}
Environment=CATALINA_HOME=${TC_ROOT}/current
Environment=CATALINA_BASE=${TC_BASE}
Environment=CATALINA_TMPDIR=${TC_BASE}/temp
Environment=GUACAMOLE_HOME=${GUAC_HOME}
ExecStart=${TC_ROOT}/current/bin/catalina.sh run
SuccessExitStatus=143
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

# ---- Guacamole web app and database ----------------------------------------------

guac_setup_home() {
  step "Setting up ${GUAC_HOME}"
  # guacd (user daemon) reads guacd.conf here; only guacamole.properties,
  # which holds the database password, is kept from other users.
  install -d -m 0755 "$GUAC_HOME" "${GUAC_HOME}/extensions" "${GUAC_HOME}/lib"
  # Debian's driver, kept current by apt.
  ln -sfn /usr/share/java/postgresql.jar "${GUAC_HOME}/lib/postgresql.jar"
  # guacd listens on "localhost", which can resolve to ::1 only, while the
  # web app connects to 127.0.0.1. Pin it in guacd.conf.
  [[ -f "${GUAC_HOME}/guacd.conf" ]] || cat >"${GUAC_HOME}/guacd.conf" <<'EOF'
# guacd configuration, written by proxmox-recipes.
# Reference: https://guacamole.apache.org/doc/gug/configuring-guacamole.html
# After editing: systemctl restart guacd
[server]
bind_host = 127.0.0.1
bind_port = 4822
EOF
}

# psql as postgres, from a folder postgres can read (not root's cwd).
pg_sql() {
  ( cd / && runuser -u postgres -- psql -q -v ON_ERROR_STOP=1 "$@" )
}

guac_grants() {
  pg_sql -d "$GUAC_DB" <<EOF
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO ${GUAC_DB_USER};
GRANT SELECT,USAGE ON ALL SEQUENCES IN SCHEMA public TO ${GUAC_DB_USER};
EOF
}

guac_fetch_jdbc() {   # <version> <destination folder>
  local v=$1 name="guacamole-auth-jdbc-${1}"
  fetch_checked "${GUAC_DL}/${v}/binary/${name}.tar.gz" \
    "${GUAC_SUMS}/${v}/binary/${name}.tar.gz.sha256" sha256 "$2/${name}.tar.gz"
  tar -xzf "$2/${name}.tar.gz" -C "$2"
  [[ -d "$2/${name}/postgresql/schema" ]] || fail "${name}.tar.gz has no postgresql/schema."
}

guac_setup_db() {   # <version>
  local v=$1 tmp pw
  [[ -f "${GUAC_HOME}/guacamole.properties" ]] && return 0   # never overwrite
  tmp=$(mktemp -d)
  chmod 0755 "$tmp"
  step "Downloading the Guacamole database extension ${v}"
  guac_fetch_jdbc "$v" "$tmp"
  step "Creating the ${GUAC_DB} database"
  pw=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32) || true
  [[ ${#pw} -eq 32 ]] || fail "Could not generate a database password."
  pg_sql <<EOF
CREATE DATABASE ${GUAC_DB};
CREATE USER ${GUAC_DB_USER} WITH PASSWORD '${pw}';
EOF
  cat "${tmp}/guacamole-auth-jdbc-${v}/postgresql/schema/"*.sql |
    pg_sql -d "$GUAC_DB" -f - >/dev/null
  guac_grants
  guac_random_admin_password
  rm -rf "$tmp"
  (
    umask 027
    cat >"${GUAC_HOME}/guacamole.properties" <<EOF
# Apache Guacamole configuration, written by proxmox-recipes.
# Reference: https://guacamole.apache.org/doc/gug/configuring-guacamole.html
# After editing: systemctl restart guacamole-tomcat

# guacd, on this container only
guacd-hostname: 127.0.0.1
guacd-port: 4822

# Users and connections live in PostgreSQL
# (https://guacamole.apache.org/doc/gug/postgresql-auth.html)
postgresql-hostname: localhost
postgresql-port: 5432
postgresql-database: ${GUAC_DB}
postgresql-username: ${GUAC_DB_USER}
postgresql-password: ${pw}
EOF
  )
  chgrp "$TC_USER" "${GUAC_HOME}/guacamole.properties"
}

# The schema creates guacadmin with the well-known password 'guacadmin',
# which the manual says to change at once. Replace it with a random one
# before the web app ever starts. Guacamole stores
# SHA-256(password + uppercase hex salt), as in 002-create-admin-user.sql.
guac_random_admin_password() {
  local pw salt hash
  step "Setting a random password for guacadmin"
  pw=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20) || true
  salt=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n' | tr 'a-f' 'A-F')
  [[ ${#pw} -eq 20 && ${#salt} -eq 64 ]] || fail "Could not generate the guacadmin password."
  hash=$(printf '%s%s' "$pw" "$salt" | sha256sum | awk '{ print toupper($1) }')
  pg_sql -d "$GUAC_DB" <<EOF
UPDATE guacamole_user
   SET password_hash = decode('${hash}', 'hex'),
       password_salt = decode('${salt}', 'hex'),
       password_date = CURRENT_TIMESTAMP
 WHERE entity_id = (SELECT entity_id FROM guacamole_entity
                     WHERE name = 'guacadmin' AND type = 'USER');
EOF
  ( umask 077; printf '%s\n' "$pw" >"$GUAC_ADMIN_PW_FILE" )
}

# Run each schema/upgrade/upgrade-pre-<X>.sql with old < X <= new, in order.
guac_upgrade_db() {   # <old version> <new version>
  local old=$1 new=$2 tmp f x
  [[ -n "$old" ]] || fail "The installed Guacamole version is unknown (${GUAC_VERSION_FILE}); not upgrading the database."
  tmp=$(mktemp -d)
  chmod 0755 "$tmp"
  guac_fetch_jdbc "$new" "$tmp"
  while IFS= read -r f; do
    x=${f##*/upgrade-pre-}
    x=${x%.sql}
    if [[ "$(printf '%s\n%s\n' "$old" "$x" | sort -V | head -n 1)" == "$old" && "$x" != "$old" ]] &&
       [[ "$(printf '%s\n%s\n' "$x" "$new" | sort -V | tail -n 1)" == "$new" ]]; then
      step "Upgrading the database: ${f##*/}"
      pg_sql -d "$GUAC_DB" -f - <"$f" >/dev/null
    fi
  done < <(find "${tmp}/guacamole-auth-jdbc-${new}/postgresql/schema/upgrade" -name 'upgrade-pre-*.sql' | sort -V)
  guac_grants
  install -m 0644 "${tmp}/guacamole-auth-jdbc-${new}/postgresql/guacamole-auth-jdbc-postgresql-${new}.jar" \
    "${GUAC_HOME}/extensions/"
  find "${GUAC_HOME}/extensions" -name 'guacamole-auth-jdbc-postgresql-*.jar' \
    ! -name "guacamole-auth-jdbc-postgresql-${new}.jar" -delete
  rm -rf "$tmp"
}

guac_deploy_web() {   # <version>
  local v=$1 tmp
  tmp=$(mktemp -d)
  chmod 0755 "$tmp"
  step "Downloading the Guacamole web app ${v}"
  fetch_checked "${GUAC_DL}/${v}/binary/guacamole-${v}.war" \
    "${GUAC_SUMS}/${v}/binary/guacamole-${v}.war.sha256" sha256 "${tmp}/guacamole.war"
  if ! ls "${GUAC_HOME}/extensions/"guacamole-auth-jdbc-postgresql-*.jar >/dev/null 2>&1; then
    guac_fetch_jdbc "$v" "$tmp"
    install -m 0644 "${tmp}/guacamole-auth-jdbc-${v}/postgresql/guacamole-auth-jdbc-postgresql-${v}.jar" \
      "${GUAC_HOME}/extensions/"
  fi
  rm -rf "${TC_BASE}/webapps/guacamole"
  install -m 0640 -o "$TC_USER" -g "$TC_USER" "${tmp}/guacamole.war" "${TC_BASE}/webapps/guacamole.war"
  rm -rf "$tmp"
}

check_guacamole() {
  local i
  step "Waiting for Guacamole"
  for (( i = 0; i < 90; i++ )); do
    if systemctl is-active --quiet guacd && systemctl is-active --quiet guacamole-tomcat &&
      curl -fs -o /dev/null --max-time 3 "http://127.0.0.1:${GUAC_PORT}/guacamole/api/languages"; then
      return 0
    fi
    sleep 2
  done
  journalctl -u guacamole-tomcat -n 30 --no-pager >&2 || true
  fail "Guacamole's web UI did not come up on port ${GUAC_PORT}."
}
