# Specification: Consolidate Configuration into `.chezmoidata.toml`

**Status:** Not Started

## Overview

The current AWS configuration uses a robust pattern where profiles are defined as a list of objects in `.chezmoidata.toml`. The `chezmoi` templates then loop through this data to generate the final `~/.aws/config` and `~/.aws/credentials` files.

This pattern is not currently used for the Docker or Kubernetes configurations, which are more hardcoded in their respective templates. This creates inconsistency and makes adding new Docker registries or Kubernetes clusters more difficult than it needs to be.

## Goal

The goal of this task is to refactor the Docker and Kubernetes configurations to follow the same data-driven pattern as the AWS configuration.

## Proposed Steps

### Docker Refactor
1.  **Update `.chezmoidata.toml`:** Add a new section, `[data.docker.registries]`, that defines a list of Docker registries, each with a URL and a `vaultSecretPath`.
2.  **Update `private_dot_docker/config.json.tmpl`:** Rewrite this template to loop through the `data.docker.registries` list and dynamically generate the `auths` block.

### Kubernetes Refactor
1.  **Update `.chezmoidata.toml`:** Add a new section, `[data.kubernetes.clusters]`, that defines a list of clusters, each with a name and a `vaultSecretPath`.
2.  **Update Kubernetes Templates:** Refactor the templates in `private_dot_kube/configs/` to be data-driven. This might involve creating a single template that loops and generates a merged kubeconfig, or having a script that loops and generates the individual files.

## Benefits
- Improved consistency across the entire configuration.
- Simplified process for adding new Docker registries or Kubernetes clusters (only need to edit `.chezmoidata.toml`).
- Reduced hardcoding in templates.
