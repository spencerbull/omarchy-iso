#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="omarchy"
iso_label="OMARCHY_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Omarchy <https://omarchy.org>"
iso_application="Omarchy Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
arch="${OMARCHY_ARCH:-x86_64}"
if [[ $arch == aarch64 ]]; then
  bootmodes=('uefi.grub')
else
  bootmodes=('bios.syslinux' 'uefi.grub')
fi
pacman_conf="pacman-offline.conf"
airootfs_image_type="squashfs"
if [[ $arch == aarch64 ]]; then
  airootfs_image_tool_options=('-comp' 'xz' '-b' '1M' '-Xdict-size' '1M')
else
  airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
fi
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/root/configurator"]="0:0:755"
  ["/var/cache/omarchy/mirror/offline/"]="0:0:775"
  ["/usr/local/bin/omarchy-upload-log"]="0:0:755"
)
