# Powershell launcher for dockerd on WSL 2

# Copyright 2021 Jonathan Bowman. All documentation and code contained
# in this file may be freely shared in compliance with the
# Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
# and is **provided "AS IS" without warranties or conditions of any kind**.
#
# To allow this script to be executed, first ask yourself if I can be trusted,
# then read the code below and make sure you feel good about it, then consider
# allowing scripts to be run by you with the following:
#
# Set-ExecutionPolicy RemoteSigned -scope CurrentUser
#
# Then download this file and unblock it with Unblock-File
#
# You might load and call this script (or just paste the function) in your
# Powershell profile at
# ~\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
#
# This function should be called with a single argument: the name of the WSL
# distribution with dockerd. To find a list of WSL distros, launch Powershell then
#
# wsl -l -q
#
# A usage example:
#
# Docker-Service Ubuntu

function Docker-Service {
  Param ([string]$distro)
  $DOCKER_DIR = "/mnt/wsl/shared-docker"
  $DOCKER_SOCK = "$DOCKER_DIR/docker.sock"
  wsl -d "$distro" sh -c "[ -S '$DOCKER_SOCK' ]"
  if ($LASTEXITCODE) {
    wsl -d "$distro" sh -c "mkdir -pm o=,ug=rw $DOCKER_DIR ; chgrp docker $DOCKER_DIR"
    wsl -d "$distro" sh -c "nohup sudo -b dockerd < /dev/null > $DOCKER_DIR/dockerd.log 2>&1"
  }
}
