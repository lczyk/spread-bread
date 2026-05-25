.SUFFIXES:
.DEFAULT_GOAL := help

PYTHON ?= python3
DOCKER ?= docker

VERSIONS := 24.04 25.10 26.04
ARCHES   := amd64 arm64

# Helpers to split "<ver>-<arch>" into pieces using `-` as separator.
# Note: ubuntu version contains `.` (not `-`) so a single split is unambiguous.
get_ver   = $(firstword $(subst -, ,$1))
get_arch  = $(lastword $(subst -, ,$1))

VER_ARCH      := $(foreach v,$(VERSIONS),$(foreach a,$(ARCHES),$(v)-$(a)))
BREAD_TARGETS  := $(addprefix build-bread-,$(VER_ARCH))
CHISEL_TARGETS := $(addprefix build-chisel-releases-bread-,$(VER_ARCH))

TEMPLATES := $(wildcard templates/*.yaml.in)
INLINED   := $(patsubst templates/%.yaml.in,inlined/%.yaml,$(TEMPLATES))

SCRIPTS := $(wildcard scripts/*.sh)

.PHONY: help
help:  ## Show this help
	@grep -E '^[a-zA-Z_./%-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-40s\033[0m %s\n", $$1, $$2}'

.PHONY: all
all: build-all inlined-yaml-files  ## Build all images + generate inlined yamls

.PHONY: build-all
build-all: $(BREAD_TARGETS) $(CHISEL_TARGETS)  ## Build all 12 images (lean + chisel, 3 vers x 2 arches)

.PHONY: build-bread
build-bread: $(BREAD_TARGETS)  ## Build all 6 lean bread images

.PHONY: build-chisel-releases-bread
build-chisel-releases-bread: $(CHISEL_TARGETS)  ## Build all 6 chisel-releases-bread images

.PHONY: inlined-yaml-files
inlined-yaml-files: $(INLINED)  ## Generate inlined/*.yaml from templates/*.yaml.in

# Hash-stamp pattern: stamp file contents = hash of all inputs that affect
# this image. FORCE-dep makes us recompute hash each run; stamp mtime only
# updates when content changes, so downstream rebuilds only fire on a real
# input change.
.PHONY: FORCE
FORCE:

.PRECIOUS: .stamp/bread-% .stamp/chisel-releases-bread-%

.stamp:
	@mkdir -p $@

.stamp/bread-%: FORCE | .stamp
	@new=$$(hack/hash_inputs.sh bread-$*) ; \
		cur=$$(cat $@ 2>/dev/null || true) ; \
		if [ "$$new" != "$$cur" ]; then \
			echo "==> building bread:$* (inputs changed)" ; \
			$(DOCKER) build \
				--tag bread:$* \
				--file images/Dockerfile.bread-$(call get_ver,$*) \
				--platform linux/$(call get_arch,$*) \
				. ; \
			echo "$$new" > $@ ; \
		else \
			echo "==> bread:$* up-to-date (stamp matches)" ; \
		fi

.stamp/chisel-releases-bread-%: .stamp/bread-% FORCE | .stamp
	@new=$$(hack/hash_inputs.sh chisel-releases-bread-$*) ; \
		cur=$$(cat $@ 2>/dev/null || true) ; \
		if [ "$$new" != "$$cur" ]; then \
			echo "==> building chisel-releases-bread:$* (inputs changed)" ; \
			$(DOCKER) build \
				--tag chisel-releases-bread:$* \
				--build-arg BASE_TAG=$* \
				--file images/Dockerfile.chisel-releases-bread-$(call get_ver,$*) \
				--platform linux/$(call get_arch,$*) \
				. ; \
			echo "$$new" > $@ ; \
		else \
			echo "==> chisel-releases-bread:$* up-to-date (stamp matches)" ; \
		fi

build-bread-%: .stamp/bread-% ; @:  ## Build a single lean bread image (e.g. build-bread-24.04-amd64)

build-chisel-releases-bread-%: .stamp/chisel-releases-bread-% ; @:  ## Build a single chisel-releases-bread image

inlined/%.yaml: templates/%.yaml.in hack/inline_scripts.py $(SCRIPTS)
	@mkdir -p inlined
	$(PYTHON) hack/inline_scripts.py $< $@

.PHONY: clean
clean:  ## Remove built images, stamps, generated inlined yamls
	-@$(foreach va,$(VER_ARCH), \
		$(DOCKER) rmi -f bread:$(va) chisel-releases-bread:$(va) 2>/dev/null ; )
	rm -rf .stamp
	rm -f $(INLINED)

.PHONY: clean-stamps
clean-stamps:  ## Remove only the .stamp/ dir (forces full rebuild on next run)
	rm -rf .stamp
