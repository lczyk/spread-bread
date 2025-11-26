
.DEFAULT_GOAL := run

.PHONY: list
list:
	@spread -list

.PHONY: run
run: build-images
	@spread
	@$(MAKE) cleanup-spread-worker-files

.PHONY: build-images
build-images:
	docker build -t sshd-plucky-arm64 -f images/Dockerfile.sshd-plucky --platform linux/arm64 .
	docker build -t sshd-plucky-amd64 -f images/Dockerfile.sshd-plucky --platform linux/amd64 .
	docker build -t sshd-noble-arm64 -f images/Dockerfile.sshd-noble --platform linux/arm64 .
	docker build -t sshd-noble-amd64 -f images/Dockerfile.sshd-noble --platform linux/amd64 .

.PHONY: cleanup-spread-worker-files
cleanup-spread-worker-files:
	rm -f .spread-worker-lock
	rm -f .spread-worker-num