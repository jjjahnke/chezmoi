

# **Architecting a Declarative and Reproducible Development Environment**

## **Introduction: Beyond Ad-Hoc Setups \- The Case for Declarative Environments**

The modern software development lifecycle demands speed, consistency, and reliability. However, the very foundation of a developer's productivity—their local development environment—is often a fragile construct of manually installed tools, shell scripts, and configuration files accumulated over time. This ad-hoc approach leads to significant challenges, including configuration drift between machines, the "it works on my machine" problem that plagues team collaboration, and the time-consuming, error-prone process of setting up a new computer. These issues represent a direct tax on developer efficiency and project stability.

This report outlines a strategic transition from fragile, imperative setup methods to a robust, declarative model. The core philosophy is to treat the development environment's configuration as code, managed under version control. This architecture will be built in two primary phases. The first phase involves constructing a foundational, *imperative* bootstrap script. This script is a necessary first step, designed to be idempotent and non-interactive, capable of provisioning a bare machine with the essential toolchains and utilities. The second, more transformative phase, pivots to a *declarative* state management system using chezmoi. This powerful tool allows the desired state of the environment—from shell configurations to complex, multi-account AWS profiles—to be defined in a Git repository. By managing the environment's state declaratively, developers gain the ability to replicate their setup perfectly across any number of machines with a single command, enforce consistency, audit changes, and securely manage secrets. This document provides a comprehensive architectural plan and implementation guide for building this modern, resilient, and portable development platform.

---

## **Part I: The Foundational Bootstrap \- A Unified, Idempotent Installation Script**

The journey towards a declarative environment begins with a solid, imperative foundation. This section details the creation of a master shell script designed to prepare a new macOS or Linux system for development. This script is not merely a sequence of commands; it is engineered to be idempotent, meaning it can be executed multiple times on the same machine without causing errors or unintended side effects. It will intelligently check for the existence of components before attempting installation, ensuring a predictable and stable outcome whether run on a clean OS or a partially configured one.

### **1.1 System Bootstrapping and Prerequisite Fulfillment**

Before any development tools can be installed, the underlying operating system must be prepared with essential build utilities and a consistent package management framework. This phase establishes the bedrock upon which all subsequent installations will be built.

#### **OS Detection and Package Manager Abstraction**

A portable script must first understand its execution environment. The initial step is to reliably detect the host operating system (macOS or Linux) and, in the case of Linux, the specific distribution family (e.g., Debian-based like Ubuntu, or RedHat-based like Fedora/CentOS). This is achieved by inspecting the output of uname and parsing files like /etc/os-release. This detection logic allows the script to select the appropriate native package manager—apt-get for Debian, dnf or yum for RedHat, and Homebrew for macOS—creating an abstraction layer that enables a single script to function across diverse systems.

#### **Non-Interactive Homebrew Installation (macOS & Linux)**

Homebrew has become the de facto package manager for macOS and serves as an excellent user-space package manager on Linux, allowing for the installation of tools without requiring sudo privileges. Its use provides a consistent interface for package installation across all target platforms. For automation, a non-interactive installation is paramount. The official Homebrew installation documentation provides a specific environment variable, NONINTERACTIVE=1, which suppresses all user prompts, including confirmation dialogs and password requests for sudo access during the initial setup.1 The bootstrap script will leverage this feature to perform a fully unattended installation:

Bash

\# Idempotent check for Homebrew  
if\! command \-v brew &\> /dev/null; then  
  echo "Homebrew not found. Installing..."  
  NONINTERACTIVE=1 /bin/bash \-c "$(curl \-fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"  
  \# Add brew to the current session's PATH  
  eval "$(/opt/homebrew/bin/brew shellenv)"  
else  
  echo "Homebrew is already installed."  
fi

This approach, which avoids interactive prompts, is essential for any automated or scripted deployment.3 After installation, the script must also configure the current shell environment to recognize the brew command, as instructed by the installer's output.

#### **Installing Essential Build Dependencies**

The ability to manage multiple Python versions with pyenv relies on compiling Python from its source code. This process has a critical dependency on a set of C libraries and development tools that are not always present on a minimal OS installation. A common failure point in automated setups is neglecting to install these prerequisites, leading to cryptic build failures. The bootstrap script must proactively install these dependencies using the previously identified package manager. The required packages vary significantly across platforms, necessitating a structured approach to their installation.5

A robust script will contain logic that maps the detected OS to the correct set of package names. This centralization of dependency information is crucial for maintainability and clarity.

| Dependency Group | Debian/Ubuntu (apt-get) | Fedora/CentOS (dnf) | macOS (brew) |
| :---- | :---- | :---- | :---- |
| C Compilers & Headers | build-essential | "Development Tools" | xcode-select \--install |
| Compression Libraries | zlib1g-dev libbz2-dev liblzma-dev | zlib-devel bzip2-devel xz-devel | xz zlib |
| SSL/TLS Library | libssl-dev | openssl-devel | openssl |
| Database Libraries | libsqlite3-dev | sqlite-devel | sqlite3 |
| Readline Library | libreadline-dev | readline-devel | readline |
| Other Dependencies | libffi-dev libncurses5-dev | libffi-devel ncurses-devel | tcl-tk |

By installing these packages early in the bootstrapping process, the script ensures that subsequent steps, particularly the installation of Python versions via pyenv, will proceed smoothly and without interruption. This proactive fulfillment of dependencies is a hallmark of a well-designed automation script. The principle of idempotency is central to this entire bootstrapping phase. A naive script that simply executes installation commands will fail or produce unpredictable behavior if run on a system where some tools are already present. A resilient script, however, precedes every installation action with a verification step. For example, it checks if brew is in the PATH before attempting to install Homebrew, or it queries the package manager to see if build-essential is already installed before running apt-get install. This "check-then-act" pattern transforms the script from a fragile, one-time installer into a reliable state-enforcement tool, capable of bringing any machine to the desired baseline configuration, regardless of its initial state.

### **1.2 Go Environment Provisioning**

Provisioning the Go toolchain requires a straightforward process that can be fully automated. While the official documentation outlines a system-wide installation requiring sudo privileges, a more modern and flexible approach aligns with the per-user philosophy of tools like nvm and pyenv. This involves installing Go into a directory within the user's home directory, thereby avoiding the need for elevated permissions and preventing conflicts with system-managed packages.

#### **Scripted Download and Installation**

The official, non-interactive installation method for Linux and macOS involves downloading a compressed archive (.tar.gz), extracting its contents, and adding the bin subdirectory to the system's PATH environment variable.7 The bootstrap script will automate this process, targeting a user-local installation path such as $HOME/.go or $HOME/.local/go.

The script will perform the following sequence of actions:

1. Define the target installation directory and the desired Go version.  
2. Check if a Go installation already exists at the target location and if its version matches the desired version. If so, the script will report that Go is already correctly installed and exit this step.  
3. If an installation exists but is outdated or if no installation is found, it will remove the old directory to ensure a clean slate. This step is critical, as the official documentation warns that extracting the archive into an existing Go tree can lead to a broken installation.7  
4. Download the appropriate Go archive for the system's architecture (e.g., amd64 or arm64) from the official Go download site.  
5. Extract the archive into the designated user-local directory (e.g., $HOME/.local/go).

#### **Shell Profile Configuration**

For the Go compiler and tools to be accessible from the command line, the location of the Go binaries must be added to the PATH environment variable. The bootstrap script must handle this configuration automatically and idempotently. It will detect the user's default shell (e.g., Zsh or Bash) and identify the correct profile file (\~/.zshrc, \~/.bashrc, or \~/.profile).

The script will then check if the PATH modification line already exists in the profile file. If the line is not present, it will be appended:

Bash

\# Example for a.zshrc profile  
PROFILE\_FILE="$HOME/.zshrc"  
GO\_BIN\_PATH="$HOME/.local/go/bin"  
PATH\_EXPORT\_LINE="export PATH=\\$PATH:$GO\_BIN\_PATH"

if\! grep \-qF "$PATH\_EXPORT\_LINE" "$PROFILE\_FILE"; then  
  echo "Adding Go to PATH in $PROFILE\_FILE..."  
  echo \-e "\\n\# Go lang configuration\\n$PATH\_EXPORT\_LINE" \>\> "$PROFILE\_FILE"  
else  
  echo "Go PATH is already configured in $PROFILE\_FILE."  
fi

This ensures that upon the next login or terminal session, the go command will be available, completing the non-interactive and user-centric installation of the Go development environment.

### **1.3 Node.js Version Management with NVM**

For modern JavaScript and Node.js development, managing multiple Node.js versions is a necessity. Node Version Manager (NVM) is the industry-standard tool for this purpose, allowing developers to install and switch between different Node.js versions on a per-project or per-shell basis.8 The bootstrap script will automate the installation of NVM and configure a sensible default Node.js version.

#### **Automating the NVM Install Script**

The official method for installing NVM is via a shell script downloaded from its GitHub repository and executed directly. This script can be invoked using curl or wget.9

Bash

curl \-o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash

This command clones the NVM repository to \~/.nvm and, crucially, attempts to modify the user's shell profile file (\~/.bashrc, \~/.zshrc, etc.) to add the necessary lines for sourcing nvm.sh.11 However, automated detection of the correct profile file can sometimes fail, especially in non-standard environments. A robust bootstrap script must not rely on this automatic modification. Instead, it should perform an idempotent check and explicitly add the NVM sourcing lines to the correct profile file based on the user's detected shell ($SHELL).

A common point of failure is when the installer modifies .bashrc for a user whose default shell is Zsh.11 The bootstrap script will prevent this by explicitly targeting the correct file:

Bash

\# Idempotent check for NVM directory  
export NVM\_DIR="$HOME/.nvm"  
if; then  
  echo "NVM not found. Installing..."  
  \# Use a specific shell to run the installer to avoid ambiguity  
  bash \-c 'curl \-o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash'  
else  
  echo "NVM is already installed."  
fi

\# Idempotently add NVM sourcing to the correct profile  
PROFILE\_FILE="$HOME/.zshrc" \# Or.bashrc based on shell detection  
NVM\_SOURCE\_SNIPPET='export NVM\_DIR="$HOME/.nvm"\\n && \\. "$NVM\_DIR/nvm.sh"'

if\! grep \-q 'NVM\_DIR' "$PROFILE\_FILE"; then  
  echo "Configuring NVM in $PROFILE\_FILE..."  
  echo \-e "\\n\# NVM configuration\\n$NVM\_SOURCE\_SNIPPET" \>\> "$PROFILE\_FILE"  
else  
  echo "NVM is already configured in $PROFILE\_FILE."  
fi

#### **Installing a Default Node.js Version**

Once NVM is installed and the shell is configured, a version of Node.js must be installed. A fresh NVM installation does not include any Node.js versions by default. The bootstrap script must load the NVM functions into the current script's environment and then use the nvm command to install a default version. The recommended practice is to install the latest Long-Term Support (LTS) release, which offers the best balance of modern features and stability.

The script will execute the following commands:

Bash

\# Source NVM to make the nvm command available in the current script session  
 && \\. "$NVM\_DIR/nvm.sh"

\# Check if the LTS version is already installed  
if\! nvm ls "lts/\*" | grep \-q "lts/\*"; then  
  echo "Installing latest LTS version of Node.js..."  
  nvm install \--lts  
  nvm alias default 'lts/\*' \# Set the LTS version as the default for new shells  
else  
  echo "Latest LTS version of Node.js is already installed."  
fi

This sequence ensures that the development environment is immediately equipped with a stable, ready-to-use Node.js runtime, completing the fully automated setup of the JavaScript development stack.

### **1.4 Python Version Management with Pyenv**

Similar to the Node.js ecosystem, Python development often requires working with multiple versions of the language to maintain compatibility with different projects and dependencies. pyenv is the premier tool for managing multiple Python installations in user space, allowing for seamless switching between versions without interfering with the system's native Python installation.5 The bootstrap process for pyenv is a multi-step operation involving the installation of the tool itself, configuration of the shell environment, and the installation of a specific Python version.

#### **Installing Pyenv**

The most reliable and recommended method for installing pyenv and its essential plugins, such as pyenv-virtualenv, is through the pyenv-installer script.13 This script simplifies the process by handling the Git clone of the pyenv repository and its plugins into the \~/.pyenv directory.

The bootstrap script will execute the installer idempotently:

Bash

\# Idempotent check for pyenv  
if \[\! \-d "$HOME/.pyenv" \]; then  
  echo "pyenv not found. Installing..."  
  curl https://pyenv.run | bash  
else  
  echo "pyenv is already installed."  
fi

This single command provides a robust starting point for the Python version management setup.

#### **Shell Initialization**

For pyenv to function correctly, it must intercept commands like python and pip and redirect them to the currently active Python version. This is accomplished through a system of "shims." To enable this mechanism, specific initialization commands must be added to the user's shell profile file (\~/.zshrc or \~/.bashrc). These commands set the PYENV\_ROOT environment variable, add the pyenv binary to the PATH, and load the pyenv shell functions.13

The bootstrap script will idempotently append the necessary configuration:

Bash

PROFILE\_FILE="$HOME/.zshrc" \# Or.bashrc based on shell detection  
PYENV\_INIT\_SNIPPET='export PYENV\_ROOT="$HOME/.pyenv"\\ncommand \-v pyenv \>/dev/null |

| export PATH="$PYENV\_ROOT/bin:$PATH"\\neval "$(pyenv init \-)"'

if\! grep \-q 'PYENV\_ROOT' "$PROFILE\_FILE"; then  
  echo "Configuring pyenv in $PROFILE\_FILE..."  
  echo \-e "\\n\# pyenv configuration\\n$PYENV\_INIT\_SNIPPET" \>\> "$PROFILE\_FILE"  
else  
  echo "pyenv is already configured in $PROFILE\_FILE."  
fi

This step is critical; without it, pyenv can install Python versions, but the shell will not be able to use them automatically.

#### **Installing a Default Python Version**

With pyenv installed, the shell configured, and the essential build dependencies fulfilled (as detailed in section 1.1), the script can now proceed to install a default Python version. This action leverages the groundwork laid by the prerequisite installation step, which prevents the build process from failing due to missing libraries.6

The script will first load the pyenv environment into the current session and then install a specific, modern, and stable version of Python. It will also set this version as the global default, ensuring that any new terminal session will use this Python version unless overridden by a project-specific setting.

Bash

\# Load pyenv into the current script session  
export PYENV\_ROOT="$HOME/.pyenv"  
export PATH="$PYENV\_ROOT/bin:$PATH"  
eval "$(pyenv init \--path)"

PYTHON\_VERSION="3.11.4"

\# Check if the desired Python version is already installed  
if\! pyenv versions \--bare | grep \-q "^$PYTHON\_VERSION$"; then  
  echo "Installing Python $PYTHON\_VERSION..."  
  pyenv install "$PYTHON\_VERSION"  
else  
  echo "Python $PYTHON\_VERSION is already installed."  
fi

\# Set the global default Python version  
if; then  
  echo "Setting global Python version to $PYTHON\_VERSION..."  
  pyenv global "$PYTHON\_VERSION"  
else  
  echo "Global Python version is already set to $PYTHON\_VERSION."  
fi

This final sequence completes the automated setup of a sophisticated, multi-version Python development environment, ready for immediate use.

### **1.5 AWS Command Line Interface (v2) Setup**

The AWS Command Line Interface (CLI) is an indispensable tool for interacting with Amazon Web Services. The bootstrap script will install AWS CLI version 2, focusing on a user-space installation method that does not require sudo privileges. This approach enhances security and avoids potential conflicts with system-level packages, aligning with modern best practices for user-managed tools.

#### **User-Space Installation**

The official AWS documentation provides a method for installing the CLI from a bundled zip archive.15 The installer script within this archive offers powerful flags for customizing the installation location. Specifically, the \--install-dir (-i) and \--bin-dir (-b) flags allow for a complete installation within the user's home directory.15 This is the key to a sudo-less installation.

The bootstrap script will automate the following procedure:

1. Define user-local installation paths, for example, $HOME/.local/aws-cli for the installation directory and $HOME/.local/bin for the binary symlink.  
2. Download the official AWS CLI v2 zip bundle for Linux x86\_64.  
3. Unzip the archive into a temporary directory.  
4. Execute the install program with the \-i and \-b flags pointing to the defined user-local paths. A community-provided script demonstrates this exact technique for a non-sudo installation.17  
5. Clean up the downloaded zip file and the temporary installation directory.

Bash

\# Idempotent check for aws cli  
if\! command \-v aws &\> /dev/null; then  
  echo "AWS CLI v2 not found. Installing..."  
  INSTALL\_DIR="$HOME/.local/aws-cli"  
  BIN\_DIR="$HOME/.local/bin"  
  mkdir \-p "$INSTALL\_DIR" "$BIN\_DIR"

  cd /tmp  
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86\_64.zip" \-o "awscliv2.zip"  
  unzip \-q awscliv2.zip  
 ./aws/install \-i "$INSTALL\_DIR" \-b "$BIN\_DIR"  
  rm \-f awscliv2.zip  
  rm \-rf aws  
  cd \-  
else  
  echo "AWS CLI v2 is already installed."  
fi

#### **PATH Configuration**

For the aws command to be executable from anywhere, the directory containing the binary symlink ($HOME/.local/bin in this example) must be included in the user's PATH environment variable. This is a standard convention for user-installed binaries, and many default shell configurations on modern systems already include this path. However, a robust script cannot make this assumption.

The bootstrap script will perform an idempotent check on the user's shell profile file (\~/.zshrc or \~/.bashrc) and add $HOME/.local/bin to the PATH if it is not already present.

Bash

PROFILE\_FILE="$HOME/.zshrc" \# Or.bashrc  
LOCAL\_BIN\_PATH="$HOME/.local/bin"  
PATH\_EXPORT\_LINE="export PATH=\\$PATH:$LOCAL\_BIN\_PATH"

if\! grep \-qF "$LOCAL\_BIN\_PATH" "$PROFILE\_FILE"; then  
  echo "Adding $LOCAL\_BIN\_PATH to PATH in $PROFILE\_FILE..."  
  echo \-e "\\n\# User-local binaries\\n$PATH\_EXPORT\_LINE" \>\> "$PROFILE\_FILE"  
else  
  echo "$LOCAL\_BIN\_PATH is already in PATH."  
fi

By completing this final configuration step, the script ensures that the AWS CLI v2 is fully installed, properly configured, and immediately accessible to the user, all without requiring elevated privileges. This concludes the foundational bootstrapping process, leaving the system ready for the transition to declarative management.

---

## **Part II: Declarative Environment Management with Chezmoi**

With the foundational tools installed by the bootstrap script, the architecture now pivots from an imperative setup to a declarative, state-managed system. This phase introduces chezmoi, a powerful dotfile manager that enables the treatment of a development environment's configuration as code. This approach provides reproducibility, versioning, and a sophisticated mechanism for managing variations between different machines, such as work and personal laptops. The focus will be on solving the user's core challenge: elegantly managing multiple AWS account configurations and securely handling credentials.

### **2.1 Principles of Declarative Dotfile Management with chezmoi**

chezmoi represents a paradigm shift from traditional dotfile management techniques, which often rely on creating symbolic links from a central repository to various locations in the user's home directory.

#### **Introducing chezmoi**

At its core, chezmoi maintains a "source of truth" for the desired state of configuration files within a dedicated directory, typically \~/.local/share/chezmoi.18 This directory is intended to be a Git repository, providing version control for the entire environment configuration. When a user runs chezmoi apply, the tool compares the state of the files in the source directory with the actual files in their target locations (e.g., \~/.gitconfig, \~/.zshrc). It then calculates and performs the minimum set of changes—creating, modifying, or deleting files—to bring the target state into alignment with the source state.19

This state-based approach is fundamentally different from symlink-based managers. Instead of linking, chezmoi copies the content, which allows the source of truth (in Git) and the live configuration files to diverge. This is a powerful feature, as it permits temporary local modifications without breaking the link to the source repository. The chezmoi diff command provides a clear view of these divergences, allowing the user to decide whether to incorporate local changes back into the source state (chezmoi add) or overwrite them with the source state (chezmoi apply).

#### **Initializing a chezmoi Repository**

The workflow begins by initializing chezmoi and linking it to a remote Git repository. This repository will become the central hub for the environment's configuration, accessible from any machine.

The typical onboarding process for an existing set of dotfiles is as follows:

1. **Initialize chezmoi:** Run chezmoi init \<your-git-repo-url\> to create the local source directory and link it to your remote dotfiles repository.20  
2. **Add Files:** For each configuration file to be managed, use the chezmoi add \<path/to/file\> command. For example, chezmoi add \~/.zshrc will copy the contents of \~/.zshrc to \~/.local/share/chezmoi/dot\_zshrc. chezmoi intelligently renames files, replacing the home directory prefix with dot\_ to create a clean structure in the source directory.  
3. **Commit and Push:** Navigate into the source directory using chezmoi cd, and then use standard Git commands (git add, git commit, git push) to save the initial state to the remote repository.20

On any subsequent machine, the entire environment can be materialized with a single command: chezmoi init \--apply \<your-git-repo-url\>.20 This command clones the repository, evaluates any templates, and applies the state to the new machine's home directory, achieving perfect reproducibility.

### **2.2 Mastering Multi-Account AWS Configurations via Templating**

The true power of chezmoi lies in its ability to manage configurations that vary across machines. This is achieved through a powerful templating engine, which provides an elegant solution to the user's requirement of managing multiple AWS account configurations.

#### **The Power of chezmoi Templates**

chezmoi uses Go's standard text/template library to process files.21 A file in the source directory is treated as a template if its name ends with a .tmpl suffix. When chezmoi apply is run, it executes the template and writes the resulting output to the target file. These templates have access to a rich set of data, including built-in variables provided by chezmoi (e.g., .chezmoi.os, .chezmoi.hostname) and custom variables defined by the user in a configuration file, \~/.config/chezmoi/chezmoi.toml.21

#### **Structuring the chezmoi Data File**

The chezmoi.toml file is the key to managing machine-to-machine differences. In it, the user can define variables that describe the context of the current machine. This context can then be used within templates to generate machine-specific content. For managing AWS configurations, a variable like machineType could be set to "work" on a company laptop and "personal" on a home computer. This single variable becomes the switch that controls which AWS profiles are generated.

The following TOML snippet illustrates a well-structured data file that defines both machine context and a reusable list of common AWS profiles.

Ini, TOML

\# \~/.config/chezmoi/chezmoi.toml  
\# This file defines machine-specific context and data for templates.

\[data\]  
\# This variable is used in templates to make decisions based on machine role.  
machineType \= "work" \# Possible values: "work", "personal"  
email \= "firstname.lastname@company.com"

\# A structured map of AWS profiles that can be iterated over in templates.  
\[data.aws.profiles\]  
  \[data.aws.profiles.default\]  
    name \= "default"  
    region \= "us-west-2"  
    output \= "json"  
  \[data.aws.profiles.personal-dev\]  
    name \= "personal-dev"  
    region \= "eu-central-1"  
    output \= "text"

#### **Creating the config.tmpl**

With the data structure defined, a template for the \~/.aws/config file can be created. This template, named dot\_aws/config.tmpl in the chezmoi source directory, will use templating logic to generate a dynamic configuration file. It can iterate over the list of common profiles and use conditional blocks to include specific profiles only when on a machine of a certain type.21

Code snippet

\# \~/.local/share/chezmoi/dot\_aws/config.tmpl  
\# This template generates the AWS config file.

\# First, generate all the common profiles defined in chezmoi.toml  
{{- range.aws.profiles }}  
\[profile {{.name }}\]  
region \= {{.region }}  
output \= {{.output }}

{{ end \-}}

\# Conditionally add work-specific profiles only on machines where  
\# machineType is set to "work" in the chezmoi.toml file.  
{{- if eq.machineType "work" }}  
\# \--- WORK PROFILES \---

\[profile work-admin\]  
region \= us-east-1  
output \= json  
sso\_start\_url \= https://my-company.awsapps.com/start  
sso\_region \= us-east-1  
sso\_account\_id \= 123456789012  
sso\_role\_name \= AdministratorAccess

\[profile work-readonly\]  
region \= us-east-1  
output \= json  
sso\_start\_url \= https://my-company.awsapps.com/start  
sso\_region \= us-east-1  
sso\_account\_id \= 123456789012  
sso\_role\_name \= ReadOnlyAccess  
{{- end }}

This approach provides a complete solution. The *structure* and *logic* of the AWS configuration are now captured in a version-controlled template. The Git repository becomes the single source of truth for how AWS profiles should be configured across all machines. Any change—adding a new profile, updating a region, or modifying an SSO setting—is made once in the template, committed to Git, and then propagated to all relevant machines with a chezmoi apply or chezmoi update. This provides a full audit trail via Git history, the ability to review changes through pull requests, and the safety of being able to revert to any previous known-good configuration. The developer is no longer just editing files; they are managing a versioned, auditable configuration system for their entire fleet of development machines.

### **2.3 Fortifying Security: Integrating a Secrets Manager for AWS Credentials**

While the \~/.aws/config file contains non-sensitive metadata, the corresponding \~/.aws/credentials file contains long-lived, highly sensitive access keys. The cardinal rule of security-conscious development is that secret material must never be committed to a Git repository, even if the repository is private. chezmoi provides a robust and secure solution to this problem through its native integration with external password and secrets managers.

#### **Introducing chezmoi's Password Manager Integration**

chezmoi extends its templating engine with functions that can dynamically fetch secrets from various backends during a chezmoi apply operation.23 This means the secrets themselves are never stored in the chezmoi source directory or the Git repository. Instead, the template contains a reference—a function call—to the secret's location in a secure, external system. chezmoi supports a wide array of backends, including HashiCorp Vault, 1Password, Bitwarden, and, critically for this use case, AWS Secrets Manager.24

#### **Implementation Example (credentials.tmpl)**

To manage the \~/.aws/credentials file, a template will be created that uses the awsSecretsManager template function. This function instructs chezmoi to use the AWS SDK to retrieve a specified secret from AWS Secrets Manager. For this to work, the machine must have some initial bootstrap AWS credentials, which could be provided by an EC2 instance profile, environment variables, or a manually configured default profile used only for this initial secret retrieval.

The template for the credentials file should be created with the private\_ prefix (e.g., private\_dot\_aws/credentials.tmpl). This is a chezmoi convention that ensures the target file is created with secure file permissions (0600), readable only by the user.

The template would look as follows:

Code snippet

\# \~/.local/share/chezmoi/private\_dot\_aws/credentials.tmpl  
\# This template securely populates the AWS credentials file.  
\# The 'private\_' prefix ensures the resulting file has permissions 0600\.

\# Fetch credentials for the default/personal profile from AWS Secrets Manager.  
\# Assumes a secret named "personal/aws/default" exists and contains a JSON  
\# object with keys "AccessKeyID" and "SecretAccessKey".  
{{- $defaultCreds := awsSecretsManager "personal/aws/default" }}  
\[default\]  
aws\_access\_key\_id \= {{ $defaultCreds.AccessKeyID }}  
aws\_secret\_access\_key \= {{ $defaultCreds.SecretAccessKey }}

\# Conditionally fetch work credentials only on work machines.  
{{ if eq.machineType "work" \-}}  
{{- $workCreds := awsSecretsManager "work/aws/developer" }}  
\[work-account\]  
aws\_access\_key\_id \= {{ $workCreds.AccessKeyID }}  
aws\_secret\_access\_key \= {{ $workCreds.SecretAccessKey }}  
{{- end }}

This implementation represents a significant leap in security posture. It establishes a complete decoupling of configuration from secrets. The non-sensitive configuration *structure* lives in the version-controlled Git repository, where it can be audited and managed collaboratively. The highly sensitive secret *values* are managed entirely out-of-band in a dedicated, secure, and auditable system like AWS Secrets Manager.

This architectural separation is profound. It enables a security model where developer machines can be treated as ephemeral. A new machine can be provisioned from a bare OS to a fully functional and authenticated development environment by running the bootstrap script followed by chezmoi apply. The necessary secrets are pulled just-in-time and are never exposed in the configuration repository. If a machine is lost, stolen, or compromised, the secrets can be rotated centrally in AWS Secrets Manager, immediately invalidating the credentials on the compromised device without requiring any changes to the version-controlled dotfiles repository. This transforms the user's setup from one of convenience to a security-first model that aligns with modern, enterprise-grade secret management practices.

---

## **Part III: The Unified Workflow \- From Zero to Fully Provisioned**

The true value of this architecture is realized when the imperative bootstrap script and the declarative chezmoi system are combined into a single, cohesive workflow. This workflow covers the entire lifecycle of a development environment, from the initial onboarding of a new machine to the day-to-day management and synchronization of configurations across multiple systems.

### **3.1 The New Machine Onboarding Process**

Provisioning a new development machine, a task that traditionally could take hours or even days of manual configuration, is reduced to a simple, deterministic, two-step process.

#### **Step 1: Execute the Bootstrap Script**

The process begins on a clean, minimal installation of macOS or a supported Linux distribution. The user executes the single, idempotent bootstrap script developed in Part I. This script runs non-interactively and performs all the necessary foundational setup:

* It installs Homebrew and essential build dependencies.  
* It installs the required development toolchains: Go, Node.js (via nvm), and Python (via pyenv).  
* It installs the AWS CLI v2 and chezmoi.  
* It correctly configures the user's shell profile (.zshrc or .bashrc) to make all the installed tools available in the PATH.

Upon completion, the machine has all the necessary binaries and utilities, but the user's personalized configuration (dotfiles) is not yet in place. The system is a blank but fully equipped canvas.

#### **Step 2: Initialize the Declarative Environment**

With the prerequisites installed, the user runs a single chezmoi command to materialize their entire personalized environment:

Bash

chezmoi init \--apply \<your-git-repo-url\>

This command orchestrates a series of powerful actions:

1. It clones the user's dotfiles Git repository into the \~/.local/share/chezmoi source directory.20  
2. It prompts the user for any initial variables required by the configuration templates (e.g., email address, machine type) if a .chezmoi.toml.tmpl is present.20  
3. It executes all templates, generating the machine-specific content for files like \~/.aws/config.  
4. It connects to the configured secrets manager (e.g., AWS Secrets Manager) to fetch and inject sensitive data into files like \~/.aws/credentials.  
5. It applies the final, desired state to the home directory, creating and populating all managed dotfiles.

At the conclusion of this step, the machine is a perfect, ready-to-use replica of the user's defined development environment. The entire process, from a bare OS to a fully provisioned and authenticated workstation, is reduced to running two commands.

### **3.2 Lifecycle Management and Cross-System Synchronization**

The declarative model also revolutionizes the ongoing maintenance and evolution of the development environment. Changes are no longer made directly to live configuration files, which can lead to configuration drift. Instead, all changes follow a structured, version-controlled workflow.

#### **Making a Change**

To modify a managed configuration file, the user employs the chezmoi edit command. For example, chezmoi edit \~/.gitconfig does not open \~/.gitconfig itself; instead, it opens the corresponding source file in the chezmoi directory (e.g., \~/.local/share/chezmoi/dot\_gitconfig.tmpl) within the user's preferred editor ($EDITOR). This ensures that all modifications are made to the source of truth.

#### **Testing and Verifying**

After saving changes to the source template, the user can preview their impact without risk. The chezmoi diff command displays a color-coded diff, showing precisely what lines will be added, removed, or modified in the target file upon application. For complex templates, the chezmoi execute-template command can be used to render the template's output to the console, allowing for interactive debugging and verification of the logic.21

#### **Applying and Propagating**

Once the user is satisfied with the previewed changes, they run chezmoi apply to update the local machine's configuration files to match the new desired state. The change is now live on the current machine. To propagate this change to all other machines, the user follows a standard Git workflow:

1. Navigate to the source directory with chezmoi cd.  
2. Use git add, git commit, and git push to save the changes to the remote dotfiles repository.

#### **Synchronizing Other Machines**

On any other machine managed by this system, updating to the latest configuration is accomplished with a single command: chezmoi update. This command is a convenient alias that performs a git pull within the source directory to fetch the latest changes from the remote repository, followed immediately by a chezmoi apply to bring the local machine's files into compliance with the new state. This closes the loop, ensuring that all development environments remain perfectly synchronized and consistent over time.

## **Conclusion: Your Environment as Code**

The architecture detailed in this report represents a fundamental shift from traditional, manual environment management to a modern, automated "Environment as Code" methodology. By combining an idempotent bootstrap script with the declarative power of chezmoi, developers can build a personal development platform that is reproducible, secure, auditable, and highly efficient.

The benefits of this approach are comprehensive. **Reproducibility** is achieved by capturing the entire environment's state in a version-controlled repository, eliminating "works on my machine" issues and enabling the flawless setup of new machines in minutes. **Security** is dramatically enhanced by decoupling configuration from secrets, leveraging dedicated secrets management systems to handle sensitive credentials, and ensuring that secret material is never stored in version control. **Auditability** is an inherent property of using Git as the source of truth; every change to the environment is captured in a commit history, allowing for easy review and rollback. Finally, **efficiency** is gained by automating away the tedious and error-prone tasks of manual setup and maintenance, freeing up developer time to focus on productive work.

This system should not be viewed as a static, final product, but rather as a powerful and extensible foundation. It provides a robust framework upon which a developer can continue to build, integrating new tools, refining configurations, and adapting to new challenges, all within a structured, secure, and version-controlled workflow. Adopting this declarative model is an investment in a more stable, secure, and productive development practice.

#### **Works cited**

1. Installation \- Homebrew Documentation, accessed October 18, 2025, [https://docs.brew.sh/Installation](https://docs.brew.sh/Installation)  
2. Unattended Installation of Homebrew via RMM : r/mac \- Reddit, accessed October 18, 2025, [https://www.reddit.com/r/mac/comments/1bov5zb/unattended\_installation\_of\_homebrew\_via\_rmm/](https://www.reddit.com/r/mac/comments/1bov5zb/unattended_installation_of_homebrew_via_rmm/)  
3. Unattended (no-prompt) Homebrew installation using expect \- Stack Overflow, accessed October 18, 2025, [https://stackoverflow.com/questions/24426424/unattended-no-prompt-homebrew-installation-using-expect](https://stackoverflow.com/questions/24426424/unattended-no-prompt-homebrew-installation-using-expect)  
4. Some questions about silent installation · Homebrew · Discussion \#4311 \- GitHub, accessed October 18, 2025, [https://github.com/orgs/Homebrew/discussions/4311](https://github.com/orgs/Homebrew/discussions/4311)  
5. Managing Multiple Python Versions With pyenv, accessed October 18, 2025, [https://realpython.com/intro-to-pyenv/](https://realpython.com/intro-to-pyenv/)  
6. Pyenv: Install and manage different Python versions \- The Gray Node, accessed October 18, 2025, [https://thegraynode.io/posts/pyenv\_manage\_python\_versions/](https://thegraynode.io/posts/pyenv_manage_python_versions/)  
7. Download and install \- The Go Programming Language, accessed October 18, 2025, [https://go.dev/doc/install](https://go.dev/doc/install)  
8. How to Install NVM (Node Version Manager) on Every Operating System \- 4Geeks, accessed October 18, 2025, [https://4geeks.com/how-to/install-nvm-on-every-operating-system](https://4geeks.com/how-to/install-nvm-on-every-operating-system)  
9. Node Version Manager – NVM Install Guide \- freeCodeCamp, accessed October 18, 2025, [https://www.freecodecamp.org/news/node-version-manager-nvm-install-guide/](https://www.freecodecamp.org/news/node-version-manager-nvm-install-guide/)  
10. Download Node.js, accessed October 18, 2025, [https://nodejs.org/en/download](https://nodejs.org/en/download)  
11. nvm-sh/nvm: Node Version Manager \- POSIX-compliant bash script to manage multiple active node.js versions \- GitHub, accessed October 18, 2025, [https://github.com/nvm-sh/nvm](https://github.com/nvm-sh/nvm)  
12. Node Version Manager install \- nvm command not found \- Stack Overflow, accessed October 18, 2025, [https://stackoverflow.com/questions/16904658/node-version-manager-install-nvm-command-not-found](https://stackoverflow.com/questions/16904658/node-version-manager-install-nvm-command-not-found)  
13. pyenv/pyenv: Simple Python version management \- GitHub, accessed October 18, 2025, [https://github.com/pyenv/pyenv](https://github.com/pyenv/pyenv)  
14. Installing pyenv \- Kolibri developer documentation, accessed October 18, 2025, [https://kolibri-dev.readthedocs.io/en/develop/howtos/installing\_pyenv.html](https://kolibri-dev.readthedocs.io/en/develop/howtos/installing_pyenv.html)  
15. Installing or updating to the latest version of the AWS CLI \- AWS Command Line Interface, accessed October 18, 2025, [https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)  
16. Installing past releases of the AWS CLI version 2 \- AWS Command Line Interface, accessed October 18, 2025, [https://docs.aws.amazon.com/cli/latest/userguide/getting-started-version.html](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-version.html)  
17. Install AWS CLI v2 without sudo \- GitHub Gist, accessed October 18, 2025, [https://gist.github.com/hertzsprung/4c412617475200157a00284f453c0d95](https://gist.github.com/hertzsprung/4c412617475200157a00284f453c0d95)  
18. chezmoi \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/](https://www.chezmoi.io/)  
19. Chezmoi \- The Blue Book, accessed October 18, 2025, [https://lyz-code.github.io/blue-book/chezmoi/](https://lyz-code.github.io/blue-book/chezmoi/)  
20. Setup \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/setup/](https://www.chezmoi.io/user-guide/setup/)  
21. Templating \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/templating/](https://www.chezmoi.io/user-guide/templating/)  
22. Manage machine-to-machine differences \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/](https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/)  
23. Password Manager Integration \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/password-managers/](https://www.chezmoi.io/user-guide/password-managers/)  
24. AWS Secrets Manager \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/password-managers/aws-secrets-manager/](https://www.chezmoi.io/user-guide/password-managers/aws-secrets-manager/)  
25. Vault \- chezmoi, accessed October 18, 2025, [https://www.chezmoi.io/user-guide/password-managers/vault/](https://www.chezmoi.io/user-guide/password-managers/vault/)  
26. Share credentials across machines using chezmoi and bitwarden | by Jose Rivera | Medium, accessed October 18, 2025, [https://medium.com/@josemrivera/share-credentials-across-machines-using-chezmoi-and-bitwarden-4069dcb6e367](https://medium.com/@josemrivera/share-credentials-across-machines-using-chezmoi-and-bitwarden-4069dcb6e367)