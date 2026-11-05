# proxmox-recipes

Recipes that install self-hosted apps into Proxmox LXC containers.

## Scope

Debian LXC containers only. Apps are installed natively using a method the
app's upstream officially documents: their apt repo or .deb, official release
binaries, documented build-from-source steps, or their own installer. No
Docker, no Podman, no undocumented workarounds. If an app doesn't have an
official native install path, it doesn't belong in this repo.

## Apps

| App | Recipe | Notes |
| --- | ------ | ----- |
| [Debian](docs/apps/debian.md) | `debian` | Plain Debian 12, no app |
| [Pi-hole](docs/apps/pihole.md) | `pihole` | Optional Unbound. Pi-hole's installer asks its own questions |
| [AdGuard Home](docs/apps/adguardhome.md) | `adguardhome` | No questions; finish setup in its web wizard on port 3000 |
| [Blocky](docs/apps/blocky.md) | `blocky` | No questions and no web UI; settings in one YAML file |
| [Unbound](docs/apps/unbound.md) | `unbound` | Recursive DNS with DNSSEC for your LAN; no questions, no web UI |
| [CoreDNS](docs/apps/coredns.md) | `coredns` | Plugin-based DNS server; no questions, no web UI, settings in the Corefile |
| [PowerDNS](docs/apps/powerdns.md) | `powerdns` | Recursor + Authoritative Server with a local `home.arpa` zone and HTTP API; no questions |

## Usage

Run this on the Proxmox host shell, replacing `<app>` with the recipe you want:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/<app>.sh)"
```

> **Warning:** Recipes run as **root on your Proxmox host**. A recipe can do
> anything root can do, so read it before you run it. Never pipe a script you
> haven't looked at into your hypervisor.

Each recipe asks how to set up the container: **Default** accepts the
recipe's defaults, **Advanced** lets you choose the container ID, hostname,
CPU, memory, disk, storage, bridge, DHCP or static IP, VLAN, DNS, root
password or SSH key, and start on boot. Containers are always unprivileged.

When a recipe finishes, the container's **Notes** (its Summary page in the
Proxmox UI) show the app name, a clickable link to the web UI built from the
app's real IP and port, and a short table: the container's IP, how to
update, and a link to the app's doc. (`recipe info` inside the container
shows ports and config files.) The notes are
written once, at install; if you later change the app's port or IP, edit
them by hand.

### Inside the container: the `recipe` command

```bash
recipe update   # upgrade the OS packages, then the app
recipe info     # app, version, IP, ports, config location
recipe help
```

`recipe update` also appends its output to `/var/log/recipe/update.log`.

### Logs and failures

Each run logs to `/var/log/proxmox-recipes/<app>-<ctid>.log` on the host.
If a step fails, the recipe shows which step and the end of the log, then
asks whether to destroy the half-built container. Cancelling before the
container is created leaves nothing behind.

### Presets (skipping questions)

Every question is backed by a plain variable, and a question is skipped
when its variable is already set. The full list is at the top of
[`misc/build.func`](misc/build.func); app options are listed in each app's
doc. For example:

```bash
SETUP_MODE=default CT_ID=150 bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/debian.sh)"
```

### Testing a branch or a local checkout

```bash
RECIPES_REF=<branch> bash ct/<app>.sh            # engine and scripts from that branch
RECIPES_SRC=/path/to/checkout bash ct/<app>.sh   # host side from local files
```

With `RECIPES_REF`, the container's `recipe update` keeps following that
branch.

## Layout

- `ct/` — host-side recipe, one per app. Runs on the Proxmox host and creates
  the LXC container.
- `install/` — the install script for each app. Runs *inside* the new
  container.
- `misc/` — the shared engine used by the recipes:
  - `core.func` — output, logging, error handling, preflight checks
  - `build.func` — host side: menus, template, `pct create`, install, summary
  - `install.func` — container side: OS setup, app install, the `recipe`
    command
- `docs/apps/` — one page per app.

## Support

If these recipes save you time, you can
[support farmnerds on Ko-fi](https://ko-fi.com/farmnerds). Every container
built by a recipe also has this link near the top of its Notes.

## Credits

Inspired by
[community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE).
The engine here is written from scratch.

## License

[MIT](LICENSE)
