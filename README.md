# proxmox-recipes

Recipes that install self-hosted apps into Proxmox LXC containers.

## Usage

Run this on the Proxmox host shell, replacing `<app>` with the recipe you want:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/<app>.sh)"
```

> **Warning:** Recipes run as **root on your Proxmox host**. A recipe can do
> anything root can do, so read it before you run it. Never pipe a script you
> haven't looked at into your hypervisor.

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

Inspired by and partly adapted from
[community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)
(MIT). Adapted files keep their original copyright notice.

## License

[MIT](LICENSE)
