

# **A Unified Architecture for Reproducible Development Environments Across Ephemeral Infrastructure**

## **I. Foundational Architecture: A Unified Framework for Environment Reproducibility**

This document outlines a comprehensive, production-grade architectural blueprint for managing and deploying consistent development environments across a diverse and ephemeral set of platforms. The core objective is to achieve complete automation and reproducibility, with a single Git repository serving as the ultimate source of truth. The proposed architecture is designed to be scalable, secure, and maintainable, reflecting modern DevOps and GitOps best practices.

### **1.1. The Modern Challenge: Managing Configuration Sprawl in Ephemeral Environments**

The contemporary software development landscape is characterized by a shift towards ephemeral, on-demand infrastructure. Development environments are no longer static, long-lived servers but are increasingly provisioned within transient environments like Docker containers, Kubernetes Pods, and dynamically allocated virtual or physical machines.1 This paradigm shift presents a significant challenge: maintaining consistency and reproducibility of developer tooling, configurations (dotfiles), and sensitive credentials (secrets) across this heterogeneous and fleeting landscape.

The user's requirement for a unified solution that spans Preboot Execution Environment (PXE) booted bare-metal servers, containerized workflows, and multi-cluster Kubernetes deployments underscores the complexity of this configuration sprawl. Traditional methods, such as manual setup, bespoke shell scripts, or simple symlink management, are inadequate. They are brittle, error-prone, difficult to scale, and fail to provide the security and auditability required for modern enterprise environments. The mandate to originate the entire process from a single Git repository necessitates a solution grounded in GitOps principles, where the desired state of the system is declared in version control and an automated process drives the actual state towards the desired state.

### **1.2. Selecting the Orchestration Engine: A Comparative Analysis of Dotfile Managers**

The selection of a dotfile manager is the most critical architectural decision, as this tool will serve as the central orchestration engine for applying configurations. The evaluation must prioritize features that address the advanced requirements of cross-platform templating, robust scripting, and, most importantly, secure, integrated secret management.

#### **1.2.1. GNU Stow**

GNU Stow is a "symlink farm manager".2 Its primary and almost exclusive function is to create symbolic links from a set of files stored in a "stow directory" to a "target directory".4 While elegant in its simplicity and effective for basic dotfile organization on a single UNIX-like machine, it is fundamentally unsuited for the complexity of this use case. Its critical limitations include:

* **No Secret Management:** Stow has no built-in capabilities for handling secrets. Sensitive data would need to be managed through a completely separate, out-of-band process, breaking the unified workflow.2  
* **No Templating:** It cannot handle machine-to-machine differences. Managing configurations for different operating systems or roles (e.g., personal vs. work) would require maintaining separate file trees or branches, a practice that is cumbersome and error-prone.6  
* **Platform Limitation:** It is designed primarily for UNIX-like environments and lacks first-class support for Windows.6

#### **1.2.2. yadm (Yet Another Dotfiles Manager)**

Yadm represents an evolution from Stow, functioning as a specialized wrapper around a bare Git repository to manage files in a user's home directory.8 It introduces several improvements, most notably a built-in mechanism for file encryption. Yadm can encrypt specified files using gpg or openssl, allowing the encrypted versions to be safely committed to a Git repository.10 It also supports the concept of "alternative files" to handle variations between systems.

However, yadm's approach to secrets remains file-centric. It relies on whole-file encryption, which can be less flexible than managing individual secret values. Crucially, it lacks the sophisticated, fine-grained integration with external, centralized secret management systems like HashiCorp Vault or cloud-native secret stores, which is a core requirement for a secure and scalable architecture.7

#### **1.2.3. chezmoi**

Chezmoi is a powerful, modern dotfile manager explicitly designed to "manage your dotfiles across multiple diverse machines, securely".11 It is architected from the ground up to solve the exact challenges posed by this use case. Distributed as a single, statically-linked binary with no dependencies, it is exceptionally well-suited for ephemeral environments where bootstrap time and dependency management are critical concerns.7

Unlike Stow's symlink-based approach, chezmoi operates on a declarative model. It computes the desired state of the target directory based on the files and templates in its source directory and then applies the minimal set of changes required to achieve that state.12 This makes it more robust and predictable than managing symlinks directly.

Its key features, which align perfectly with the stated requirements, are:

* **Powerful Templating:** It utilizes Go's text/template engine, allowing a single source file to generate different configurations based on machine attributes like operating system, architecture, hostname, or user-defined variables. This eliminates the need for separate branches or complex shell logic to manage variations.14  
* **Native Secret Management Integration:** This is chezmoi's most significant advantage. It provides first-class support for fetching secrets directly from a wide array of external password managers and secret stores, including HashiCorp Vault, AWS Secrets Manager, 1Password, and many others. Secrets are retrieved in-memory during template execution and injected into the final configuration files, meaning plaintext secrets are never stored on disk in the source repository.16  
* **Extensible Scripting Engine:** Chezmoi can execute scripts during the apply process. Scripts can be configured to run every time, only once per machine, or only when their content changes. This allows for imperative tasks like package installation, system configuration, or dependency bootstrapping to be managed declaratively within the dotfiles repository.14  
* **Cross-Platform Support:** Chezmoi provides first-class support for Linux, macOS, Windows, and other UNIX-like systems from a single codebase.7

The following table synthesizes a comparison of these tools against the critical requirements of this project, demonstrating chezmoi's clear superiority.

| Feature | GNU Stow | yadm | chezmoi |
| :---- | :---- | :---- | :---- |
| **Primary Approach** | Symlink Management | Bare Git Repo Wrapper | Declarative State Management |
| **Distribution** | Perl Script | Bash Script | Single Go Binary |
| **Bootstrap Requirements** | Perl | git | None |
| **Windows Support** | No 6 | Yes 7 | Yes 7 |
| **Templating (Machine Differences)** | No 6 | Alternative Files, Templates 7 | Go Templates 7 |
| **Secret Management** | No 6 | Whole-file Encryption (gpg, openssl) 10 | Yes (Native Integration) 7 |
| **Password Manager Integration** | No 7 | No 7 | Yes 7 |
| **Run Scripts on Apply** | No 6 | Yes (bootstrap script) 7 | Yes (run\_ scripts) 7 |
| **Show Diff Before Apply** | No | Yes 7 | Yes 7 |

Based on this exhaustive analysis, **chezmoi** is the unequivocal choice for the orchestration engine of this architecture.

### **1.3. Architecting for Security: The Imperative of a Centralized Secret Store**

While chezmoi offers robust file encryption capabilities 20, relying on encryption within the Git repository, even for a private one, introduces unnecessary risk and operational overhead. The industry best practice for managing secrets at scale is to use a dedicated, centralized secret management system. This approach decouples the lifecycle of secrets from the configuration code, provides a single, auditable point of control, and enables advanced features like dynamic secrets and automated rotation.

For this architecture, **HashiCorp Vault** is the recommended "Tier 0" authority for all secrets. Vault is a tool built specifically for "secrets management, encryption as a service, and privileged access management".21 It provides a unified, API-driven interface to any secret, backed by strong, identity-based access control and detailed audit logs.21 By integrating Vault, the system gains:

* A single, secure source of truth for all credentials.  
* The ability to generate dynamic, short-lived credentials for services like databases and cloud providers, drastically reducing the risk associated with static secrets.21  
* A robust policy framework for enforcing the principle of least privilege, where applications and users are granted access only to the secrets they explicitly require.22  
* A clear separation of concerns, where the dotfiles repository manages configuration *declarations* and Vault manages sensitive *values*.

Chezmoi's native integration with Vault makes this combination particularly powerful, allowing for the seamless and secure injection of secrets at the moment of configuration application.18

### **1.4. The Unified Bootstrap Flow: An Architectural Overview**

The power of this architecture lies in its standardized, universal bootstrap process, which remains consistent regardless of the underlying provisioning mechanism. The process can be abstracted into a sequence of well-defined stages, transforming a bare machine into a fully configured development environment.

The key to this universality is the chezmoi one-line installer, which acts as a standardized payload. The specific provisioning method—be it a PXE boot script, a Dockerfile RUN instruction, or a Kubernetes Init Container—is merely a trigger mechanism whose sole responsibility is to execute this single command. This design dramatically simplifies the architecture, abstracting away the complexities of each environment's provisioning layer. Instead of engineering three distinct bootstrap workflows, the system relies on one universal bootstrap payload and three simple triggers. This makes the architecture highly extensible; supporting a new platform requires only determining how to execute a shell command on first boot, not re-architecting the entire configuration and secret deployment pipeline.

The end-to-end flow is as follows:

1. **Provisioning:** A new machine instance is created (e.g., via PXE boot, docker run, or kubectl apply).  
2. **Bootstrap Trigger:** A post-installation or container-entrypoint mechanism (e.g., a cloud-init script, a Dockerfile command, or an Init Container) executes the universal chezmoi bootstrap command.  
3. **chezmoi Installation & Initialization:** The one-line command downloads the chezmoi binary and immediately executes chezmoi init \--apply \<git-repo-url\>, which clones the user's dotfiles repository from the specified Git source.11  
4. **Configuration & Templating:** chezmoi reads its configuration file (which can itself be a template), gathers facts about the local machine (OS, architecture, hostname), and evaluates all .tmpl files to compute the target state of the filesystem.  
5. **Secret Injection:** During template evaluation, chezmoi encounters template functions like {{ (vault "...").data.data.password }}. It authenticates to the configured HashiCorp Vault instance (using credentials provided via the environment), fetches the required secrets in memory, and prepares to inject them into the target files.16  
6. **State Application:** chezmoi atomically applies the desired state. It creates configuration files with secrets now embedded, sets file permissions, creates directories and symlinks, and executes any run\_ scripts to install packages or perform other setup tasks.  
7. **Ready State:** The process completes, leaving a fully configured, secure, and ready-to-use development environment.

## **II. Mastering Dotfile and System Management with chezmoi**

A successful implementation hinges on a well-structured and maintainable chezmoi repository. This section provides a detailed blueprint for organizing the repository to maximize scalability, clarity, and automation.

### **2.1. Structuring the dotfiles Git Repository for Scalability**

The layout of the chezmoi source directory (typically \~/.local/share/chezmoi) directly maps to the desired state of the target home directory. Adhering to established conventions is crucial for maintainability.

* **File and Directory Naming:**  
  * Files and directories in the home directory that begin with a dot should be prefixed with dot\_ in the source directory. For example, \~/.zshrc is managed as dot\_zshrc.12  
  * For nested dotfiles, the directory structure should be mirrored. For instance, \~/.config/nvim/init.vim becomes dot\_config/nvim/init.vim in the source directory.25  
  * Files that should be created with restricted permissions (mode 0600\) should be prefixed with private\_. For example, private\_dot\_ssh/config will create \~/.ssh/config with the correct permissions.  
  * Executable files should be prefixed with executable\_.  
* **Script Organization:**  
  * Scripts are a powerful feature for handling imperative tasks. They must be placed in the source directory with a filename beginning with run\_.19  
  * **run\_once\_:** These scripts are executed only once on a given machine. chezmoi tracks their execution by storing a hash of their contents (post-templating) in a local database. They are ideal for initial setup tasks like installing a package manager.14  
  * **run\_onchange\_:** These scripts are executed whenever their contents change. This is perfect for managing lists of packages; when the list is updated, the script re-runs to install the new packages.14  
  * **Execution Order:** The before\_ and after\_ attributes can be added to script filenames (e.g., run\_once\_before\_install-packages.sh) to control whether they execute before or after chezmoi applies file and directory changes.19  
  * **.chezmoiscripts Directory:** To avoid cluttering the source directory with scripts that do not correspond to any file in the home directory, they can be placed in a .chezmoiscripts directory at the root of the source path.19  
* **Data and Externals:**  
  * **.chezmoidata.\<format\>:** To separate data from logic, static values and lists should be stored in a data file like .chezmoidata.toml. This data is then accessible within any template, making it easy to manage things like lists of packages to install without hardcoding them in scripts.14  
  * **.chezmoiexternal.\<format\>:** This file is used to declaratively manage content from external sources. Instead of using git submodules, which chezmoi does not directly support for this purpose, an external definition can pull down and unpack a .tar.gz archive from a URL or clone a Git repository into the source directory. This is the recommended way to manage third-party plugins like Oh My Zsh or Vim plugin managers.26

### **2.2. Dynamic Configuration with the Go Template Engine**

Templating is the core mechanism that enables a single source of truth to manage multiple, diverse machines.14 Any file in the source directory with a .tmpl suffix is processed by Go's text/template engine before its target state is computed.15

* **Core Concepts:**  
  * **Syntax:** Template logic is enclosed in double curly braces, {{ }}. This can include printing a variable ({{.chezmoi.hostname }}), conditional blocks ({{ if eq.chezmoi.os "linux" }}), and loops ({{ range.packages }}).14  
  * **Built-in Variables:** chezmoi provides a rich set of built-in variables under the .chezmoi object, including .chezmoi.os (e.g., "linux", "darwin"), .chezmoi.arch (e.g., "amd64", "arm64"), and .chezmoi.hostname.15 These are the primary inputs for conditional logic.  
  * **Custom Variables:** Data from the .chezmoidata file and the chezmoi configuration file are also available within templates, allowing for highly customized and abstract logic.  
* **Practical Examples:**  
  * **OS-Specific Package Installation:** A script named run\_onchange\_install-packages.sh.tmpl can contain logic to use the correct package manager for the host OS.  
    Go  
    \#\!/bin/sh  
    set \-eu  
    {{ if eq.chezmoi.os "darwin" \-}}  
    \# macOS  
    brew install bat eza fd  
    {{ else if eq.chezmoi.os "linux" \-}}  
    \# Linux (Debian-based)  
    sudo apt-get update  
    sudo apt-get install \-y bat exa fd-find  
    {{ end \-}}

    This pattern ensures that the correct commands are executed on each platform, all from a single script template.14  
  * Context-Specific Configuration (Work vs. Personal): On first run, chezmoi can prompt the user for information to configure the environment. The promptBoolOnce function is particularly useful for setting a persistent variable that defines the machine's context.  
    In .chezmoi.toml.tmpl:  
    Go  
    \[data\]  
      isWorkMachine \= {{ promptBoolOnce. "isWorkMachine" "Is this a work machine?" }}

    Then, in dot\_gitconfig.tmpl:  
    Go  
    \[user\]  
      name \= "Your Name"  
    {{ if.isWorkMachine \-}}  
      email \= {{ (vault "secret/work/identity").data.data.email }}  
    {{ else \-}}  
      email \= {{ (vault "secret/personal/identity").data.data.email }}  
    {{ end \-}}

    This powerful pattern allows a single set of dotfiles to correctly configure distinct identities and settings based on the machine's role, which is determined interactively on the very first run and then remembered.14

### **2.3. Automating Beyond Configuration Files with run\_ Scripts**

Scripts bridge the gap between declarative configuration and the imperative steps often required to bootstrap a full development environment. A well-designed set of scripts can automate package installation, system settings modifications, and dependency setup in an idempotent and reliable manner.

The use of ordered run\_before\_ scripts enables the creation of an implicit dependency graph, which is essential for robust automation. For example, a script named run\_once\_before\_00-install-dependencies.sh can ensure that tools like curl and git are present. A subsequent script, run\_once\_before\_10-install-vault-cli.sh, can then install the HashiCorp Vault CLI. Only after these before scripts have successfully executed will chezmoi proceed to the main apply phase, where it evaluates templates. This sequencing guarantees that when a template calls the vault function, the necessary CLI tool is already installed and available. This structured approach transforms a simple script runner into a reliable, ordered bootstrapping engine, preventing common race conditions and making the entire setup process more resilient and debuggable.

* Use Case: Declarative Package Management:  
  In .chezmoidata.toml:  
  Ini, TOML  
  \[packages\]  
    darwin \= \["ripgrep", "neovim", "tmux"\]  
    linux \= \["ripgrep", "neovim", "tmux"\]

  In run\_onchange\_install-packages.sh.tmpl:  
  Go  
  \#\!/bin/sh  
  set \-eu  
  {{ if eq.chezmoi.os "darwin" \-}}  
  brew install {{.packages.darwin | join " " }}  
  {{ else if eq.chezmoi.os "linux" \-}}  
  sudo apt-get update  
  sudo apt-get install \-y {{.packages.linux | join " " }}  
  {{ end \-}}

  This pattern declaratively defines the desired packages per OS in a central data file. The script, which only re-runs if the template's output changes (i.e., if the package list is modified), handles the imperative installation logic. This is a clean, maintainable, and idempotent approach to software management.14

## **III. A Tiered, Context-Aware Strategy for Secret Management**

A robust secret management strategy requires a multi-layered approach that addresses the different ways secrets are consumed in various environments, from direct injection into a developer's shell configuration to populating native Kubernetes Secret objects. All secrets originate from a single Tier 0 source of truth: HashiCorp Vault.

### **3.1. Tier 0: HashiCorp Vault as the Central Source of Truth**

All sensitive information—API keys, passwords, private SSH keys, certificates—must be mastered and stored in a central HashiCorp Vault instance.

* **Structure:** A Key-Value (KV) Version 2 secrets engine is recommended. Secrets should be organized logically using a path structure that reflects their context, such as secret/dev/github-token or secret/prod/database/postgres-password.30  
* **Access Control:** Access to Vault paths must be governed by strict, identity-based policies. The chezmoi process will authenticate with a specific Vault token and role, granting it read-only access to developer-specific secrets. In Kubernetes, pods will authenticate using a Kubernetes Service Account identity, restricting their access to only the secrets required for their specific application. This enforces the principle of least privilege at every layer.22  
* **chezmoi Integration:** For chezmoi to communicate with Vault, the VAULT\_ADDR and VAULT\_TOKEN environment variables must be present in the shell environment where chezmoi apply is executed. The initial bootstrap token can be provided securely during the provisioning phase.18

### **3.2. Tier 1: User-Level Secrets via chezmoi Template Functions**

For environments where a user is directly interacting with the system (e.g., a developer workstation, a Docker container used for development), chezmoi is the direct consumer of secrets from Vault.

* **Implementation:** chezmoi provides a built-in vault template function. This function executes the vault kv get \-format=json \<path\> command, parses the JSON output, and makes the data available within the template.18 The output is cached per chezmoi run to avoid redundant API calls.  
* **Example Template:** A template for \~/.gitconfig can dynamically pull user identity, and a template for a shell environment file can inject an API key.  
  Go  
  // In source file: private\_dot\_gitconfig.tmpl  
  \[user\]  
    name \= {{ (vault "secret/dev/identity").data.data.name }}  
    email \= {{ (vault "secret/dev/identity").data.data.email }}  
    signingkey \= {{ (vault "secret/dev/identity").data.data.gpg\_key\_id }}

  Go  
  // In source file: dot\_zshrc.d/secrets.tmpl  
  export GITHUB\_TOKEN="{{ (vault "secret/dev/api-keys").data.data.github\_token }}"

This pattern ensures that secrets are fetched at apply-time and exist only in the generated files within the target home directory. The Git repository contains only the non-sensitive templates that reference the secrets.16

### **3.3. Tier 2: Kubernetes Secret Integration Patterns**

Injecting secrets into Kubernetes workloads presents a different challenge. While a developer's shell needs a secret injected directly into a file, a Kubernetes Pod requires that secret to be available as a mounted volume or an environment variable, both of which are sourced from a native Kubernetes Secret object.34 This represents a fundamental difference in consumption models. Attempting to bridge this gap by having chezmoi execute kubectl create secret commands is an imperative anti-pattern that is brittle and insecure. The Kubernetes ecosystem has developed mature, declarative, operator-based patterns to solve this problem correctly. Therefore, secret delivery to Kubernetes must be treated as a distinct architectural pattern.

#### **3.3.1. Pattern A: The GitOps Approach with Sealed Secrets**

This pattern is well-suited for strict GitOps workflows where every resource in the cluster, including secrets, must have a corresponding declaration in a Git repository.

* **Architecture:** A SealedSecret is a Kubernetes Custom Resource that contains a standard Kubernetes Secret encrypted using asymmetric cryptography. The public key is provided by a sealed-secrets-controller running in the target cluster. This controller is the only entity that holds the private key, and thus is the only one capable of decrypting the SealedSecret and creating the corresponding native Secret object in the cluster.35  
* **Workflow:** The kubeseal command-line tool is used to perform the encryption. A chezmoi run\_ script can automate this process:  
  1. Fetch the plaintext secret from Vault.  
  2. Pipe the secret into kubectl create secret generic \<name\> \--from-literal=... \--dry-run=client \-o yaml.  
  3. Pipe the resulting YAML manifest into kubeseal to generate the SealedSecret YAML manifest.  
  4. This encrypted manifest can then be safely stored in the chezmoi Git repository and applied to the cluster.  
* **Trade-offs:** This approach maintains GitOps purity but has drawbacks. Each Kubernetes cluster has a unique sealing key, so secrets must be re-sealed for each target cluster. It also couples the secret's lifecycle to Git commits; rotating a secret requires a new commit and deployment.

#### **3.3.2. Pattern B (Recommended): The Operator Pattern with External Secrets Operator (ESO)**

This is the most robust, scalable, and recommended pattern for managing secrets in Kubernetes. It decouples the secret's lifecycle from the Git repository and enables dynamic, automated updates.

* **Architecture:** The External Secrets Operator (ESO) is a Kubernetes operator that synchronizes secrets from external stores like HashiCorp Vault directly into native Kubernetes Secret objects.38  
* **Workflow:**  
  1. A SecretStore (or ClusterSecretStore) Custom Resource is deployed to the cluster. This resource defines the connection details and authentication method for the Vault instance.40  
  2. In an application's namespace, an ExternalSecret Custom Resource is created. This manifest is a declarative statement of intent, for example: "Fetch the key api-key from the secret at path secret/dev/myapplication in Vault, and synchronize its value into a Kubernetes Secret named myapp-api-key under the key token".40  
  3. The ESO controller continuously watches for these resources. When it sees the ExternalSecret, it authenticates to Vault, retrieves the specified secret value, and creates or updates the target Kubernetes Secret accordingly.  
* **Benefits:** This pattern is superior for several reasons. The ExternalSecret manifest contains no sensitive data and can be safely stored in the chezmoi Git repository. The same manifest can be applied to any cluster where ESO is installed, achieving true portability. Secrets can be rotated in Vault, and ESO will automatically update the corresponding Kubernetes Secret without any changes to the Git repository, enabling dynamic secret management.

The following matrix provides a clear guide for selecting the appropriate secret management strategy based on the target environment.

| Environment | Recommended Pattern | Orchestrator | Rationale |
| :---- | :---- | :---- | :---- |
| Developer Workstation / VM | chezmoi Template Functions | chezmoi | Direct, in-memory injection of secrets into configuration files at apply-time. Secrets are never stored on disk in the source repo. |
| Ephemeral Docker Container | chezmoi Template Functions | chezmoi (--one-shot) | Same as workstation. The \--one-shot flag ensures chezmoi cleans up after itself, leaving a clean environment. |
| Kubernetes (GitOps Workflow) | Sealed Secrets | chezmoi script \+ kubeseal | Encrypted secret representation is stored in Git, aligning with strict GitOps principles. Best for static secrets. |
| Kubernetes (Dynamic/Cloud-Native) | **External Secrets Operator** | Kubernetes Operator | **(Strongly Recommended)** Decouples secret lifecycle from Git. Enables dynamic rotation and true portability of secret declarations. Most secure and scalable option. |

## **IV. Implementation Blueprint: Containerized and Cloud-Native Environments**

This section provides concrete, actionable implementation patterns for the user's container-based workflows, translating the architectural principles into practical examples.

### **4.1. Pattern 1: Building Pre-Configured Docker Images**

For creating consistent, portable, and ready-to-use developer environments, baking the configuration directly into a Docker image is a highly effective strategy. This ensures that every container instantiated from the image is identical and fully set up.

The chezmoi init \--one-shot command is purpose-built for this scenario. It is an atomic operation that combines cloning the repository, applying the state, and then completely removing all traces of chezmoi and its source/cache directories. This results in a clean final image that contains only the generated dotfiles, not the management tooling itself.24

**Example Dockerfile:**

Dockerfile

\# Start from a base image  
FROM ubuntu:22.04

\# Install prerequisite dependencies for chezmoi and secret management  
\# This should include git, curl, and the CLI for your secret manager (e.g., vault)  
RUN apt-get update && \\  
    apt-get install \-y \--no-install-recommends git curl ca-certificates vault && \\  
    rm \-rf /var/lib/apt/lists/\*

\# Pass Vault credentials securely as build-time arguments.  
\# These will not be persisted in the final image layers.  
ARG VAULT\_ADDR  
ARG VAULT\_TOKEN

\# Set the environment variables required by the chezmoi vault function  
ENV VAULT\_ADDR=$VAULT\_ADDR  
ENV VAULT\_TOKEN=$VAULT\_TOKEN

\# Run the chezmoi one-shot installer.  
\# Replace 'your-github-username' with the actual username or full repo URL.  
\# This single command installs chezmoi, clones the dotfiles repo, applies all  
\# configurations and secrets, and then purges itself.  
RUN sh \-c "$(curl \-fsLS get.chezmoi.io)" \-- init \--one-shot your-github-username

\# Unset the VAULT\_TOKEN environment variable to ensure it's not present at runtime.  
\# While build-time ARGs are not in the final layers, cleaning the ENV is good practice.  
ENV VAULT\_TOKEN=""

\# Set the default user and command for the container  
USER developer  
WORKDIR /home/developer  
CMD \["/bin/zsh"\]

This Dockerfile provides a robust template for creating self-contained, fully configured development images. The use of build arguments for the VAULT\_TOKEN is critical for security, as it prevents the token from being baked into the image layers.28

### **4.2. Pattern 2: On-Demand Configuration with Kubernetes Init Containers**

In Kubernetes, it is often desirable to configure an environment at runtime rather than building it into the container image. This is particularly useful when working with persistent volumes (PersistentVolumeClaim) that need to be populated with a user's dotfiles and tools upon pod creation, or when the configuration needs to be dynamically updated without rebuilding an image. Kubernetes Init Containers provide the perfect lifecycle hook for this task.

An Init Container is a specialized container that runs and must complete successfully before the main application containers in a Pod are started.46 This allows for sequential setup tasks, such as environment configuration.

**Example Kubernetes Pod Manifest:**

YAML

apiVersion: v1  
kind: Pod  
metadata:  
  name: ephemeral-dev-pod  
spec:  
  volumes:  
    \# This volume will be shared between the init container and the main container.  
    \# It will be populated with the dotfiles.  
    \- name: home-directory  
      emptyDir: {}

  \# The init container runs first to set up the environment.  
  initContainers:  
    \- name: dotfiles-and-secrets-init  
      \# Use a minimal image that contains the necessary tools (curl, git).  
      image: alpine/git:latest  
      command:  
        \- /bin/sh  
        \- \-c  
        \- |  
          \# Install dependencies within the init container  
          apk add \--no-cache curl

          \# Execute the chezmoi one-shot command to configure the mounted volume  
          \# The HOME environment variable is set to the mount path to ensure  
          \# chezmoi applies the dotfiles to the correct location.  
          sh \-c "$(curl \-fsLS get.chezmoi.io)" \-- init \--one-shot your-github-username  
      env:  
        \# The HOME variable directs chezmoi to the shared volume  
        \- name: HOME  
          value: /home/developer  
        \# The Vault address for the cluster's internal Vault service  
        \- name: VAULT\_ADDR  
          value: "http://vault.default.svc.cluster.local:8200"  
        \# The Vault token is securely sourced from a pre-existing Kubernetes Secret.  
        \# This secret would be created by a cluster administrator or a bootstrap process.  
        \- name: VAULT\_TOKEN  
          valueFrom:  
            secretKeyRef:  
              name: vault-bootstrap-token  
              key: token  
      volumeMounts:  
        \- name: home-directory  
          mountPath: /home/developer

  \# The main application container starts only after the init container succeeds.  
  containers:  
    \- name: development-environment  
      image: ubuntu:22.04 \# A generic base image  
      command: \["/bin/sleep", "3600"\] \# Keep the container running  
      env:  
        \- name: HOME  
          value: /home/developer  
      volumeMounts:  
        \# Mount the configured home directory  
        \- name: home-directory  
          mountPath: /home/developer

In this pattern, the Init Container acts as a dedicated setup stage. It mounts a shared volume, securely receives a Vault token from a Kubernetes Secret, and executes the chezmoi bootstrap process to populate the volume with the complete, secret-infused development environment. The main container then starts, mounting the same volume as its home directory, thereby inheriting the fully configured state without needing any setup logic in its own image.28

## **V. Implementation Blueprint: Bare-Metal and VM Provisioning**

Automating the setup of physical machines provisioned via PXE boot requires integrating the dotfile management workflow into the operating system's post-installation lifecycle. This bridges the gap between low-level hardware provisioning and high-level user environment configuration.

### **5.1. Integrating with the PXE Boot Post-Installation Lifecycle**

The PXE boot process itself is a standardized mechanism for a machine's firmware to download and execute a network boot program, typically an operating system installer.48 The critical phase for our purposes is what happens *after* the base OS has been installed to disk and the machine reboots for the first time.

Modern Linux distributions, including Ubuntu and RHEL derivatives, have largely standardized on cloud-init as the framework for handling this first-boot configuration, even on bare metal.50 cloud-init is a service that runs early in the boot process and searches for configuration data (referred to as user-data and meta-data) from a variety of sources, most commonly an HTTP endpoint specified during the automated installation.52 This user-data can contain declarative instructions and shell scripts to be executed, providing the perfect hook to trigger the chezmoi bootstrap process. This approach supersedes older, distribution-specific mechanisms like Debian Preseed or Red Hat Kickstart.52

During a PXE-based autoinstall, the kernel boot parameters can include a URL pointing to the user-data file, which the cloud-init service on the newly installed system will then fetch and execute.50

### **5.2. The cloud-init user-data Payload**

The user-data file, typically written in YAML format (\#cloud-config), will contain all the necessary steps to prepare the system and launch the universal chezmoi bootstrap command.

**Example user-data.yaml for Automated Provisioning:**

YAML

\#cloud-config

\# 1\. Create the primary development user  
users:  
  \- name: devuser  
    gecos: Development User  
    primary\_group: devuser  
    groups: \[sudo, docker\]  
    sudo: ALL=(ALL) NOPASSWD:ALL  
    shell: /bin/zsh  
    \# It is highly recommended to inject an initial SSH key for access  
    ssh\_authorized\_keys:  
      \- ssh-rsa AAAA... your-public-key

\# 2\. Install prerequisite packages needed for the bootstrap process  
package\_update: true  
packages:  
  \- git  
  \- curl  
  \- zsh  
  \# The vault CLI is required for chezmoi's secret functions  
  \- vault

\# 3\. Execute the chezmoi bootstrap command as the newly created user  
runcmd:  
  \- |  
    \# This command block will be executed by root.  
    \# We must switch to the 'devuser' to run chezmoi in the correct user context.  
    \# The entire script is passed to 'su' to run in a login shell (-l).  
    su \-l devuser \-c " \\  
      export VAULT\_ADDR='http://vault.service.consul:8200'; \\  
      export VAULT\_TOKEN='s.initial-bootstrap-token'; \\  
      sh \-c \\"\\$(curl \-fsLS get.chezmoi.io)\\" \-- init \--apply your-github-username \\  
    "

This user-data script provides a complete, automated workflow for bare-metal systems 57:

1. **User Creation:** It first creates a non-root user with appropriate permissions and shell, which is a security best practice.  
2. **Dependency Installation:** It uses cloud-init's package module to install git, curl, and the vault CLI—all prerequisites for the chezmoi process.  
3. **Bootstrap Execution:** The runcmd module executes the final command. It is critical that this command is run as the devuser, not as root. The su \-l devuser \-c "..." command ensures that the entire bootstrap process, including the cloning of the dotfiles repository and the application of configurations, occurs within the correct user's home directory and with the correct permissions.

A significant security consideration in this workflow is the provisioning of the initial VAULT\_TOKEN. In the example, it is hardcoded for clarity, but in a production environment, it should be a short-lived bootstrap token injected via a secure mechanism, such as parameters passed by the provisioning system (e.g., Harvester's configuration allows for commands 60) or retrieved from a secure metadata service.

## **VI. Advanced Strategy: Cross-Cluster Secret Portability**

A core requirement of this architecture is the ability to easily extract secrets from one Kubernetes cluster and recreate them in another. This portability is crucial for disaster recovery, cluster migration, and standing up new environments. The recommended solution achieves this not by imperatively copying secret data, but by declaratively synchronizing secret definitions from a single source of truth.

### **6.1. The Anti-Pattern: Manual Secret Extraction and Migration**

The most straightforward but deeply flawed approach to migrating secrets is to manually extract them from the source cluster and apply them to the destination. A common command for this is:  
kubectl get secret \<secret-name\> \-n \<namespace\> \-o yaml | kubectl apply \-n \<namespace\> \-f \-  
This method is an anti-pattern for several reasons:

* **Insecurity:** It exposes the Base64-encoded secret data in the terminal, in shell history, and potentially in logs. While Base64 is not plaintext, it offers zero confidentiality and can be trivially decoded.35  
* **Imperative and Error-Prone:** The process is manual, requires direct kubectl access to both clusters, and is susceptible to human error.  
* **Breaks the Source of Truth:** The newly created secret in the destination cluster is a disconnected copy. It is no longer managed by the central secret store (Vault) and will not receive updates if the original secret is rotated. It becomes stale, unmanaged configuration drift.

### **6.2. The Recommended Solution: Declarative Synchronization via External Secrets Operator**

True portability is achieved not by moving data, but by moving *declarations*. The state of the secrets in any given cluster should be a function of declarative manifests stored in Git and the values stored in Vault. The External Secrets Operator (ESO) is the engine that makes this declarative reconciliation possible.

The portability of the secret management system is embodied in the ExternalSecret manifests. These are non-sensitive YAML files that simply point to a secret in Vault. To migrate all secrets to a new cluster, one does not need to touch the secret data itself. Instead, the process involves applying these declarative manifests to the new cluster, and the operator handles the secure fetching and creation of the native Kubernetes Secret objects.

**Step-by-Step Cross-Cluster Migration Procedure:**

1. **Prerequisite: Centralized Secrets:** Ensure all secrets required by your Kubernetes applications are mastered in a single, accessible HashiCorp Vault instance.  
2. Store Declarations in Git: All ExternalSecret manifests, which define the mapping from Vault paths to Kubernetes Secret objects, must be stored in the central chezmoi Git repository. A logical location would be a dedicated subdirectory, such as kubernetes/secrets/. These manifests contain no sensitive data.  
   Example kubernetes/secrets/database-credentials.yaml:  
   YAML  
   apiVersion: external-secrets.io/v1beta1  
   kind: ExternalSecret  
   metadata:  
     name: postgres-credentials  
     namespace: my-app  
   spec:  
     secretStoreRef:  
       name: vault-backend  
       kind: ClusterSecretStore  
     target:  
       name: postgres-credentials-secret \# Name of the K8s Secret to create  
     data:  
     \- secretKey: username  
       remoteRef:  
         key: secret/data/prod/postgres  
         property: username  
     \- secretKey: password  
       remoteRef:  
         key: secret/data/prod/postgres  
         property: password

3. **Bootstrap the New Cluster:** On the new, destination Kubernetes cluster, install the External Secrets Operator. This can be done via its Helm chart.40  
4. **Configure the SecretStore:** Apply the ClusterSecretStore manifest (also stored in the Git repository) to the new cluster. This manifest configures how ESO authenticates to Vault. This is a one-time setup step per cluster.  
5. Apply Declarative Manifests: Apply the directory of ExternalSecret manifests from the Git repository to the new cluster. This can be done with a simple kubectl command or, preferably, through a GitOps controller like ArgoCD that monitors the repository.  
   kubectl apply \-f kubernetes/secrets/  
6. **Automatic Reconciliation:** The External Secrets Operator in the new cluster will detect the ExternalSecret resources. It will then use the configured ClusterSecretStore to authenticate to Vault, fetch the specified secret values, and automatically create the corresponding native Kubernetes Secret objects (e.g., postgres-credentials-secret) in the correct namespaces.

This workflow is idempotent, fully automated, and secure. It perfectly fulfills the requirement for secret portability by treating the ExternalSecret manifests as the portable artifact, while the sensitive data remains securely stored and managed in Vault.39

## **VII. Conclusion and Strategic Roadmap**

### **7.1. Summary of the Integrated Architecture**

The proposed architecture provides a robust, secure, and highly automated solution for managing developer environments across diverse and ephemeral infrastructure. It is founded on a set of synergistic, best-in-class tools, each chosen for its specific strengths:

* **chezmoi as the Orchestration Engine:** Serves as the central point of control, applying declarative state, executing bootstrap scripts, and managing machine-specific configurations through its powerful templating engine.  
* **A Git Repository as the Single Source of Truth:** Contains all configuration *declarations*, including dotfile templates, installation scripts, and Kubernetes manifests for secrets. This enables a fully GitOps-centric workflow.  
* **HashiCorp Vault as the Secret Authority:** Acts as the centralized, secure backend for all sensitive data, decoupling secrets from the configuration repository and providing enterprise-grade access control and lifecycle management.  
* **External Secrets Operator as the Kubernetes Bridge:** Seamlessly and securely synchronizes secrets from Vault into native Kubernetes Secret objects, enabling a declarative and portable approach to secret management in cloud-native environments.

This integrated system allows for the complete, unattended provisioning of a developer environment—from a bare-metal server to a Kubernetes pod—with a single bootstrap command, fulfilling all core requirements of the user query.

### **7.2. Phased Implementation Roadmap**

A phased approach is recommended to ensure a smooth and successful adoption of this architecture.

**Phase 1: Foundation Setup (1-2 Weeks)**

1. **Establish the dotfiles Git Repository:** Create a new Git repository. Install chezmoi on a primary workstation and begin adding core dotfiles (.zshrc, .gitconfig, .vimrc) using chezmoi add.  
2. **Deploy and Configure HashiCorp Vault:** Set up a development instance of HashiCorp Vault. Create an initial KV secrets engine and populate it with a few test secrets, such as a Git user email and a mock API key.  
3. **Integrate chezmoi with Vault:** Configure the local workstation with the Vault CLI and the necessary environment variables. Convert the static dotfiles in the chezmoi repository into templates (.tmpl) that fetch values using the vault template function. Verify that chezmoi apply correctly populates the files with secrets from Vault.

**Phase 2: Containerization and Ephemeral Environments (1 Week)**

1. **Develop Dockerfile Pattern:** Create a Dockerfile that follows the pattern outlined in Section 4.1. Use build arguments to pass Vault credentials and execute the chezmoi init \--one-shot command. Build and test the image to ensure it produces a fully configured container.  
2. **Develop Kubernetes Init Container Pattern:** Create a Kubernetes Pod manifest with an Init Container as described in Section 4.2. Deploy it to a test cluster and verify that the main container starts with a home directory populated by chezmoi.

**Phase 3: Kubernetes Secret Integration (2 Weeks)**

1. **Deploy External Secrets Operator (ESO):** Install ESO into a test Kubernetes cluster using its official Helm chart.  
2. **Configure SecretStore:** Create and apply a ClusterSecretStore manifest that configures ESO to connect and authenticate to the Vault instance. Add this manifest to the Git repository.  
3. **Create ExternalSecret Manifests:** For a sample application, create ExternalSecret manifests that declare the desired synchronization from Vault to Kubernetes Secret objects. Add these manifests to the Git repository.  
4. **End-to-End Validation:** Deploy a sample application pod that mounts the secrets created by ESO. Verify that the application can successfully read the secret values that originated in Vault. Test the cross-cluster portability by repeating steps 1, 2, and 3 on a second cluster and applying the same manifests.

**Phase 4: Bare-Metal Automation (2-3 Weeks)**

1. **Set up PXE Boot Environment:** Configure a PXE boot server with DHCP and TFTP/HTTP services capable of deploying a standard Linux distribution (e.g., Ubuntu Server).  
2. **Develop cloud-init Payload:** Create a user-data.yaml file as described in Section 5.2. This script should create a user, install dependencies, and execute the chezmoi bootstrap command.  
3. **Test and Refine:** Host the user-data.yaml file on an HTTP server and configure the PXE installer's kernel parameters to fetch it. Provision a test machine (physical or virtual) and verify that it boots, installs the OS, runs cloud-init, and successfully configures the user environment via chezmoi. Refine the script for robustness and security, particularly around the initial Vault token injection.

#### **Works cited**

1. Why use chezmoi?, accessed October 18, 2025, [https://www.chezmoi.io/why-use-chezmoi/](https://www.chezmoi.io/why-use-chezmoi/)  
2. Stow \- GNU, accessed October 18, 2025, [https://www.gnu.org/software/stow/manual/stow.html](https://www.gnu.org/software/stow/manual/stow.html)  
3. Managing my dotfiles with GNU Stow | by Wesley Schwengle | Medium, accessed October 18, 2025, [https://medium.com/@waterkip/managing-my-dotfiles-with-gnu-stow-262d2540a866](https://medium.com/@waterkip/managing-my-dotfiles-with-gnu-stow-262d2540a866)  
4. Managing dotfiles with stow \- Apiumhub, accessed October 18, 2025, [https://apiumhub.com/tech-blog-barcelona/managing-dotfiles-with-stow/](https://apiumhub.com/tech-blog-barcelona/managing-dotfiles-with-stow/)  
5. My Approach to Managing Dot Files with GNU Stow \- ikawnoclastic thoughts, accessed October 18, 2025, [https://ikawnoclast.com/2025/05/19/my-approach-to-managing-dot-files-with-gnu-stow/](https://ikawnoclast.com/2025/05/19/my-approach-to-managing-dot-files-with-gnu-stow/)  
6. Effortlessly Manage Dotfiles on Unix-based Systems with GNU Stow and GitHub \- Corti.com, accessed October 18, 2025, [https://www.corti.com/effortlessly-manage-dotfiles-on-unix-with-gnu-stow-and-github/](https://www.corti.com/effortlessly-manage-dotfiles-on-unix-with-gnu-stow-and-github/)  
7. Comparison table \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/comparison-table/](https://www.chezmoi.io/comparison-table/)  
8. Getting Started \- yadm, accessed October 18, 2025, [https://yadm.io/docs/getting\_started](https://yadm.io/docs/getting_started)  
9. debops.yadm — DebOps v2.1.9 documentation, accessed October 18, 2025, [https://docs.debops.org/en/stable-2.1/ansible/roles/yadm/](https://docs.debops.org/en/stable-2.1/ansible/roles/yadm/)  
10. Encryption \- yadm, accessed October 18, 2025, [https://yadm.io/docs/encryption](https://yadm.io/docs/encryption)  
11. chezmoi \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/](https://www.chezmoi.io/)  
12. Design \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/frequently-asked-questions/design/](https://www.chezmoi.io/user-guide/frequently-asked-questions/design/)  
13. Architecture \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/developer-guide/architecture/](https://www.chezmoi.io/developer-guide/architecture/)  
14. Managing dotfiles with Chezmoi | Nathaniel Landau \- natelandau.com, accessed October 18, 2025, [https://natelandau.com/managing-dotfiles-with-chezmoi/](https://natelandau.com/managing-dotfiles-with-chezmoi/)  
15. Templating \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/templating/](https://www.chezmoi.io/user-guide/templating/)  
16. Password Manager Integration \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/password-managers/](https://www.chezmoi.io/user-guide/password-managers/)  
17. AWS Secrets Manager \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/password-managers/aws-secrets-manager/](https://www.chezmoi.io/user-guide/password-managers/aws-secrets-manager/)  
18. Vault \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/password-managers/vault/](https://www.chezmoi.io/user-guide/password-managers/vault/)  
19. Use scripts to perform actions \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/)  
20. Encryption \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/encryption/](https://www.chezmoi.io/user-guide/encryption/)  
21. hashicorp/vault: A tool for secrets management, encryption as a service, and privileged access management \- GitHub, accessed October 18, 2025, [https://github.com/hashicorp/vault](https://github.com/hashicorp/vault)  
22. HashiCorp Vault | Identity-based secrets management, accessed October 18, 2025, [https://www.hashicorp.com/en/products/vault](https://www.hashicorp.com/en/products/vault)  
23. HashiCorp Vault | Identity-based secrets management, accessed October 18, 2025, [https://www.hashicorp.com/products/vault](https://www.hashicorp.com/products/vault)  
24. Daily operations \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/daily-operations/](https://www.chezmoi.io/user-guide/daily-operations/)  
25. lazappi/chezmoi-dotfiles: Dotfiles repository for use with ... \- GitHub, accessed October 18, 2025, [https://github.com/lazappi/chezmoi-dotfiles](https://github.com/lazappi/chezmoi-dotfiles)  
26. Include files from elsewhere \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/include-files-from-elsewhere/](https://www.chezmoi.io/user-guide/include-files-from-elsewhere/)  
27. .chezmoiexternal.  
28. Containers and VMs \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/machines/containers-and-vms/](https://www.chezmoi.io/user-guide/machines/containers-and-vms/)  
29. Setup \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/setup/](https://www.chezmoi.io/user-guide/setup/)  
30. Manage Environment Variables With Vault \- Mia-Platform Documentation, accessed October 18, 2025, [https://docs.mia-platform.eu/docs/products/console/project-configuration/manage-environment-variables/manage-environment-variables-with-vault](https://docs.mia-platform.eu/docs/products/console/project-configuration/manage-environment-variables/manage-environment-variables-with-vault)  
31. Manage Secrets Using HashiCorp Vault \- digital.ai Documentation, accessed October 18, 2025, [https://docs.digital.ai/deploy/docs/22.1/how-to/manage-secrets-using-hashicorp-vault](https://docs.digital.ai/deploy/docs/22.1/how-to/manage-secrets-using-hashicorp-vault)  
32. How to Secure Kubernetes Secrets and Sensitive Data \- Palo Alto Networks, accessed October 18, 2025, [https://www.paloaltonetworks.com/cyberpedia/kubernetes-secrets](https://www.paloaltonetworks.com/cyberpedia/kubernetes-secrets)  
33. vault \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/reference/templates/vault-functions/vault/](https://www.chezmoi.io/reference/templates/vault-functions/vault/)  
34. Secrets | Kubernetes, accessed October 18, 2025, [https://kubernetes.io/docs/concepts/configuration/secret/](https://kubernetes.io/docs/concepts/configuration/secret/)  
35. Sealed Secrets: Securely Storing Kubernetes Secrets in Git \- Civo.com, accessed October 18, 2025, [https://www.civo.com/learn/sealed-secrets-in-git](https://www.civo.com/learn/sealed-secrets-in-git)  
36. How To Use “Sealed Secrets” In Kubernetes. | by Abdullah AlShamrani \- Medium, accessed October 18, 2025, [https://medium.com/@abdullah.devops.91/how-to-use-sealed-secrets-in-kubernetes-b6c69c84d1c2](https://medium.com/@abdullah.devops.91/how-to-use-sealed-secrets-in-kubernetes-b6c69c84d1c2)  
37. bitnami-labs/sealed-secrets: A Kubernetes controller and tool for one-way encrypted Secrets \- GitHub, accessed October 18, 2025, [https://github.com/bitnami-labs/sealed-secrets](https://github.com/bitnami-labs/sealed-secrets)  
38. How to Configure External Secrets Operator with Vault in DOKS \- DigitalOcean, accessed October 18, 2025, [https://www.digitalocean.com/community/developer-center/how-to-configure-external-secrets-operator-with-vault-in-doks](https://www.digitalocean.com/community/developer-center/how-to-configure-external-secrets-operator-with-vault-in-doks)  
39. Kubernetes \- External Secrets Operator, accessed October 18, 2025, [https://external-secrets.io/latest/provider/kubernetes/](https://external-secrets.io/latest/provider/kubernetes/)  
40. Getting started \- External Secrets Operator, accessed October 18, 2025, [https://external-secrets.io/v0.4.4/guides-getting-started/](https://external-secrets.io/v0.4.4/guides-getting-started/)  
41. ExternalSecret \- External Secrets Operator, accessed October 18, 2025, [https://external-secrets.io/v0.4.4/api-externalsecret/](https://external-secrets.io/v0.4.4/api-externalsecret/)  
42. ExternalSecret \- External Secrets Operator, accessed October 18, 2025, [https://external-secrets.io/latest/api/externalsecret/](https://external-secrets.io/latest/api/externalsecret/)  
43. init \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/reference/commands/init/](https://www.chezmoi.io/reference/commands/init/)  
44. twpayne/chezmoi: Manage your dotfiles across multiple diverse machines, securely. \- GitHub, accessed October 18, 2025, [https://github.com/twpayne/chezmoi](https://github.com/twpayne/chezmoi)  
45. jasonmorganson/dotfiles: Dotfiles, managed with chezmoi \- GitHub, accessed October 18, 2025, [https://github.com/jasonmorganson/dotfiles](https://github.com/jasonmorganson/dotfiles)  
46. Init Containers | Kubernetes, accessed October 18, 2025, [https://kubernetes.io/docs/concepts/workloads/pods/init-containers/](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)  
47. Chezmoi \- The Blue Book, accessed October 18, 2025, [https://lyz-code.github.io/blue-book/chezmoi/](https://lyz-code.github.io/blue-book/chezmoi/)  
48. PXE Boot and Network Installation \- Cycle.io, accessed October 18, 2025, [https://cycle.io/learn/pxe-boot-and-network-installation](https://cycle.io/learn/pxe-boot-and-network-installation)  
49. Understand PXE boot in Configuration Manager \- Microsoft Learn, accessed October 18, 2025, [https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/os-deployment/understand-pxe-boot](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/os-deployment/understand-pxe-boot)  
50. PXE Booting And Autobuilding Ubuntu 22.04 \- Ivory And Jade, accessed October 18, 2025, [https://punkto.org/blog/ubuntu\_22\_autobuilding](https://punkto.org/blog/ubuntu_22_autobuilding)  
51. Cloud-init as PXE alternative for client machines? : r/linuxadmin \- Reddit, accessed October 18, 2025, [https://www.reddit.com/r/linuxadmin/comments/vi4twl/cloudinit\_as\_pxe\_alternative\_for\_client\_machines/](https://www.reddit.com/r/linuxadmin/comments/vi4twl/cloudinit_as_pxe_alternative_for_client_machines/)  
52. Using Kickstart, Preseed, and Cloud-Init \- Cycle.io, accessed October 18, 2025, [https://cycle.io/learn/kickstart-preseed-and-cloud-init](https://cycle.io/learn/kickstart-preseed-and-cloud-init)  
53. The four easiest places to get started with automation \- Red Hat, accessed October 18, 2025, [https://www.redhat.com/en/blog/easiest-automation](https://www.redhat.com/en/blog/easiest-automation)  
54. Overall they aren't that different. If someone else is doing the provisioning an... | Hacker News, accessed October 18, 2025, [https://news.ycombinator.com/item?id=5350572](https://news.ycombinator.com/item?id=5350572)  
55. AutomatedInstallation \- Debian Wiki, accessed October 18, 2025, [https://wiki.debian.org/AutomatedInstallation](https://wiki.debian.org/AutomatedInstallation)  
56. iPXE script for deploying Ubuntu 20.04 autoinstall nocloud-net method \- GitHub Gist, accessed October 18, 2025, [https://gist.github.com/tlhakhan/03dbb4867f70d17d205c179a58fd5923](https://gist.github.com/tlhakhan/03dbb4867f70d17d205c179a58fd5923)  
57. Using Custom Cloud-init Initialization Scripts to Set Up Managed Nodes, accessed October 18, 2025, [https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingcustomcloudinitscripts.htm](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingcustomcloudinitscripts.htm)  
58. All cloud config examples \- cloud-init 25.3 documentation, accessed October 18, 2025, [https://cloudinit.readthedocs.io/en/latest/reference/examples.html](https://cloudinit.readthedocs.io/en/latest/reference/examples.html)  
59. Use User Data for Initial Configuration \- User Documentation \- Switch Cloud Portal, accessed October 18, 2025, [https://cloud.switch.ch/-/documentation/compute/cloud-init-and-user-data/use-user-data-for-initial-configuration/](https://cloud.switch.ch/-/documentation/compute/cloud-init-and-user-data/use-user-data-for-initial-configuration/)  
60. PXE Boot Installation | Harvester \- Harvester Overview, accessed October 18, 2025, [https://docs.harvesterhci.io/v1.6/install/pxe-boot-install/](https://docs.harvesterhci.io/v1.6/install/pxe-boot-install/)  
61. Managing Secrets using kubectl \- Kubernetes, accessed October 18, 2025, [https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kubectl/](https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kubectl/)