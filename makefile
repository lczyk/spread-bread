.SUFFIXES:
.DEFAULT_GOAL := help

PYTHON ?= python3
DOCKER ?= docker

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

.PRECIOUS: .stamp/bread-% .stamp/bread-chisel-releases-%

.stamp:
	@mkdir -p $@

.stamp/bread-%: FORCE | .stamp
	@hack/build_image.sh bread-$*

.stamp/bread-chisel-releases-%: .stamp/bread-% FORCE | .stamp
	@hack/build_image.sh bread-chisel-releases-$*

inlined/%.yaml: templates/%.yaml.in hack/inline_scripts.py $(SCRIPTS)
	@mkdir -p inlined
	$(PYTHON) hack/inline_scripts.py $< $@

.PHONY: clean
clean:  ## Remove built images, stamps, generated inlined yamls
	-@$(foreach va,$(FULL_VER_ARCH), \
		$(DOCKER) rmi -f bread:$(va) bread-chisel-releases:$(va) 2>/dev/null ; )
	rm -rf .stamp
	rm -f $(INLINED)

.PHONY: clean-stamps
clean-stamps:  ## Remove only the .stamp/ dir (forces full rebuild on next run)
	rm -rf .stamp
