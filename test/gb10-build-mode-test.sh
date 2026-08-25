#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
source_contract="$repo_root/builder/gb10-omarchy-source.sh"

profile_value() {
  local architecture=$1
  OMARCHY_ARCH=$architecture bash -c '
    declare -A file_permissions
    source "$1/configs/profiledef.sh"
    printf "%s|%s|%s\n" "$arch" "${bootmodes[*]}" "${airootfs_image_tool_options[*]}"
  ' _ "$repo_root"
}

x86_profile=$(profile_value x86_64)
arm_profile=$(profile_value aarch64)
[[ $x86_profile == 'x86_64|bios.syslinux uefi.grub|-comp xz -Xbcj x86 -b 1M -Xdict-size 1M' ]]
[[ $arm_profile == 'aarch64|uefi.grub|-comp xz -b 1M -Xdict-size 1M' ]]

source "$repo_root/builder/node-release.sh"
node_manifest=$'aaaa  node-v24.7.0-linux-x64.tar.gz\nbbbb  node-v24.7.0-linux-arm64.tar.gz\ncccc  node-v24.7.0-linux-arm64.tar.xz'
IFS=$'\t' read -r node_x64_file node_x64_sha < <(select_node_release linux-x64 <<<"$node_manifest")
IFS=$'\t' read -r node_arm_file node_arm_sha < <(select_node_release linux-arm64 <<<"$node_manifest")
[[ $node_x64_file == node-v24.7.0-linux-x64.tar.gz && $node_x64_sha == aaaa ]]
[[ $node_arm_file == node-v24.7.0-linux-arm64.tar.gz && $node_arm_sha == bbbb ]]
if select_node_release linux-riscv64 <<<"$node_manifest" >/dev/null; then
  echo "Node release selection unexpectedly accepted a missing platform" >&2
  exit 1
fi
if select_node_release linux-arm64 <<<"$node_manifest"$'\ndddd  node-v25.0.0-linux-arm64.tar.gz' >/dev/null; then
  echo "Node release selection unexpectedly accepted duplicate platform archives" >&2
  exit 1
fi

source "$repo_root/builder/limine-hook.sh"
limine_functions=$'reset_enroll_config() {\n\tis_supported_uefi_arch || return 0\n}\n\nenroll_config() {\n\tis_supported_uefi_arch || return 0\n}'
limine_function_uses_supported_arch reset_enroll_config <<<"$limine_functions"
limine_function_uses_supported_arch enroll_config <<<"$limine_functions"
missing_enroll_support=$'reset_enroll_config() {\n\tis_supported_uefi_arch || return 0\n}\n\nenroll_config() {\n\tis_x64 || return 0\n}'
if limine_function_uses_supported_arch enroll_config <<<"$missing_enroll_support"; then
  echo "Limine hook validation unexpectedly accepted missing AArch64 enrollment" >&2
  exit 1
fi

source "$repo_root/builder/archiso-aarch64-grub-modules.sh"
grub_modules=(all_video at_keyboard boot keylayouts linux usb usbserial_common usbserial_ftdi usbserial_pl2303 usbserial_usbdebug video)
filter_archiso_aarch64_grub_modules grub_modules
[[ ${grub_modules[*]} == 'all_video boot linux video' ]]

source "$repo_root/builder/archiso-aarch64-mkinitcpio.sh"
printf '%s\n' 'HOOKS=(base udev microcode modconf kms memdisk archiso filesystems keyboard)' >"$fixture/archiso.conf"
configure_archiso_aarch64_mkinitcpio "$fixture/archiso.conf"
[[ $(<"$fixture/archiso.conf") == 'HOOKS=(base udev modconf kms archiso filesystems keyboard)' ]]
printf '%s\n' 'HOOKS=(base udev modconf kms archiso filesystems keyboard)' >"$fixture/unexpected-archiso.conf"
if configure_archiso_aarch64_mkinitcpio "$fixture/unexpected-archiso.conf" >/dev/null 2>&1; then
  echo "AArch64 mkinitcpio overlay unexpectedly accepted a drifted hook layout" >&2
  exit 1
fi

source "$repo_root/builder/arm64-kernel-image.sh"
truncate -s 64 "$fixture/raw-arm64-image" "$fixture/efi-stub-arm64-image" "$fixture/invalid-efi-image"
printf 'ARMd' | dd of="$fixture/raw-arm64-image" bs=1 seek=56 conv=notrunc status=none
printf 'MZ' | dd of="$fixture/efi-stub-arm64-image" bs=1 conv=notrunc status=none
printf 'ARMd' | dd of="$fixture/efi-stub-arm64-image" bs=1 seek=56 conv=notrunc status=none
printf 'MZ' | dd of="$fixture/invalid-efi-image" bs=1 conv=notrunc status=none
is_raw_arm64_kernel_image "$fixture/raw-arm64-image"
is_raw_arm64_kernel_image "$fixture/efi-stub-arm64-image"
if is_raw_arm64_kernel_image "$fixture/invalid-efi-image"; then
  echo "raw ARM64 image validation unexpectedly accepted an image without ARMd magic" >&2
  exit 1
fi

source "$repo_root/builder/publish-iso.sh"
printf 'first\n' >"$fixture/first.iso"
printf 'second\n' >"$fixture/second.iso"
set +e
publish_iso_no_replace "$fixture/first.iso" "$fixture/published.iso" >/dev/null 2>&1 &
first_pid=$!
publish_iso_no_replace "$fixture/second.iso" "$fixture/published.iso" >/dev/null 2>&1 &
second_pid=$!
wait "$first_pid"
first_status=$?
wait "$second_pid"
second_status=$?
set -e
if (( (first_status == 0) + (second_status == 0) != 1 )); then
  echo "concurrent ISO publication did not produce exactly one winner" >&2
  exit 1
fi
[[ $(<"$fixture/published.iso") == first || $(<"$fixture/published.iso") == second ]]
remaining_sources=0
[[ -e $fixture/first.iso ]] && ((remaining_sources += 1))
[[ -e $fixture/second.iso ]] && ((remaining_sources += 1))
[[ $remaining_sources == 1 ]]

for config in grub.cfg loopback.cfg; do
  sed \
    -e 's|%KERNEL%|linux-gb10|g' \
    -e 's|%KERNEL_OPTIONS%||g' \
    "$repo_root/configs/grub/$config" > "$fixture/$config"
  grep -Fq 'vmlinuz-linux-gb10' "$fixture/$config"
  grep -Fq 'initramfs-linux-gb10.img' "$fixture/$config"
  if grep -Fq 'linux-t2' "$fixture/$config"; then
    echo "unexpected T2 kernel in rendered GB10 $config" >&2
    exit 1
  fi
done

if "$repo_root/bin/omarchy-iso-make" --gb10 >"$fixture/missing-package-dir.log" 2>&1; then
  echo "--gb10 unexpectedly accepted a missing --package-dir" >&2
  exit 1
fi
grep -Fq -- '--gb10 requires --package-dir DIR' "$fixture/missing-package-dir.log"

if "$repo_root/bin/omarchy-iso-make" --gb10 --quattro >"$fixture/quattro.log" 2>&1; then
  echo "--gb10 unexpectedly accepted the Quattro installer flow" >&2
  exit 1
fi
grep -Fq 'main-compatible installer flow' "$fixture/quattro.log"

mkdir "$fixture/packages"
if "$repo_root/bin/omarchy-iso-make" --gb10 --package-dir "$fixture/packages" >"$fixture/missing-runtime.log" 2>&1; then
  echo "--gb10 unexpectedly accepted a package directory without a runtime archive" >&2
  exit 1
fi
grep -Fq 'expected exactly one linux-gb10 runtime archive' "$fixture/missing-runtime.log"

touch "$fixture/packages/linux-gb10-6.17.13.nvidia1029-1-aarch64.pkg.tar.xz"
if "$repo_root/bin/omarchy-iso-make" --gb10 --package-dir "$fixture/packages" >"$fixture/missing-headers.log" 2>&1; then
  echo "--gb10 unexpectedly accepted a package directory without a headers archive" >&2
  exit 1
fi
grep -Fq 'expected exactly one linux-gb10-headers archive' "$fixture/missing-headers.log"

touch "$fixture/packages/linux-gb10-headers-6.17.13.nvidia1029-1-aarch64.pkg.tar.xz"
if "$repo_root/bin/omarchy-iso-make" --gb10 --package-dir "$fixture/packages" >"$fixture/missing-checksums.log" 2>&1; then
  echo "--gb10 unexpectedly accepted packages without SHA256SUMS" >&2
  exit 1
fi
grep -Fq 'must contain SHA256SUMS' "$fixture/missing-checksums.log"

sha256sum "$fixture/packages/linux-gb10-6.17.13.nvidia1029-1-aarch64.pkg.tar.xz" \
  | sed "s|$fixture/packages/||" > "$fixture/packages/SHA256SUMS"
if "$repo_root/bin/omarchy-iso-make" --gb10 --package-dir "$fixture/packages" >"$fixture/incomplete-checksums.log" 2>&1; then
  echo "--gb10 unexpectedly accepted a partial SHA256SUMS manifest" >&2
  exit 1
fi
grep -Fq 'SHA256SUMS does not cover linux-gb10-headers' "$fixture/incomplete-checksums.log"

archinstall_fixture="$fixture/installer.py"
cat > "$archinstall_fixture" <<'PY'
for file in ('BOOTIA32.EFI', 'BOOTX64.EFI'):
    pass
hook_command = (
    f'/usr/bin/cp /usr/share/limine/BOOTIA32.EFI {efi_dir_path_target}/ && /usr/bin/cp /usr/share/limine/BOOTX64.EFI {efi_dir_path_target}/'
)
loader_path = '\\EFI\\arch-limine\\BOOTX64.EFI'
loader_path = '\\EFI\\arch-limine\\BOOTIA32.EFI'
PY
python3 "$repo_root/configs/airootfs/usr/local/lib/omarchy-iso/patch-archinstall-gb10.py" "$archinstall_fixture"
grep -Fq 'BOOTAA64.EFI' "$archinstall_fixture"
if grep -Eq 'BOOT(X64|IA32)\.EFI' "$archinstall_fixture"; then
  echo "Archinstall GB10 patch left an x86 EFI fallback behind" >&2
  exit 1
fi

if grep -Eq '^\[(multilib|arch-mact2)\]$' "$repo_root/configs/pacman-online-gb10.conf"; then
  echo "GB10 pacman configuration contains an x86-only repository" >&2
  exit 1
fi

grep -Fq 'node_platform=linux-arm64' "$repo_root/builder/build-iso.sh"
grep -Fq 'packages.$OMARCHY_ARCH' "$repo_root/builder/build-iso.sh"
grep -Fq '"$offline_mirror_dir"/*.pkg.tar.*' "$repo_root/builder/build-iso.sh"
grep -Fq 'CONTAINER_IMAGE=menci/archlinuxarm@sha256:3e1074c407fc1a57c2a2117af6920c96a7cc906fa6f1f2da8a4a7fd3aa2c2f4e' "$repo_root/bin/omarchy-iso-make"
grep -Fq 'CONTAINER_PLATFORM_ARGS=(--platform linux/arm64)' "$repo_root/bin/omarchy-iso-make"
grep -Fq -- '-v "$PACKAGE_DIR:/packages:ro"' "$repo_root/bin/omarchy-iso-make"
grep -Fq '.gb10-build.XXXXXX' "$repo_root/bin/omarchy-iso-make"
grep -Fq 'explicit OMARCHY_INSTALLER_REPO and GB10 branch OMARCHY_INSTALLER_REF' "$repo_root/bin/omarchy-iso-make"
grep -Fq 'http://mirror.archlinuxarm.org/aarch64/$repo' "$repo_root/configs/airootfs/root/configurator"
grep -Fq 'pacman-key --populate archlinuxarm' "$repo_root/configs/airootfs/root/.automated_script.sh"
grep -Fq 'magic at offset 56' "$repo_root/builder/build-iso.sh"
grep -Fq 'edk2-shell' "$repo_root/builder/build-iso.sh"
grep -Fq 'source /builder/gb10-omarchy-source.sh' "$repo_root/builder/build-iso.sh"
grep -Fq 'validate_gb10_omarchy_source "$omarchy_source"' "$repo_root/builder/build-iso.sh"
grep -Fq 'selected Omarchy source is not GB10-capable' "$source_contract"
grep -Fq 'does not fail closed for unsupported GB10 lifecycle paths' "$source_contract"
grep -Fq 'install/helpers/gb10-lifecycle.sh' "$source_contract"
grep -Fq 'omarchy-guard-gb10-lifecycle .*\|\| exit 1' "$source_contract"
grep -Fq 'cannot consume the bundled AArch64 Node.js release' "$source_contract"
grep -Fq 'cannot remove the live ISO installer sudo policy on errors and signals' "$source_contract"
grep -Fq 'gb10_guard_precedes_mutation' "$source_contract"
grep -Fq 'does not guard Limine finalization before mutation' "$source_contract"
grep -Fq 'does not validate the installed AArch64 Limine deployment' "$source_contract"
grep -Fq 'nvidia-open-dkms=610.57.04-1' "$source_contract"
grep -Fq 'nvidia-utils=610.57.04-1' "$source_contract"
grep -Fq 'usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin' "$repo_root/builder/build-iso.sh"
grep -Fq 'usr/lib/firmware/nvidia/610.57.04/ucodes_ga10x.bin' "$repo_root/builder/build-iso.sh"
grep -Fq 'limine-mkinitcpio-hook=1.37.1-4' "$repo_root/builder/build-iso.sh"
grep -Fq 'mkarchiso_command=/tmp/mkarchiso-aarch64' "$repo_root/builder/build-iso.sh"
grep -Fq 'arch-install-scripts' "$repo_root/builder/build-iso.sh"
grep -Fq 'archiso-v87-aarch64-grub.patch' "$repo_root/builder/build-iso.sh"
cp "$repo_root/archiso/archiso/mkarchiso" "$fixture/mkarchiso"
patch --batch --forward "$fixture/mkarchiso" \
  <"$repo_root/builder/archiso-v87-aarch64-grub.patch" >/dev/null
grep -Fq 'source /builder/archiso-aarch64-grub-modules.sh' "$fixture/mkarchiso"
grep -Fq 'filter_archiso_aarch64_grub_modules grubmodules' "$fixture/mkarchiso"
grep -Fq 'patched AArch64 Limine hook' "$repo_root/builder/build-iso.sh"
grep -Fq 'final GB10 offline repository must contain exactly one kernel and headers package' "$repo_root/builder/build-iso.sh"
grep -Fq 'does not enable AArch64 reset recovery' "$repo_root/builder/build-iso.sh"
grep -Fq 'does not enable AArch64 config enrollment' "$repo_root/builder/build-iso.sh"
grep -Fq 'export OMARCHY_ISO_INSTALL=1' "$repo_root/configs/airootfs/root/.automated_script.sh"

grep -Fq "ALL_kver='/boot/vmlinuz-linux-gb10'" "$repo_root/builder/linux-gb10.preset"
grep -Fq "archiso_image='/boot/initramfs-linux-gb10.img'" "$repo_root/builder/linux-gb10.preset"

echo "GB10 build mode tests passed"
