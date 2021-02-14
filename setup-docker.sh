#!/bin/sh

# This is a work-in-progress! PleasedDon't use it yet.
# 
#
# Copyright 2021 Jonathan Bowman. All documentation and code contained
# in this file may be freely shared in compliance with the
# Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
# and is provided "AS IS" without warranties or conditions of any kind.
#
# To use this script (don't; WIP), first ask yourself if I can be trusted, then read the code
# below and make sure you feel good about it, then consider downloading and
# executing this code that comes with no warranties or claims of suitability.
#
# OUT="$(mktemp)"; wget -q -O - https://raw.githubusercontent.com/bowmanjd/docker-wsl/main/setup-docker.sh > $OUT; . $OUT


# If root, query for username and test if user is sudoer
if [ $USER = "root" ]; then
  read -p 'Non-root username to use: ' USERNAME
  getent passwd | grep -q "^$USERNAME:" && unset NEW_USER || NEW_USER="true"
  SUDO=""
else
  USERNAME=$USER
  SUDO="sudo"
fi


# If DNS lookup fails, doctor resolv.conf
if ! nslookup -timeout=2 google.com > /dev/null 2&>1 ; then
  $SUDO unlink /etc/resolv.conf 
  echo "nameserver 1.1.1.1" | $SUDO tee /etc/resolv.conf
  echo -e "[network]\ngenerateResolvConf = false" | $SUDO tee -a /etc/wsl.conf
fi

# Get distro info so that ID=distro
. /etc/os-release

# Update packages, clean docker residue, and install docker
case "$ID" in
   "fedora") $SUDO dnf upgrade -y
     $SUDO dnf remove moby-engine docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine
     $SUDO dnf install dnf-plugins-core sudo passwd cracklib-dicts
     $SUDO dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
     $SUDO dnf install docker-ce docker-ce-cli containerd.io
     
   ;;
   "debian|ubuntu") $SUDO apt-get update
     $SUDO apt-get upgrade -y
     $SUDO apt-get remove -y docker docker-engine docker.io containerd runc
     $SUDO apt-get install -y --no-install-recommends apt-transport-https ca-certificates curl gnupg2 sudo passwd
     echo "deb [arch=amd64] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" | $SUDO tee /etc/apt/sources.list.d/docker.list
     $SUDO apt update
     $SUDO apt install docker-ce docker-ce-cli containerd.io
   ;;
   "alpine") $SUDO apk upgrade -U
     $SUDO apk del docker-cli docker-engine docker-openrc docker-compose docker
     $SUDO apk add sudo
     $SUDO apk add docker --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community
   ;;
esac

if [ $NEW_USER ] ; then
  $SUDO adduser "$USERNAME"
  if ! $SUDO getent shadow | grep -q "^$USERNAME:\$" ; then
    $SUDO passwd "$USERNAME"
  fi
fi

SUDO_GROUP=$(getent group | grep -Eo "^(wheel|sudo)\b")
if ! groups $USERNAME | grep -qw "$SUDO_GROUP" ; then
  if command -v usermod > /dev/null 2&>1 ; then
    $SUDO usermod -aG "$SUDO_GROUP" "$USERNAME"
  else
    $SUDO addgroup "$USERNAME" "$SUDO_GROUP"
  fi
fi

SUDOERS="%$SUDO_GROUP ALL=(ALL) ALL" 
if ! $SUDO sh -c "EDITOR=cat visudo 2> /dev/null" | grep -q "^$SUDOERS"; then
  echo "$SUDOERS" | $SUDO sh -c "EDITOR='tee -a' visudo 1>/dev/null"
fi

SUDODOCKERD="%docker ALL=(ALL) ALL" 
SUDO_DOCKERD="%docker ALL=(ALL)  NOPASSWD: /usr/bin/dockerd"
if ! $SUDO sh -c "EDITOR=cat visudo 2> /dev/null" | grep -q "^$SUDO_DOCKERD"; then
  echo "$SUDO_DOCKERD" | $SUDO sh -c "EDITOR='tee -a' visudo 1>/dev/null"
fi
