# Makefile for managing the Dockerized Development Environment

# Variables
IMAGE_NAME ?= jahnke/dev-env
IMAGE_TAG  ?= latest
CONTAINER_NAME ?= dev-container-$(shell openssl rand -hex 3)

.PHONY: help build run

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  build    Build the Docker image ('$(IMAGE_NAME):$(IMAGE_TAG)')"
	@echo "  run      Run a new development container. Pass a custom name with 'make run CONTAINER_NAME=my-session'"
	@echo "  help     Show this help message"

build:
	@echo "--> Building Docker image: $(IMAGE_NAME):$(IMAGE_TAG)..."
	@docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "--> Build complete."

run:
	@echo "--> Launching new development container named '$(CONTAINER_NAME)'..."
	@./scripts/run-dev-container.sh --name "$(CONTAINER_NAME)" --image "$(IMAGE_NAME):$(IMAGE_TAG)"
