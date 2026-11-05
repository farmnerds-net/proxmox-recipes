# Caddy

[Caddy](https://caddyserver.com/) is a web server and **reverse proxy** with
automatic HTTPS. Put it in front of the apps in your other containers and
reach each one at its own name, like `https://jellyfin.example.com`, with
certificates Caddy gets and renews for you. It's also the proxy
[Authelia](authelia.md) needs.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/caddy.sh)"
```

The recipe follows Caddy's
[Debian install guide](https://caddyserver.com/docs/install#debian-ubuntu-raspbian):
it adds Caddy's stable apt repository and installs the `caddy` package,
which runs Caddy as the systemd `caddy` service. It asks no questions.

Caddy starts with the package's example `/etc/caddy/Caddyfile`, which shows
a welcome page on port 80. The container's **Notes** link to it.

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 1 core                            |
| Memory    | 512 MB                            |
| Disk      | 2 GB                              |
| Network   | DHCP on `vmbr0`                   |

## After install

**Fixed IP:** your router and DNS point at this container. Reserve its
address in your DHCP server, or choose a static IP in the recipe's Advanced
mode.

### Add your sites

Edit the Caddyfile inside the container, then reload (no downtime):

```bash
pct enter <id>
nano /etc/caddy/Caddyfile
systemctl reload caddy
```

Each site is a name and where to send it. **Use the app's LAN address**, not
`localhost`: the apps run in other containers.

```
jellyfin.example.com {
	reverse_proxy 192.168.1.30:8096
}

pihole.example.com {
	reverse_proxy 192.168.1.20:80
}
```

Check a change before reloading with
`caddy validate --config /etc/caddy/Caddyfile`.
[Caddyfile docs](https://caddyserver.com/docs/caddyfile),
[reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy).

### HTTPS

**Reachable from the internet:** Caddy gets certificates from Let's Encrypt
or ZeroSSL by itself
([automatic HTTPS](https://caddyserver.com/docs/automatic-https)). For that:

1. Your domain's DNS (A/AAAA records) points at your public IP.
2. Your router forwards ports **80 and 443** (TCP, and UDP 443 for HTTP/3)
   to this container.

**Only on your network:** add `tls internal` to a site. Caddy then signs its
own certificates. Browsers will warn until you trust Caddy's root
certificate, which is in the container at
`/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`.

```
nas.home.example.com {
	tls internal
	reverse_proxy 192.168.1.40:5000
}
```

Getting real certificates for names that aren't reachable from the internet
needs the DNS challenge, which needs a Caddy plugin for your DNS provider.
The packaged Caddy has only the standard modules, so that means a
[custom build](https://caddyserver.com/docs/build), which this recipe
doesn't do.

### Protect apps with Authelia

With an [Authelia](authelia.md) container, Caddy can require a login before
any app. This setup was tested with the Authelia recipe, following
[Authelia's Caddy guide](https://www.authelia.com/integration/proxies/caddy/):

```
auth.example.com {
	reverse_proxy <authelia-ip>:9091
}

app.example.com {
	forward_auth <authelia-ip>:9091 {
		uri /api/authz/forward-auth
		copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
	}
	reverse_proxy 192.168.1.50:8080
}
```

Logged-out visitors to `app.example.com` are sent to the Authelia portal;
once logged in, the app receives the user's name and groups in the
`Remote-User` and `Remote-Groups` headers.

## Ports and config

| Port | Use |
| ---- | --- |
| 80 | HTTP (and certificate checks) |
| 443 | HTTPS (TCP), HTTP/3 (UDP) |
| 2019 | Admin API, on `127.0.0.1` only |

Config: `/etc/caddy/Caddyfile`. Certificates and keys:
`/var/lib/caddy/.local/share/caddy`. Logs: `journalctl -u caddy`.

## Updating

Inside the container:

```bash
recipe update
```

Caddy comes from its apt repository, so this upgrades it along with the OS
packages (keeping your Caddyfile), then checks the Caddyfile and that Caddy
is running.

## Upstream docs

- [Install](https://caddyserver.com/docs/install#debian-ubuntu-raspbian)
- [Running as a service](https://caddyserver.com/docs/running)
- [Caddyfile](https://caddyserver.com/docs/caddyfile)
- [Automatic HTTPS](https://caddyserver.com/docs/automatic-https)
- [forward_auth](https://caddyserver.com/docs/caddyfile/directives/forward_auth)
