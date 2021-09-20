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

# Check for mount point being modified in wsl.conf
WIN_ROOT=$(awk -F "=" '/root/ {print $2}' /etc/wsl.conf | tr -d ' ')
if [ -z "$WIN_ROOT" ]; then
  WIN_ROOT=/mnt/
fi
POWERSHELL="${WIN_ROOT}c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
SUDO_DOCKERD="%docker ALL=(ALL)  NOPASSWD: /usr/bin/dockerd"

confirm () {
  printf "%sIs this OK [Y/n/q]:" "$1"
  read -r REPLY
  echo
  case "$REPLY" in
    q*|Q*) echo "Ending script now at user's request."
      exit 1 ;;
    n*|N*) echo "Skipping at user's request."
      return 1 ;;
    *) return 0 ;;
  esac
}

confedit () {
  section=$1
  key=$2
  value=$3
  filename="/etc/wsl.conf"
  tempconf=$(mktemp)

  cp -p "$filename" "$tempconf"

  # normalize line spacing
  CONF=$(sed '/^$/d' "$tempconf" | sed '2,$ s/^\[/\n\[/g')"\n\n"

  if printf "%s" "$CONF" | grep -qF "[$section]" ; then
    if printf "%s" "$CONF" | sed -n "/^\[$section\]$/,/^$/p" | grep -q "^$key" ; then
      CONF=$(printf "%s" "$CONF" | sed "/^\[$section\]$/,/^$/ s/^$key\s*=.\+/$key = $value/")"\n\n"
    else
      CONF=$(printf "%s" "$CONF" | sed "/^\[$section\]$/,/^$/ s/^$/$key = $value\n/")"\n\n"
    fi
  else
    CONF="${CONF}[$section]\n$key = $value\n\n"
  fi
  printf "%s" "$CONF" > "$tempconf" && mv "$tempconf" "$filename"
}

# If root, query for username
if [ "$USER" = "root" ]; then
  printf 'Non-root username to use: '
  read -r USERNAME
  getent passwd | grep -q "^$USERNAME:" && unset NEW_USER || NEW_USER="true"
  SUDO=""
else
  USERNAME=$USER
  if ! groups "$USERNAME" | grep -qEw "sudo|wheel" ; then
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
  printf "[network]\ngenerateResolvConf = false\n\n" | $SUDO tee -a /etc/wsl.conf
fi

# Get distro info so that ID=distro
. /etc/os-release

if ! echo "$ID" | grep -qEw 'fedora|alpine|debian|ubuntu' ; then
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
     "debian"|"ubuntu") $SUDO apt-get update
       $SUDO apt-get upgrade -y
       $SUDO apt-get remove -y docker docker-engine docker.io containerd runc
       $SUDO apt-get install -y --no-install-recommends apt-transport-https ca-certificates curl gnupg2 sudo passwd
       $SUDO curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
       echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" | $SUDO tee /etc/apt/sources.list.d/docker.list
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
if ! groups "$USERNAME" | grep -qw "$SUDO_GROUP" ; then
  echo
  echo "Adding $USERNAME to group $SUDO_GROUP now."
  if confirm ; then
    if command -v usermod > /dev/null 2>&1 ; then
      $SUDO usermod -aG "$SUDO_GROUP" "$USERNAME"
    else
      $SUDO addgroup "$USERNAME" "$SUDO_GROUP"
    fi
  fi
fi

SUDOERS="%$SUDO_GROUP ALL=(ALL) ALL" 
NORMALIZED=$(echo "$SUDOERS" | sed 's/\s\+/\\s\\+/g')
if ! "$SUDO" sh -c 'EDITOR=cat visudo 2> /dev/null' | grep -q "^$NORMALIZED" ; then
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

if ! groups "$USERNAME" | grep -qw "docker" ; then
  echo
  echo "Adding $USERNAME to group docker now."
  if confirm ; then
    if command -v usermod > /dev/null 2>&1 ; then
      $SUDO usermod -aG docker "$USERNAME"
    else
      $SUDO addgroup "$USERNAME" docker
    fi
  fi
fi

NORMALIZED=$(echo "$SUDO_DOCKERD" | sed 's/\s\+/\\s\\+/g')
if ! "$SUDO" sh -c 'EDITOR=cat visudo 2> /dev/null' | grep -q "^$NORMALIZED"; then
  echo
  echo "Enabling passwordless sudo access to launch dockerd for everyone in group docker."
  if confirm ; then
    echo "$SUDO_DOCKERD" | $SUDO sh -c "EDITOR='tee -a' visudo 1>/dev/null"
  fi
fi

USERID=$(id -u "$USERNAME")
DISTRO_REGISTRY=$($POWERSHELL "Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\*\ DistributionName | Where-Object -Property DistributionName -eq $WSL_DISTRO_NAME | select -exp PSPath" | tr -d '\r\n')
DEFAULT_UID=$($POWERSHELL "Get-ItemProperty '$DISTRO_REGISTRY' -Name DefaultUid | select -exp DefaultUid" | tr -d '\r\n')
if [ "$USERID" != "$DEFAULT_UID" ] ; then
  echo
  echo "Setting $USERNAME as default user for WSL distro $WSL_DISTRO_NAME."
  if confirm ; then
    $POWERSHELL "Set-ItemProperty '$DISTRO_REGISTRY' -Name DefaultUid -Value $USERID"
  fi
fi


if ! grep -q '/mnt/wsl' "/etc/docker/daemon.json" ; then
  DOCKERD_CONFIG='{\n  "hosts": ["unix:///mnt/wsl/shared-docker/docker.sock"]'
  [ "$ID" = "debian" ] && DOCKERD_CONFIG="${DOCKERD_CONFIG},\n  \"iptables\": false"
  DOCKERD_CONFIG="${DOCKERD_CONFIG}\n}"
  echo
  printf "%s" "$DOCKERD_CONFIG"
  echo "A new /etc/docker/daemon.json will be created or overwritten with the above contents."
  if [ -r "/etc/docker/daemon.json" ] ; then
    echo "This will replace the existing file, which currently contains:"
    cat "/etc/docker/daemon.json"
  fi
  confirm && echo "$DOCKERD_CONFIG" | $SUDO tee "/etc/docker/daemon.json"
  $SUDO chgrp docker "/etc/docker/daemon.json"
fi

HOMEDIR=$(getent passwd | grep -w "$USERNAME" | cut -d: -f6)
LAUNCHER_DIR="$HOMEDIR/.local/bin"
LAUNCHER="$LAUNCHER_DIR/docker-service.sh"
LAUNCHER_TEMP=$(mktemp)
printf "#!/bin/sh\n\nDOCKER_DISTRO='%s'\nWIN_ROOT='%s'\n" "$WSL_DISTRO_NAME" "$WIN_ROOT"> "$LAUNCHER_TEMP"
cat <<-'EOF' >> "$LAUNCHER_TEMP"
DOCKER_DIR=/mnt/wsl/shared-docker
DOCKER_SOCK="$DOCKER_DIR/docker.sock"
export DOCKER_HOST="unix://$DOCKER_SOCK"
if [ ! -S "$DOCKER_SOCK" ]; then
    sudo mkdir -pm o=,ug=rwx "$DOCKER_DIR"
    sudo chgrp docker "$DOCKER_DIR"
    "${WIN_ROOT}"c/Windows/System32/wsl.exe -d $DOCKER_DISTRO sh -c "nohup sudo -b dockerd < /dev/null > $DOCKER_DIR/dockerd.log 2>&1"
fi
EOF

echo
echo "Adding $LAUNCHER startup script now, with these contents:"
cat "$LAUNCHER_TEMP"

if [ ! -r "$LAUNCHER" ] && confirm ; then
  mkdir -p "$LAUNCHER_DIR"
  mv "$LAUNCHER_TEMP" "$LAUNCHER"
  chmod u=rwx,g=rx,o= "$LAUNCHER"
  sudo chgrp docker "$LAUNCHER"
fi
