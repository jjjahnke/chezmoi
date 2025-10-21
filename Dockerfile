#
# Dockerfile for a Declarative, Pre-baked Development Environment
#

# Start from a stable Ubuntu base image
FROM ubuntu:22.04

# Set frontend to noninteractive to avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential dependencies for the bootstrap script
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    curl \
    git \
    zsh \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user with sudo privileges and set zsh as the shell
RUN useradd --create-home --shell /bin/zsh --groups sudo jahnke \
    && echo "jahnke:jahnke" | chpasswd \
    && echo "jahnke ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to the non-root user for the bootstrap process
USER jahnke
WORKDIR /home/jahnke

# Copy the bootstrap script into the image
COPY bootstrap.sh /home/jahnke/bootstrap.sh

# Make the bootstrap script executable
RUN chmod +x /home/jahnke/bootstrap.sh

# Run the bootstrap script to install all development tools
# This is the long-running step that pre-bakes the image
RUN /home/jahnke/bootstrap.sh

# Set the default user and command for when the container is run
USER jahnke
WORKDIR /home/jahnke
CMD ["/bin/zsh"]
