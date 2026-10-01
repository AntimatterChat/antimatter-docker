# antimatter-docker

Builds the ready-to-use Antimatter Docker image: the Antimatter server with its plugins
prepackaged (Agents, Boards, Calls, GitHub, GitLab, Jira, Metrics, Playbooks), signed with the
Antimatter plugin signing key, for `linux/amd64` and `linux/arm64`.

Two images are built from the same scripts (see *Variants*):

| Image                                   | Variant  | Built from                                                  |
|-----------------------------------------|----------|-------------------------------------------------------------|
| `ghcr.io/antimatterchat/antimatter`      | `stable` | the `antimatter` branch of every repository                 |
| `ghcr.io/antimatterchat/antimatter-next` | `next`   | `antimatter-dev` of the server, Calls and Voice Channels; `antimatter` of the other plugins |

Everything is compiled inside Docker (`docker/build.Dockerfile`), so a local build and the GitHub
build run the same toolchain.

```
fetch-sources.sh   clone the server and plugin repos into src/
build-plugins.sh   make dist in each plugin          -> out/plugins/*.tar.gz
build-server.sh    web app + linux amd64/arm64 build -> out/server/antimatter-linux-<arch>.tar.gz
sign-plugins.sh    detached signatures               -> out/plugins/*.tar.gz.sig
build-image.sh     runtime image (Dockerfile)        -> ghcr.io/antimatterchat/antimatter[-next]
```

## What gets built

- `build.env`: server repository/ref, image name, platforms, toolchain image.
- `plugins.json`: the plugin repositories, the ref built for each, and the plugin version. The
  plugins derive their version from git tags, which the forks don't carry, so the build tags each
  checkout `v<version>` (override with `VERSION_<PLUGIN>=...`). Keep versions semver-comparable:
  the mobile apps check the Calls and Playbooks versions to enable features.
- `variants/<variant>.env`: one image variant, selected with `VARIANT=<variant>` (default
  `stable`). Its settings override `build.env` (e.g. `IMAGE`, `SERVER_REF`). In `plugins.json`, a
  plugin with a `"variants"` list is only built for the variants it names, and
  `"overrides": {"<variant>": {"ref": ...}}` changes its fields for one variant.

Both default to an `antimatter` branch in every repository (see *Building on GitHub*). For one
build, each component's ref is picked as follows (first match wins):

1. an explicit ref: `SERVER_REF=...` for the server; `REF_<PLUGIN>=...` or
   `PLUGIN_REFS="calls=new-ui boards=my-fix"` for plugins;
2. `PREFER_REF=...`: used for every repository that has that branch or tag;
3. the default from the variant, `build.env` and `plugins.json`.

For a feature spanning several repositories, e.g. a new UI in the server and in Calls, push a
`new-ui` branch to each and build with `PREFER_REF=new-ui` (the *prefer_ref* field of the GitHub
workflow); the other plugins build from their default branch. Give such builds their own image tag
(the workflow's *version* field) so they don't replace `latest`.

### Variants

- `stable` (`variants/stable.env`): `build.env` and `plugins.json` as they are.
- `next` (`variants/next.env`): the `antimatter-dev` integration branches, which carry features
  not merged into `antimatter` yet (the Fusion web UI, voice channels). The server and Calls build
  from `antimatter-dev`, and the Voice Channels plugin, which needs both, is only part of this
  image. Published as `ghcr.io/antimatterchat/antimatter-next`.

```sh
VARIANT=next scripts/build-all.sh
```

With `SOURCES=local`, checkouts still build at their current branch: check out `antimatter-dev`
where the variant expects it, or set `SERVER_REF_LOCAL` / `REF_<PLUGIN>`.

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
5. `antimatter-next` is built by running the workflow with *variant* `next`, or by a
   `repository_dispatch` event of type `antimatter-dev-updated`, which the forks can send when
   their `antimatter-dev` branch changes. It needs a token allowed to write this repository's
   contents (e.g. a fine-grained token with *Contents: read and write* on antimatter-docker), stored
   as a secret of the fork:
   ```yaml
   # .github/workflows/rebuild-antimatter-next.yml in a fork
   on:
     push:
       branches: [antimatter-dev]
   jobs:
     dispatch:
       runs-on: ubuntu-latest
       steps:
         - run: gh api repos/AntimatterChat/antimatter-docker/dispatches -f event_type=antimatter-dev-updated
           env:
             GH_TOKEN: ${{ secrets.ANTIMATTER_DOCKER_DISPATCH_TOKEN }}
   ```
   Its tags are `latest`, `sha-<commit>` and the `version` input, on
   `ghcr.io/antimatterchat/antimatter-next`.

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

`SOURCES=local` reads the checkouts next to this repository (`../antimatter`,
`../antimatter-plugin-*`; see `SERVER_LOCAL` in `build.env` and `local` in `plugins.json`), at their
current branch unless `SERVER_REF_LOCAL` / `REF_<PLUGIN>` say otherwise. The result is loaded as
`ghcr.io/antimatterchat/antimatter:dev`. To publish a multi-platform image instead:
`PUSH=1 TAGS="ghcr.io/antimatterchat/antimatter:1.0.0" scripts/build-image.sh` (after
`docker login ghcr.io`).

## Trying it locally

```sh
docker compose -f compose.local.yml up -d
```

Then open http://localhost:8065 and create the first account (it becomes the system admin). It
runs the published `latest` image with a local PostgreSQL, on localhost only; set
`ANTIMATTER_IMAGE=ghcr.io/antimatterchat/antimatter:dev` to try an image built by
`scripts/build-image.sh`. While the GHCR package is private, run `docker login ghcr.io` first with
a GitHub token that has `read:packages`. `docker compose -f compose.local.yml down -v` removes it
all, data included.

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
provides `antimatter` and `amctl` in `/antimatter/bin` (renamed from `mattermost` and `mmctl` when
built from a server ref older than that rename). The server still reads its settings from
`MM_*` environment variables until its own rebrand adds the `AM_*` names.

## License

Apache License 2.0 (see `LICENSE`), except `Dockerfile`, which is adapted from the Mattermost
server's Dockerfile and stays under the GNU AGPL v3 (see `NOTICE` and `LICENSE-AGPL-3.0`).
