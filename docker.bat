@echo off

set DOCKER_DISTRO=fedora
wsl -d %DOCKER_DISTRO% docker -H unix:///mnt/wsl/shared-docker/docker.sock %*
