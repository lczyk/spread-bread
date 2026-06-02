.DEFAULT_GOAL := help

DOCKER ?= docker

# Rock dirs = every subdir with a rockcraft.yaml (tests/ has none).
DIRS := $(patsubst %/rockcraft.yaml,%,$(wildcard */rockcraft.yaml))

# Native arch for the default `test` filter (uname -m -> docker/spread arch).
# Accept both linux (x86_64/aarch64) and macos/docker (amd64/arm64) spellings.
UNAME_M := $(shell uname -m)
ifeq ($(filter $(UNAME_M),x86_64 amd64),$(UNAME_M))
  NATIVE_ARCH := amd64
else ifeq ($(filter $(UNAME_M),aarch64 arm64),$(UNAME_M))
  NATIVE_ARCH := arm64
else
  $(error unsupported host arch: $(UNAME_M))
endif

# Default spread filter: every rock dir on the native arch.
SPREAD_FILTER ?= $(addprefix rock:,$(addsuffix -$(NATIVE_ARCH),$(DIRS)))

.PHONY: help
help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+%?:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "rock dirs: $(DIRS)"

# Pack one rock dir, e.g. `make build-bread-24.04`. Syncs the shared
# hack/patches first, then short-circuits on a stamp of all build inputs so it
# only repacks on a real change. rockcraft names the artefact
# <name>_<ver>_<arch>.rock (underscores); the predictable <dir>.rock has none,
# so `*_*.rock` only ever matches the freshly-packed file.
.PHONY: build-%
build-%:  ## Pack one rock (make build-<dir>)
	@ruby sync_shared.rb $*
	@cd $* && \
		new=$$(hack/hash_inputs.sh) ; cur=$$(cat .rock.stamp 2>/dev/null || true) ; \
		if [ "$$new" = "$$cur" ] && [ -f $*.rock ]; then \
			echo "==> $* up-to-date" ; \
		else \
			echo "==> packing $*" ; \
			rockcraft pack --verbosity=brief && mv *_*.rock $*.rock && echo "$$new" > .rock.stamp ; \
		fi

.PHONY: build-all
build-all: $(addprefix build-,$(DIRS))  ## Pack every rock (narrow via DIRS="bread-24.04 ...")

.PHONY: load
load:  ## Load every built rock into the local daemon as spread-rock-<dir>:latest
	@for d in $(DIRS); do \
		f="$$d/$$d.rock" ; \
		[ -f "$$f" ] || { echo "skip $$d (no $$f)"; continue; } ; \
		echo "==> load $$f -> spread-rock-$$d:latest" ; \
		skopeo --insecure-policy copy "oci-archive:$$f" "docker-daemon:spread-rock-$$d:latest" ; \
	done

.PHONY: test
test: build-all load  ## Build + load all rocks, then run the top-level spread suite (native arch)
	cd tests && spread $(SPREAD_FILTER)

.PHONY: spread-only
spread-only: load  ## Load prebuilt rocks + run spread, no packing (for ci where rocks are downloaded)
	cd tests && spread $(SPREAD_FILTER)

.PHONY: size
size:  ## Show packed rock sizes
	@for d in $(DIRS); do [ -f $$d/$$d.rock ] && printf '%-32s %s\n' "$$d" "$$(du -h $$d/$$d.rock | cut -f1)" || echo "$$d (not built)" ; done

.PHONY: ls-rock-%
ls-rock-%:  ## List a rock's filesystem (make ls-rock-<dir>)
	@tag=ls-$*-$$$$ ; \
		skopeo --insecure-policy copy oci-archive:$*/$*.rock docker-daemon:$$tag:latest > /dev/null ; \
		cid=$$($(DOCKER) create $$tag:latest) ; \
		$(DOCKER) export $$cid | tar tv ; \
		$(DOCKER) rm $$cid > /dev/null ; \
		$(DOCKER) rmi $$tag:latest > /dev/null

.PHONY: clean
clean:  ## Remove packed rocks, stamps, synced hack/patches + loaded tags
	@for d in $(DIRS); do rm -f $$d/$$d.rock $$d/.rock.stamp ; rm -rf $$d/hack $$d/patches ; done
	-@for d in $(DIRS); do $(DOCKER) rmi -f "spread-rock-$$d:latest" 2>/dev/null ; done
