# Authelia

[Authelia](https://www.authelia.com/) puts one login page, with optional
two-factor authentication, in front of the web apps behind your reverse
proxy. When someone opens a protected app, the proxy asks Authelia whether
they're logged in; if not, they're sent to the Authelia portal first. Log in
once and every protected app on your domain lets you in (single sign-on).

**Authelia needs a reverse proxy that serves your domain over HTTPS**
(Nginx Proxy Manager, Caddy, Traefik, nginx, HAProxy, ...). It does not work
on an IP address or over plain `http://`. The recipe doesn't set up the
proxy.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/authelia.sh)"
```

The recipe follows Authelia's
[bare-metal install guide](https://www.authelia.com/integration/deployment/bare-metal/):
it adds Authelia's apt repository and installs the `authelia` package, which
comes with its systemd service. It asks one question:

- **Portal URL**: the HTTPS address you'll log in at, on your own domain,
  for example `https://auth.example.com`. The login is shared across the
  domain the portal is under (`example.com` here), so every app you protect
  must be on that domain, e.g. `https://jellyfin.example.com`. A bare public
  suffix such as `duckdns.org` doesn't work; `you.duckdns.org` does.

The package only ships an example configuration, so the recipe writes a
minimal one following Authelia's
[get-started guide](https://www.authelia.com/integration/prologue/get-started/):

| Part | Setting |
| --- | --- |
| Users | File: `/etc/authelia/users_database.yml`, with one user, `admin`, and a random password |
| Access | Deny by default; anything on `*.<your domain>` needs a login (one factor) |
| Storage | SQLite, `/var/lib/authelia/db.sqlite3` |
| Email | None: messages are written to `/var/lib/authelia/notification.txt` |
| Secrets | Generated with `authelia crypto rand`, in `/var/lib/authelia/secrets` |

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 1 core                            |
| Memory    | 512 MB                            |
| Disk      | 2 GB                              |
| Network   | DHCP on `vmbr0`                   |

## After install

**Fixed IP:** your proxy points at this container. Reserve its address in
your DHCP server, or choose a static IP in the recipe's Advanced mode.

### 1. Put it behind your reverse proxy

Point your portal URL (e.g. `auth.example.com`) at
`http://<container-ip>:9091` in your reverse proxy, with HTTPS. Then
protect each app by adding Authelia's forward-auth check to that app's
proxy entry. Authelia has a guide for each proxy:

- [Nginx Proxy Manager](https://www.authelia.com/integration/proxies/nginx-proxy-manager/)
- [Caddy](https://www.authelia.com/integration/proxies/caddy/) (there is a [Caddy recipe](caddy.md), tested with this one)
- [Traefik](https://www.authelia.com/integration/proxies/traefik/)
- [nginx](https://www.authelia.com/integration/proxies/nginx/)
- [HAProxy](https://www.authelia.com/integration/proxies/haproxy/)
- [All proxies](https://www.authelia.com/integration/proxies/introduction/)

### 2. Log in

Open your portal URL and log in as **admin**. The password is in the
container:

```bash
pct exec <id> -- cat /root/authelia-admin-password
```

### 3. Two-factor and password resets without email

Authelia normally emails a code when you register a second factor (an
authenticator app or a security key) or reset a password. With no email
set up, it writes those messages to a file instead. Read the code there:

```bash
pct exec <id> -- tail -n 20 /var/lib/authelia/notification.txt
```

To send real email, replace the `notifier:` section of
`/etc/authelia/configuration.yml` with an `smtp:` one, as in
[Authelia's SMTP docs](https://www.authelia.com/configuration/notifications/smtp/),
then `systemctl restart authelia`.

### Users

Edit `/etc/authelia/users_database.yml`; Authelia picks up changes on its
own. Make each user's password hash with:

```bash
authelia crypto hash generate argon2
```

and change the admin's `email` to a real address. See
[the users file docs](https://www.authelia.com/configuration/first-factor/file/).

### Require two-factor

In `/etc/authelia/configuration.yml`, change `policy: 'one_factor'` to
`policy: 'two_factor'` (or add rules per app, see
[access control](https://www.authelia.com/configuration/security/access-control/)),
then `systemctl restart authelia`.

## Ports and config

| Port | Use |
| ---- | --- |
| 9091 | Portal and API (HTTP; your proxy adds HTTPS) |

Config: `/etc/authelia/configuration.yml` (the package's full example is
next to it as `configuration.yml.dist`). After editing, check it with
`authelia validate-config --config /etc/authelia/configuration.yml`
(as root that also needs the secret variables, so `systemctl restart
authelia` and `journalctl -u authelia` are simpler).

The secrets (session, storage encryption, password-reset token) are loaded
from `/var/lib/authelia/secrets` by
`/etc/systemd/system/authelia.service.d/proxmox-recipes.conf`. **Back up
that folder with the database**: the database is encrypted with the
storage secret.

## Updating

Inside the container:

```bash
recipe update
```

Authelia comes from its apt repository, so this upgrades it along with the
OS packages (keeping your configuration), checks the configuration, and
restarts it.

## Upstream docs

- [Bare-metal install](https://www.authelia.com/integration/deployment/bare-metal/)
- [Get started](https://www.authelia.com/integration/prologue/get-started/)
- [Proxy integration](https://www.authelia.com/integration/proxies/introduction/)
- [Access control](https://www.authelia.com/configuration/security/access-control/)
- [Passwords guide](https://www.authelia.com/reference/guides/passwords/)
