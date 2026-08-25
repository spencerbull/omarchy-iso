#!/usr/bin/env bash

configure_archiso_aarch64_mkinitcpio() {
  local config=$1
  local hook hook_body hook_line replacement
  local -a filtered_hooks=() hook_lines=() hooks=()
  local -i memdisk_count=0 microcode_count=0

  mapfile -t hook_lines < <(grep -E '^HOOKS=\([^)]*\)$' "$config")
  if (( ${#hook_lines[@]} != 1 )); then
    echo "ERROR: unexpected Archiso mkinitcpio hook layout: $config" >&2
    return 1
  fi

  hook_line=${hook_lines[0]}
  hook_body=${hook_line#HOOKS=\(}
  hook_body=${hook_body%\)}
  read -r -a hooks <<<"$hook_body"

  for hook in "${hooks[@]}"; do
    case "$hook" in
      microcode) ((microcode_count += 1)) ;;
      memdisk) ((memdisk_count += 1)) ;;
      *) filtered_hooks+=("$hook") ;;
    esac
  done
  if (( microcode_count != 1 || memdisk_count != 1 )); then
    echo "ERROR: expected exactly one microcode and memdisk hook: $config" >&2
    return 1
  fi

  # CPU microcode packages and memdiskfind are x86-only. Keeping memdisk after
  # excluding memtest86+ makes mkinitcpio report an incomplete ARM64 image.
  printf -v replacement 'HOOKS=(%s)' "${filtered_hooks[*]}"
  sed -i "s|^HOOKS=.*$|$replacement|" "$config"

  mapfile -t hook_lines < <(grep -E '^HOOKS=\([^)]*\)$' "$config")
  if (( ${#hook_lines[@]} != 1 )) || [[ ${hook_lines[0]} != "$replacement" ]]; then
    echo "ERROR: failed to remove x86-only Archiso mkinitcpio hooks: $config" >&2
    return 1
  fi
}
