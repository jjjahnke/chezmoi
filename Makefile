# Makefile for managing the Dockerized Development Environment

# Variables
IMAGE_NAME ?= jahnke/dev-env
IMAGE_TAG  ?= latest
CONTAINER_NAME ?= dev-container-$(shell openssl rand -hex 3)

.PHONY: help build run validate

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  build    Build the Docker image ('$(IMAGE_NAME):$(IMAGE_TAG)')"
	@echo "  run      Run a new development container. Pass a custom name with 'make run CONTAINER_NAME=my-session'"
	@echo "  validate Run the nightly-loop stub-engine regression test against bin/executable_nightly-loop.sh"
	@echo "  help     Show this help message"

build:
	@echo "--> Building Docker image: $(IMAGE_NAME):$(IMAGE_TAG)..."
	@docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "--> Build complete."

run:
	@echo "--> Launching new development container named '$(CONTAINER_NAME)'..."
	@./scripts/run-dev-container.sh --name "$(CONTAINER_NAME)" --image "$(IMAGE_NAME):$(IMAGE_TAG)"

# The loop gate for this repo: a deterministic stub-engine test of the harness in
# the source tree (not ~/bin, which changes only on chezmoi apply). No model, no network.
validate:
	@bash tests/nightly-loop-test.sh bin/executable_nightly-loop.sh
