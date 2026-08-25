#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
source "$repo_root/configs/airootfs/usr/local/lib/omarchy-iso/platform.sh"

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

assert_detected() {
  omarchy_is_gb10 "$fixture" || {
    echo "expected GB10 detection to succeed" >&2
    exit 1
  }
}

assert_rejected() {
  if omarchy_is_gb10 "$fixture"; then
    echo "expected GB10 detection to fail" >&2
    exit 1
  fi
}

mkdir -p "$fixture/devices/soc0"
printf '%s\n' jep106:0426:8901 > "$fixture/devices/soc0/soc_id"
mkdir -p "$fixture/bus/pci/devices/0000:01:00.0"
printf '%s\n' 0x10de > "$fixture/bus/pci/devices/0000:01:00.0/vendor"
printf '%s\n' 0x2e12 > "$fixture/bus/pci/devices/0000:01:00.0/device"
printf '%s\n' 0x0000 > "$fixture/bus/pci/devices/0000:01:00.0/subsystem_device"
assert_detected

printf '%s\n' jep106:0426:8902 > "$fixture/devices/soc0/soc_id"
assert_rejected

printf '%s\n' jep106:0426:8901 > "$fixture/devices/soc0/soc_id"
printf '%s\n' 0x2e13 > "$fixture/bus/pci/devices/0000:01:00.0/device"
assert_rejected

printf '%s\n' 0x2e12 > "$fixture/bus/pci/devices/0000:01:00.0/device"
rm "$fixture/devices/soc0/soc_id"
assert_rejected

printf '%s\n' jep106:0426:8901 > "$fixture/devices/soc0/soc_id"
assert_detected

printf '%s\n' 0x21ec > "$fixture/bus/pci/devices/0000:01:00.0/subsystem_device"
assert_detected

echo "GB10 platform detection tests passed"
