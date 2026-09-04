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
limine_functions=$'reset_enroll_config() {\n\tis_supported_arch || return 0\n}\n\nenroll_config() {\n\tis_supported_arch || return 0\n}'
limine_function_uses_supported_arch reset_enroll_config <<<"$limine_functions"
limine_function_uses_supported_arch enroll_config <<<"$limine_functions"
missing_enroll_support=$'reset_enroll_config() {\n\tis_supported_arch || return 0\n}\n\nenroll_config() {\n\tis_x64 || return 0\n}'
if limine_function_uses_supported_arch enroll_config <<<"$missing_enroll_support"; then
  echo "Limine hook validation unexpectedly accepted missing AArch64 enrollment" >&2
  exit 1
fi

source "$repo_root/builder/archiso-aarch64-grub-modules.sh"
grub_modules=(all_video at_keyboard boot keylayouts linux usb usbserial_common usbserial_ftdi usbserial_pl2303 usbserial_usbdebug video)
filter_archiso_aarch64_grub_modules grub_modules
[[ ${grub_modules[*]} == 'all_video boot linux video' ]]

source "$repo_root/builder/archiso-aarch64-mkinitcpio.sh"
early_input_modules='MODULES=(i2c_tegra i2c_hid i2c_hid_acpi hid_generic hid_multitouch)'
printf '%s\n' 'HOOKS=(base udev microcode modconf kms memdisk archiso plymouth filesystems keyboard)' >"$fixture/archiso.conf"
configure_archiso_aarch64_mkinitcpio "$fixture/archiso.conf"
[[ $(<"$fixture/archiso.conf") == $'HOOKS=(base udev modconf kms archiso filesystems keyboard)\n'"$early_input_modules" ]]
printf '%s\n' 'HOOKS=(microcode base udev plymouth modconf kms archiso filesystems keyboard memdisk)' >"$fixture/boundary-archiso.conf"
configure_archiso_aarch64_mkinitcpio "$fixture/boundary-archiso.conf"
[[ $(<"$fixture/boundary-archiso.conf") == $'HOOKS=(base udev modconf kms archiso filesystems keyboard)\n'"$early_input_modules" ]]
printf '%s\n' 'HOOKS=(base udev modconf kms archiso filesystems keyboard)' >"$fixture/unexpected-archiso.conf"
if configure_archiso_aarch64_mkinitcpio "$fixture/unexpected-archiso.conf" >/dev/null 2>&1; then
  echo "AArch64 mkinitcpio overlay unexpectedly accepted a drifted hook layout" >&2
  exit 1
fi
printf '%s\n' 'HOOKS=(base udev microcode microcode modconf kms memdisk archiso plymouth filesystems keyboard)' >"$fixture/duplicate-archiso.conf"
duplicate_hooks_before=$(<"$fixture/duplicate-archiso.conf")
if configure_archiso_aarch64_mkinitcpio "$fixture/duplicate-archiso.conf" >/dev/null 2>&1; then
  echo "AArch64 mkinitcpio overlay unexpectedly accepted duplicate x86-only hooks" >&2
  exit 1
fi
[[ $(<"$fixture/duplicate-archiso.conf") == "$duplicate_hooks_before" ]]
printf '%s\n' \
  'MODULES=(usbhid)' \
  'HOOKS=(base udev microcode modconf kms memdisk archiso plymouth filesystems keyboard)' \
  >"$fixture/unexpected-modules-archiso.conf"
unexpected_modules_before=$(<"$fixture/unexpected-modules-archiso.conf")
if configure_archiso_aarch64_mkinitcpio "$fixture/unexpected-modules-archiso.conf" >/dev/null 2>&1; then
  echo "AArch64 mkinitcpio overlay unexpectedly accepted an existing module assignment" >&2
  exit 1
fi
[[ $(<"$fixture/unexpected-modules-archiso.conf") == "$unexpected_modules_before" ]]

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

source "$repo_root/builder/grub-platform.sh"
render_grub_config() {
  local config=$1 platform=$2 kernel=$3 splash=$4 options=$5 output=$6

  cp "$repo_root/configs/grub/$config" "$output"
  configure_grub_platform "$output" "$platform"
  sed -i \
    -e "s|%KERNEL%|$kernel|g" \
    -e "s|%BOOT_SPLASH_KERNEL_OPTIONS%|$splash|g" \
    -e "s|%KERNEL_OPTIONS%|$options|g" \
    "$output"
}

for config in grub.cfg loopback.cfg; do
  render_grub_config "$config" gb10 linux-gb10 '' plymouth.enable=0 "$fixture/$config"
  grep -Fq 'vmlinuz-linux-gb10' "$fixture/$config"
  grep -Fq 'initramfs-linux-gb10.img' "$fixture/$config"
  [[ $(grep -Fc 'plymouth.enable=0' "$fixture/$config") == 2 ]]
  grep -Fxq 'default=archlinux' "$fixture/$config"
  grep -Fxq 'timeout=0' "$fixture/$config"
  if grep -Fq 'n1x-recovery' "$fixture/$config"; then
    echo "rendered GB10 config unexpectedly contains the N1x recovery entry in $config" >&2
    exit 1
  fi
  if grep -E '^[[:space:]]*linux .* (quiet|splash)( |$)' "$fixture/$config" >/dev/null; then
    echo "rendered GB10 config unexpectedly enables a quiet Plymouth boot in $config" >&2
    exit 1
  fi
  if grep -Fq 'linux-t2' "$fixture/$config"; then
    echo "unexpected T2 kernel in rendered GB10 $config" >&2
    exit 1
  fi

  render_grub_config "$config" n1x linux-n1x '' plymouth.enable=0 "$fixture/n1x-$config"
  grep -Fq 'vmlinuz-linux-n1x' "$fixture/n1x-$config"
  grep -Fq 'initramfs-linux-n1x.img' "$fixture/n1x-$config"
  [[ $(grep -Fc 'plymouth.enable=0' "$fixture/n1x-$config") == 3 ]]
  grep -Fxq 'default=n1x-recovery' "$fixture/n1x-$config"
  grep -Fxq 'timeout=-1' "$fixture/n1x-$config"
  grep -Fq -- "--id 'n1x-recovery'" "$fixture/n1x-$config"
  grep -Fq 'omarchy.n1x_recovery=1' "$fixture/n1x-$config"
  grep -Fq 'nomodeset module_blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm,nvidia_peermem,nouveau' "$fixture/n1x-$config"
  grep -Fq 'console=tty0 fbcon=map:0 earlycon' "$fixture/n1x-$config"

  render_grub_config "$config" '' linux-t2 'quiet splash ' xe.enable_panel_replay=0 "$fixture/x86-$config"
  grep -F 'quiet splash xe.enable_panel_replay=0' "$fixture/x86-$config" >/dev/null
  grep -Fxq 'default=archlinux' "$fixture/x86-$config"
  if grep -Fq 'n1x-recovery' "$fixture/x86-$config"; then
    echo "rendered x86 config unexpectedly contains the N1x recovery entry in $config" >&2
    exit 1
  fi
  if grep -Fq 'plymouth.enable=0' "$fixture/x86-$config"; then
    echo "rendered x86 entry unexpectedly disables Plymouth in $config" >&2
    exit 1
  fi
done

if "$repo_root/bin/omarchy-iso-make" --gb10 >"$fixture/missing-package-dir.log" 2>&1; then
  echo "--gb10 unexpectedly accepted a missing --package-dir" >&2
  exit 1
fi
grep -Fq -- '--gb10 requires --package-dir DIR' "$fixture/missing-package-dir.log"

if "$repo_root/bin/omarchy-iso-make" --n1x >"$fixture/missing-n1x-package-dir.log" 2>&1; then
  echo "--n1x unexpectedly accepted a missing --package-dir" >&2
  exit 1
fi
grep -Fq -- '--n1x requires --package-dir DIR' "$fixture/missing-n1x-package-dir.log"

if "$repo_root/bin/omarchy-iso-make" --gb10 --n1x >"$fixture/mixed-arm-platform.log" 2>&1; then
  echo "mutually exclusive ARM image profiles were unexpectedly accepted" >&2
  exit 1
fi
grep -Fq 'mutually exclusive' "$fixture/mixed-arm-platform.log"

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

mkdir "$fixture/packages-n1x"
if "$repo_root/bin/omarchy-iso-make" --n1x --package-dir "$fixture/packages-n1x" >"$fixture/missing-n1x-runtime.log" 2>&1; then
  echo "--n1x unexpectedly accepted a package directory without a runtime archive" >&2
  exit 1
fi
grep -Fq 'expected exactly one linux-n1x runtime archive' "$fixture/missing-n1x-runtime.log"

touch "$fixture/packages-n1x/linux-n1x-7.0.14.nvidia1018-1-aarch64.pkg.tar.xz"
if "$repo_root/bin/omarchy-iso-make" --n1x --package-dir "$fixture/packages-n1x" >"$fixture/missing-n1x-headers.log" 2>&1; then
  echo "--n1x unexpectedly accepted a package directory without a headers archive" >&2
  exit 1
fi
grep -Fq 'expected exactly one linux-n1x-headers archive' "$fixture/missing-n1x-headers.log"

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
grep -Fq '.${ARM_PLATFORM}-build.XXXXXX' "$repo_root/bin/omarchy-iso-make"
grep -Fq 'explicit OMARCHY_INSTALLER_REPO and branch OMARCHY_INSTALLER_REF' "$repo_root/bin/omarchy-iso-make"
grep -Fq 'http://mirror.archlinuxarm.org/aarch64/$repo' "$repo_root/configs/airootfs/root/configurator"
grep -Fq 'pacman-key --populate archlinuxarm' "$repo_root/configs/airootfs/root/.automated_script.sh"
grep -Fq 'magic at offset 56' "$repo_root/builder/build-iso.sh"
grep -Fq 'edk2-shell' "$repo_root/builder/build-iso.sh"
grep -Fq 'source /builder/gb10-omarchy-source.sh' "$repo_root/builder/build-iso.sh"
grep -Fq 'source /builder/grub-platform.sh' "$repo_root/builder/build-iso.sh"
grep -Fq 'validate_arm_omarchy_source "$omarchy_source"' "$repo_root/builder/build-iso.sh"
grep -Fq 'selected Omarchy source is not ARM-image-capable' "$source_contract"
grep -Fq 'does not fail closed for unsupported GB10 lifecycle paths' "$source_contract"
grep -Fq 'install/helpers/gb10-lifecycle.sh' "$source_contract"
grep -Fq 'omarchy-guard-gb10-lifecycle .*\|\| exit 1' "$source_contract"
grep -Fq 'cannot consume the bundled AArch64 Node.js release' "$source_contract"
grep -Fq 'cannot remove the live ISO installer sudo policy on errors and signals' "$source_contract"
grep -Fq 'arm_image_guard_precedes_mutation' "$source_contract"
grep -Fq 'does not guard Limine finalization before mutation' "$source_contract"
grep -Fq 'does not validate the installed AArch64 Limine deployment' "$source_contract"
grep -Fq 'nvidia-open-dkms=610.57.04-1' "$source_contract"
grep -Fq 'nvidia-utils=610.57.04-1' "$source_contract"
grep -Fq 'usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin' "$repo_root/builder/build-iso.sh"
grep -Fq 'usr/lib/firmware/nvidia/610.57.04/ucodes_ga10x.bin' "$repo_root/builder/build-iso.sh"
grep -Fq 'limine-mkinitcpio-hook=1.38.0-1' "$repo_root/builder/build-iso.sh"
grep -Fq 'mkarchiso_command=/tmp/mkarchiso-aarch64' "$repo_root/builder/build-iso.sh"
grep -Fq 'arch-install-scripts' "$repo_root/builder/build-iso.sh"
grep -Fq 'archiso-v87-aarch64-grub.patch' "$repo_root/builder/build-iso.sh"
cp "$repo_root/archiso/archiso/mkarchiso" "$fixture/mkarchiso"
patch --batch --forward --fuzz=0 "$fixture/mkarchiso" \
  <"$repo_root/builder/archiso-v87-aarch64-grub.patch" >/dev/null
grep -Fq 'source /builder/archiso-aarch64-grub-modules.sh' "$fixture/mkarchiso"
grep -Fq 'filter_archiso_aarch64_grub_modules grubmodules' "$fixture/mkarchiso"
cp "$repo_root/archiso/archiso/mkarchiso" "$fixture/drifted-mkarchiso"
sed -i 's/all_video at_keyboard boot/all_video renamed_at_keyboard boot/' "$fixture/drifted-mkarchiso"
if patch --batch --forward --fuzz=0 --dry-run "$fixture/drifted-mkarchiso" \
  <"$repo_root/builder/archiso-v87-aarch64-grub.patch" >/dev/null 2>&1; then
  echo "strict Archiso patch unexpectedly accepted changed GRUB module context" >&2
  exit 1
fi
grep -Fq 'exactly one AArch64 Limine hook' "$repo_root/builder/build-iso.sh"
grep -Fq 'final $OMARCHY_ARM_PLATFORM offline repository must contain exactly one kernel and headers package' "$repo_root/builder/build-iso.sh"
grep -Fq 'does not enable AArch64 reset recovery' "$repo_root/builder/build-iso.sh"
grep -Fq 'does not enable AArch64 config enrollment' "$repo_root/builder/build-iso.sh"
grep -Fq 'cannot discover ARM kernels without pkgbase metadata' "$repo_root/builder/build-iso.sh"
grep -Fq 'export OMARCHY_ISO_INSTALL=1' "$repo_root/configs/airootfs/root/.automated_script.sh"
grep -Fq 'export OMARCHY_ARM_IMAGE_INSTALL=1' "$repo_root/configs/airootfs/root/.automated_script.sh"
grep -Fq 'export OMARCHY_ARM_PLATFORM="$(cat /root/omarchy_arm_platform)"' "$repo_root/configs/airootfs/root/.automated_script.sh"
grep -Fq 'export OMARCHY_INSTALL_DEBUG_LOGS=1' "$repo_root/configs/airootfs/root/.automated_script.sh"
grep -Fq 'n1x_live_recovery_requested' "$repo_root/configs/airootfs/root/.automated_script.sh"
grep -Fq 'exec /bin/bash -l' "$repo_root/configs/airootfs/root/.automated_script.sh"
grep -Fq 'ssh root@omarchy-n1x-rescue.local' "$repo_root/configs/airootfs/usr/local/sbin/omarchy-n1x-live-probe"
grep -Fq '["/root/.ssh"]="0:0:700"' "$repo_root/configs/profiledef.sh"
grep -Fq '["/root/.ssh/authorized_keys"]="0:0:600"' "$repo_root/configs/profiledef.sh"
ssh-keygen -l -f "$repo_root/builder/n1x-recovery-authorized-key" >/dev/null
grep -Fq 'install -m0600 /builder/n1x-recovery-authorized-key' "$repo_root/builder/build-iso.sh"
grep -Fq 'install -Dm0644 /builder/n1x-recovery-sshd.conf' "$repo_root/builder/build-iso.sh"
grep -Fxq 'PasswordAuthentication no' "$repo_root/builder/n1x-recovery-sshd.conf"
grep -Fxq 'PermitRootLogin prohibit-password' "$repo_root/builder/n1x-recovery-sshd.conf"
grep -Fq 'omarchy-n1x-rescue >"$build_cache_dir/airootfs/etc/hostname"' "$repo_root/builder/build-iso.sh"
grep -Fq 'OMARCHY_ARM_IMAGE_INSTALL="${OMARCHY_ARM_IMAGE_INSTALL:-0}"' "$repo_root/configs/airootfs/root/.automated_script.sh"
grep -Fq 'OMARCHY_ARM_PLATFORM="${OMARCHY_ARM_PLATFORM:-}"' "$repo_root/configs/airootfs/root/.automated_script.sh"
grep -Fq 'OMARCHY_INSTALL_DEBUG_LOGS="${OMARCHY_INSTALL_DEBUG_LOGS:-0}"' "$repo_root/configs/airootfs/root/.automated_script.sh"
grep -Fq 'OMARCHY_ARM_IMAGE_INSTALL' "$repo_root/configs/airootfs/root/configurator"
if grep -Fq 'omarchy_is_gb10 /sys' "$repo_root/configs/airootfs/root/configurator"; then
  echo "AArch64 configurator unexpectedly requires the Coleman GB10 hardware tuple" >&2
  exit 1
fi
grep -Fq 'OMARCHY_ARM_IMAGE_INSTALL' "$repo_root/builder/gb10-omarchy-source.sh"
grep -Fq 'OMARCHY_INSTALL_DEBUG_LOGS' "$repo_root/builder/gb10-omarchy-source.sh"

grep -Fq "ALL_kver='/boot/vmlinuz-linux-gb10'" "$repo_root/builder/linux-gb10.preset"
grep -Fq "archiso_image='/boot/initramfs-linux-gb10.img'" "$repo_root/builder/linux-gb10.preset"
grep -Fq "ALL_kver='/boot/vmlinuz-linux-n1x'" "$repo_root/builder/linux-n1x.preset"
grep -Fq "archiso_image='/boot/initramfs-linux-n1x.img'" "$repo_root/builder/linux-n1x.preset"

echo "GB10 build mode tests passed"
