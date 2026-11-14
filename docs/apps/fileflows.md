# FileFlows

[FileFlows](https://fileflows.com/) processes files with flows you build
in its web UI. It's most often used for media: converting video to HEVC
or AV1, removing unwanted audio and subtitle tracks, and renaming or
moving files once they're done. It can also run flows on any other kind
of file. The Server has a built-in processing node, and you can add more
machines as Agents.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/fileflows.sh)"
```

The recipe follows FileFlows'
[Linux install guide](https://fileflows.com/docs/installation/linux) and
[systemd guide](https://fileflows.com/docs/installation/linux/systemd-service).
It asks no questions. It:

- installs the .NET 10 SDK from
  [Microsoft's package repository](https://learn.microsoft.com/dotnet/core/install/linux-debian)
- installs FFmpeg from Debian (version 7.1 on Debian 13), which FileFlows
  finds on its own at `/usr/bin/ffmpeg`
- downloads the latest FileFlows release and extracts it into `/opt/fileflows`
- runs FileFlows' own `--systemd install --root true`, which creates and
  starts the `fileflows` service, running as root

Because the service runs as root inside the unprivileged container, it can
read and write whatever media you bind-mount in.

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 13, unprivileged container |
| CPU       | 4 cores (the built-in node converts on the CPU) |
| Memory    | 4 GB                              |
| Disk      | 16 GB                             |
| Network   | DHCP on `vmbr0`                   |

## After install

The container's **Notes** in the Proxmox UI have a direct link to the web
UI, `http://<container-ip>:19200/`.

### 1. Run the setup wizard

The first visit opens FileFlows' setup wizard, where you accept its EULA.
For media flows, make sure the **Video** plugin is installed (**Plugins**
in the web UI).

FileFlows sends anonymous usage statistics (which flow elements and
plugins you use, and how many files were processed or failed) once the
EULA is accepted. To turn that off, use the **Disable Telemetry** option
in FileFlows' settings.

### 2. No login

The free version of FileFlows has no login: anyone who can reach port
19200 can use it and run flows on your files.
[User login](https://fileflows.com/docs/authentication/forms) is a
paid-licence feature. Keep the container on a trusted network, and don't
publish port 19200 to the internet without an authenticating proxy in
front of it.

### 3. Give the container your media

The recipe does not change host config, so it does not mount your media.
Add a bind mount from the host:

```bash
pct set <id> -mp0 /path/on/host,mp=/media
pct reboot <id>
```

In an unprivileged container, root is uid 100000 on the host. FileFlows
rewrites and moves files, so the host folder must be writable by that uid
(or by a group it belongs to). For a network share mounted on the host,
mount it with `uid=100000,gid=100000`.

Then add a library for `/media` (or a folder in it) and attach a flow.

### Temporary files

The built-in node works in `/opt/fileflows/Temp`, on the container's disk.
A conversion needs room for a full copy of the file being processed, so
for large files, raise the disk size, or bind-mount a fast disk and point
the node's temp path at it (**Nodes** in the web UI).

### Hardware encoding and other tools

The built-in node encodes on the CPU. A GPU must be passed in from the
host. That's a host-side change the recipe doesn't make. Adding an Agent
on a machine that already has a GPU is often easier.

FileFlows also looks for `mkvmerge`, `mkvextract`, `7z`, `unrar` and
`dovi_tool` in `/usr/bin`. Some flow elements need them. Install the
Debian package that provides one if a flow asks for it (for example
`apt install mkvtoolnix`).

## Ports and config

| Port  | Use                                   |
| ----- | ------------------------------------- |
| 19200 | Web UI, and the API Agents connect to |

| Path | What |
| ---- | ---- |
| `/opt/fileflows/Data/` | Database (`FileFlows.sqlite`), settings, backups |
| `/opt/fileflows/Logs/` | Logs |
| `/opt/fileflows/Temp/` | Built-in node's working files |
| `/etc/systemd/system/fileflows.service` | Service, written by FileFlows' installer |

## Updating

FileFlows can update itself from its web UI.

`recipe update` inside the container does the same thing: it upgrades the
OS packages (including .NET and FFmpeg), downloads the latest FileFlows
release, and, if it is newer, applies it with the release's own
`server-upgrade.sh`. Your `Data/` folder is kept.

FileFlows' in-app update restarts the service once more than needed: its
start script fails on the first launch after an update, and systemd starts
it again 10 seconds later. That is harmless. `recipe update` avoids it by
applying the update with the service stopped.

## Upstream docs

- [Install on Linux](https://fileflows.com/docs/installation/linux)
- [Run as a systemd service](https://fileflows.com/docs/installation/linux/systemd-service)
- [Authentication (licensed)](https://fileflows.com/docs/authentication/forms)
