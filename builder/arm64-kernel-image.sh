#!/bin/bash

raw_arm64_image_magic() {
  dd if="$1" bs=1 skip=56 count=4 status=none | od -An -tx1 | tr -d ' \n'
}

raw_arm64_image_prefix() {
  dd if="$1" bs=1 count=2 status=none | od -An -tx1 | tr -d ' \n'
}

is_raw_arm64_kernel_image() {
  local image=$1

  [[ $(raw_arm64_image_magic "$image") == 41524d64 ]] &&
    [[ $(raw_arm64_image_prefix "$image") != 4d5a ]]
}
