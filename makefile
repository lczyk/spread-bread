.SUFFIXES:

.DEFAULT_GOAL := run

help:  ## Show this help
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: list
list:  ## List all discovered spread tasks
	@spread -list

.PHONY: run
run: build-images  ## Run spread (default)
	@spread

.PHONY: build-images
build-images:  ## Build the sshd docker images (plucky + noble, arm64 + amd64)
	docker build -t bread-sshd-plucky-arm64 -f images/Dockerfile.sshd-plucky --platform linux/arm64 .
	docker build -t bread-sshd-plucky-amd64 -f images/Dockerfile.sshd-plucky --platform linux/amd64 .
	docker build -t bread-sshd-noble-arm64 -f images/Dockerfile.sshd-noble --platform linux/arm64 .
	docker build -t bread-sshd-noble-amd64 -f images/Dockerfile.sshd-noble --platform linux/amd64 .

.PHONY: clean
clean:  ## Remove spread containers, images, and worker state
	rm -f .spread-worker-num
	rm -f .spread-reuse.yaml
	docker ps -a --filter "name=bread-" --format "{{.ID}}" | xargs -r docker rm -f
	docker images --filter=reference='bread-sshd-*' --format "{{.ID}}" | xargs -r docker rmi -f
