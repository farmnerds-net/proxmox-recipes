# proxmox-recipes

Recipes that install self-hosted apps into Proxmox LXC containers.

## Scope

Debian LXC containers only. Apps are installed natively using a method the
app's upstream officially documents: their apt repo or .deb, official release
binaries, documented build-from-source steps, or their own installer. No
Docker, no Podman, no undocumented workarounds. If an app doesn't have an
official native install path, it doesn't belong in this repo.

## Usage

Run this on the Proxmox host shell, replacing `<app>` with the recipe you want:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/<app>.sh)"
```

> **Warning:** Recipes run as **root on your Proxmox host**. A recipe can do
> anything root can do, so read it before you run it. Never pipe a script you
> haven't looked at into your hypervisor.

### Updating an app

Inside any container built by a recipe:

```bash
recipe update
```

That upgrades the OS packages and the app. `recipe info` shows the app's
version, IP, ports and where its config lives.

## Layout

- `ct/` — host-side recipe, one per app. Runs on the Proxmox host and creates
  the LXC container.
- `install/` — the install script for each app. Runs *inside* the new
  container.
- `misc/` — the shared engine used by the recipes:
  - `build.func`
  - `install.func`
  - `tools.func`
  - `core.func`

## Credits

Inspired by
[community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE).
The engine here is written from scratch.

## License

[MIT](LICENSE)
