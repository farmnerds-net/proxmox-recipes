# shellcheck shell=bash
#
# install/authelia.sh - Authelia, a single sign-on and two-factor
# authentication portal that sits behind your reverse proxy.
#
# Runs inside the container, sourced by misc/install.func. Follows
# Authelia's official documentation:
#
#   Install:  https://www.authelia.com/integration/deployment/bare-metal/
#             (the authelia-security.gpg key in /usr/share/keyrings, the
#             'apt.authelia.com stable main' repository, then
#             'apt install authelia'; the package ships the systemd unit,
#             an 'authelia' user and /etc/authelia/configuration.yml)
#   Config:   https://www.authelia.com/integration/prologue/get-started/
#             (the required sections: secrets, authentication_backend,
#             storage, session cookies, notifier, access_control)
#   Session:  https://www.authelia.com/configuration/session/introduction/
#             (cookie domain and https authelia_url rules)
#   Users:    https://www.authelia.com/configuration/first-factor/file/
#   Secrets:  https://www.authelia.com/configuration/methods/secrets/
#             (AUTHELIA_<KEY>_FILE environment variables), values from
#             'authelia crypto rand'
#
# The secrets live in /var/lib/authelia/secrets, not under /etc/authelia:
# the package's tmpfiles rule resets everything under /etc/authelia to mode
# 0640 at boot, which would make a directory there unreadable.
#
# App options (from ct/authelia.sh):
#   AUTHELIA_URL   the portal's public https URL, e.g. https://auth.example.com

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="9091/tcp (portal, put it behind your HTTPS reverse proxy)"
  APP_CONFIG="/etc/authelia/configuration.yml, users in /etc/authelia/users_database.yml; admin password in /root/authelia-admin-password"
}

AU_KEYRING="/usr/share/keyrings/authelia-security.gpg"
AU_KEY_URL="https://www.authelia.com/keys/authelia-security.gpg"
AU_ETC="/etc/authelia"
AU_CONF="${AU_ETC}/configuration.yml"
AU_USERS="${AU_ETC}/users_database.yml"
AU_LIB="/var/lib/authelia"
AU_SECRETS="${AU_LIB}/secrets"
AU_DROPIN="/etc/systemd/system/authelia.service.d/proxmox-recipes.conf"
AU_ADMIN_PASS="/root/authelia-admin-password"
AU_PORT=9091

app_install() {
  local url=${AUTHELIA_URL:?AUTHELIA_URL is not set} cookie_domain
  cookie_domain=$(authelia_cookie_domain "$url")

  step "Adding Authelia's apt repository"
  curl -fsSL --retry 2 --max-time 30 -o "$AU_KEYRING" "$AU_KEY_URL"
  printf 'deb [arch=%s signed-by=%s] https://apt.authelia.com stable main\n' \
    "$(dpkg --print-architecture)" "$AU_KEYRING" >/etc/apt/sources.list.d/authelia.list
  apt_quiet update
  step "Installing Authelia"
  apt_quiet install authelia

  install -d -m 0750 -o authelia -g authelia "$AU_LIB"
  write_secrets
  write_users "$cookie_domain"
  write_config "$url" "$cookie_domain"
  write_dropin
  step "Checking the configuration"
  authelia_validate
  systemctl daemon-reload
  systemctl enable authelia
  systemctl restart authelia
  check_authelia
}

# Authelia comes from its apt repository, so 'recipe update' has already
# upgraded it with the OS packages (keeping the recipe's configuration.yml).
app_update() {
  step "Checking the configuration"
  authelia_validate
  systemctl restart authelia
  check_authelia
}

app_version() {
  dpkg-query -W -f '${Version}' authelia 2>/dev/null
}

# https://auth.example.com -> example.com; https://example.com -> example.com
authelia_cookie_domain() {   # <url>
  local host=${1#https://}
  host=${host%%/*}
  host=${host%%:*}
  if [[ "${host#*.}" == *.* ]]; then
    printf '%s' "${host#*.}"
  else
    printf '%s' "$host"
  fi
}

authelia_validate() {
  runuser -u authelia -- env \
    AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE="${AU_SECRETS}/jwt" \
    AUTHELIA_SESSION_SECRET_FILE="${AU_SECRETS}/session" \
    AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE="${AU_SECRETS}/storage" \
    authelia validate-config --config "$AU_CONF"
}

write_secrets() {
  local name
  step "Generating secrets"
  install -d -m 0700 -o authelia -g authelia "$AU_SECRETS"
  for name in jwt session storage; do
    [[ -s "${AU_SECRETS}/${name}" ]] && continue   # never replace a secret
    authelia crypto rand --length 64 --charset alphanumeric |
      sed -n 's/^Random Value: //p' >"${AU_SECRETS}/${name}"
    [[ -s "${AU_SECRETS}/${name}" ]] || fail "Could not generate the ${name} secret."
    chown authelia:authelia "${AU_SECRETS}/${name}"
    chmod 0400 "${AU_SECRETS}/${name}"
  done
}

write_users() {   # <cookie domain>
  local out pass digest
  [[ -s "$AU_USERS" ]] && return 0   # never overwrite existing users
  step "Creating the admin user"
  out=$(authelia crypto hash generate argon2 --random --random.length 24)
  pass=$(sed -n 's/^Random Password: //p' <<<"$out")
  digest=$(sed -n 's/^Digest: //p' <<<"$out")
  # shellcheck disable=SC2016  # a literal $argon2id$ prefix
  [[ -n "$pass" && "$digest" == '$argon2id$'* ]] || fail "Could not create the admin password."
  (umask 077; printf '%s\n' "$pass" >"$AU_ADMIN_PASS")
  cat >"$AU_USERS" <<EOF
# Authelia users. Docs: https://www.authelia.com/reference/guides/passwords/
# Make a password hash with: authelia crypto hash generate argon2
# Authelia reloads this file when it changes (watch: true).
users:
  admin:
    disabled: false
    displayname: 'Administrator'
    password: '${digest}'
    email: 'admin@$1'
    groups:
      - 'admins'
EOF
  chown authelia:authelia "$AU_USERS"
  chmod 0640 "$AU_USERS"
}

write_config() {   # <url> <cookie domain>
  local url=$1 domain=$2
  step "Writing ${AU_CONF} for ${url}"
  [[ -f "${AU_CONF}.dist" ]] || cp -p "$AU_CONF" "${AU_CONF}.dist"
  cat >"$AU_CONF" <<EOF
# Authelia configuration, written by proxmox-recipes.
# Full reference (the packaged example): ${AU_CONF}.dist
# Docs: https://www.authelia.com/configuration/prologue/introduction/
# Secrets (JWT, session, storage key) are loaded from files in
# ${AU_SECRETS} by ${AU_DROPIN}.
# After editing: systemctl restart authelia

server:
  address: 'tcp://:${AU_PORT}/'

log:
  level: 'info'

totp:
  issuer: '${domain}'

authentication_backend:
  file:
    path: '${AU_USERS}'
    watch: true

access_control:
  default_policy: 'deny'
  rules:
    - domain: '*.${domain}'
      policy: 'one_factor'

session:
  cookies:
    - domain: '${domain}'
      authelia_url: '${url}'

storage:
  local:
    path: '${AU_LIB}/db.sqlite3'

notifier:
  filesystem:
    filename: '${AU_LIB}/notification.txt'
EOF
  chown authelia:authelia "$AU_CONF"
  chmod 0440 "$AU_CONF"
}

write_dropin() {
  install -d -m 0755 "${AU_DROPIN%/*}"
  cat >"$AU_DROPIN" <<EOF
# Written by proxmox-recipes: load Authelia's secrets from files, as in
# https://www.authelia.com/configuration/methods/secrets/
[Service]
Environment=AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE=${AU_SECRETS}/jwt
Environment=AUTHELIA_SESSION_SECRET_FILE=${AU_SECRETS}/session
Environment=AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE=${AU_SECRETS}/storage
EOF
}

check_authelia() {
  local i
  step "Waiting for Authelia to start"
  for (( i = 0; i < 30; i++ )); do
    if systemctl is-active --quiet authelia &&
      curl -fs --max-time 3 "http://127.0.0.1:${AU_PORT}/api/health" | grep -q '"OK"'; then
      return 0
    fi
    sleep 2
  done
  journalctl -u authelia -n 20 --no-pager >&2 || true
  fail "Authelia did not start (no answer on port ${AU_PORT})."
}
