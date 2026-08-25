#!/bin/bash

# Publish a regular file without ever replacing an existing destination. Source
# and destination live below the same release directory, so hard-link creation
# provides an atomic no-replace operation even when builds finish concurrently.
publish_iso_no_replace() {
  local source=$1 destination=$2

  [[ -f $source ]] || {
    echo "ERROR: ISO publication source is missing: $source" >&2
    return 1
  }

  if ! ln -- "$source" "$destination"; then
    echo "ERROR: refusing to overwrite existing GB10 ISO: $destination" >&2
    return 1
  fi

  rm -- "$source"
}
