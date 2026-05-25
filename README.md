# spread-bread

because it rhymes 🤷🏻‍♀️

non-trivial example project + image host for Canonical [`spread`](https://github.com/canonical/spread) testing framework, using prebuilt docker images as the backend.

here is this project's pet bread:

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

## flavours

two image flavours, each for ubuntu 24.04, 25.10, 26.04 x amd64/arm64:

- **`bread`** -- base image: ubuntu + sshd. general-purpose spread system; the test suite installs whatever else it needs.
- **`bread-chisel-releases`** -- built on top of bread, adds `chisel` + the shell + container tooling typically needed by [chisel-releases](https://github.com/canonical/chisel-releases) spread tests (curl, wget, git, jq, file, sudo, tree, docker.io, skopeo).

## layout

```
spread-bread/
  makefile                       # build images + generate inlined yamls
  hack/
    build_image.sh               # per-image build w/ hash-stamp short-circuit
    hash_inputs.sh               # per-image input hash (drives stamp invalidation)
    inline_scripts.py            # splice scripts/*.sh into yaml templates
  scripts/                       # allocate/discard scripts, one pair per flavour
  images/                        # one Dockerfile per (flavour, ubuntu version)
  templates/                     # yaml templates with `source scripts/...` markers
  inlined/                       # generated self-contained spread yamls (distribution artefacts)
  demo/                          # worked example consuming the bread images
    spread.yaml                  # hand-maintained inlined yaml, LTS-only (24.04 + 26.04, both arches)
    makefile
    tests/{unit,integration,lib}/
```

## using

default goal is `help`:

```
make           # list targets
make all       # build all images + generate inlined yamls
```

build all images locally:

```
make build-all
```

narrow the matrix via `VER` / `ARCH`:

```
make build-bread VER=24.04
make build-bread VER=24.04 ARCH=amd64
make build-bread-chisel-releases ARCH=arm64
```

generate distribution yamls (already committed under `inlined/`, but regenerate after script edits):

```
make inlined-yaml-files
```

run the demo (LTS systems only -- 24.04 + 26.04 x amd64/arm64). builds the required `bread` images first if missing:

```
make demo
```

## ghcr

images will eventually be published to `ghcr.io/lczyk/spread-bread/{bread,bread-chisel-releases}:<ver>` as multiarch manifests. not yet wired up.

