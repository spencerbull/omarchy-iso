#!/bin/bash

set -e

source /builder/node-release.sh
source /builder/arm64-kernel-image.sh
source /builder/limine-hook.sh
source /builder/gb10-omarchy-source.sh

OMARCHY_ARCH=${OMARCHY_ARCH:-x86_64}
OMARCHY_KERNEL=${OMARCHY_KERNEL:-linux-t2}

case "$OMARCHY_ARCH:$OMARCHY_KERNEL" in
  x86_64:linux-t2)
    online_pacman_conf="/configs/pacman-online-${OMARCHY_MIRROR}.conf"
    ;;
  aarch64:linux-gb10)
    online_pacman_conf=/configs/pacman-online-gb10.conf
    if [[ ${OMARCHY_PACKAGE_DIR:-} != /packages || ! -d /packages ]]; then
      echo "ERROR: GB10 builds require the prebuilt package directory at /packages" >&2
      exit 1
    fi
    ;;
  *)
    echo "ERROR: unsupported ISO architecture/kernel pair: $OMARCHY_ARCH/$OMARCHY_KERNEL" >&2
    exit 1
    ;;
esac

# These packages are installed into the container used to build the ISO.
pacman-key --init
if [[ $OMARCHY_ARCH == aarch64 ]]; then
  pacman --noconfirm -Sy archlinuxarm-keyring
  pacman-key --populate archlinuxarm
  # Arch Linux ARM does not publish the archiso package. Install the runtime
  # dependencies declared by archiso and execute the repository's pinned
  # submodule copy instead.
  pacman --noconfirm -Sy \
    arch-install-scripts \
    dosfstools \
    e2fsprogs \
    erofs-utils \
    libarchive \
    libisoburn \
    mtools \
    squashfs-tools \
    git sudo base-devel jq grub
  mkarchiso_command=/archiso/archiso/mkarchiso
else
  pacman --noconfirm -Sy archlinux-keyring
  pacman-key --populate archlinux
  pacman --noconfirm -Sy archiso git sudo base-devel jq grub
  mkarchiso_command=mkarchiso
fi

# Setup build locations.
build_cache_dir=/var/cache
offline_mirror_dir="$build_cache_dir/airootfs/var/cache/omarchy/mirror/offline"
mkdir -p "$build_cache_dir" "$offline_mirror_dir"

package_name=""
package_arch=""
package_version=""
validate_package_archive() {
  local archive=$1
  local package_info

  if ! package_info=$(bsdtar -xOf "$archive" .PKGINFO); then
    echo "ERROR: cannot read package metadata: $archive" >&2
    return 1
  fi

  package_name=$(awk -F ' = ' '$1 == "pkgname" { print $2; exit }' <<<"$package_info")
  package_arch=$(awk -F ' = ' '$1 == "arch" { print $2; exit }' <<<"$package_info")
  package_version=$(awk -F ' = ' '$1 == "pkgver" { print $2; exit }' <<<"$package_info")
  if [[ -z $package_name || -z $package_arch || -z $package_version ]]; then
    echo "ERROR: package metadata is missing pkgname, pkgver, or arch: $archive" >&2
    return 1
  fi

  if [[ $OMARCHY_ARCH == aarch64 && $package_arch != aarch64 && $package_arch != any ]]; then
    echo "ERROR: GB10 package '$package_name' has unsupported architecture '$package_arch': $archive" >&2
    return 1
  fi
  if [[ $OMARCHY_ARCH == aarch64 ]]; then
    case "$package_name" in
      amd-ucode|intel-ucode|syslinux|broadcom-wl|linux-t2|linux-t2-headers|apple-bcm-firmware|apple-t2-audio-config|t2fanrd|tiny-dfr|lib32-*)
        echo "ERROR: x86-only package '$package_name' is forbidden in the GB10 offline repository" >&2
        return 1
        ;;
    esac
  fi
}

rebuild_offline_repo() {
  local archive
  local -a archives=()

  shopt -s nullglob
  for archive in "$offline_mirror_dir"/*.pkg.tar.*; do
    [[ $archive == *.sig ]] || archives+=("$archive")
  done
  shopt -u nullglob

  if (( ${#archives[@]} == 0 )); then
    echo "ERROR: no package archives are available for the offline repository" >&2
    return 1
  fi

  repo-add "$offline_mirror_dir/offline.db.tar.gz" "${archives[@]}"
}

seed_gb10_packages() {
  local archive
  local runtime_count=0
  local headers_count=0
  local runtime_version=""
  local headers_version=""
  local kernel_member=""
  local arm64_magic=""
  local arm64_prefix=""
  local extracted_kernel=""
  local -a archives=()
  local -a kernel_members=()

  if [[ ! -f /packages/SHA256SUMS ]]; then
    echo "ERROR: /packages must contain SHA256SUMS" >&2
    return 1
  fi
  while IFS= read -r archive; do
    archive_name=${archive##*/}
    if ! awk -v name="$archive_name" '{ file=$2; sub(/^\*/, "", file); if (file == name) found=1 } END { exit !found }' /packages/SHA256SUMS; then
      echo "ERROR: SHA256SUMS does not cover $archive_name" >&2
      return 1
    fi
  done < <(find /packages -maxdepth 1 -type f \
    \( -name '*.pkg.tar.xz' -o -name '*.pkg.tar.zst' \) -print)
  if ! (cd /packages && sha256sum --check --strict SHA256SUMS); then
    echo "ERROR: GB10 package checksum verification failed" >&2
    return 1
  fi

  mapfile -d '' archives < <(
    find /packages -maxdepth 1 -type f \
      \( -name '*.pkg.tar.xz' -o -name '*.pkg.tar.zst' \) -print0
  )
  if (( ${#archives[@]} == 0 )); then
    echo "ERROR: no prebuilt package archives found in /packages" >&2
    return 1
  fi

  for archive in "${archives[@]}"; do
    validate_package_archive "$archive"
    case "$package_name" in
      linux-gb10)
        ((runtime_count += 1))
        runtime_version=$package_version
        kernel_members=()
        mapfile -t kernel_members < <(bsdtar -tf "$archive" | grep -E '^usr/lib/modules/[^/]+/vmlinuz$' || true)
        if (( ${#kernel_members[@]} != 1 )); then
          echo "ERROR: linux-gb10 must contain exactly one module-tree vmlinuz" >&2
          return 1
        fi
        kernel_member=${kernel_members[0]}
        extracted_kernel=$(mktemp)
        if ! bsdtar -xOf "$archive" "$kernel_member" >"$extracted_kernel"; then
          rm -f -- "$extracted_kernel"
          echo "ERROR: failed to extract linux-gb10 vmlinuz for validation" >&2
          return 1
        fi
        arm64_magic=$(raw_arm64_image_magic "$extracted_kernel")
        arm64_prefix=$(raw_arm64_image_prefix "$extracted_kernel")
        if ! is_raw_arm64_kernel_image "$extracted_kernel"; then
          rm -f -- "$extracted_kernel"
          echo "ERROR: linux-gb10 vmlinuz is not a raw ARM64 Image (magic at offset 56 is ${arm64_magic:-missing}, prefix is ${arm64_prefix:-missing})" >&2
          return 1
        fi
        rm -f -- "$extracted_kernel"
        ;;
      linux-gb10-headers)
        ((headers_count += 1))
        headers_version=$package_version
        ;;
    esac
    cp -f -- "$archive" "$offline_mirror_dir/"
  done

  if (( runtime_count != 1 || headers_count != 1 )); then
    echo "ERROR: /packages must contain exactly one linux-gb10 and one linux-gb10-headers archive" >&2
    return 1
  fi
  if [[ $runtime_version != "$headers_version" ]]; then
    echo "ERROR: linux-gb10 runtime ($runtime_version) and headers ($headers_version) versions do not match" >&2
    return 1
  fi

  rebuild_offline_repo
}

if [[ $OMARCHY_ARCH == aarch64 ]]; then
  seed_gb10_packages
fi

# Pre-import the Omarchy signing key so pacman can verify published packages.
pacman-key --add /builder/omarchy.gpg
pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571

# In GB10 mode omarchy-keyring must be supplied by the prebuilt package
# directory. x86_64 continues to use the selected published channel.
pacman --config "$online_pacman_conf" --noconfirm -Sy omarchy-keyring
pacman-key --populate omarchy

# We base our ISO on the official archiso releng config.
cp -r /archiso/configs/releng/* "$build_cache_dir/"
rm "$build_cache_dir/airootfs/etc/motd"

# Avoid using reflector for mirror identification as we are relying on a fixed
# repository configuration during the offline build.
rm -rf "$build_cache_dir/airootfs/etc/systemd/system/multi-user.target.wants/reflector.service"
rm -rf "$build_cache_dir/airootfs/etc/systemd/system/reflector.service.d"
rm -rf "$build_cache_dir/airootfs/etc/xdg/reflector"

# Bring in our shared configs, then apply the bounded architecture overlay.
cp -r /configs/* "$build_cache_dir/"

if [[ $OMARCHY_ARCH == aarch64 ]]; then
  # Start from releng's maintained live package list, but explicitly remove
  # x86-only firmware, virtualization, rescue, and BIOS boot packages. The
  # Omarchy base manifest is handled separately below and is never filtered.
  gb10_live_excludes=(
    amd-ucode
    broadcom-wl
    edk2-shell
    hyperv
    intel-ucode
    linux
    memtest86+
    memtest86+-efi
    open-vm-tools
    refind
    reflector
    syslinux
    virtualbox-guest-utils-nox
  )
  cp "$build_cache_dir/packages.x86_64" "$build_cache_dir/packages.aarch64"
  for excluded_package in "${gb10_live_excludes[@]}"; do
    escaped_package=${excluded_package//+/[+]}
    sed -i "\\|^${escaped_package}$|d" "$build_cache_dir/packages.aarch64"
  done

  rm "$build_cache_dir/airootfs/etc/mkinitcpio.d/linux.preset"
  cp /builder/linux-gb10.preset "$build_cache_dir/airootfs/etc/mkinitcpio.d/linux-gb10.preset"
  sed -i 's/ udev microcode / udev /' "$build_cache_dir/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
  kernel_options=""
else
  kernel_options="xe.enable_panel_replay=0"
fi

for grub_config in "$build_cache_dir/grub/grub.cfg" "$build_cache_dir/grub/loopback.cfg"; do
  sed -i \
    -e "s|%KERNEL%|$OMARCHY_KERNEL|g" \
    -e "s|%KERNEL_OPTIONS%|$kernel_options|g" \
    "$grub_config"
done

# Persist the build selection for the live installer.
echo "$OMARCHY_MIRROR" > "$build_cache_dir/airootfs/root/omarchy_mirror"
echo "$OMARCHY_ARCH" > "$build_cache_dir/airootfs/root/omarchy_arch"

# Setup Omarchy itself.
if [[ -d /omarchy ]]; then
  cp -rp /omarchy "$build_cache_dir/airootfs/root/omarchy"
else
  git clone -b "$OMARCHY_INSTALLER_REF" "https://github.com/$OMARCHY_INSTALLER_REPO.git" "$build_cache_dir/airootfs/root/omarchy"
fi

if [[ $OMARCHY_ARCH == aarch64 ]]; then
  omarchy_source="$build_cache_dir/airootfs/root/omarchy"
  validate_gb10_omarchy_source "$omarchy_source"
fi

# Make log uploader available in the ISO too.
mkdir -p "$build_cache_dir/airootfs/usr/local/bin/"
cp "$build_cache_dir/airootfs/root/omarchy/bin/omarchy-upload-log" "$build_cache_dir/airootfs/usr/local/bin/omarchy-upload-log"

# Copy the Omarchy Plymouth theme to the ISO.
mkdir -p "$build_cache_dir/airootfs/usr/share/plymouth/themes/omarchy"
cp -r "$build_cache_dir/airootfs/root/omarchy/default/plymouth/"* "$build_cache_dir/airootfs/usr/share/plymouth/themes/omarchy/"

# Download and verify the architecture-matched Node.js binary.
NODE_DIST_URL=https://nodejs.org/dist/latest
if [[ $OMARCHY_ARCH == aarch64 ]]; then
  node_platform=linux-arm64
else
  node_platform=linux-x64
fi
NODE_SHASUMS=$(curl -fsSL "$NODE_DIST_URL/SHASUMS256.txt")
if ! IFS=$'\t' read -r NODE_FILENAME NODE_SHA < <(select_node_release "$node_platform" <<<"$NODE_SHASUMS"); then
  echo "ERROR: could not find Node.js $node_platform release metadata" >&2
  exit 1
fi

curl -fsSL "$NODE_DIST_URL/$NODE_FILENAME" -o "/tmp/$NODE_FILENAME"
echo "$NODE_SHA /tmp/$NODE_FILENAME" | sha256sum -c - || {
  echo "ERROR: Node.js checksum verification failed!" >&2
  exit 1
}
mkdir -p "$build_cache_dir/airootfs/opt/packages/"
cp "/tmp/$NODE_FILENAME" "$build_cache_dir/airootfs/opt/packages/"

# Add packages installed in the live ISO itself.
packages_file="$build_cache_dir/packages.$OMARCHY_ARCH"
if [[ $OMARCHY_ARCH == aarch64 ]]; then
  arch_packages=(linux-gb10 archlinuxarm-keyring git gum jq openssl plymouth omarchy-keyring lvm2 cryptsetup parted)
else
  arch_packages=(linux-t2 git gum jq openssl plymouth tzupdate omarchy-keyring lvm2 cryptsetup parted)
fi
printf '%s\n' "${arch_packages[@]}" >> "$packages_file"

read_package_list() {
  local list=$1
  awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$list"
}

append_gb10_platform_packages() {
  local list=$1
  local package

  while IFS= read -r package; do
    case "$package" in
      amd-ucode|intel-ucode|syslinux|broadcom-wl|apple-*|asusctl|dell-xps-touchpad-haptics|intel-ipu7-camera|intel-lpmd|intel-media-driver|libva-intel-driver|lib32-*|linux-firmware-marvell|linux-ptl|linux-ptl-headers|linux-t2|linux-t2-headers|macbook12-spi-driver-dkms|nvidia-580xx-*|nvidia-dkms|t2fanrd|thermald|tiny-dfr|tuxedo-drivers-nocompatcheck-dkms|vpl-gpu-rt|vulkan-asahi|vulkan-intel|vulkan-radeon|yt6801-dkms)
        echo "GB10: excluding platform-irrelevant package from $list: $package"
        ;;
      linux|linux-t2)
        echo "GB10: replacing $package with linux-gb10 from $list"
        all_packages+=(linux-gb10)
        ;;
      linux-headers|linux-t2-headers)
        echo "GB10: replacing $package with linux-gb10-headers from $list"
        all_packages+=(linux-gb10-headers)
        ;;
      *)
        all_packages+=("$package")
        ;;
    esac
  done < <(read_package_list "$list")
}

# Build the complete offline closure. Omarchy's base package manifest is added
# verbatim and deliberately receives no architecture filtering: a missing
# package is a hard build failure, not an implicit feature removal.
mapfile -t all_packages < <(read_package_list "$packages_file")
base_packages="$build_cache_dir/airootfs/root/omarchy/install/omarchy-base.packages"
other_packages="$build_cache_dir/airootfs/root/omarchy/install/omarchy-other.packages"
for required_package_list in "$packages_file" "$base_packages" "$other_packages" /builder/archinstall.packages; do
  if [[ ! -f $required_package_list ]]; then
    echo "ERROR: required package manifest is missing: $required_package_list" >&2
    exit 1
  fi
done
mapfile -t omarchy_base_packages < <(read_package_list "$base_packages")
if (( ${#omarchy_base_packages[@]} == 0 )); then
  echo "ERROR: Omarchy base package manifest is empty: $base_packages" >&2
  exit 1
fi
if [[ $OMARCHY_ARCH == aarch64 ]]; then
  for base_package in "${omarchy_base_packages[@]}"; do
    case "$base_package" in
      amd-ucode|intel-ucode|syslinux|broadcom-wl|linux-t2|linux-t2-headers|apple-bcm-firmware|apple-t2-audio-config|t2fanrd|tiny-dfr|lib32-*)
        echo "ERROR: Omarchy base manifest contains x86-only package '$base_package'; refusing to filter it" >&2
        exit 1
        ;;
    esac
  done
fi
all_packages+=("${omarchy_base_packages[@]}")

if [[ $OMARCHY_ARCH == aarch64 ]]; then
  append_gb10_platform_packages "$other_packages"
  append_gb10_platform_packages /builder/archinstall.packages
  all_packages+=(
    linux-gb10
    linux-gb10-headers
    archlinuxarm-keyring
    nvidia-open-dkms=610.57.04-1
    nvidia-utils=610.57.04-1
    libva-nvidia-driver
    limine-mkinitcpio-hook=1.37.1-4
    limine-snapper-sync=1.31.0-1
  )
else
  mapfile -t omarchy_other_packages < <(read_package_list "$other_packages")
  mapfile -t archinstall_packages < <(read_package_list /builder/archinstall.packages)
  all_packages+=("${omarchy_other_packages[@]}" "${archinstall_packages[@]}")
fi
mapfile -t all_packages < <(printf '%s\n' "${all_packages[@]}" | sort -u)

# Resolve every requested package and dependency before invoking mkarchiso.
# pacman exits non-zero for an incomplete closure, which intentionally aborts
# the build rather than producing a partially provisioned ISO.
mkdir -p /tmp/offlinedb
if ! pacman --config "$online_pacman_conf" --noconfirm -Syw \
  "${all_packages[@]}" --cachedir "$offline_mirror_dir/" --dbpath /tmp/offlinedb; then
  echo "ERROR: complete $OMARCHY_ARCH Omarchy package closure could not be resolved" >&2
  exit 1
fi

if [[ $OMARCHY_ARCH == aarch64 ]]; then
  nvidia_open_count=0
  nvidia_utils_count=0
  limine_hook_count=0
  final_kernel_count=0
  final_headers_count=0
  final_kernel_version=""
  final_headers_version=""
  shopt -s nullglob
  for archive in "$offline_mirror_dir"/*.pkg.tar.*; do
    [[ $archive == *.sig ]] && continue
    validate_package_archive "$archive"
    case "$package_name" in
      linux-gb10)
        ((final_kernel_count += 1))
        final_kernel_version=$package_version
        mapfile -t final_kernel_members < <(bsdtar -tf "$archive" | grep -E '^usr/lib/modules/[^/]+/vmlinuz$' || true)
        if (( ${#final_kernel_members[@]} != 1 )); then
          echo "ERROR: final linux-gb10 package must contain exactly one module-tree vmlinuz" >&2
          exit 1
        fi
        final_kernel_image=$(mktemp)
        if ! bsdtar -xOf "$archive" "${final_kernel_members[0]}" >"$final_kernel_image"; then
          rm -f -- "$final_kernel_image"
          echo "ERROR: failed to extract final linux-gb10 vmlinuz for validation" >&2
          exit 1
        fi
        if ! is_raw_arm64_kernel_image "$final_kernel_image"; then
          final_magic=$(raw_arm64_image_magic "$final_kernel_image")
          final_prefix=$(raw_arm64_image_prefix "$final_kernel_image")
          rm -f -- "$final_kernel_image"
          echo "ERROR: final linux-gb10 vmlinuz is not a raw ARM64 Image (magic ${final_magic:-missing}, prefix ${final_prefix:-missing})" >&2
          exit 1
        fi
        rm -f -- "$final_kernel_image"
        ;;
      linux-gb10-headers)
        ((final_headers_count += 1))
        final_headers_version=$package_version
        ;;
      nvidia-open-dkms)
        ((nvidia_open_count += 1))
        if [[ $package_version != 610.57.04-1 ]]; then
          echo "ERROR: GB10 requires nvidia-open-dkms 610.57.04-1, found $package_version" >&2
          exit 1
        fi
        ;;
      nvidia-utils)
        ((nvidia_utils_count += 1))
        if [[ $package_version != 610.57.04-1 ]]; then
          echo "ERROR: GB10 requires nvidia-utils 610.57.04-1, found $package_version" >&2
          exit 1
        fi
        for firmware in \
          usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin \
          usr/lib/firmware/nvidia/610.57.04/ucodes_ga10x.bin; do
          if ! bsdtar -tf "$archive" | grep -Fxq "$firmware"; then
            echo "ERROR: nvidia-utils is missing GB10 firmware payload $firmware" >&2
            exit 1
          fi
        done
        ;;
      limine-mkinitcpio-hook)
        ((limine_hook_count += 1))
        if [[ $package_version != 1.37.1-4 ]]; then
          echo "ERROR: GB10 requires limine-mkinitcpio-hook 1.37.1-4, found $package_version" >&2
          exit 1
        fi
        common_functions=usr/lib/limine/limine-common-functions
        limine_install=usr/bin/limine-install
        for aarch64_marker in BOOTAA64.EFI limine_aa64.efi systemd-bootaa64.efi; do
          if ! bsdtar -xOf "$archive" "$common_functions" | grep -Fq "$aarch64_marker"; then
            echo "ERROR: patched Limine hook is missing AArch64 marker $aarch64_marker" >&2
            exit 1
          fi
        done
        if ! bsdtar -xOf "$archive" "$limine_install" | grep -Fq 'is_supported_uefi_arch'; then
          echo "ERROR: patched Limine installer does not enable its AArch64 deployment path" >&2
          exit 1
        fi
        if ! bsdtar -xOf "$archive" "$common_functions" | limine_function_uses_supported_arch reset_enroll_config; then
          echo "ERROR: patched Limine hook does not enable AArch64 reset recovery" >&2
          exit 1
        fi
        if ! bsdtar -xOf "$archive" "$common_functions" | limine_function_uses_supported_arch enroll_config; then
          echo "ERROR: patched Limine hook does not enable AArch64 config enrollment" >&2
          exit 1
        fi
        ;;
    esac
  done
  shopt -u nullglob
  if (( nvidia_open_count != 1 || nvidia_utils_count != 1 )); then
    echo "ERROR: GB10 offline repository must contain exactly one NVIDIA 610.57.04 open driver/userspace pair" >&2
    exit 1
  fi
  if (( limine_hook_count != 1 )); then
    echo "ERROR: GB10 offline repository must contain exactly one patched AArch64 Limine hook" >&2
    exit 1
  fi
  if (( final_kernel_count != 1 || final_headers_count != 1 )); then
    echo "ERROR: final GB10 offline repository must contain exactly one kernel and headers package" >&2
    exit 1
  fi
  if [[ $final_kernel_version != "$final_headers_version" ]]; then
    echo "ERROR: final GB10 kernel ($final_kernel_version) and headers ($final_headers_version) versions do not match" >&2
    exit 1
  fi
fi
rebuild_offline_repo

# Create a symlink to the offline mirror instead of duplicating it.
mkdir -p /var/cache/omarchy/mirror
ln -s "$offline_mirror_dir" /var/cache/omarchy/mirror/offline

# The live environment and target installer use only the complete offline repo.
cp "$build_cache_dir/pacman-offline.conf" "$build_cache_dir/airootfs/etc/pacman.conf"

"$mkarchiso_command" -v -w "$build_cache_dir/work/" -o /out/ "$build_cache_dir/"

if [[ -n ${HOST_UID:-} && -n ${HOST_GID:-} ]]; then
  chown -R "$HOST_UID:$HOST_GID" /out/
fi
