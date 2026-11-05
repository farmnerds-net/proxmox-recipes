# shellcheck shell=bash
#
# install/documenso.sh - Documenso, an open-source document signing app
# (an alternative to DocuSign), with PostgreSQL in the same container.
#
# Runs inside the container, sourced by misc/install.func. Follows
# Documenso's official documentation:
#
#   Install:  https://docs.documenso.com/docs/self-hosting/deployment/manual
#             (Node.js 24+, npm 11.17+, PostgreSQL 14+; clone the repo,
#             'cp .env.example .env', set the required variables, then
#             'npm ci', 'npm run build', 'npm run prisma:migrate-deploy',
#             and a systemd unit running as www-data that loads the .env
#             with EnvironmentFile). The recipe builds the latest release
#             tag, not the main branch, and builds only the app: the
#             guide's 'npm run build' runs 'turbo run build' for every
#             workspace, including the docs website, which runs a 4 GB
#             container out of memory. The repo's own package.json "ci"
#             script builds the app with
#             'turbo run build --filter=@documenso/remix'; the recipe does
#             the same.
#   Env:      https://docs.documenso.com/docs/self-hosting/configuration/environment
#             (required variables; secrets of at least 32 characters, made
#             with 'openssl rand')
#   Signing:  https://docs.documenso.com/docs/self-hosting/configuration/signing-certificate/local
#             (self-signed .p12 from openssl genrsa / req -x509 / pkcs12
#             -export with a password; NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH
#             and NEXT_PRIVATE_SIGNING_PASSPHRASE)
#   Node.js:  https://nodejs.org/en/download (official prebuilt Linux
#             binaries, checked against the release's SHASUMS256.txt). The
#             major version comes from the release's package.json "engines".
#
# Two differences from the manual guide's unit file, both taken from how
# upstream itself starts the app ('npm run start' in apps/remix, and
# docker/start.sh):
#   - WorkingDirectory is apps/remix. The server serves its static files
#     from 'build/client' relative to the working directory, so the guide's
#     repo-root WorkingDirectory serves pages without their CSS and JS.
#   - NODE_ENV=production is set, as apps/remix's start script does.
#
# Updates build the new release in a separate directory and only swap it
# in once the build has succeeded, so a failed build leaves the running
# version alone.
#
# Email is not set up: Documenso needs an SMTP server to send signing
# requests. The SMTP settings are in the .env (see docs/apps/documenso.md).

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="3000/tcp (web UI), 5432 on 127.0.0.1 only (PostgreSQL)"
  APP_CONFIG="/var/www/documenso/.env (all settings, including SMTP and secrets); signing certificate /etc/documenso/cert.p12"
}

DOCUMENSO_REPO="https://github.com/documenso/documenso.git"
DOCUMENSO_API="https://api.github.com/repos/documenso/documenso/releases/latest"
DOCUMENSO_DIR="/var/www/documenso"
DOCUMENSO_ENV="${DOCUMENSO_DIR}/.env"
DOCUMENSO_ETC="/etc/documenso"
DOCUMENSO_CERT="${DOCUMENSO_ETC}/cert.p12"
DOCUMENSO_UNIT="/etc/systemd/system/documenso.service"
DOCUMENSO_USER="www-data"
DOCUMENSO_DB="documenso"
NODE_DIR="/opt/nodejs"
NODE_DIST="https://nodejs.org/dist"

# Build tools: no telemetry from Turborepo or Next.js tooling.
export TURBO_TELEMETRY_DISABLED=1 NEXT_TELEMETRY_DISABLED=1 DO_NOT_TRACK=1

app_install() {
  local tag
  apt_quiet install --no-install-recommends git openssl xz-utils postgresql
  tag=$(documenso_latest_tag)
  documenso_build "$tag" "$DOCUMENSO_DIR"
  setup_database
  make_signing_cert
  write_env
  documenso_migrate "$DOCUMENSO_DIR"
  write_unit
  systemctl daemon-reload
  systemctl enable --now documenso
  check_documenso
}

app_update() {
  local latest current new old
  latest=$(documenso_latest_tag)
  current=$(app_version)
  if [[ "v${current}" == "$latest" ]]; then
    msg "Documenso ${current} is already the latest release."
    return 0
  fi
  step "Updating Documenso ${current} -> ${latest}"
  new="${DOCUMENSO_DIR}.new"
  old="${DOCUMENSO_DIR}.old"
  rm -rf -- "$new" "$old"
  documenso_build "$latest" "$new"
  install -m 0640 -o root -g "$DOCUMENSO_USER" "$DOCUMENSO_ENV" "${new}/.env"

  step "Switching to Documenso ${latest}"
  systemctl stop documenso
  if ! documenso_migrate "$new"; then
    systemctl start documenso
    fail "The database update for ${latest} failed; Documenso ${current} is still running."
  fi
  mv -- "$DOCUMENSO_DIR" "$old"
  mv -- "$new" "$DOCUMENSO_DIR"
  write_unit
  systemctl daemon-reload
  systemctl start documenso
  check_documenso
  rm -rf -- "$old"
}

app_web() {
  local port
  port=$(env_get PORT)
  printf 'http %s /\n' "${port:-3000}"
}

app_version() {
  sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "${DOCUMENSO_DIR}/package.json" 2>/dev/null | head -n 1
}

# ---- release and Node.js ----------------------------------------------------

documenso_latest_tag() {
  local tag
  tag=$(curl -fsSL --retry 2 --max-time 30 "$DOCUMENSO_API" |
    sed -n 's/^ *"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
  [[ "$tag" =~ ^v[0-9]+(\.[0-9]+)+$ ]] || fail "Could not find Documenso's latest release on GitHub."
  printf '%s' "$tag"
}

node_arch() {
  case "$(dpkg --print-architecture)" in
    amd64) printf 'x64' ;;
    arm64) printf 'arm64' ;;
    *) fail "No Node.js build for architecture $(dpkg --print-architecture)." ;;
  esac
}

node_major_for() {   # <checkout> -> the Node.js major its package.json asks for
  local major
  major=$(sed -n 's/^ *"node": *"[^0-9]*\([0-9][0-9]*\).*/\1/p' "$1/package.json" | head -n 1)
  [[ "$major" =~ ^[0-9]+$ ]] || fail "Could not read the Node.js version from Documenso's package.json."
  printf '%s' "$major"
}

# Installs the latest Node.js <major>.x to /opt/nodejs, unless it is
# already there.
node_install() {   # <major>
  local major=$1 base tmp pkg have=""
  base="${NODE_DIST}/latest-v${major}.x"
  tmp=$(mktemp -d)
  curl -fsSL --retry 2 --max-time 30 -o "${tmp}/SHASUMS256.txt" "${base}/SHASUMS256.txt"
  pkg=$(awk -v a="linux-$(node_arch).tar.xz" '$2 ~ ("^node-v[0-9.]+-" a "$") { print $2; exit }' "${tmp}/SHASUMS256.txt")
  [[ -n "$pkg" ]] || { rm -rf "$tmp"; fail "Could not find Node.js ${major} for $(node_arch)."; }
  [[ -x "${NODE_DIR}/bin/node" ]] && have=$("${NODE_DIR}/bin/node" --version)
  if [[ "$pkg" == "node-${have}-linux-$(node_arch).tar.xz" ]]; then
    rm -rf "$tmp"
    return 0
  fi
  step "Installing Node.js ${pkg#node-}"
  curl -fsSL --retry 2 --max-time 300 -o "${tmp}/${pkg}" "${base}/${pkg}"
  ( cd "$tmp" && grep "  ${pkg}\$" SHASUMS256.txt | sha256sum -c --quiet - ) ||
    { rm -rf "$tmp"; fail "Checksum mismatch for ${pkg}; not installing it."; }
  rm -rf -- "${NODE_DIR}.new"
  mkdir -p "${NODE_DIR}.new"
  tar -C "${NODE_DIR}.new" --strip-components=1 -xJf "${tmp}/${pkg}"
  rm -rf -- "$NODE_DIR"
  mv -- "${NODE_DIR}.new" "$NODE_DIR"
  ln -sf "${NODE_DIR}/bin/node" /usr/local/bin/node
  ln -sf "${NODE_DIR}/bin/npm" /usr/local/bin/npm
  ln -sf "${NODE_DIR}/bin/npx" /usr/local/bin/npx
  rm -rf "$tmp"
}

# ---- build ------------------------------------------------------------------

# Node.js caps its heap at about half the container's memory, which is too
# little for the build's TypeScript check. Let it use all but 1 GB.
build_heap_mb() {
  local mem_mb
  mem_mb=$(awk '$1 == "MemTotal:" { print int($2 / 1024) }' /proc/meminfo)
  (( mem_mb - 1024 > 2048 )) || fail "The build needs at least 3 GB of memory; this container has ${mem_mb} MB."
  printf '%s' $(( mem_mb - 1024 ))
}

documenso_build() {   # <tag> <directory>
  local tag=$1 dir=$2 heap
  heap=$(build_heap_mb)
  step "Downloading Documenso ${tag}"
  git clone --quiet --depth 1 --branch "$tag" "$DOCUMENSO_REPO" "$dir"
  node_install "$(node_major_for "$dir")"
  step "Installing Documenso's dependencies (npm ci)"
  ( cd "$dir" && npm ci --no-audit --no-fund )
  step "Building Documenso (this takes several minutes)"
  ( cd "$dir" && NODE_OPTIONS="--max-old-space-size=${heap}" \
      npx --no-install turbo run build --filter=@documenso/remix )
  [[ -f "${dir}/apps/remix/build/server/main.js" ]] || fail "The build did not produce apps/remix/build/server/main.js."
}

documenso_migrate() {   # <directory>
  step "Updating the database schema"
  ( cd "$1" && npm run prisma:migrate-deploy )
}

# ---- configuration ----------------------------------------------------------

random_hex() { openssl rand -hex 32; }

setup_database() {
  local pass
  step "Creating the PostgreSQL database"
  systemctl enable --now postgresql
  pass=$(random_hex)
  if runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DOCUMENSO_DB}'" | grep -q 1; then
    runuser -u postgres -- psql -q -c "ALTER ROLE ${DOCUMENSO_DB} WITH LOGIN PASSWORD '${pass}'"
  else
    runuser -u postgres -- psql -q -c "CREATE ROLE ${DOCUMENSO_DB} WITH LOGIN PASSWORD '${pass}'"
  fi
  if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DOCUMENSO_DB}'" | grep -q 1; then
    runuser -u postgres -- createdb -O "$DOCUMENSO_DB" "$DOCUMENSO_DB"
  fi
  DOCUMENSO_DB_URL="postgres://${DOCUMENSO_DB}:${pass}@127.0.0.1:5432/${DOCUMENSO_DB}"
}

make_signing_cert() {
  local tmp
  step "Creating a self-signed signing certificate"
  install -d -m 0750 -o root -g "$DOCUMENSO_USER" "$DOCUMENSO_ETC"
  DOCUMENSO_CERT_PASS=$(random_hex)
  tmp=$(mktemp -d)
  openssl genrsa -out "${tmp}/private.key" 2048 2>/dev/null
  openssl req -new -x509 -key "${tmp}/private.key" -out "${tmp}/certificate.crt" -days 3650 \
    -subj "/O=Documenso on $(hostname)/CN=$(hostname) self-signed signing certificate"
  CERT_PASS=$DOCUMENSO_CERT_PASS openssl pkcs12 -export -out "${tmp}/certificate.p12" \
    -inkey "${tmp}/private.key" -in "${tmp}/certificate.crt" -password env:CERT_PASS
  install -m 0640 -o root -g "$DOCUMENSO_USER" "${tmp}/certificate.p12" "$DOCUMENSO_CERT"
  rm -rf "$tmp"
}

env_set() {   # <key> <value>: set KEY="value" in the .env, adding it if missing
  local key=$1 line
  line="${key}=\"$2\""
  if grep -q "^${key}=" "$DOCUMENSO_ENV"; then
    KEY=$key LINE=$line awk '
      index($0, ENVIRON["KEY"] "=") == 1 { print ENVIRON["LINE"]; next } { print }
    ' "$DOCUMENSO_ENV" >"${DOCUMENSO_ENV}.tmp"
    cat "${DOCUMENSO_ENV}.tmp" >"$DOCUMENSO_ENV"
    rm -f "${DOCUMENSO_ENV}.tmp"
  else
    printf '%s\n' "$line" >>"$DOCUMENSO_ENV"
  fi
}

env_get() {   # <key> -> its value in the .env, quotes removed
  sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$DOCUMENSO_ENV" 2>/dev/null | tail -n 1
}

write_env() {
  local ip
  step "Writing ${DOCUMENSO_ENV}"
  ip=$(ct_ipv4)
  ip=${ip%% *}
  install -m 0640 -o root -g "$DOCUMENSO_USER" "${DOCUMENSO_DIR}/.env.example" "$DOCUMENSO_ENV"
  env_set NEXTAUTH_SECRET "$(random_hex)"
  env_set NEXT_PRIVATE_ENCRYPTION_KEY "$(random_hex)"
  env_set NEXT_PRIVATE_ENCRYPTION_SECONDARY_KEY "$(random_hex)"
  env_set NEXT_PUBLIC_WEBAPP_URL "http://${ip:-localhost}:3000"
  env_set NEXT_PRIVATE_INTERNAL_WEBAPP_URL "http://localhost:3000"
  env_set PORT "3000"
  env_set NEXT_PRIVATE_DATABASE_URL "$DOCUMENSO_DB_URL"
  env_set NEXT_PRIVATE_DIRECT_DATABASE_URL "$DOCUMENSO_DB_URL"
  env_set NEXT_PRIVATE_SIGNING_TRANSPORT "local"
  env_set NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH "$DOCUMENSO_CERT"
  env_set NEXT_PRIVATE_SIGNING_PASSPHRASE "$DOCUMENSO_CERT_PASS"
}

write_unit() {
  cat >"$DOCUMENSO_UNIT" <<EOF
# Written by proxmox-recipes, from Documenso's manual deployment guide:
#   https://docs.documenso.com/docs/self-hosting/deployment/manual
# Settings live in ${DOCUMENSO_ENV}; after editing it:
#   systemctl restart documenso
[Unit]
Description=Documenso
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=${DOCUMENSO_USER}
WorkingDirectory=${DOCUMENSO_DIR}/apps/remix
EnvironmentFile=${DOCUMENSO_ENV}
Environment=NODE_ENV=production
ExecStart=${NODE_DIR}/bin/node build/server/main.js
TimeoutSec=15
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

check_documenso() {
  local i port
  port=$(env_get PORT)
  port=${port:-3000}
  step "Waiting for Documenso to start"
  for (( i = 0; i < 90; i++ )); do
    if systemctl is-active --quiet documenso &&
      curl -fs -o /dev/null --max-time 5 "http://127.0.0.1:${port}/api/health"; then
      return 0
    fi
    sleep 2
  done
  journalctl -u documenso -n 30 --no-pager >&2 || true
  fail "Documenso did not start (no answer on port ${port})."
}
