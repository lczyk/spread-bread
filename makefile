.SUFFIXES:
.DEFAULT_GOAL := help

DOCKER ?= docker

# Cross-compiled go binaries baked into bread-chisel-releases + bread-test.
# Pinned to specific upstream commits for reproducibility.
CHISEL_REF := v1.4.2
SPREAD_REF := 9fdce848027b944a50d25ed2271f17c213b44bd5
GO_BUILDER_IMAGE := ubuntu/go:1.25-26.04_edge
# Docker CLI built from docker/cli source at tag v$(DOCKER_VERSION); ubuntu
# apt's docker.io is built with go 1.24 and crashes under qemu emulation, and
# docker.com's static tarballs don't cover s390x / ppc64le.
DOCKER_VERSION := 29.5.2

# Full matrix.
VERSIONS := 22.04 24.04 25.10 26.04 26.10
ARCHES   := amd64 arm64 s390x ppc64le
# Arches with native runners (local dev + ci). s390x / ppc64le images build
# under qemu and publish untested; tests + demo stay on the native pair.
NATIVE_ARCHES := amd64 arm64

# Optional narrowing via env vars, e.g.:
#   make build-bread VER=24.04
#   make build-bread VER=24.04 ARCH=amd64
#   make build-bread-chisel-releases ARCH=arm64
VER  ?=
ARCH ?=
SELECTED_VERS   := $(if $(strip $(VER)),$(VER),$(VERSIONS))
SELECTED_ARCHES := $(if $(strip $(ARCH)),$(ARCH),$(ARCHES))
SELECTED_VER_ARCH := $(foreach v,$(SELECTED_VERS),$(foreach a,$(SELECTED_ARCHES),$(v)-$(a)))

# Host-arch detection (uname -m -> docker arch name). SELECTED_ARCH defaults to
# the host arch but honours an explicit ARCH=... override.
HOST_ARCH   := $(shell uname -m | sed -e 's/^x86_64$$/amd64/' -e 's/^aarch64$$/arm64/')
SELECTED_ARCH := $(if $(strip $(ARCH)),$(ARCH),$(HOST_ARCH))

# Full (non-narrowed) matrix used by `clean` so it nukes everything.
FULL_VER_ARCH := $(foreach v,$(VERSIONS),$(foreach a,$(ARCHES),$(v)-$(a)))

BREAD_STAMPS  := $(addprefix .stamp/bread-,$(SELECTED_VER_ARCH))
CHISEL_STAMPS := $(addprefix .stamp/bread-chisel-releases-,$(SELECTED_VER_ARCH))

# The test-host image only exists at 26.04, native arches only. ARCH
# narrowing applies.
BREAD_TEST_STAMPS := $(addprefix .stamp/bread-test-26.04-,$(if $(strip $(ARCH)),$(ARCH),$(NATIVE_ARCHES)))

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
build-bread-test: $(BREAD_TEST_STAMPS)  ## Build the bread-test (26.04 only, native arches) test-host image

# Run the contract/integration spread suite (tests/spread.yaml). Builds the
# test-host image + inlined yamls first. Pass extra spread args via SPREAD_ARGS,
# e.g. make test SPREAD_ARGS='-debug'.
SPREAD_ARGS ?=
# The contract-bread-chisel-releases run task allocates the per-version
# bread-chisel-releases:<ver>-<arch> images via the host docker socket, so all
# four versions (host arch) must exist before the suite runs.
# List the bread base stamps explicitly (not just via the chisel-releases
# prereq) so make builds them as direct goals -- the .stamp/bread-% pattern
# also matches bread-chisel-releases-%, so chained-implicit base builds are
# unreliable.
TEST_STAMPS := .stamp/bread-test-26.04-$(SELECTED_ARCH) \
	$(foreach v,$(VERSIONS),.stamp/bread-$(v)-$(SELECTED_ARCH) .stamp/bread-chisel-releases-$(v)-$(SELECTED_ARCH))
.PHONY: test
test: $(TEST_STAMPS) inlined-yaml-files  ## Run the spread test suite (host arch; ARCH=... to override, SPREAD_ARGS=... for flags)
	cd tests && spread $(SPREAD_ARGS) outer:ubuntu-26.04-$(SELECTED_ARCH)

.PHONY: check-base
check-base:  ## Report upstream ubuntu base-image digest drift (non-zero exit on drift)
	@hack/check_base.sh --check

.PHONY: update-base
update-base:  ## Rewrite base Dockerfile @sha256 pins to the current upstream digests
	@hack/check_base.sh --write

# Demo runs only on LTS versions (24.04, 26.04) x native arches, regardless of VER/ARCH narrowing.
DEMO_STAMPS := $(foreach a,$(NATIVE_ARCHES),.stamp/bread-24.04-$(a) .stamp/bread-26.04-$(a))

.PHONY: demo
demo: $(DEMO_STAMPS)  ## Run the spread demo on LTS systems (24.04 + 26.04, native arches)
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

inlined/%.yaml: templates/%.yaml.in hack/inline_scripts.rb $(SCRIPTS)
	@mkdir -p inlined
	ruby hack/inline_scripts.rb $< $@

.PHONY: shell
shell: .stamp/bread-26.04-$(SELECTED_ARCH)  ## Drop into a bread:26.04 shell (host arch). Override via ARCH=...
	$(DOCKER) run --rm -it \
		--platform "linux/$(SELECTED_ARCH)" \
		bread:26.04-$(SELECTED_ARCH) bash

.PHONY: nuke-spread
nuke-spread:  ## Kill stray spread processes + force-remove bread containers
	-pkill spread
	-$(DOCKER) ps | grep bread | cut -d' ' -f1 | xargs -r $(DOCKER) rm --force

.PHONY: clean
clean:  ## Remove built images, stamps, generated inlined yamls, cached binaries
	-@$(foreach va,$(FULL_VER_ARCH), \
		$(DOCKER) rmi -f bread:$(va) bread-chisel-releases:$(va) 2>/dev/null ; )
	-@$(foreach a,$(NATIVE_ARCHES), \
		$(DOCKER) rmi -f bread-test:26.04-$(a) 2>/dev/null ; )
	rm -rf .stamp
	rm -rf cache
	rm -f $(INLINED)

.PHONY: clean-stamps
clean-stamps:  ## Remove only the .stamp/ dir (forces full rebuild on next run)
	rm -rf .stamp
