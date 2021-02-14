# A Powershell function for launching WSL docker.
# To use, paste the contents of this file in your Powershell profile at
# ~\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
# then set the DOCKER_DISTRO variable to your WSL distro.
# The following command will list WSL distributions from which to choose:
# wsl -l -q

$DOCKER_DISTRO = "fedora"
function docker {
    wsl -d $DOCKER_DISTRO docker -H unix:///mnt/wsl/shared-docker/docker.sock @Args
}
