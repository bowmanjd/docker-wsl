#!/bin/sh

# This is a work-in-progress! Please don't use it yet.
# 
#
# Copyright 2021 Jonathan Bowman. All documentation and code contained
# in this file may be freely shared in compliance with the
# Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
# and is provided "AS IS" without warranties or conditions of any kind.
#
# To use this script, first ask yourself if I can be trusted (I can't; this is
# a work-in-progress), then read the code below and make sure you feel good
# about it, then consider downloading and executing this code that comes with
# no warranties or claims of suitability.
#
# OUT="$(mktemp)"; wget -q -O - https://raw.githubusercontent.com/bowmanjd/docker-wsl/main/setup-docker.sh > $OUT; . $OUT


DOCKER_GID=36257

POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
SUDO_DOCKERD="%docker ALL=(ALL)  NOPASSWD: /usr/bin/dockerd"

confirm () {
  read -p "${1}Is this OK [Y/n/q]:" -n 1
  echo
  case "$REPLY" in
    q|Q) echo "Ending script now at user's request."
      exit 1 ;;
    n|N) echo "Skipping at user's request."
      return 1 ;;
    *) return 0 ;;
  esac
}

# If root, query for username
if [ $USER = "root" ]; then
  read -p 'Non-root username to use: ' USERNAME
  getent passwd | grep -q "^$USERNAME:" && unset NEW_USER || NEW_USER="true"
  SUDO=""
else
  USERNAME=$USER
  if ! groups $USERNAME | grep -qEw "sudo|wheel" ; then
    echo "Unfortunately, sudo is not configured correctly for user $USERNAME."
    echo "Please try switching to a sudo-enabled user, or correctly configuring"
    echo 'sudo with the command "visudo".'
  fi
  SUDO="sudo"
fi

# If DNS lookup fails, doctor resolv.conf
if ! nslookup -timeout=2 google.com > /dev/null ; then
  echo "DNS lookup failed. Package installation will fail."
  confirm "This script will now edit your resolv.conf. " || exit 1
  $SUDO unlink /etc/resolv.conf 
  echo "nameserver 1.1.1.1" | $SUDO tee /etc/resolv.conf
  echo -e "[network]\ngenerateResolvConf = false" | $SUDO tee -a /etc/wsl.conf
fi

# Get distro info so that ID=distro
. /etc/os-release

if ! echo "$ID" | grep -Ew 'fedora|alpine|debian|ubuntu' ; then
  echo
  echo "This script is built to support Alpine, Debian, Fedora, or Ubuntu distributions."
  echo "You are using $ID."
  echo "Continuing anyway."
  confirm || exit 1
fi

echo
echo "Packages will now be updated, old Docker packages will be removed,"
echo "and official Docker packages will be installed."

if confirm ; then
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
fi

if [ $NEW_USER ] ; then
  echo
  echo "Adding user $USERNAME now."
  confirm || exit 1
  $SUDO adduser "$USERNAME"
  if ! $SUDO getent shadow | grep -q "^$USERNAME:\$" ; then
    $SUDO passwd "$USERNAME"
  fi
fi


SUDO_GROUP=$(getent group | grep -Eo "^(wheel|sudo)\b")
if ! groups $USERNAME | grep -qw "$SUDO_GROUP" ; then
  echo
  echo "Adding $USERNAME to group $SUDO_GROUP now."
  if confirm ; then
    if command -v usermod > /dev/null 2&>1 ; then
      $SUDO usermod -aG "$SUDO_GROUP" "$USERNAME"
    else
      $SUDO addgroup "$USERNAME" "$SUDO_GROUP"
    fi
  fi
fi

SUDOERS="%$SUDO_GROUP ALL=(ALL) ALL" 
if ! $SUDO sh -c "EDITOR=cat visudo 2> /dev/null" | grep -q "$(echo ^$SUDOERS | sed 's/\s\+/\\s\\+/g')" ; then
  echo
  echo "Enabling sudo access for everyone in group $SUDO_GROUP."
  if confirm ; then
    echo "$SUDOERS" | $SUDO sh -c "EDITOR='tee -a' visudo 1>/dev/null"
  fi
fi

CURRENT_DOCKER_GID=$(getent group | grep -Ew "^docker" | cut -d: -f3)
if [ "$DOCKER_GID" != "$CURRENT_DOCKER_GID" ] ; then
  if ! getent group | grep -qw "$DOCKER_GID" ; then
    echo
    echo "Changing ID of docker group from $CURRENT_DOCKER_GID to $DOCKER_GID."
    confirm && $SUDO sed -i -e "s/^\(docker:x\):[^:]\+/\1:$DOCKER_GID/" /etc/group
  else
    echo
    echo "Group ID $DOCKER_GID already exists. Cannot change ID of Docker group."
    confirm "Continuing anyway. " || exit 1
  fi
fi

if ! $SUDO sh -c "EDITOR=cat visudo 2> /dev/null" | grep -q "$(echo ^$SUDO_DOCKERD | sed 's/\s\+/\\s\\+/g')"; then
  echo
  echo "Enabling passwordless sudo access to launch dockerd for everyone in group docker."
  if confirm ; then
    echo "$SUDO_DOCKERD" | $SUDO sh -c "EDITOR='tee -a' visudo 1>/dev/null"
  fi
fi

USERID=$(id -u $USERNAME)
DISTRO_REGISTRY=$($POWERSHELL "Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\*\ DistributionName | Where-Object -Property DistributionName -eq $WSL_DISTRO_NAME | select -exp PSPath" | tr -d '\r\n')
DEFAULT_UID=$($POWERSHELL "Get-ItemProperty '$DISTRO_REGISTRY' -Name DefaultUid | select -exp DefaultUid" | tr -d '\r\n')
if [ $USERID != $DEFAULT_UID ] ; then
  echo
  echo "Setting $USERNAME as default user for WSL distro $WSL_DISTRO_NAME."
  if confirm ; then
    $POWERSHELL "Set-ItemProperty '$DISTRO_REGISTRY' -Name DefaultUid -Value $USERID"
  fi
fi
