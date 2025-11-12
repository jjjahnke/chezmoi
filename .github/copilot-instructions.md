# Copilot instructions for the chezmoi repository

These are concise, actionable guidelines to help an AI coding assistant be productive when making edits in this repository.

## What matters (big picture)
- This repo is a "declarative development environment" that is provisioned via Ansible.
- The primary entrypoint for setting up a new machine is the `provision.sh` script, which executes the `provision.yml` Ansible playbook.
- The playbook runs `bootstrap.sh` to install toolchains (Go, nvm, pyenv, Vault CLI, etc.).
- After bootstrapping, `chezmoi` manages the dotfiles using Go templates (`*.tmpl`), `private_` and `dot_` naming conventions, and `run_` scripts.
- Secrets are sourced from HashiCorp Vault at apply-time using chezmoi's `vault` template function; secrets must never be committed in plaintext.

## Developer workflows (explicit commands)
- Provision a new machine (automated):
  - `./provision.sh <ip_address>`
- Authenticate to GitHub (one-time manual step after provisioning):
  - `gh auth login`
- Work on chezmoi source files locally:
  - Edit the source via: `chezmoi edit ~/.<filename>`
  - Preview changes: `chezmoi diff`
  - Apply changes locally: `chezmoi apply`
  - Commit changes in the source dir: `chezmoi cd && git add . && git commit -m "msg" && git push`

## Project-specific conventions and patterns
- **Spec Directory:** The `spec/` directory tracks the project's features.
  - Files ending in `_DONE.md` describe features that are **already implemented**.
  - Files **without** the `_DONE` suffix describe planned or in-progress work.
- **Naming Conventions:**
  - `dot_zshrc.tmpl` -> produces `~/.zshrc`
  - `private_dot_kube/...` -> produces `~/.kube/...` with restricted permissions
- **Secret Management:**
  - The Ansible playbook uses a root Vault token stored as an encrypted `!vault` string in `vault_vars.yml`.
  - The `repopulate_vault.sh` script is the single source of truth for creating secrets and the `chezmoi-readonly` policy.
  - `chezmoi` templates use the `vault` function to fetch secrets, e.g., `{{ (vault "secret/personal/api-keys").data.data.gemini_api_key }}`.

## Security rules
- Never add plaintext secrets, tokens, or credentials into the repository.
- Use `private_` prefixes for files that must have restricted permissions.
- When adding a new secret, ensure it is added to the `repopulate_vault.sh` script, including an update to the `chezmoi-readonly` policy within that same script.

## Files to read first when working in this repo
- `README.md` (high-level architecture and user-facing commands)
- `provision.yml` and `provision.sh` (the core provisioning workflow)
- `bootstrap.sh` (system-level tool installation)
- `repopulate_vault.sh.tmpl` (the source of truth for secrets and policies)
- `spec/*.md` (detailed conventions and project status)
