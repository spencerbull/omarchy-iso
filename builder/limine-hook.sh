limine_function_uses_supported_arch() {
  local function_name=$1

  awk -v function_name="$function_name" '
    $0 ~ "^[[:space:]]*" function_name "\\(\\)[[:space:]]*\\{" {
      in_function = 1
      next
    }
    in_function && /is_supported_uefi_arch/ {
      supports_arch = 1
    }
    in_function && /^}/ {
      function_closed = 1
      exit(supports_arch ? 0 : 1)
    }
    END {
      if (!function_closed) {
        exit 1
      }
    }
  '
}
