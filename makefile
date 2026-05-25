.SUFFIXES:
.DEFAULT_GOAL := help

PYTHON ?= python3
DOCKER ?= docker

# Cross-compiled go binaries baked into bread-chisel-releases + bread-test.
# Pinned to specific upstream commits for reproducibility.
CHISEL_REF := 5fb43b8f3e7ec3fcc854f3c84a4668a5cefd9848
SPREAD_REF := 9fdce848027b944a50d25ed2271f17c213b44bd5
GO_BUILDER_IMAGE := ubuntu/go:1.25-26.04_edge
# Docker CLI fetched from docker.com static; ubuntu apt's docker.io is built
# with go 1.24 and crashes under qemu emulation, so we ship upstream's static.
DOCKER_VERSION := 29.5.2

# Full matrix.
VERSIONS := 24.04 25.10 26.04
ARCHES   := amd64 arm64

# Optional narrowing via env vars, e.g.:
#   make build-bread VER=24.04
#   make build-bread VER=24.04 ARCH=amd64
#   make build-bread-chisel-releases ARCH=arm64
VER  ?=
ARCH ?=
SELECTED_VERS   := $(if $(strip $(VER)),$(VER),$(VERSIONS))
SELECTED_ARCHES := $(if $(strip $(ARCH)),$(ARCH),$(ARCHES))
SELECTED_VER_ARCH := $(foreach v,$(SELECTED_VERS),$(foreach a,$(SELECTED_ARCHES),$(v)-$(a)))

# Full (non-narrowed) matrix used by `clean` so it nukes everything.
FULL_VER_ARCH := $(foreach v,$(VERSIONS),$(foreach a,$(ARCHES),$(v)-$(a)))

BREAD_STAMPS  := $(addprefix .stamp/bread-,$(SELECTED_VER_ARCH))
CHISEL_STAMPS := $(addprefix .stamp/bread-chisel-releases-,$(SELECTED_VER_ARCH))

# The test-host image only exists at 26.04. ARCH narrowing applies.
BREAD_TEST_STAMPS := $(addprefix .stamp/bread-test-26.04-,$(SELECTED_ARCHES))

TEMPLATES := $(wildcard templates/*.yaml.in)
INLINED   := $(patsubst templates/%.yaml.in,inlined/%.yaml,$(TEMPLATES))

SCRIPTS := $(wildcard scripts/*.sh)

.PHONY: help
help:  ## Show this help
	@grep -E '^[a-zA-Z_./-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-40s\033[0m %s\n", $$1, $$2}'

.PHONY: all
all: build-all inlined-yaml-files  ## Build all images + generate inlined yamls

.PHONY: build-all
build-all: build-bread build-bread-chisel-releases  ## Build all images (narrow via VER=... ARCH=...)

.PHONY: build-bread
build-bread: $(BREAD_STAMPS)  ## Build bread images (narrow via VER=... ARCH=...)

.PHONY: build-bread-chisel-releases
build-bread-chisel-releases: $(CHISEL_STAMPS)  ## Build bread-chisel-releases images (narrow via VER=... ARCH=...)

.PHONY: build-bread-test
build-bread-test: $(BREAD_TEST_STAMPS)  ## Build the bread-test (26.04 only, both arches) test-host image

# Demo runs only on LTS versions (24.04, 26.04) x both arches, regardless of VER/ARCH narrowing.
DEMO_STAMPS := $(foreach a,$(ARCHES),.stamp/bread-24.04-$(a) .stamp/bread-26.04-$(a))

.PHONY: demo
demo: $(DEMO_STAMPS)  ## Run the spread demo on LTS systems (24.04 + 26.04, both arches)
	$(MAKE) -C demo run

.PHONY: inlined-yaml-files
inlined-yaml-files: $(INLINED)  ## Generate inlined/*.yaml from templates/*.yaml.in

# Hash-stamp pattern: stamp file contents = hash of all inputs that affect
# this image. FORCE-dep makes us recompute hash each run; stamp content only
# updates when inputs change, so downstream rebuilds only fire on a real
# input change. Heavy lifting lives in hack/build_image.sh.
.PHONY: FORCE
FORCE:

.PRECIOUS: .stamp/bread-% .stamp/bread-chisel-releases-% .stamp/bread-test-% .stamp/binaries

.stamp:
	@mkdir -p $@

# Cross-compile chisel + spread for both arches via a single
# Canonical ubuntu/go:1.25-26.04_edge builder container. Stamp content =
# hash of inputs (CHISEL_REF + SPREAD_REF + builder image + script).
BINARIES_ENV := CHISEL_REF="$(CHISEL_REF)" SPREAD_REF="$(SPREAD_REF)" GO_BUILDER_IMAGE="$(GO_BUILDER_IMAGE)" DOCKER_VERSION="$(DOCKER_VERSION)"

.stamp/binaries: FORCE | .stamp
	@set -e ; \
		new=$$($(BINARIES_ENV) hack/hash_inputs.sh binaries) ; \
		cur=$$(cat $@ 2>/dev/null || true) ; \
		if [ "$$new" != "$$cur" ]; then \
			echo "==> building go binaries (chisel + spread + docker, both arches)" ; \
			$(BINARIES_ENV) hack/build_binaries.sh ; \
			echo "$$new" > $@ ; \
		else \
			echo "==> go binaries up-to-date (stamp matches)" ; \
		fi

.stamp/bread-%: FORCE | .stamp
	@hack/build_image.sh bread-$*

.stamp/bread-chisel-releases-%: .stamp/bread-% .stamp/binaries FORCE | .stamp
	@hack/build_image.sh bread-chisel-releases-$*

.stamp/bread-test-%: .stamp/bread-% .stamp/binaries FORCE | .stamp
	@hack/build_image.sh bread-test-$*

inlined/%.yaml: templates/%.yaml.in hack/inline_scripts.py $(SCRIPTS)
	@mkdir -p inlined
	$(PYTHON) hack/inline_scripts.py $< $@

.PHONY: clean
clean:  ## Remove built images, stamps, generated inlined yamls, cached binaries
	-@$(foreach va,$(FULL_VER_ARCH), \
		$(DOCKER) rmi -f bread:$(va) bread-chisel-releases:$(va) 2>/dev/null ; )
	-@$(foreach a,$(ARCHES), \
		$(DOCKER) rmi -f bread-test:26.04-$(a) 2>/dev/null ; )
	rm -rf .stamp
	rm -rf cache
	rm -f $(INLINED)

.PHONY: clean-stamps
clean-stamps:  ## Remove only the .stamp/ dir (forces full rebuild on next run)
	rm -rf .stamp
