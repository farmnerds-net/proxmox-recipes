# proxmox-recipes

So this started out as, really, an admiration of 1st off the original site I came across that had Proxmox helper scripts. https://tteck.github.io/Proxmox/ r.i.p 
and then over time I was searching for more containers, more VM's that were just a simple copy-paste script to get an app up and running quickly.
Then the community scripts came on the scene and was growing very rapidly. https://community-scripts.org 
And then just out of sheer curiosity and want, I wanted to try to replicate with some GitHub repos that weren't on the main helper scripts page yet. I figured out how to get a script going, decided for the time being I only wanted LXC's. No VM's yet, and I was making only installers for repos that I personally wanted to list out.

Only GitHub repos.

Only Debian for now.

Only native / bare-metal installs, no dockers.

Only OFFICIAL native installs for the time being.

I decided I will have an 'experimental' repo for apps that may get "undockerised" for native-install. Essentially non-official documented install scripts would be classified, to me, as experimental.

I run every one of them individually before posting simply to make sure the container comes up and the app works.
So that is where I am with this. 
I hope someone gets something out of this outside of just myself. Enjoy.

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
| [Technitium DNS Server](docs/apps/technitium.md) | `technitium` | Recursive + authoritative DNS with ad blocking, all from a web console on port 5380; no questions |
| [cloudflared](docs/apps/cloudflared.md) | `cloudflared` | Cloudflare Tunnel connector; paste your tunnel token inside the container afterwards |
| [Documenso](docs/apps/documenso.md) | `documenso` | Document signing, built from source (slow install). Set up SMTP before signing up |
| [CrowdSec](docs/apps/crowdsec.md) | `crowdsec` | Central Local API for agents and bouncers on your network; asks whether to share signals (default no) |
| [Authelia](docs/apps/authelia.md) | `authelia` | Single sign-on / 2FA portal for apps behind your HTTPS reverse proxy; asks for the portal URL |
| [Caddy](docs/apps/caddy.md) | `caddy` | Reverse proxy with automatic HTTPS; no questions, sites in the Caddyfile. Pairs with Authelia |
| [FileFlows](docs/apps/fileflows.md) | `fileflows` | Flow-based file and media processing on Debian 13. No questions and no login (a paid feature), so keep it on a trusted network |
| [Apache Guacamole](docs/apps/guacamole.md) | `guacamole` | Remote desktop (RDP, VNC, SSH) in the browser, with users and connections in PostgreSQL. No questions; compiles guacd, so the install takes a few minutes |

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

### Recipes from another repo

The engine can also run recipes whose app files live in a different repo,
such as
[proxmox-recipes-experimental](https://github.com/farmnerds-net/proxmox-recipes-experimental).
Such a recipe sets `RECIPES_APP_REPO` to that repo. `misc/` still comes
from this repo; the install script, the docs link in the notes and the
container's `recipe update` use the other one. To test both from local
checkouts:

```bash
RECIPES_SRC=/path/to/proxmox-recipes RECIPES_APP_SRC=/path/to/other-repo bash ct/<app>.sh
```

`RECIPES_APP_REF` picks the other repo's branch (default `main`).

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
