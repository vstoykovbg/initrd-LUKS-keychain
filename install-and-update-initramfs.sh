#!/bin/sh

# set -e

# Check if the script is being executed as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Please execute this script as root. Installation aborted."
  exit 1
fi

./install.sh
install_exit_status=$?

if [ $install_exit_status -eq 0 ]; then # If the encrypted keychain is opened...
  # update-initramfs -u 
  update-initramfs -u -k $(uname -r)
  return $?
else
  echo "Failed to install, skipping \"update-initramfs -u\"."
  return 1
fi

