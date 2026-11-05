# CLAUDE.md — proxmox-recipes

Read this before doing anything in this repo. These rules are not suggestions.

## What this repo is

Interactive recipes that create a Debian LXC container on a Proxmox VE host
and install one self-hosted app into it, natively. The engine in `misc/` is
written from scratch for this repo.

## Scope rules (hard)

- **Debian LXC only.** No Ubuntu, Alpine, or other templates.
- **Native installs only, using a method upstream officially documents:**
  their apt repo or .deb, official release binaries/tarballs, documented
  build-from-source steps, or their own official installer.
- **No Docker, no Podman, no container-in-container**, and no workarounds
  upstream doesn't document (e.g. extracting files from a container image,
  reverse-engineering a Dockerfile). If an app has no official native install
  path, it does not belong here. Stop and tell the user. Do not invent one.
- Before writing an app recipe, find and cite the upstream doc page the
  install follows (in a comment at the top of `install/<app>.sh`).

## Clean-room rule

The engine is original work. Do **not** copy code, function names, variable
names (e.g. `var_cpu`, `var_ram`), menu text, or flow from
community-scripts/ProxmoxVE or any other helper-script project. Don't read
their source while writing ours. General Proxmox knowledge (`pct`, `pveam`,
`pvesm`) is fine.

## Layout

- `ct/<app>.sh`: host-side recipe. Declares app metadata and defaults, then
  calls the engine. Runs on the Proxmox host as root.
- `install/<app>.sh`: runs inside the new container. Defines `app_install`
  and `app_update`.
- `misc/core.func`: colors, messages, spinner, error trap, logging, preflight
  checks (root, PVE version, arch, internet).
- `misc/build.func`: host side. Menus, template download (`pveam`),
  `pct create`, start, network wait, pushing and running the install script,
  summary screen, cleanup-on-failure.
- `misc/install.func`: container side. apt setup, locale/timezone, network
  check, installs the `recipe` command, writes `/etc/recipe/info`, cleanup.
- `misc/tools.func`: shared helpers (GitHub latest release, systemd unit
  writer, etc.). Add a helper only when a second recipe needs it.

## Engine design

- **Interactive via whiptail**, with two paths: *Default* (accept the
  recipe's defaults, minimal questions) and *Advanced* (CT ID, hostname,
  cores, RAM, disk, storage, bridge, DHCP/static IP + gateway, VLAN, DNS,
  root password or SSH key, start on boot).
- **Every menu answer is stored in a plain variable** and menus are skipped
  when that variable is already set. A future non-interactive repo will reuse
  this engine by pre-setting the variables, so never read input anywhere except
  the menu layer.
- **Unprivileged containers only** in v1.
- **Local source override:** recipes normally fetch `misc/` and `install/`
  from `https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/`.
  If `RECIPES_SRC` is set to a local path, load from disk instead. All
  testing uses `RECIPES_SRC`.
- **App repos:** a recipe may set `RECIPES_APP_REPO` (owner/name) to keep
  its `install/` and `docs/` in another repo that uses this engine, e.g.
  `farmnerds-net/proxmox-recipes-experimental`. Keep that working: the
  engine fetches `misc/` from here and app files with `app_fetch`, never
  the other way round. The scope rules above apply to this repo only.
- **Logging:** host log at `/var/log/proxmox-recipes/<app>-<ctid>.log`. On
  error, show the failing step and last log lines, then offer to destroy the
  half-built container.
- **No telemetry.** Nothing phones home, ever.
- Bash: `set -Eeuo pipefail`, quote everything, ShellCheck clean
  (`.func` files are checked as bash).

## The `recipe` command (inside every container)

Installed to `/usr/local/bin/recipe`.

- `recipe update`: `apt update && apt full-upgrade`, then fetches the latest
  `install/<app>.sh` from the repo and runs its `app_update`.
- `recipe info`: app, installed version, IP, ports, install date, where creds
  or config live.
- `recipe help`: usage.
- Reserved for later: `recipe logs`, `recipe backup`.

## Testing rules (hard)

Claude Code runs as root on a Proxmox host. Protect it.

- **Test on farmlab2 only**, never the production host.
- **Only create, modify, or destroy containers with IDs 900–999.** Never
  touch any other CT or VM, even to read-modify-write.
- **Never change host config:** no edits to `/etc/network/`, `/etc/pve/`
  (except the 9xx CTs `pct` itself manages), storage, firewall, or cluster
  settings. If a recipe seems to need that, stop and ask.
- Before `pct destroy`, confirm the ID is in 900–999.
- Destroy test containers once a test passes; leave a failing one up only if
  the user wants to inspect it.
- Test DNS apps (Pi-hole, Unbound) by querying the container directly
  (`dig @<ct-ip>`). Never point the network or host at a test DNS server.
- A stage is done only when ShellCheck passes **and** a real install on the
  host succeeds end to end.

## Git

- Work on a branch per stage (`stage-1-engine-core`, ...), push it, and open
  a PR to `main` for the user to review. Don't push straight to `main`.
- Commit messages: short imperative subject, body explains why.

## Roadmap

1. Engine core + `ct/debian.sh` (plain Debian container, no app).
2. `install.func` + `recipe` command; `recipe update` works on the Debian CT.
3. Pi-hole, with Unbound as an optional checkbox (per Pi-hole's official
   Unbound guide).
4. Polish: failure cleanup, logs, per-app README docs.
