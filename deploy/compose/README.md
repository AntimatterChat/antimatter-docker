# Deploying Antimatter with Docker Compose

A production setup on one host, from the published images:

```
                 :80, :443                     internal networks
 users ───────▶  nginx  ──────────────▶  antimatter  ──────▶  postgres
   │            (TLS, redirect,            :8065     ──────▶  antimatter-gifs   (profile gifs)
   │             websockets)                 ▲
   └────────── :8443 UDP+TCP (Calls media) ──┘
```

- **nginx** terminates TLS (your certificates, or Let's Encrypt with the `acme` profile),
  redirects HTTP to HTTPS and proxies the API and the websockets to Antimatter.
- **antimatter** is `ghcr.io/antimatterchat/antimatter` or `antimatter-next` (see
  [Choosing the image](#choosing-the-image)). Its port 8065 is only reachable by nginx; the Calls
  media port is published directly.
- **postgres** and **antimatter-gifs** sit on internal networks without Internet access: only
  Antimatter reaches them.

Files: [`compose.yaml`](compose.yaml), [`.env.example`](.env.example) (every variable),
[`nginx/antimatter.conf.template`](nginx/antimatter.conf.template).

## Requirements

- Docker Engine 25 or newer with the Compose plugin (`docker compose`).
- A domain name pointing to the host, e.g. `chat.example.com`, and a certificate for it (or
  Let's Encrypt).
- Open ports: 80/tcp and 443/tcp (nginx), 8443/udp and 8443/tcp (Calls).
- 2 CPUs and 4 GB of RAM for a few hundred users, more for larger teams; disk for the files
  users upload.

## Choosing the image

| Image | What it is |
|---|---|
| `ghcr.io/antimatterchat/antimatter` | The stable server and plugins: Agents, Boards, Calls, GitHub, GitLab, Jira, Metrics, Playbooks. |
| `ghcr.io/antimatterchat/antimatter-next` | The integration branches, rebuilt every night: the stable plugins plus GIFs and stickers, voice channels, polls, mail, calendar, notes and whiteboard, and the features not merged into the stable branch yet (Fusion web UI). |

Set `ANTIMATTER_IMAGE` in `.env` and pin a tag: `X.Y.Z` (releases of the stable image),
`nightly-<YYYYMMDD>` (`antimatter-next`) or `sha-<commit>` (both); `latest` changes under you. The GIF service is only useful with
`antimatter-next`, which ships the GIFs plugin.

Upgrades only go forward: the server migrates the database when it starts, so moving from
`antimatter-next` back to `antimatter`, or to an older version, needs a restore from a backup
taken before.

## First start

```sh
cd deploy/compose            # or a copy of this directory on the server, e.g. /srv/antimatter
cp .env.example .env
chmod 600 .env
# Edit .env: ANTIMATTER_DOMAIN, ANTIMATTER_IMAGE, POSTGRES_PASSWORD (openssl rand -hex 32),
# CALLS_ICE_HOST, and with the GIF service COMPOSE_PROFILES=gifs and GIFS_API_KEY.

# Your certificate (or see "Let's Encrypt" below):
mkdir -p certs
cp /path/to/fullchain.pem /path/to/privkey.pem certs/
chmod 600 certs/privkey.pem    # nginx reads it as root

docker compose up -d
docker compose ps              # wait for antimatter to be (healthy): the first start takes a while
```

Then create the first system admin, before anyone else can sign up (the first account created
becomes the system admin):

```sh
docker compose exec antimatter amctl --local user create --system-admin --email-verified \
    --email admin@example.com --username admin --password 'a-long-password'
docker compose exec antimatter amctl --local team create --name main --display-name "Main"
docker compose exec antimatter amctl --local team users add main admin
```

and log in at `https://<ANTIMATTER_DOMAIN>`. Start the command with a space to keep the
password out of your shell history (with `HISTCONTROL=ignorespace`), or change it once logged in.

`amctl --local` talks to the server through its local socket inside the container, without
logging in; anyone who can run `docker compose exec` on the host is a system admin.

## Configuration

Server settings come from three places:

1. `compose.yaml` sets those that belong to the deployment as `MM_*` variables: the database,
   `SiteURL` (`https://<ANTIMATTER_DOMAIN>`), the listen address, the file storage
   (`/antimatter/data`), the plugin directories, the trusted proxy headers and the Calls ports.
2. Any other `MM_<SECTION>_<SETTING>` variable you add to `.env`, e.g. SMTP (see the end of
   `.env.example`). The whole `.env` is passed to the antimatter container, which only reads the
   `MM_*` variables.
3. Everything else: **System Console**, saved in `/antimatter/config/config.json` (the `config`
   volume).

Settings set by variables are shown as locked in the System Console. The server still reads the
`MM_*` names; `AM_*` names come with the server rebrand. After changing `.env`, apply it with
`docker compose up -d`.

### TLS

**Your own certificate**: `certs/fullchain.pem` (the certificate followed by the intermediates)
and `certs/privkey.pem`, read by nginx at start. After replacing them:
`docker compose exec nginx nginx -s reload`.

**Let's Encrypt** (profile `acme`): certbot gets the first certificate on its own port 80, then a
`certbot` service renews it twice a day through nginx (`/.well-known/acme-challenge/`).

```sh
# In .env: COMPOSE_PROFILES=acme (or gifs,acme), ACME_EMAIL, and
#   TLS_CERTIFICATE=/etc/letsencrypt/live/<ANTIMATTER_DOMAIN>/fullchain.pem
#   TLS_CERTIFICATE_KEY=/etc/letsencrypt/live/<ANTIMATTER_DOMAIN>/privkey.pem
env_get() { sed -n "s/^$1=//p" .env; }
docker compose stop nginx      # if it runs: certbot needs port 80 for this first certificate
docker compose run --rm -p 80:80 --entrypoint certbot certbot certonly --standalone \
    -d "$(env_get ANTIMATTER_DOMAIN)" -m "$(env_get ACME_EMAIL)" --agree-tos --no-eff-email
docker compose up -d
```

nginx loads renewed certificates when reloaded; reload it every day from the host's crontab:

```
17 4 * * * cd /srv/antimatter && docker compose exec -T nginx nginx -s reload
```

### nginx

[`nginx/antimatter.conf.template`](nginx/antimatter.conf.template) follows the reverse proxy
setup Mattermost recommends: HTTP/2, TLS 1.2 and 1.3, websocket upgrades on
`/api/v4/websocket` and on any other path (plugin websockets), `client_max_body_size 100M` (keep
it at least the System Console's *Maximum File Size*), 256 × 16k proxy buffers, long read
timeouts, and a cache for the static files Antimatter marks as cacheable. The server sends
`X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy` and `X-Frame-Options` itself;
nginx adds HSTS. The image renders the template at start with `ANTIMATTER_DOMAIN`,
`TLS_CERTIFICATE` and `TLS_CERTIFICATE_KEY`; check a change with
`docker compose exec nginx nginx -t`, apply it with `docker compose restart nginx`.

Keep `HTTPS_PORT=443`: the HTTP to HTTPS redirect assumes the standard port.

### Calls

Call media (audio, video, screen sharing) don't go through nginx: the Calls plugin's RTC server
listens on `CALLS_PORT` (8443 by default, UDP and TCP; the same port on the host and in the
container) and clients connect to it directly. Open the port in the firewall, UDP and TCP.

- `CALLS_ICE_HOST`: the public IP address of the host (or a hostname resolving to it), which
  clients send the media to. Set it when the host is behind NAT or has no Internet access. Empty,
  Calls finds the address with the STUN server of its *ICE Servers Configurations* setting
  (Mattermost's public one by default).
- Without Internet access, also empty the STUN servers: `MM_CALLS_ICE_SERVERS_CONFIGS=[]` in
  `.env`.
- Calls settings can be set with `MM_CALLS_<SETTING>` variables (`AM_CALLS_*` also works), e.g.
  `MM_CALLS_ICE_HOST_PORT_OVERRIDE` when a NAT maps another public port.
- Clients that block UDP fall back to TCP on the same port; behind stricter firewalls, users need
  a TURN server (*ICE Servers Configurations* in **System Console > Plugins > Calls**).

Voice channels (`antimatter-next`) use Calls and need nothing more.

### GIF service and GIFs plugin

With `antimatter-next`, the GIFs plugin adds GIFs and stickers to the emoji picker, backed by
the [antimatter-gifs](https://github.com/AntimatterChat/antimatter-gifs) service. Enable it with
`COMPOSE_PROFILES=gifs` and a `GIFS_API_KEY` (`openssl rand -hex 32`) in `.env`, then
`docker compose up -d`.

On its first start, the one-shot `antimatter-gifs-init` service imports the bundled sticker pack
into the `gifs-data` volume (about a minute and a half; `docker compose up -d` waits for it) and
the service starts. It refuses to start without `GIFS_API_KEY`. To re-import the stickers after an
upgrade: `docker compose run --rm antimatter-gifs stickers`. To add GIFs, see the service's README
(`docker compose run --rm -v "$PWD/gifs:/import:ro" antimatter-gifs import -manifest /import/manifest.json`).

**Internal only (default).** The service is on the internal `gifs` network, which only
Antimatter shares: no port is published and nginx can't reach it. The plugin calls the API and
proxies the media files, so browsers and apps never connect to the service. Because every
request comes from Antimatter with the same key, the service's per-client rate limit is off
(`GIFS_RATE_LIMIT=0`); the plugin caches answers.

**Plugin settings.** Plugin settings can't be set one by one with `MM_*` variables: the only
variable is `MM_PLUGINSETTINGS_PLUGINS`, a JSON object that replaces the settings of *every*
plugin and locks them all in the System Console. Set them with `amctl` instead (or in **System
Console > Plugins > GIFs**: *GIF service URL* `http://antimatter-gifs:8080/v2`, *API key*):

```sh
env_get() { sed -n "s/^$1=//p" .env; }
# Settings, merged into the existing configuration (keys in lower case, like the System Console):
docker compose exec -T antimatter amctl --local config patch /dev/stdin <<EOF
{"PluginSettings": {"Plugins": {"com.antimatterchat.gifs": {
  "serviceurl": "http://antimatter-gifs:8080/v2",
  "apikey": "$(env_get GIFS_API_KEY)",
  "uploadkey": "$(env_get GIFS_UPLOAD_KEY)"
}}}}
EOF
# Install the plugin from the image's prepackaged plugins, then enable it:
docker compose exec antimatter amctl --local plugin marketplace install com.antimatterchat.gifs
docker compose exec antimatter amctl --local plugin enable com.antimatterchat.gifs
```

`uploadkey` (with `GIFS_UPLOAD_KEY` set) lets users add GIFs and stickers from the picker; who
can is the plugin's *Who can add GIFs and stickers* setting (system admins by default). Changing
`GIFS_API_KEY` later means updating `apikey` too; the service accepts several comma-separated
keys while you switch.

The other plugins of `antimatter-next` that aren't enabled by default install the same way:

```sh
for id in com.antimatterchat.voice-channels com.antimatterchat.polls com.antimatterchat.mail \
          com.antimatterchat.calendar com.antimatterchat.notes com.antimatterchat.whiteboard; do
    docker compose exec antimatter amctl --local plugin marketplace install "$id"
    docker compose exec antimatter amctl --local plugin enable "$id"
done
```

**Exposing the GIF service (optional).** To let other Tenor API clients use the service, or
browsers load the media without going through Antimatter, publish it under
`https://<ANTIMATTER_DOMAIN>/gifs/`:

1. Uncomment the `location /gifs/` block at the end of `nginx/antimatter.conf.template`.
2. Create `compose.override.yaml` next to `compose.yaml` (Compose reads it automatically):

   ```yaml
   services:
     nginx:
       networks: [frontend, gifs]
       depends_on: [antimatter, antimatter-gifs]
     antimatter-gifs:
       environment:
         AM_GIFS_PUBLIC_URL: https://chat.example.com/gifs   # your domain
         AM_GIFS_TRUST_PROXY: "true"                         # client addresses from nginx
         AM_GIFS_RATE_LIMIT: "20"                            # per API key and client address
   ```
3. `docker compose up -d`.

The API then needs one of the API keys from anyone on the Internet (give other clients their
own key: `GIFS_API_KEY=key-for-antimatter,key-for-others`). Media URLs now point to
`https://<ANTIMATTER_DOMAIN>/gifs/media/`, so browsers load the files from there instead of
through the plugin: turn *Serve the media through Antimatter* off in the plugin settings to match.
The plugin keeps using the internal address for the API. With a rate limit, all of Antimatter's
users share one budget (same key and address): keep it generous or give Antimatter a key on a
separate service.

## Operations

```sh
docker compose ps                        # state and health
docker compose logs -f antimatter        # also in the logs volume (/antimatter/logs)
docker compose restart antimatter
```

### Upgrades

1. Read the release notes and take a backup (below).
2. Change the image tags in `.env` (or keep `latest` tags), then:

   ```sh
   docker compose pull
   docker compose up -d
   ```

The server migrates its database on start; follow it with `docker compose logs -f antimatter`.
Prepackaged plugins are upgraded from the new image. For a new PostgreSQL major version, dump the
database, start the new version on a new volume and restore the dump into it: the data
directory format changes between major versions.

### Backups

Back up the database and the volumes together, ideally while nobody writes (or stop
`antimatter` for a consistent copy):

```sh
stamp=$(date +%Y%m%d-%H%M%S)
mkdir -p backups
# Database
docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
    > "backups/antimatter-db-$stamp.dump"
# Uploaded files, configuration and plugins
docker run --rm --volumes-from "$(docker compose ps -q antimatter)" -v "$PWD/backups:/backup" \
    alpine tar -czf "/backup/antimatter-files-$stamp.tar.gz" -C / \
    antimatter/config antimatter/data antimatter/plugins antimatter/client/plugins
# GIF service (profile gifs): its index and media
docker run --rm -v antimatter_gifs-data:/data:ro -v "$PWD/backups:/backup" \
    alpine tar -czf "/backup/antimatter-gifs-$stamp.tar.gz" -C / data
```

`config` and `data` are the essential ones; the plugin directories can be large and are rebuilt
from the image for prepackaged plugins, but hold the plugins you uploaded. Copy `.env` and
`certs/` (or the `letsencrypt` volume) somewhere safe as well, and the backups off the host.
Volume names start with the project name, `antimatter` (`docker volume ls`).

To restore on a fresh host (same `.env`):

```sh
docker compose up -d postgres
docker compose exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner' \
    < backups/antimatter-db-<stamp>.dump
docker compose create antimatter
docker run --rm --volumes-from "$(docker compose ps -aq antimatter)" -v "$PWD/backups:/backup" \
    alpine tar -xzf "/backup/antimatter-files-<stamp>.tar.gz" -C /
# GIF service (profile gifs)
docker volume create antimatter_gifs-data
docker run --rm -v antimatter_gifs-data:/data -v "$PWD/backups:/backup" \
    alpine tar -xzf "/backup/antimatter-gifs-<stamp>.tar.gz" -C /
docker compose up -d
```

### Security notes

- Keep `.env` and `certs/privkey.pem` readable by root only; they hold the database password,
  the GIF service keys and the TLS key.
- PostgreSQL and the GIF service publish no port; only nginx (80, 443) and Calls (8443) are
  reachable from outside.
- All containers run with `no-new-privileges`; Antimatter runs as uid 2000 on a distroless image,
  the GIF service as uid 10001 with a read-only root filesystem.
- Restrict who can create accounts in **System Console > Authentication > Signup** once the
  first admin exists.
