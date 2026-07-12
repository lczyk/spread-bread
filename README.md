# spread-bread

<img src="assets/logo.png" alt="Spread-bread logo" align="right" width="300">

[![CI](https://github.com/lczyk/spread-bread/actions/workflows/ci.yaml/badge.svg)](https://github.com/lczyk/spread-bread/actions/workflows/ci.yaml)
[![downloads](https://img.shields.io/github/v/release/lczyk/spread-bread?label=downloads)](https://github.com/lczyk/spread-bread/releases/latest)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white)](#)
[![bread](https://img.shields.io/badge/%F0%9F%8D%9E-bread-fb83ac)](https://github.com/lczyk/spread-bread/releases/latest)

[![ghcr bread](https://img.shields.io/badge/ghcr-bread-blue?logo=docker)](https://github.com/lczyk/spread-bread/pkgs/container/spread-bread%2Fbread)
[![ghcr bread-chisel-releases](https://img.shields.io/badge/ghcr-bread--chisel--releases-blue?logo=docker)](https://github.com/lczyk/spread-bread/pkgs/container/spread-bread%2Fbread-chisel-releases)

because it rhymes 🤷🏻‍♀️

prebuilt docker images + ready-to-use spread yamls so you can drop Canonical [`spread`](https://github.com/canonical/spread) into any project without writing a backend or maintaining test infra. images live on ghcr as multiarch manifests; per-version yamls live as github release assets.


> [!WARNING]
> This project has many footguns. The test containers are run with no authentication and in --privileged mode. Make sure you know what you are doing.

## flavours

two image flavours, each for ubuntu 24.04, 25.10, 26.04, 26.10 x amd64 / arm64 / s390x / ppc64le, published as multiarch tags at `ghcr.io/lczyk/spread-bread/<flavour>:<ver>`. heads-up: s390x + ppc64le images build under qemu and ship untested (no native runners); amd64 + arm64 are tested on every release:

- **`bread`** -- base: ubuntu + sshd. general-purpose spread system; the test suite installs whatever else it needs.
- **`bread-chisel-releases`** -- bread + `chisel` + the shell + container tooling typically needed by [chisel-releases](https://github.com/canonical/chisel-releases) spread tests (curl, wget, git, jq, file, sudo, tree, docker, skopeo). `chisel` and `docker` are built from source (canonical/chisel pinned by SHA, docker/cli pinned by version tag) so the bundled binaries are go 1.25+ and survive qemu emulation.

## using (the common case)

drop a ready-made spread yaml into your project. no clone, no build. yamls are attached to the rolling [`downloads`](https://github.com/lczyk/spread-bread/releases/latest) release:

```
curl -fsSL https://github.com/lczyk/spread-bread/releases/latest/download/bread-chisel-releases-26.04.yaml -o spread.yaml
spread
```

allocate inside the yaml `docker run`s the matching multiarch ghcr image; `--platform linux/<arch>` picks the right arch from the manifest list. first run pulls the image; subsequent runs hit the local docker cache.

available yamls in the release:

- `bread-{24.04,25.10,26.04,26.10}.yaml`
- `bread-chisel-releases-{24.04,25.10,26.04,26.10}.yaml`

### networking (linux vs macOS)

the allocate script reaches the container's sshd in one of two ways, picked automatically from `uname`:

- **`bridge`** (default on linux) -- connects to the container's docker bridge IP. relies on the host sharing the docker bridge network, so `172.17.x.x` is routable.
- **`publish`** (default on macOS) -- publishes sshd to `127.0.0.1:<ephemeral port>` and connects there. Docker Desktop on macOS runs the daemon in a VM, so bridge IPs are not host-routable; publishing a port is.

override the default with `BREAD_NET`:

```
BREAD_NET=publish spread   # force port-publishing (e.g. to test the macOS path on linux)
BREAD_NET=bridge  spread   # force bridge IPs
```

one more macOS gotcha: spread packs the project with the host `tar`, and macOS `tar` injects `._*` AppleDouble sidecar files (resource-fork metadata) into the archive. they unpack as real files in the container and can break tools that scan for `*.yaml` etc. export `COPYFILE_DISABLE=1` so macOS `tar` skips them:

```
export COPYFILE_DISABLE=1
spread
```

## install spread

prefer a precompiled spread CLI over `go install`? same release ships statically-linked binaries for linux amd64 / arm64 / s390x / ppc64le:

```
curl -fsSL https://github.com/lczyk/spread-bread/releases/latest/download/spread-linux-amd64 -o /usr/local/bin/spread
chmod +x /usr/local/bin/spread
```

verify the checksum:

```
curl -fsSL https://github.com/lczyk/spread-bread/releases/latest/download/spread-linux-amd64.sha256 | sha256sum -c -
```

verify the cosign signature (keyless OIDC, no account):

```
curl -fsSL https://github.com/lczyk/spread-bread/releases/latest/download/spread-linux-amd64.cosign.bundle -o spread.cosign.bundle
cosign verify-blob --bundle spread.cosign.bundle \
    --certificate-identity-regexp '^https://github\.com/lczyk/spread-bread/' \
    --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
    /usr/local/bin/spread
```

the cert-identity regex above is approximate; consult the actual issued cert on the first signed release if `cosign verify-blob` rejects it.

## layout (for contributors)

```
spread-bread/
  makefile                       # build images + generate inlined yamls + run contract tests
  hack/
    build_binaries.sh            # cross-compile chisel + spread + docker cli in one ubuntu/go builder
    build_image.sh               # per-image build w/ hash-stamp short-circuit
    hash_inputs.sh               # per-image input hash (drives stamp invalidation)
    check_base.sh                # detect upstream ubuntu base digest drift; rewrite @sha256 pins
    inline_scripts.rb            # splice scripts/*.sh into yaml templates
  scripts/                       # allocate / discard scripts, one pair per flavour
  images/                        # one Dockerfile per (flavour, ubuntu version)
  templates/                     # yaml templates with `source scripts/...` markers
  inlined/                       # generated self-contained spread yamls (release artefacts)
  cache/binaries/                # gitignored; cross-compiled chisel / spread / docker per arch
  demo/                          # worked example with local builds + a small test suite
    spread.yaml                  # hand-maintained inlined yaml, LTS-only (24.04 + 26.04, both arches)
    makefile
    tests/{unit,integration,lib}/
  tests/                         # spread-in-spread contract tests against the inlined yamls
    spread.yaml                  # outer spread (uses the bread-test image as its system)
    Dockerfile.bread-test-26.04  # test-host image: bread:26.04 + docker + spread (not published)
    contract-{bread,bread-chisel-releases}/run/task.yaml
    _inner-{bread,bread-chisel-releases}/contract/task.yaml
  .github/workflows/             # ci (build + test) on PR / push to main; release on r* tag; daily base-refresh
```

## using (contributor / dev)

default goal is `help`:

```
make           # list targets
make all       # build all images + generate inlined yamls
```

narrow the matrix via `VER` / `ARCH`:

```
make build-bread VER=24.04
make build-bread VER=24.04 ARCH=amd64
make build-bread-chisel-releases ARCH=arm64
```

regenerate distribution yamls (already committed under `inlined/`, but regenerate after script edits):

```
make inlined-yaml-files
```

run the demo (LTS systems only -- 24.04 + 26.04 x amd64 / arm64). builds the required `bread` images first if missing:

```
make demo
```

run the spread-in-spread contract tests against the locally-built images (same as ci):

```
cd tests && spread
```

the outer spreads a `bread-test` container; that container runs an inner spread against each inlined yaml; the inner asserts the contract (ubuntu version + arch match the system name, plus `chisel --version` + tool presence for the chisel flavour).

## publishing

`release.yaml` triggers on push of an `r[0-9]+` tag. on success it:

- builds the binary cache + all images -- amd64 / arm64 on per-arch native runners, s390x / ppc64le under qemu.
- pushes 8 multiarch manifests to `ghcr.io/lczyk/spread-bread/{bread,bread-chisel-releases}:<ver>`.
- attaches `inlined/*.yaml` to a rolling github release called `yamls`. older `r*` releases are deleted (release objects only; the underlying tags stay).

ci (`ci.yaml`) is build + test on every PR + push to main; no publish.

anyway, here is this project's pet bread:

```
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣴⣶⣿
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣴⣿⣿⣿⣿⡟
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠤⣤⣄⣉⠙⢻⡟⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠴⢿⣷⣦⣤⣈⣉⣀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⠒⠶⣶⣦⣤⣈⠙⢻⡟⠁⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠐⠾⢿⣷⣦⣤⣤⣤⣤⡤⠊⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣀⠐⠶⣶⣤⣄⡉⠻⣿⣿⠏⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠾⢿⣿⣦⣤⣬⣉⣉⣤⠞⠁⠀⠀⠀⠀⠀⠀⠀⠀
⠀⢠⣄⠑⠲⠤⣈⠙⢻⣿⡿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⢀⣿⣿⣿⣶⣦⣤⣤⠞⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠸⣿⣿⣿⠿⠟⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
```