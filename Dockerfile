# Define a base for the image
# noble is the latest LTS release
# jammy is the current release supported by GradeScope
FROM ubuntu:jammy

# Avoid interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Set up environment
ENV TZ=America/New_York

# Set up locale
RUN apt-get update && \
    apt-get install -y locales && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Set up sources (for ARM64)
COPY --chown=root:root sources.list /etc/apt/sources.list

# Install Git, Neovim
RUN apt-get install -y \
  sudo \
  git \
  vim \
  neovim \
  nano \
  wget \
  curl \
  xxd

# Install sudo and give sudo-user passwordless root access
# RUN apt-get update && \
#     apt-get install -y sudo && \
#     rm -rf /var/lib/apt/lists/*
#
# RUN useradd -ms /bin/bash root && \
#     echo "sudo-user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/sudo-user && \
#     chmod 0440 /etc/sudoers.d/sudo-user
#
# USER sudo-user

USER root

CMD [ "bash" ]
