.SUFFIXES:
.DEFAULT_GOAL := help

.PHONY: help
help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: list
list:  ## List all discovered spread tasks
	@spread -list

.PHONY: run
run:  ## Run spread (requires bread images already built; see top-level makefile)
	@spread

.PHONY: clean
clean:  ## Remove spread worker state + lingering demo containers
	rm -f .spread-worker-num
	rm -f .spread-reuse.yaml
	@docker ps -a --filter "name=bread-" --format "{{.ID}}" | xargs -r docker rm -f
