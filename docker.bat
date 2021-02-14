@echo off
rem A Windows batch file for launching WSL docker.
rem To use, place this file in your PATH, such as C:\Windows\System32\
rem then set the DOCKER_DISTRO variable to your WSL distro.
rem The following command will list WSL distributions from which to choose:
rem wsl -l -q

set DOCKER_DISTRO=fedora
wsl -d %DOCKER_DISTRO% docker -H unix:///mnt/wsl/shared-docker/docker.sock %*
