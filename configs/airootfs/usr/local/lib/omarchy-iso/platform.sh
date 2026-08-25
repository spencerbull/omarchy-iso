#!/usr/bin/env bash

omarchy_is_gb10_soc() {
  local sysfs_root=${1:-/sys}
  local soc_id_file="$sysfs_root/devices/soc0/soc_id"
  local soc_id

  [[ -r $soc_id_file ]] || return 1
  soc_id=$(tr -d '\0\r\n' < "$soc_id_file")
  [[ $soc_id == jep106:0426:8901 ]]
}

omarchy_is_gb10_pci() {
  local sysfs_root=${1:-/sys}
  local device_dir vendor device

  for device_dir in "$sysfs_root"/bus/pci/devices/*; do
    [[ -d $device_dir && -r $device_dir/vendor && -r $device_dir/device ]] || continue
    read -r vendor < "$device_dir/vendor"
    read -r device < "$device_dir/device"
    if [[ ${vendor,,} == 0x10de && ${device,,} == 0x2e12 ]]; then
      return 0
    fi
  done

  return 1
}

omarchy_is_gb10() {
  local sysfs_root=${1:-/sys}
  omarchy_is_gb10_soc "$sysfs_root" && omarchy_is_gb10_pci "$sysfs_root"
}
