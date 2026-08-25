#!/usr/bin/env bash

configure_archiso_aarch64_mkinitcpio() {
  local config=$1
  local hooks

  hooks=$(<"$config")
  if [[ $hooks != *' udev microcode '* || $hooks != *' kms memdisk '* ]]; then
    echo "ERROR: unexpected Archiso mkinitcpio hook layout: $config" >&2
    return 1
  fi

  # CPU microcode packages and memdiskfind are x86-only. Keeping memdisk after
  # excluding memtest86+ makes mkinitcpio report an incomplete ARM64 image.
  sed -i \
    -e 's/ udev microcode / udev /' \
    -e 's/ kms memdisk / kms /' \
    "$config"

  hooks=$(<"$config")
  if [[ $hooks == *' microcode '* || $hooks == *' memdisk '* ]]; then
    echo "ERROR: failed to remove x86-only Archiso mkinitcpio hooks: $config" >&2
    return 1
  fi
}
