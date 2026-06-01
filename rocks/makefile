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
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "rock dirs: $(DIRS)"

.PHONY: build-all
build-all:  ## Pack every rock (narrow via DIRS="bread-24.04 ...")
	@for d in $(DIRS); do echo "==> build $$d" && $(MAKE) -C $$d build || exit 1; done

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

.PHONY: clean
clean:  ## Per-dir clean + remove the loaded spread-rock-* tags
	@for d in $(DIRS); do $(MAKE) -C $$d clean ; done
	-@for d in $(DIRS); do $(DOCKER) rmi -f "spread-rock-$$d:latest" 2>/dev/null ; done
