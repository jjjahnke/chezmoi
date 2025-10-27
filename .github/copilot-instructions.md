# Copilot instructions for the chezmoi repository

These are concise, actionable guidelines to help an AI coding assistant be productive when making edits in this repository.

Short contract
- Input: a requested change to repository dotfiles, bootstrap scripts, or supporting docs.
- Output: a small, focused change (file edit(s), test, or doc) that follows the project's declarative, idempotent, and secrets-safe patterns.
- Error modes: don't add secrets into the repo, avoid breaking the bootstrap idempotency, don't assume Vault credentials are available.

What matters (big picture)
- This repo is a "declarative development environment" built around two phases:
  1. An idempotent bootstrap script (`bootstrap.sh`) that installs toolchains (Homebrew, Go, nvm, pyenv, Vault CLI, kubectl, etc.).
  2. A `chezmoi`-managed dotfiles repository using Go templates (`*.tmpl`), `private_` and `dot_` naming conventions, and `run_` scripts to perform imperative work during apply.
- Secrets are sourced from HashiCorp Vault at apply-time using chezmoi's `vault` template function; secrets must never be committed in plaintext.
- The repository is used to produce user home-directory artifacts (e.g., `~/.zshrc`, `~/.aws/config`, `~/.kube/configs/*`) via template execution and file-mode hints (`private_` prefix).

Developer workflows (explicit commands)
- Bootstrap a machine (idempotent):
  - /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jjjahnke/chezmoi/main/bootstrap.sh)"
- Initialize and apply the chezmoi repo:
  - chezmoi init --apply jjjahnke/chezmoi
- Work on chezmoi source files locally:
  - Edit the source via: chezmoi edit ~/.<filename> (e.g., `chezmoi edit ~/.gitconfig`)
  - Preview changes: `chezmoi diff`
  - Apply changes locally: `chezmoi apply`
  - Commit changes in the source dir: `chezmoi cd && git add . && git commit -m "msg" && git push`
- Build/run Docker image for dev environment:
  - make build
  - make run

Project-specific conventions and patterns (explicit examples)
- Naming conventions in chezmoi source (examples in repo):
  - dot_zshrc.tmpl -> produces ~/.zshrc
  - dot_gitconfig.tmpl -> produces ~/.gitconfig
  - private_dot_kube/configs/<cluster>.yaml.tmpl -> produces ~/.kube/configs/<cluster>.yaml with restricted permissions
  - run_once_* and run_onchange_* scripts placed in the source tree; scripts may be templated (`*.tmpl`) and are used to run imperative steps during apply.
- Template usage:
  - Use built-in `.chezmoi` variables (e.g., `.chezmoi.os`, `.chezmoi.hostname`, `.chezmoi.arch`) for conditionals.
  - Access repo data from `.chezmoidata.toml` and `~/.config/chezmoi/chezmoi.toml` when templating.
  - Vault usage example already present in repo: `{{ (vault "secret/personal/api-keys").data.data.gemini_api_key }}` (see `spec/Adding_Personal_API_Key_from_Vault.md`).
- Security rules:
  - Never add secrets or Vault tokens into the repository.
  - Use `private_` prefixes where files must be created with strict permissions (e.g., SSH, kube configs).
  - When modifying templates that reference Vault, ensure the bootstrap/run scripts install the `vault` CLI before templates that call `vault` are executed (see `bootstrap.sh` ordering).

Integration points and external dependencies
- HashiCorp Vault: The `chezmoi` templates call the `vault` CLI. Authentication is handled automatically via the AppRole method. During initial setup, Ansible provisions a machine-specific RoleID and SecretID to a file on the VM (`~/.vault-credentials`). On shell startup, a script in `.zshrc` uses these credentials to fetch a temporary, short-lived `VAULT_TOKEN`. The root token is stored in an encrypted Ansible Vault file (`secrets.yml`) and is only used by the Ansible playbook during provisioning.
- chezmoi: the tooling assumes standard chezmoi layout and the use of template evaluation; changes to file naming or templating must preserve expected outputs.
- Docker and Makefile: used to build a pre-baked dev image; `scripts/run-dev-container.sh` is used by `make run`.
- Kubernetes tools: `kubectl`, `kubectx`, and `kubens` are installed by `bootstrap.sh` and used indirectly by the kube config templates in `private_dot_kube/configs/`.

Linter/build/test expectations
- There is no central language-specific build; edits should be minimal and shell/scripting-friendly.
- When modifying shell scripts:
  - Preserve idempotency. Every install step must check for existing installation.
  - Avoid requiring interactive prompts.
- If adding a new script or template, prefer adding a short `spec/` doc explaining the change and how to validate (one or two commands).

Do/Don't quick checklist for edits
- DO: Reference `bootstrap.sh`, `Makefile`, and `spec/` docs when changing workflows.
- DO: Add or update a `spec/` markdown file for any non-trivial change describing how to validate.
- DO: Use `private_` filename prefix for files that must be permission-restricted.
- DO: Keep Vault usage templated and avoid embedding credentials.
- DON'T: Add plaintext secrets, tokens, or credentials into the repo.
- DON'T: Change naming conventions (dot_/private_) without updating chezmoi expectations and docs.

Files to read first when working in this repo
- `README.md` (high-level architecture and commands)
- `bootstrap.sh` (installation order and idempotency patterns)
- `Makefile` and `scripts/run-dev-container.sh` (docker build/run flow)
- `spec/*.md` (detailed conventions and examples)
- `dot_*.tmpl` and `private_*` files at repo root to understand real templates

When unsure ask the user
- Should this change introduce new Vault paths or secrets? (If yes, the change must include `spec/` steps for storing the secret in Vault.)
- Is this change intended for all machines or only a machine context (work vs personal)?

If you modify or add templates, include a short validation example. Example: "Run `chezmoi apply` on a local test user with `VAULT_ADDR` and a short-lived `VAULT_TOKEN` and confirm `~/.zshrc` contains the exported key." 


---

If you'd like, I can refine or shorten any section, or include more precise examples from a specific file.
