
.DEFAULT_GOAL := run

.PHONY: list
list:
	@spread -list

.PHONY: run
run: build-images
	@spread

.PHONY: build-images
build-images:
	docker build -t bread-sshd-plucky-arm64 -f images/Dockerfile.sshd-plucky --platform linux/arm64 .
	docker build -t bread-sshd-plucky-amd64 -f images/Dockerfile.sshd-plucky --platform linux/amd64 .
	docker build -t bread-sshd-noble-arm64 -f images/Dockerfile.sshd-noble --platform linux/arm64 .
	docker build -t bread-sshd-noble-amd64 -f images/Dockerfile.sshd-noble --platform linux/amd64 .

.PHONY: clean
clean:
	rm -f .spread-worker-num
	rm -f .spread-reuse.yaml
	# remove just the spread bread containers
	docker ps -a --filter "name=bread-" --format "{{.ID}}" | xargs -r docker rm -f
	# remove the above images
	docker images --filter=reference='bread-sshd-*' --format "{{.ID}}" | xargs -r docker rmi -f