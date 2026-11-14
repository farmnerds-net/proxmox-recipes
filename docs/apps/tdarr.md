# Tdarr

[Tdarr](https://tdarr.io/) transcodes and health-checks a media library.
It scans your folders and runs each file through a flow or plugin stack
that you choose, for example converting to HEVC, removing unwanted audio
or subtitle tracks, or checking for corrupt files. The work is done by
**Nodes**: one runs in this container, and you can add more on other
machines (for example a desktop with a GPU).

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/tdarr.sh)"
```

The recipe follows Tdarr's
[Linux install guide](https://docs.tdarr.io/docs/installation/windows-linux-macos)
and asks no questions. It:

- installs `mkvtoolnix` and `handbrake-cli` from Debian, which the guide
  lists for Tdarr's startup tests (FFmpeg comes bundled with Tdarr)
- downloads the official `Tdarr_Updater` to `/opt/tdarr` and runs it. The
  Updater downloads the latest `Tdarr_Server` and `Tdarr_Node` next to
  itself and checks their SHA-256 hashes
- generates a random API key and sets it as `seededApiKey` before the
  server first starts, as Tdarr's
  [authentication docs](https://docs.tdarr.io/docs/other/authentication)
  recommend. Otherwise, the first person to open the web UI could create
  the admin account
- creates and starts two systemd services: `tdarr-server` and `tdarr-node`
  (the internal Node, which connects with the same API key)

Both services run as root inside the unprivileged container, so they can
read and write whatever media you bind-mount in.

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 4 cores (the internal Node transcodes on the CPU) |
| Memory    | 4 GB                              |
| Disk      | 16 GB                             |
| Network   | DHCP on `vmbr0`                   |

## After install

The container's **Notes** in the Proxmox UI have a direct link to the web
UI, `http://<container-ip>:8265/`.

### 1. Sign in

Tdarr created an `admin` user. Its password is the seeded API key. Read it
on the host with:

```bash
pct exec <id> -- cat /etc/tdarr/server.env
```

Sign in as `admin` with the value after `seededApiKey=`, then change the
password in Tdarr. The API key keeps working after you change the
password, and the internal Node uses it.

### 2. Give the container your media

The recipe does not change host config, so it does not mount your media.
Add a bind mount from the host, with the container stopped or running:

```bash
pct set <id> -mp0 /path/on/host,mp=/media
pct reboot <id>
```

In an unprivileged container, root is uid 100000 on the host. Tdarr
rewrites files, so the host folder must be writable by that uid (or by a
group it belongs to). For a network share mounted on the host, mount it
with `uid=100000,gid=100000`.

### 3. Add a library

In the web UI, go to **Libraries**, add `/media` (or a folder in it) as the
source and `/opt/tdarr/cache` as the transcode cache. The cache uses the
container's disk. For a large library, bind-mount a bigger, fast disk (an
NVMe dataset is ideal) and use that instead:

```bash
pct set <id> -mp1 /path/on/fast/disk,mp=/cache
```

Then choose a flow or plugins and start a scan. To try a flow on a few
files first, turn off folder watching and the scheduled scan.

### Hardware transcoding

The internal Node uses the CPU (x264, x265 and SVT-AV1 all pass Tdarr's
encoder test). A GPU needs to be passed in from the host. That is a
host-side change the recipe doesn't make. Adding another Node on a machine
that already has a GPU is often easier: install Tdarr_Node there and point
it at `http://<container-ip>:8266` with the same API key. The Server and
every Node must see the media and the cache at the same paths, or have
`pathTranslators` set in that Node's config (see Tdarr's install guide).

### Closed-caption check

At startup the Node log shows `Scanner test 4: CCExtractor not working`.
Tdarr bundles a CCExtractor that needs `libtesseract.so.4`, and Debian
ships version 5. Tdarr notes that CCExtractor is only used to detect
closed captions, so everything else works. The recipe doesn't add an
unsupported workaround for it.

## Ports and config

| Port | Use                                      |
| ---- | ---------------------------------------- |
| 8265 | Web UI                                   |
| 8266 | Server: Nodes on other machines connect here |

| Path | What |
| ---- | ---- |
| `/opt/tdarr/configs/Tdarr_Server_Config.json` | Server settings (ports, auth) |
| `/opt/tdarr/configs/Tdarr_Node_Config.json` | Internal Node settings |
| `/etc/tdarr/server.env` | `seededApiKey` (root only) |
| `/etc/tdarr/node.env` | Internal Node's `apiKey`, `nodeName` and `serverURL` (root only) |
| `/opt/tdarr/server/` | Tdarr's database, plugins and backups |
| `/opt/tdarr/logs/` | Server, Node and Updater logs |

Environment variables override the JSON files, so the Node's API key,
name and server URL are set in `/etc/tdarr/node.env`, not the JSON. After
editing either file: `systemctl restart tdarr-server tdarr-node`.

To stop using the internal Node (e.g. when only GPU Nodes should work):
`systemctl disable --now tdarr-node`.

## Updating

Inside the container:

```bash
recipe update
```

This upgrades the OS packages, stops Tdarr, runs `Tdarr_Updater` again
(it keeps the old version until the new one is in place) and starts Tdarr.
To pin a version, set `requiredVersion` for both modules in
`/opt/tdarr/configs/Tdarr_Updater_Config.json` (default `"latest"`).

## Upstream docs

- [Install on Linux](https://docs.tdarr.io/docs/installation/windows-linux-macos)
- [Authentication](https://docs.tdarr.io/docs/other/authentication)
- [Configuration variables](https://docs.tdarr.io/docs/installation/configuration-variables)
