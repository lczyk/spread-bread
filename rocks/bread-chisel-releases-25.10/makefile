.DEFAULT_GOAL := help

DOCKER ?= docker

# Predictable artefact name (matches the dir + the spread-rock-<dir> load tag).
ROCK := bread-chisel-releases-25.10.rock

.PHONY: help
help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: $(ROCK)  ## Pack the rock (short-circuits if no inputs changed)

.PHONY: FORCE
FORCE:

.rock.stamp: FORCE
	@new=$$(hack/hash_inputs.sh) ; \
		cur=$$(cat $@ 2>/dev/null || true) ; \
		[ "$$new" = "$$cur" ] || echo "$$new" > $@

$(ROCK): .rock.stamp
	rockcraft pack --verbosity=brief
	mv bread-chisel-releases_25.10_*.rock $(ROCK)

.PHONY: size
size:  ## Show the packed rock size
	@if [ -f $(ROCK) ]; then du -h $(ROCK) | cut -f1; else echo "$(ROCK) not built"; fi

.PHONY: ls-rock
ls-rock: $(ROCK)  ## List the rock filesystem (skopeo -> docker export -> tar tv)
	@tag=bread-cr-ls-$$$$ ; \
		skopeo --insecure-policy copy oci-archive:$(ROCK) docker-daemon:$$tag:latest > /dev/null ; \
		cid=$$($(DOCKER) create $$tag:latest) ; \
		$(DOCKER) export $$cid | tar tv ; \
		$(DOCKER) rm $$cid > /dev/null ; \
		$(DOCKER) rmi $$tag:latest > /dev/null

.PHONY: clean
clean:  ## Remove the packed rock + stamp
	rm -f $(ROCK) .rock.stamp
