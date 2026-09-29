# antimatter-docker

Builds the ready-to-use Antimatter Docker image: the Antimatter server with its plugins
prepackaged (Agents, Boards, Calls, GitHub, GitLab, Jira, Metrics, Playbooks), signed with the
Antimatter plugin signing key, for `linux/amd64` and `linux/arm64`.

Everything is compiled inside Docker (`docker/build.Dockerfile`), so a local build and the GitHub
build run the same toolchain.

```
fetch-sources.sh   clone the server and plugin repos into src/
build-plugins.sh   make dist in each plugin          -> out/plugins/*.tar.gz
build-server.sh    web app + linux amd64/arm64 build -> out/server/antimatter-linux-<arch>.tar.gz
sign-plugins.sh    detached signatures               -> out/plugins/*.tar.gz.sig
build-image.sh     runtime image (Dockerfile)        -> ghcr.io/antimatterchat/antimatter
```

## What gets built

- `build.env`: server repository/ref, image name, platforms, toolchain image.
- `plugins.json`: the plugin repositories and the ref built for each.

Both default to an `antimatter` branch in every repository (see *Building on GitHub*). Override any
ref for one build with `SERVER_REF=...` or `REF_<PLUGIN>=...` (e.g. `REF_CALLS=my-branch`).

## Plugin signing

The server only installs prepackaged plugins whose detached signature verifies against the
Antimatter plugin signing key compiled into it (fingerprint in
`keys/antimatter-plugin-signing.fingerprint`, public key in `keys/`). The server must therefore
include the change that trusts this key (server branch `antimatter-plugin-signing`).

The private key never goes into a repository. `sign-plugins.sh` reads it from
`ANTIMATTER_PLUGIN_SIGNING_KEY` (armored key, the GitHub secret), `ANTIMATTER_PLUGIN_SIGNING_KEY_FILE`,
or `~/.config/antimatter/plugin-signing/private-key.asc`, and refuses any other key. Keep an
offline backup of the private key and of `revocation-certificate.rev`; if the key is lost or
leaked, generate a new one, update `keys/` and the server's embedded key, and rebuild.

## Building on GitHub

1. Create `AntimatterChat/antimatter-docker` and push this repository to it.
2. Push the work to an `antimatter` branch of each fork (or change the refs in `build.env` /
   `plugins.json`), e.g.:
   ```sh
   # server: the branch combining the fork work, including antimatter-plugin-signing
   git -C ../mattermost push <remote> <your-server-branch>:antimatter
   # each plugin
   git -C ../mattermost-plugin-calls push <remote> rebrand-antimatter:antimatter
   ```
3. Add the repository secret `ANTIMATTER_PLUGIN_SIGNING_KEY` (Settings → Secrets and variables →
   Actions) with the full content of `~/.config/antimatter/plugin-signing/private-key.asc`.
   Then delete the local copy once it's backed up offline.
4. Run the *Build Antimatter image* workflow (Actions tab), or push to `main` / a `v*` tag.
   Images are published to `ghcr.io/antimatterchat/antimatter` with tags `latest` (main),
   `<version>` (tags `vX.Y.Z` or the `version` input) and `sha-<commit>`. Make the package public
   under the organisation's Packages settings if you want anonymous pulls.

The forks still carry upstream's GitHub workflows, which need Mattermost's secrets and fail on the
forks; disable Actions on the fork repositories (Settings → Actions) or delete those workflows.

## Building locally

Requirements: Docker with the buildx plugin (`docker-buildx` package), Python 3, git, gpg, and
permission to use Docker (be in the `docker` group). Plan for ~16 GB of RAM for the server web app
build (`BUILD_NODE_OPTIONS` in `build.env`) and ~30 GB of disk.

```sh
# from your local checkouts next to this repo (current branch of each, committed work only)
SOURCES=local scripts/build-all.sh
# or from GitHub
scripts/build-all.sh
```

`SOURCES=local` reads the server from `../mattermost-nolicense` (`SERVER_LOCAL` in `build.env`);
pick its branch with `SERVER_REF_LOCAL=antimatter-plugin-signing`. The result is loaded as
`ghcr.io/antimatterchat/antimatter:dev`. To publish a multi-platform image instead:
`PUSH=1 TAGS="ghcr.io/antimatterchat/antimatter:1.0.0" scripts/build-image.sh` (after
`docker login ghcr.io`).

## Running

```sh
cp .env.example .env    # set SITE_URL and POSTGRES_PASSWORD
docker compose up -d
```

Antimatter listens on port 8065 (put a TLS reverse proxy in front of it) and Calls uses 8443 UDP
and TCP. Data, config, logs and plugins live in named volumes. Boards, Calls, Playbooks and Agents
are enabled on first start; the others are offered in the Marketplace (installed offline from the
prepackaged bundles) for an admin to enable.

The image keeps upstream's layout under `/antimatter`, runs as uid 2000 on a distroless base, and
provides `antimatter` and `amctl` in `/antimatter/bin`. The server still reads its settings from
`MM_*` environment variables until its own rebrand adds the `AM_*` names.

## License

Apache License 2.0 (see `LICENSE`), except `Dockerfile`, which is adapted from the Mattermost
server's Dockerfile and stays under the GNU AGPL v3 (see `NOTICE` and `LICENSE-AGPL-3.0`).
