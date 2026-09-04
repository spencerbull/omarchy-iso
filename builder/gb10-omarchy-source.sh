arm_image_guard_precedes_mutation() {
  local source_file=$1
  local error_marker=$2
  local mutation_marker=$3
  local arch_line authorization_line error_line return_line mutation_line

  arch_line=$(grep -n -m1 -F '$(uname -m) == aarch64' "$source_file" | cut -d: -f1 || true)
  authorization_line=$(grep -n -m1 -F 'OMARCHY_ARM_IMAGE_INSTALL' "$source_file" | cut -d: -f1 || true)
  error_line=$(grep -n -m1 -F "$error_marker" "$source_file" | cut -d: -f1 || true)
  mutation_line=$(grep -n -m1 -F "$mutation_marker" "$source_file" | cut -d: -f1 || true)
  return_line=$(awk -v start="$error_line" -v end="$mutation_line" '
    NR > start && NR < end && /^[[:space:]]*return 1[[:space:]]*$/ { print NR; exit }
  ' "$source_file")

  [[ -n $arch_line && -n $authorization_line && -n $error_line && -n $return_line && -n $mutation_line ]] &&
    ((arch_line <= authorization_line && authorization_line < error_line && error_line < return_line && return_line < mutation_line))
}

validate_arm_omarchy_source() {
  local omarchy_source=$1
  local required_arm_file guarded_gb10_command
  local install_arch_guard_line install_helper_line

  for required_arm_file in \
    boot.sh \
    install.sh \
    bin/omarchy-update \
    bin/omarchy-hw-nvidia-gb10 \
    default/pacman/pacman-aarch64.conf \
    default/pacman/mirrorlist-aarch64 \
    install/config/all.sh \
    install/config/mise-work.sh \
    install/config/hardware/nvidia.sh \
    install/config/hardware/nvidia/gb10-kernel.sh \
    install/config/hardware/nvidia/n1x-kernel.sh \
    install/config/hardware/nvidia/n1x-recovery.sh \
    install/config/hardware/nvidia/n1x-probe \
    install/helpers/errors.sh \
    install/helpers/gb10-lifecycle.sh \
    install/helpers/logging.sh \
    install/helpers/node-release.sh \
    install/login/limine-snapper.sh; do
    if [[ ! -f $omarchy_source/$required_arm_file ]]; then
      echo "ERROR: selected Omarchy source is not ARM-image-capable; missing $required_arm_file" >&2
      return 1
    fi
  done

  if ! grep -Fq 'hardware/nvidia/gb10-kernel.sh' "$omarchy_source/install/config/all.sh"; then
    echo "ERROR: selected Omarchy source does not activate the GB10 kernel configuration" >&2
    return 1
  fi
  if ! grep -Fq 'hardware/nvidia/n1x-kernel.sh' "$omarchy_source/install/config/all.sh" ||
    ! grep -Fq 'hardware/nvidia/n1x-recovery.sh' "$omarchy_source/install/config/all.sh"; then
    echo "ERROR: selected Omarchy source does not activate the N1x kernel and recovery configuration" >&2
    return 1
  fi
  if ! grep -Fq 'nvidia-open-dkms=610.57.04-1' "$omarchy_source/install/config/hardware/nvidia.sh" ||
    ! grep -Fq 'nvidia-utils=610.57.04-1' "$omarchy_source/install/config/hardware/nvidia.sh"; then
    echo "ERROR: selected Omarchy source does not pin the ARM NVIDIA driver pair" >&2
    return 1
  fi
  if ! grep -Fq 'Omarchy online installation is unavailable on ARM' "$omarchy_source/boot.sh" ||
    ! grep -Fq 'disabled on AArch64 until a complete versioned package repository' "$omarchy_source/install/helpers/gb10-lifecycle.sh" ||
    ! grep -Fq '$(uname -m) != x86_64' "$omarchy_source/install/helpers/gb10-lifecycle.sh"; then
    echo "ERROR: selected Omarchy source does not fail closed for unsupported GB10 lifecycle paths" >&2
    return 1
  fi

  install_arch_guard_line=$(grep -n -m1 'OMARCHY_ARM_IMAGE_INSTALL' "$omarchy_source/install.sh" | cut -d: -f1)
  install_helper_line=$(grep -n -m1 'helpers/all.sh' "$omarchy_source/install.sh" | cut -d: -f1)
  if [[ -z $install_arch_guard_line || -z $install_helper_line || $install_arch_guard_line -ge $install_helper_line ]]; then
    echo "ERROR: selected Omarchy source does not reject unsupported ARM before helper mutations" >&2
    return 1
  fi

  if ! grep -Fq 'omarchy-node-release-platform' "$omarchy_source/install/config/mise-work.sh" ||
    ! grep -Fq 'linux-arm64' "$omarchy_source/install/helpers/node-release.sh" ||
    ! grep -Fq 'Expected exactly one bundled Node.js' "$omarchy_source/install/helpers/node-release.sh"; then
    echo "ERROR: selected Omarchy source cannot consume the bundled AArch64 Node.js release" >&2
    return 1
  fi

  for guarded_gb10_command in \
    bin/omarchy-branch-set \
    bin/omarchy-channel-set \
    bin/omarchy-migrate \
    bin/omarchy-refresh-pacman \
    bin/omarchy-reinstall-pkgs \
    bin/omarchy-update \
    bin/omarchy-update-aur-pkgs \
    bin/omarchy-update-available-reset \
    bin/omarchy-update-branch \
    bin/omarchy-update-firmware \
    bin/omarchy-update-git \
    bin/omarchy-update-keyring \
    bin/omarchy-update-orphan-pkgs \
    bin/omarchy-update-perform \
    bin/omarchy-update-restart \
    bin/omarchy-update-system-pkgs \
    bin/omarchy-update-time; do
    if ! grep -Fq 'omarchy-guard-gb10-lifecycle' "$omarchy_source/$guarded_gb10_command" ||
      ! grep -Eq 'omarchy-guard-gb10-lifecycle .*\|\| exit 1' "$omarchy_source/$guarded_gb10_command"; then
      echo "ERROR: selected Omarchy source does not fail closed in $guarded_gb10_command" >&2
      return 1
    fi
  done

  if ! grep -Fq 'bash -Ee -o pipefail' "$omarchy_source/install/helpers/logging.sh" ||
    ! grep -Fq '$(uname -m) != x86_64' "$omarchy_source/install/helpers/logging.sh"; then
    echo "ERROR: selected Omarchy source does not propagate non-x86 installer-stage failures" >&2
    return 1
  fi
  if ! grep -Fq 'trap catch_errors ERR INT TERM' "$omarchy_source/install/helpers/errors.sh" ||
    ! grep -Fq 'trap exit_handler EXIT' "$omarchy_source/install/helpers/errors.sh" ||
    ! grep -Fq 'OMARCHY_INSTALL_DEBUG_LOGS' "$omarchy_source/install/helpers/errors.sh" ||
    ! grep -Fq 'OMARCHY_ISO_INSTALL' "$omarchy_source/install/helpers/errors.sh" ||
    ! grep -Fq '/mnt/etc/sudoers.d/99-omarchy-installer' "$omarchy_source/install/helpers/errors.sh" ||
    ! grep -Fq 'cleanup_chroot_installer_sudoers || true' "$omarchy_source/install/helpers/errors.sh"; then
    echo "ERROR: selected Omarchy source cannot remove the live ISO installer sudo policy on errors and signals or provide GB10 error diagnostics" >&2
    return 1
  fi

  if ! arm_image_guard_precedes_mutation \
    "$omarchy_source/install/config/hardware/nvidia/gb10-kernel.sh" \
    'authorization disappeared before the kernel transition' \
    'omarchy-pkg-add'; then
    echo "ERROR: selected Omarchy source does not guard the kernel transition before mutation" >&2
    return 1
  fi
  if ! arm_image_guard_precedes_mutation \
    "$omarchy_source/install/config/hardware/nvidia/n1x-kernel.sh" \
    'authorization disappeared before the N1x kernel transition' \
    'omarchy-pkg-add'; then
    echo "ERROR: selected Omarchy source does not guard the N1x kernel transition before mutation" >&2
    return 1
  fi
  if ! arm_image_guard_precedes_mutation \
    "$omarchy_source/install/config/hardware/nvidia.sh" \
    'authorization disappeared before NVIDIA driver installation' \
    'omarchy-pkg-add'; then
    echo "ERROR: selected Omarchy source does not guard NVIDIA installation before mutation" >&2
    return 1
  fi
  if ! arm_image_guard_precedes_mutation \
    "$omarchy_source/install/login/limine-snapper.sh" \
    'authorization disappeared before Limine finalization' \
    'sudo tee'; then
    echo "ERROR: selected Omarchy source does not guard Limine finalization before mutation" >&2
    return 1
  fi
  if ! grep -Fq 'authorization disappeared before Limine validation' "$omarchy_source/install/login/limine-snapper.sh" ||
    ! grep -Fq 'authorization disappeared before NVRAM validation' "$omarchy_source/install/login/limine-snapper.sh"; then
    echo "ERROR: selected Omarchy source does not revalidate ARM image authorization before final Limine and NVRAM checks" >&2
    return 1
  fi
  if ! grep -Fq '/boot/EFI/limine/limine_aa64.efi' "$omarchy_source/install/login/limine-snapper.sh" ||
    ! grep -Fq '/boot/EFI/BOOT/BOOTAA64.EFI' "$omarchy_source/install/login/limine-snapper.sh"; then
    echo "ERROR: selected Omarchy source does not validate the installed AArch64 Limine deployment" >&2
    return 1
  fi
  if ! grep -Fq 'limine-entry-tool --add-uki linux-n1x-rescue' "$omarchy_source/install/login/limine-snapper.sh" ||
    grep -Fq 'MKINITCPIO_FALLBACK=linux-n1x' "$omarchy_source/install/login/limine-snapper.sh" ||
    ! grep -Fq 'omarchy.n1x_recovery=1' "$omarchy_source/install/login/limine-snapper.sh" ||
    ! grep -Fq 'nomodeset module_blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm,nvidia_peermem,nouveau' "$omarchy_source/install/login/limine-snapper.sh" ||
    ! grep -Fq 'systemd.unit=multi-user.target console=tty0 fbcon=map:0 earlycon' "$omarchy_source/install/login/limine-snapper.sh"; then
    echo "ERROR: selected Omarchy source does not provide the compact N1x headless recovery entry" >&2
    return 1
  fi
  if ! grep -Fq 'options nvidia_drm modeset=0' "$omarchy_source/install/config/hardware/nvidia.sh" ||
    ! grep -Fq 'sudo rm -f /etc/mkinitcpio.conf.d/nvidia.conf' "$omarchy_source/install/config/hardware/nvidia.sh" ||
    ! grep -Fq 'MODULES+=(i2c_tegra i2c_hid i2c_hid_acpi hid_generic hid_multitouch usbhid)' "$omarchy_source/install/config/hardware/nvidia/n1x-kernel.sh" ||
    ! grep -Fq 'chrootable_systemctl_enable sshd.service' "$omarchy_source/install/config/hardware/nvidia/n1x-recovery.sh" ||
    ! grep -Fq 'PasswordAuthentication no' "$omarchy_source/install/config/hardware/nvidia/n1x-recovery.sh" ||
    ! grep -Fq 'PermitRootLogin no' "$omarchy_source/install/config/hardware/nvidia/n1x-recovery.sh" ||
    ! grep -Fq 'chrootable_systemctl_enable systemd-networkd.service' "$omarchy_source/install/config/hardware/nvidia/n1x-recovery.sh" ||
    ! grep -Fq 'chrootable_systemctl_enable systemd-resolved.service' "$omarchy_source/install/config/hardware/nvidia/n1x-recovery.sh" ||
    ! grep -Fq 'omarchy-n1x-probe.service' "$omarchy_source/install/config/hardware/nvidia/n1x-recovery.sh"; then
    echo "ERROR: selected Omarchy source does not provide late NVIDIA loading and SSH recovery for N1x" >&2
    return 1
  fi
}
