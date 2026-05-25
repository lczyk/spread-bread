# spread-bread

because it rhymes 🤷🏻‍♀️

non-trivial example project + image host for Canonical [`spread`](https://github.com/canonical/spread) testing framework, using prebuilt docker images as the backend.

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

- **`bread`** -- lean: ubuntu + sshd only. for general-purpose spread testing where the test suite installs whatever it needs.
- **`chisel-releases-bread`** -- built on top of lean bread, adds `chisel` + the shell+container tooling typically needed by [chisel-releases](https://github.com/canonical/chisel-releases) spread tests (curl, wget, git, jq, file, sudo, tree, docker.io, skopeo).

## layout

```
spread-bread/
  makefile                       # build images + generate inlined yamls
  hack/
    inline_scripts.py            # splice scripts/*.sh into yaml templates
    hash_inputs.sh               # per-image input hash (drives stamp invalidation)
  scripts/                       # allocate/discard scripts, one pair per flavour
  images/                        # one Dockerfile per (flavour, ubuntu version)
  templates/                     # yaml templates with `source scripts/...` markers
  inlined/                       # generated self-contained spread yamls (distribution artefacts)
  demo/                          # worked example consuming the lean bread images
    spread.yaml                  # hand-maintained inlined yaml, all 6 systems
    makefile
    tests/{unit,integration,lib}/
```

## using

build all images locally:

```
make build-all
```

build a single image:

```
make build-bread-24.04-amd64
make build-chisel-releases-bread-25.10-arm64
```

generate distribution yamls (already committed under `inlined/`, but regenerate after script edits):

```
make inlined-yaml-files
```

run the demo:

```
cd demo && make run
```

## ghcr

images will eventually be published to `ghcr.io/lczyk/spread-bread/{bread,chisel-releases-bread}:<ver>` as multiarch manifests. not yet wired up.
