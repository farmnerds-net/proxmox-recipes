# Documenso

[Documenso](https://documenso.com/) is an open-source document signing app,
an alternative to DocuSign. You upload a PDF, place signature and other
fields on it, and send it to the people who need to sign. They get an
email with a link and sign in the browser. The finished PDF is sealed with a
digital signature.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/documenso.sh)"
```

The recipe follows Documenso's
[manual deployment guide](https://docs.documenso.com/docs/self-hosting/deployment/manual),
which builds the app from source. It asks no questions. It:

- installs PostgreSQL from Debian and creates a `documenso` database with a
  random password
- installs Node.js from the [official binaries](https://nodejs.org/en/download)
  to `/opt/nodejs` (the version Documenso's release asks for)
- clones the latest Documenso **release** to `/var/www/documenso` and runs
  `npm ci`, the build and the database migrations
- writes `/var/www/documenso/.env` with random secrets
- creates a self-signed signing certificate (see below)
- creates and starts the systemd `documenso` service, running as `www-data`

**The install is slower than most recipes.** The build takes a few minutes and needs
the 4 GB of memory the recipe gives the container. Once it runs, Documenso
uses far less; you can lower the memory afterwards in the Proxmox UI, but
raise it again before `recipe update`, which rebuilds the app.

Two things differ from the guide:

- The guide's `npm run build` builds every part of Documenso's repository,
  including its documentation website, and runs out of memory. The recipe
  builds only the app, with the command Documenso's own `package.json` uses
  for that (`turbo run build --filter=@documenso/remix`).
- The guide's sample service file starts the app from the repository root.
  The recipe starts it from `apps/remix`, as Documenso's own start script
  does. From the root, the server can't find its CSS and JavaScript files.

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 4 cores (for the build)           |
| Memory    | 4 GB (for the build)              |
| Disk      | 16 GB                             |
| Network   | DHCP on `vmbr0`                   |

## After install

The container's **Notes** in the Proxmox UI have a direct link to the web
UI, `http://<container-ip>:3000/`.

### 1. Set up email first

**Do this before you sign up.** Documenso only lets you sign in once your
email address is verified, and it sends the verification link by email. It
also emails every signing request, so it is not usable without email.

The recipe doesn't ask for SMTP settings, because the password is a secret
and recipe options are visible on the host's process list. Set them inside
the container:

```bash
pct enter <id>
nano /var/www/documenso/.env
```

Change these lines to match your mail provider (an SMTP relay such as your
email host, Brevo, Mailgun or Amazon SES):

```bash
NEXT_PRIVATE_SMTP_TRANSPORT="smtp-auth"
NEXT_PRIVATE_SMTP_HOST="smtp.example.com"
NEXT_PRIVATE_SMTP_PORT="587"
NEXT_PRIVATE_SMTP_USERNAME="you@example.com"
NEXT_PRIVATE_SMTP_PASSWORD="..."
NEXT_PRIVATE_SMTP_FROM_NAME="Documenso"
NEXT_PRIVATE_SMTP_FROM_ADDRESS="sign@example.com"
```

Use port `465` with `NEXT_PRIVATE_SMTP_SECURE="true"` if your provider wants
TLS from the start. Resend and MailChannels are also supported; see the
[email settings](https://docs.documenso.com/docs/self-hosting/configuration/environment#email-configuration).
Then restart Documenso:

```bash
systemctl restart documenso
```

If you signed up before email worked, just sign in again: Documenso sends a
new verification email.

### 2. Set the public URL

`NEXT_PUBLIC_WEBAPP_URL` in the same file must be the exact address you
open Documenso at. The recipe sets it to `http://<container-ip>:3000`.
**Sign-up and sign-in fail with "Forbidden" from any other address**, even
the container's hostname: Documenso rejects login requests from pages it
doesn't recognize as its own. Links in emails use this address too, so it
only works on your network.

If people outside your network will sign, put Documenso behind a domain
(for example with a [Cloudflare Tunnel](cloudflared.md) pointed at
`http://<container-ip>:3000`), set the URL to match, and restart:

```bash
NEXT_PUBLIC_WEBAPP_URL="https://sign.example.com"
```

Keep `NEXT_PRIVATE_INTERNAL_WEBAPP_URL` as `http://localhost:3000`: the app
uses it to call itself for background jobs.

### 3. Create your account

Open the web UI and **sign up**. Anyone who can reach the web UI can create
an account. Once yours exists, you can turn signups off with
`NEXT_PUBLIC_DISABLE_SIGNUP="true"` in the `.env` (then restart).

### The signing certificate

Documenso seals each signed PDF with a certificate. The recipe makes a
self-signed one (valid 10 years) at `/etc/documenso/cert.p12`, with a random
password in the `.env`. Signing works, but PDF readers such as Adobe
Acrobat show the signature as **not trusted**, because no public authority
issued the certificate. To use your own, follow Documenso's
[certificate guide](https://docs.documenso.com/docs/self-hosting/configuration/signing-certificate/local),
replace the file, and update `NEXT_PRIVATE_SIGNING_PASSPHRASE`.

## Ports and config

| Port | Use |
| ---- | --- |
| 3000 | Web UI and API (HTTP) |
| 5432 | PostgreSQL, on `127.0.0.1` only |

All settings, including the database password and encryption keys, are in
`/var/www/documenso/.env`. **Back it up**: documents are encrypted with
`NEXT_PRIVATE_ENCRYPTION_KEY`, so a database backup is useless without it.
Uploaded documents are stored in the PostgreSQL database.

Logs: `journalctl -u documenso`.

Document reminders need scheduled jobs, which the default job runner doesn't
do. Everything else (sending, signing, completion emails) works.

## Updating

Inside the container:

```bash
recipe update
```

This upgrades the OS packages, then, if there is a new Documenso release,
builds it in `/var/www/documenso.new` next to the running copy. Only when
the build succeeds does it stop Documenso, update the database, swap the new
copy in and start it again. A failed build leaves the running version alone.
It takes as long as the install and needs the same memory. Your `.env` is
kept.

## Upstream docs

- [Manual deployment](https://docs.documenso.com/docs/self-hosting/deployment/manual)
- [Environment variables](https://docs.documenso.com/docs/self-hosting/configuration/environment)
- [Signing certificate](https://docs.documenso.com/docs/self-hosting/configuration/signing-certificate/local)
- [GitHub](https://github.com/documenso/documenso)
