# Debian

A plain Debian 12 container with no app installed: a clean base to build on,
with the `recipe` command for keeping it up to date.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/debian.sh)"
```

Choose **Default** to accept the defaults, or **Advanced** to set every
option yourself.

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 1 core                            |
| Memory    | 512 MB (+ 512 MB swap)            |
| Disk      | 4 GB                              |
| Network   | DHCP on `vmbr0`                   |
| Root login| none (use `pct enter <id>`)       |

## What gets installed

Only what every recipe installs: the latest Debian 12 packages
(`apt full-upgrade`), `ca-certificates`, `curl`, the C.UTF-8 locale and the
`recipe` command.

## Ports and config

None. There is no app.

## Updating

Inside the container:

```bash
recipe update
```

This runs `apt update && apt full-upgrade`. There is no app to update.
